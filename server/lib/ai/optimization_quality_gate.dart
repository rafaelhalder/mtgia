import 'optimization_validator.dart';

class OptimizationSwapGateResult {
  OptimizationSwapGateResult({
    required this.removals,
    required this.additions,
    required this.droppedReasons,
  });

  final List<String> removals;
  final List<String> additions;
  final List<String> droppedReasons;

  bool get changed => droppedReasons.isNotEmpty;
}

OptimizationSwapGateResult filterUnsafeOptimizeSwapsByCardData({
  required List<String> removals,
  required List<String> additions,
  required List<Map<String, dynamic>> originalDeck,
  required List<Map<String, dynamic>> additionsData,
  required String archetype,
}) {
  final pairCount = [
    removals.length,
    additions.length,
  ].reduce((a, b) => a < b ? a : b);

  final safeRemovals = <String>[];
  final safeAdditions = <String>[];
  final droppedReasons = <String>[];
  final structuralRecoveryScenario =
      _isStructuralRecoveryScenario(originalDeck);

  for (var i = 0; i < pairCount; i++) {
    final removalName = removals[i];
    final additionName = additions[i];

    final removedCard = _findCardByName(originalDeck, removalName);
    final addedCard = _findCardByName(additionsData, additionName);

    if (removedCard.isEmpty || addedCard.isEmpty) {
      droppedReasons.add(
        '$removalName -> $additionName removida pelo gate: dados incompletos para validar a troca.',
      );
      continue;
    }

    final removedRole = _classifyFunctionalRole(removedCard);
    final addedRole = _classifyFunctionalRole(addedCard);
    final cmcDelta = _getCmc(addedCard) - _getCmc(removedCard);
    final rolePreserved = removedRole == addedRole ||
        (removedRole == 'utility' && addedRole == 'utility');

    final criticalRoles = _criticalRolesForArchetype(archetype);
    final losingCriticalRole =
        criticalRoles.contains(removedRole) && !rolePreserved;
    final structuralRecoveryUpgrade = structuralRecoveryScenario &&
        _isStructuralRecoveryUpgrade(
          removedCard: removedCard,
          addedCard: addedCard,
          removedRole: removedRole,
          addedRole: addedRole,
          archetype: archetype,
          cmcDelta: cmcDelta,
        );
    final addedIsLand = ((addedCard['type_line'] as String?) ?? '')
        .toLowerCase()
        .contains('land');
    final nonStructuralLandSwap = addedIsLand && removedRole != 'land';
    final temporaryManaBurst = _isTemporaryManaBurstCard(addedCard);
    final riskyTemporaryRampSwap = temporaryManaBurst &&
        archetype.trim().toLowerCase() != 'combo' &&
        removedRole != 'ramp';

    final shouldDrop = losingCriticalRole ||
        (!rolePreserved && cmcDelta > 1) ||
        (archetype.toLowerCase() == 'aggro' && cmcDelta > 0) ||
        nonStructuralLandSwap ||
        riskyTemporaryRampSwap ||
        _looksLikeOffThemeRoleSwap(
          removedRole: removedRole,
          addedRole: addedRole,
          archetype: archetype,
        );

    if (shouldDrop && !structuralRecoveryUpgrade) {
      droppedReasons.add(
        '$removalName -> $additionName removida pelo gate: '
        'papel $removedRole -> $addedRole, delta CMC ${cmcDelta >= 0 ? '+' : ''}$cmcDelta.',
      );
      continue;
    }

    safeRemovals.add(removalName);
    safeAdditions.add(additionName);
  }

  return OptimizationSwapGateResult(
    removals: safeRemovals,
    additions: safeAdditions,
    droppedReasons: droppedReasons,
  );
}

bool _isStructuralRecoveryScenario(List<Map<String, dynamic>> originalDeck) {
  var totalCards = 0;
  var landCount = 0;
  var nonLandCount = 0;
  var colorProducingLandCount = 0;

  for (final card in originalDeck) {
    final qty = (card['quantity'] as int?) ?? 1;
    final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
    totalCards += qty;

    if (typeLine.contains('land')) {
      landCount += qty;
      if (_landLooksColorProducing(card)) {
        colorProducingLandCount += qty;
      }
    } else {
      nonLandCount += qty;
    }
  }

  if (totalCards == 0) return false;

  final landRatio = landCount / totalCards;
  return landRatio >= 0.65 ||
      landCount >= 50 ||
      nonLandCount <= 20 ||
      (landCount >= 40 && colorProducingLandCount <= 8);
}

bool _isTemporaryManaBurstCard(Map<String, dynamic> card) {
  final name = ((card['name'] as String?) ?? '').toLowerCase();
  final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
  final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
  final generatesMana =
      oracle.contains('add {') || oracle.contains('add one mana');

  if (!generatesMana) return false;
  if (!(typeLine.contains('instant') || typeLine.contains('sorcery'))) {
    return false;
  }

  return name.contains('ritual') ||
      oracle.contains('until end of turn') ||
      oracle.contains('for each');
}

bool _isStructuralRecoveryUpgrade({
  required Map<String, dynamic> removedCard,
  required Map<String, dynamic> addedCard,
  required String removedRole,
  required String addedRole,
  required String archetype,
  required int cmcDelta,
}) {
  final removedIsLand = ((removedCard['type_line'] as String?) ?? '')
      .toLowerCase()
      .contains('land');
  if (!removedIsLand || removedRole != 'land') return false;

  final addedAllowedRoles = switch (archetype.trim().toLowerCase()) {
    'control' => {'ramp', 'draw', 'removal', 'wipe', 'protection', 'utility'},
    'midrange' => {
        'ramp',
        'draw',
        'removal',
        'creature',
        'protection',
        'utility'
      },
    'aggro' => {'ramp', 'removal', 'creature', 'protection', 'utility'},
    _ => {'ramp', 'draw', 'removal', 'protection', 'utility'},
  };

  if (!addedAllowedRoles.contains(addedRole)) return false;
  if (cmcDelta > 3) return false;

  final addedOracle =
      ((addedCard['oracle_text'] as String?) ?? '').toLowerCase();
  final addedTypeLine =
      ((addedCard['type_line'] as String?) ?? '').toLowerCase();
  if (addedTypeLine.contains('land')) return true;

  return addedOracle.contains('draw') ||
      addedOracle.contains('counter target') ||
      addedOracle.contains('destroy target') ||
      addedOracle.contains('exile target') ||
      addedOracle.contains('add {') ||
      addedOracle.contains('mana of any') ||
      addedTypeLine.contains('creature') ||
      addedTypeLine.contains('artifact');
}

List<String> buildOptimizationRejectionReasons({
  required ValidationReport validationReport,
  required String archetype,
  required double preCurve,
  required double postCurve,
  required String preManaAssessment,
  required String postManaAssessment,
}) {
  final reasons = <String>[];

  if (validationReport.verdict == 'reprovado') {
    reasons.add(
      'Validação automática reprovou as trocas (score ${validationReport.score}/100).',
    );
  }

  if (validationReport.verdict != 'aprovado') {
    reasons.add(
      'A validação final não fechou como "aprovado" (score ${validationReport.score}/100). Optimize só retorna sucesso quando a melhoria é aprovada sem ressalvas.',
    );
  }

  if (validationReport.score < 70) {
    reasons.add(
      'Score final abaixo do mínimo para aceitar a otimização com sucesso (${validationReport.score}/100; mínimo 70).',
    );
  }

  final criticalRoles = _criticalRolesForArchetype(archetype);
  for (final role in criticalRoles) {
    if ((validationReport.functional.roleDelta[role] ?? 0) < 0) {
      reasons.add('A otimização piorou a categoria crítica "$role".');
    }
  }

  if (_isManaAssessmentWorse(preManaAssessment, postManaAssessment)) {
    reasons.add('A otimização piorou a base de mana.');
  }

  if (_manaAssessmentStillBroken(postManaAssessment)) {
    reasons.add(
      'A base de mana continua com problema crítico após a otimização.',
    );
  }

  if (archetype.toLowerCase() == 'aggro' && postCurve > preCurve + 0.05) {
    reasons.add('Aggro não pode ficar mais lento após a otimização.');
  }

  if (validationReport.functional.questionable >= 2) {
    reasons.add(
      'Foram detectadas ${validationReport.functional.questionable} trocas questionáveis.',
    );
  }

  if (_criticRejected(validationReport)) {
    final criticScore =
        (validationReport.critic?['approval_score'] as num?)?.toInt();
    reasons.add(
      'A segunda revisão crítica da IA rejeitou a proposta${criticScore != null ? ' (approval_score $criticScore/100)' : ''}.',
    );
  }

  if (!_hasMaterialImprovement(
    validationReport: validationReport,
    archetype: archetype,
    preManaAssessment: preManaAssessment,
    postManaAssessment: postManaAssessment,
  )) {
    reasons.add(
      'As trocas não demonstraram ganho mensurável suficiente em consistência, mana ou execução do plano.',
    );
  }

  return reasons.toSet().toList();
}

Set<String> _criticalRolesForArchetype(String archetype) {
  return switch (archetype.trim().toLowerCase()) {
    'aggro' => {'creature', 'ramp', 'removal', 'protection'},
    'control' => {'removal', 'draw', 'wipe', 'ramp', 'protection'},
    'midrange' => {'removal', 'ramp', 'draw'},
    _ => {'removal', 'ramp'},
  };
}

bool _looksLikeOffThemeRoleSwap({
  required String removedRole,
  required String addedRole,
  required String archetype,
}) {
  final normalized = archetype.trim().toLowerCase();

  if (normalized == 'aggro' &&
      {'creature', 'removal', 'protection', 'engine'}.contains(removedRole) &&
      !{'creature', 'removal', 'protection', 'engine'}.contains(addedRole)) {
    return true;
  }

  if (normalized == 'control' &&
      {'removal', 'draw', 'wipe', 'protection'}.contains(removedRole) &&
      !{'removal', 'draw', 'wipe', 'protection', 'ramp'}.contains(addedRole)) {
    return true;
  }

  if (normalized == 'midrange' &&
      {'removal', 'ramp', 'draw'}.contains(removedRole) &&
      !{'removal', 'ramp', 'draw', 'creature', 'protection'}
          .contains(addedRole)) {
    return true;
  }

  return false;
}

bool _isManaAssessmentWorse(String before, String after) {
  final beforeLower = before.toLowerCase();
  final afterLower = after.toLowerCase();
  final beforeHasIssue = beforeLower.contains('falta mana');
  final afterHasIssue = afterLower.contains('falta mana');
  return !beforeHasIssue && afterHasIssue;
}

bool _manaAssessmentStillBroken(String assessment) {
  return assessment.toLowerCase().contains('falta mana');
}

bool _criticRejected(ValidationReport validationReport) {
  final critic = validationReport.critic;
  if (critic == null) return false;

  final verdict = critic['verdict']?.toString().trim().toLowerCase() ?? '';
  final approvalScore = (critic['approval_score'] as num?)?.toDouble() ?? 50.0;
  return verdict == 'reprovado' || approvalScore < 60;
}

bool _hasMaterialImprovement({
  required ValidationReport validationReport,
  required String archetype,
  required String preManaAssessment,
  required String postManaAssessment,
}) {
  final monteCarlo = validationReport.monteCarlo;
  final consistencyDelta =
      monteCarlo.after.consistencyScore - monteCarlo.before.consistencyScore;
  final keepableDelta =
      monteCarlo.after.keepableRate - monteCarlo.before.keepableRate;
  final keep7Delta = monteCarlo.afterMulligan.keepAt7Rate -
      monteCarlo.beforeMulligan.keepAt7Rate;
  final screwImprovement =
      monteCarlo.before.screwRate - monteCarlo.after.screwRate;
  final manaImproved = _manaAssessmentStillBroken(preManaAssessment) &&
      !_manaAssessmentStillBroken(postManaAssessment);

  var pressureDelta = 0.0;
  switch (archetype.trim().toLowerCase()) {
    case 'aggro':
    case 'midrange':
      pressureDelta =
          monteCarlo.after.turn2PlayRate - monteCarlo.before.turn2PlayRate;
      break;
    case 'control':
      pressureDelta =
          monteCarlo.after.turn4PlayRate - monteCarlo.before.turn4PlayRate;
      break;
    default:
      pressureDelta =
          monteCarlo.after.turn3PlayRate - monteCarlo.before.turn3PlayRate;
      break;
  }

  final functionalClearlyPositive = validationReport.functional.upgrades > 0 &&
      validationReport.functional.tradeoffs == 0 &&
      validationReport.functional.questionable == 0;

  if (manaImproved) return true;
  if (consistencyDelta > 0) return true;
  if (keepableDelta > 0.01) return true;
  if (keep7Delta > 0.01) return true;
  if (screwImprovement > 0.01) return true;
  if (pressureDelta > 0.01) return true;

  return functionalClearlyPositive &&
      consistencyDelta >= 0 &&
      keepableDelta >= 0 &&
      keep7Delta >= 0 &&
      screwImprovement >= 0 &&
      pressureDelta >= 0;
}

String _classifyFunctionalRole(Map<String, dynamic> card) {
  final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
  final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();

  if (typeLine.contains('land')) return 'land';

  if (oracle.contains('draw') ||
      oracle.contains('look at the top') ||
      (oracle.contains('scry') && oracle.contains('draw'))) {
    return 'draw';
  }

  if (oracle.contains('destroy target') ||
      oracle.contains('exile target') ||
      oracle.contains('counter target') ||
      (oracle.contains('return target') && oracle.contains('to its owner')) ||
      (oracle.contains('deals') &&
          oracle.contains('damage') &&
          (oracle.contains('target creature') ||
              oracle.contains('target planeswalker') ||
              oracle.contains('any target')))) {
    return 'removal';
  }

  if (oracle.contains('destroy all') ||
      oracle.contains('exile all') ||
      (oracle.contains('each creature') && oracle.contains('damage'))) {
    return 'wipe';
  }

  if (oracle.contains('add {') ||
      (oracle.contains('search your library for a') &&
          oracle.contains('land')) ||
      oracle.contains('mana of any') ||
      (typeLine.contains('artifact') && oracle.contains('add'))) {
    return 'ramp';
  }

  if (oracle.contains('search your library') && !oracle.contains('land')) {
    return 'tutor';
  }

  if (oracle.contains('hexproof') ||
      oracle.contains('indestructible') ||
      oracle.contains('shroud') ||
      oracle.contains('ward')) {
    return 'protection';
  }

  if (typeLine.contains('creature')) return 'creature';
  if (typeLine.contains('artifact')) return 'artifact';
  if (typeLine.contains('enchantment')) return 'enchantment';
  if (typeLine.contains('planeswalker')) return 'planeswalker';

  return 'utility';
}

int _getCmc(Map<String, dynamic> card) {
  final cmc = card['cmc'];
  if (cmc == null) return 0;
  if (cmc is int) return cmc;
  if (cmc is double) return cmc.toInt();
  return int.tryParse(cmc.toString()) ?? 0;
}

bool _landLooksColorProducing(Map<String, dynamic> card) {
  final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
  if (!typeLine.contains('land')) return false;

  final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
  final colors = (card['colors'] as List?)?.cast<String>() ?? const <String>[];
  final colorIdentity =
      (card['color_identity'] as List?)?.cast<String>() ?? const <String>[];

  if (colors.isNotEmpty || colorIdentity.isNotEmpty) return true;
  if (oracle.contains('mana of any color') ||
      oracle.contains('mana of any type')) {
    return true;
  }

  return oracle.contains('{w}') ||
      oracle.contains('{u}') ||
      oracle.contains('{b}') ||
      oracle.contains('{r}') ||
      oracle.contains('{g}');
}

Map<String, dynamic> _findCardByName(
  List<Map<String, dynamic>> cards,
  String name,
) {
  for (final card in cards) {
    final cardName = ((card['name'] as String?) ?? '').toLowerCase();
    if (cardName == name.toLowerCase()) {
      return card;
    }
  }
  return <String, dynamic>{};
}
