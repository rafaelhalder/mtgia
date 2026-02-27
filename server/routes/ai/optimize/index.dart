import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/color_identity.dart';
import '../../../lib/card_validation_service.dart';
import '../../../lib/ai/otimizacao.dart';
import '../../../lib/ai/optimization_validator.dart';
import '../../../lib/ai/edhrec_service.dart';
import '../../../lib/http_responses.dart';
import '../../../lib/logger.dart';
import '../../../lib/edh_bracket_policy.dart';

int _optimizeRequestCount = 0;
int _emptySuggestionFallbackTriggeredCount = 0;
int _emptySuggestionFallbackAppliedCount = 0;
int _emptySuggestionFallbackNoCandidateCount = 0;
int _emptySuggestionFallbackNoReplacementCount = 0;

Map<String, dynamic> _buildEmptyFallbackAggregate() {
  final triggered = _emptySuggestionFallbackTriggeredCount;
  final applied = _emptySuggestionFallbackAppliedCount;
  final triggerRate = _optimizeRequestCount > 0
      ? (triggered / _optimizeRequestCount)
      : 0.0;
  final applyRate = triggered > 0 ? (applied / triggered) : 0.0;

  return {
    'request_count': _optimizeRequestCount,
    'triggered_count': triggered,
    'applied_count': applied,
    'no_candidate_count': _emptySuggestionFallbackNoCandidateCount,
    'no_replacement_count': _emptySuggestionFallbackNoReplacementCount,
    'trigger_rate': triggerRate,
    'apply_rate': applyRate,
  };
}

/// Classe para análise de arquétipo do deck
/// Implementa detecção automática baseada em curva de mana, tipos de cartas e cores
class DeckArchetypeAnalyzer {
  final List<Map<String, dynamic>> cards;
  final List<String> colors;

  DeckArchetypeAnalyzer(this.cards, this.colors);

  /// Calcula a curva de mana média (CMC - Converted Mana Cost)
  double calculateAverageCMC() {
    if (cards.isEmpty) return 0.0;

    final nonLandCards = cards.where((c) {
      final typeLine = (c['type_line'] as String?) ?? '';
      return !typeLine.toLowerCase().contains('land');
    }).toList();

    if (nonLandCards.isEmpty) return 0.0;

    double totalCMC = 0;
    for (final card in nonLandCards) {
      totalCMC += (card['cmc'] as num?)?.toDouble() ?? 0.0;
    }

    return totalCMC / nonLandCards.length;
  }

  /// Conta cartas por tipo
  /// Agora conta tipos múltiplos (ex: Artifact Creature conta para ambos)
  Map<String, int> countCardTypes() {
    final counts = <String, int>{
      'creatures': 0,
      'instants': 0,
      'sorceries': 0,
      'enchantments': 0,
      'artifacts': 0,
      'planeswalkers': 0,
      'lands': 0,
      'battles': 0,
    };

    for (final card in cards) {
      final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();

      // Conta TODOS os tipos presentes na carta (não apenas o principal)
      // Isso permite estatísticas mais precisas para arquétipos
      if (typeLine.contains('land')) {
        counts['lands'] = counts['lands']! + 1;
      }
      if (typeLine.contains('creature')) {
        counts['creatures'] = counts['creatures']! + 1;
      }
      if (typeLine.contains('planeswalker')) {
        counts['planeswalkers'] = counts['planeswalkers']! + 1;
      }
      if (typeLine.contains('instant')) {
        counts['instants'] = counts['instants']! + 1;
      }
      if (typeLine.contains('sorcery')) {
        counts['sorceries'] = counts['sorceries']! + 1;
      }
      if (typeLine.contains('artifact')) {
        counts['artifacts'] = counts['artifacts']! + 1;
      }
      if (typeLine.contains('enchantment')) {
        counts['enchantments'] = counts['enchantments']! + 1;
      }
      if (typeLine.contains('battle')) {
        counts['battles'] = counts['battles']! + 1;
      }
    }

    return counts;
  }

  /// Detecta o arquétipo baseado nas estatísticas do deck
  /// Retorna: 'aggro', 'midrange', 'control', 'combo', 'voltron', 'tribal', 'stax', 'aristocrats'
  String detectArchetype() {
    final avgCMC = calculateAverageCMC();
    final typeCounts = countCardTypes();
    final totalNonLands = cards.length - (typeCounts['lands'] ?? 0);

    if (totalNonLands == 0) return 'unknown';

    final creatureRatio = (typeCounts['creatures'] ?? 0) / totalNonLands;
    final instantSorceryRatio =
        ((typeCounts['instants'] ?? 0) + (typeCounts['sorceries'] ?? 0)) /
            totalNonLands;
    final enchantmentRatio = (typeCounts['enchantments'] ?? 0) / totalNonLands;

    // Regras de classificação baseadas em heurísticas de MTG

    // Aggro: CMC baixo (< 2.5), muitas criaturas (> 40%)
    if (avgCMC < 2.5 && creatureRatio > 0.4) {
      return 'aggro';
    }

    // Control: CMC alto (> 3.0), poucos criaturas (< 25%), muitos instants/sorceries
    if (avgCMC > 3.0 && creatureRatio < 0.25 && instantSorceryRatio > 0.35) {
      return 'control';
    }

    // Combo: Muitos instants/sorceries (> 40%) e poucos criaturas
    if (instantSorceryRatio > 0.4 && creatureRatio < 0.3) {
      return 'combo';
    }

    // Stax/Enchantress: Muitos enchantments (> 30%)
    if (enchantmentRatio > 0.3) {
      return 'stax';
    }

    // Midrange: Valor médio de CMC e equilíbrio de tipos
    if (avgCMC >= 2.5 &&
        avgCMC <= 3.5 &&
        creatureRatio >= 0.25 &&
        creatureRatio <= 0.45) {
      return 'midrange';
    }

    // Default to midrange se não se encaixar em nenhuma categoria
    return 'midrange';
  }

  /// Analisa a base de mana (Devotion vs Sources)
  Map<String, dynamic> analyzeManaBase() {
    final manaSymbols = {'W': 0, 'U': 0, 'B': 0, 'R': 0, 'G': 0};
    final landSources = {'W': 0, 'U': 0, 'B': 0, 'R': 0, 'G': 0, 'Any': 0};

    // 1. Contar símbolos de mana nas cartas (Devotion)
    for (final card in cards) {
      final manaCost = (card['mana_cost'] as String?) ?? '';
      for (final color in manaSymbols.keys) {
        manaSymbols[color] =
            manaSymbols[color]! + manaCost.split(color).length - 1;
      }
    }

    // 2. Contar fontes de mana nos terrenos (Heurística melhorada via Oracle Text)
    for (final card in cards) {
      final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
      if (typeLine.contains('land')) {
        final cardColors = (card['colors'] as List?)?.cast<String>() ?? [];
        final oracleText =
            ((card['oracle_text'] as String?) ?? '').toLowerCase();

        // Detecção de Rainbow Lands via texto (sem hardcode de nomes)
        if (oracleText.contains('add one mana of any color') ||
            oracleText.contains('add one mana of any type')) {
          landSources['Any'] = landSources['Any']! + 1;
        }
        // Detecção de Fetch Lands (simplificada)
        else if (oracleText.contains('search your library for') &&
            (oracleText.contains('plains') ||
                oracleText.contains('island') ||
                oracleText.contains('swamp') ||
                oracleText.contains('mountain') ||
                oracleText.contains('forest'))) {
          // Fetch lands contam como "Any" das cores que buscam, mas para simplificar a heurística
          // e evitar complexidade excessiva, vamos considerar como "Any" se buscar 2+ tipos,
          // ou contar especificamente se for simples.
          // Por segurança, Fetchs genéricas contam como Any no contexto de correção de cor.
          landSources['Any'] = landSources['Any']! + 1;
        } else if (cardColors.isEmpty) {
          // Terrenos incolores que não são rainbow nem fetch (ex: Reliquary Tower)
          // Não contam para cores.
        } else {
          for (final color in cardColors) {
            if (landSources.containsKey(color)) {
              landSources[color] = landSources[color]! + 1;
            }
          }
        }
      }
    }

    return {
      'symbols': manaSymbols,
      'sources': landSources,
      'assessment': _assessManaBase(manaSymbols, landSources),
    };
  }

  String _assessManaBase(Map<String, int> symbols, Map<String, int> sources) {
    if (symbols.isEmpty) return 'N/A';
    final totalSymbols = symbols.values.fold<int>(0, (a, b) => a + b);
    if (totalSymbols == 0) return 'N/A';

    final issues = <String>[];

    symbols.forEach((color, count) {
      if (count > 0) {
        final percent = count / totalSymbols;
        final sourceCount = sources[color]! + sources['Any']!;

        // Regra de Frank Karsten (simplificada):
        // Para castar consistentemente spells de uma cor, você precisa de X fontes.
        // Se a cor representa > 30% dos símbolos, precisa de pelo menos 15 fontes.
        if (percent > 0.30 && sourceCount < 15) {
          issues.add('Falta mana $color (Tem $sourceCount fontes, ideal > 15)');
        } else if (percent > 0.10 && sourceCount < 10) {
          issues.add('Falta mana $color (Tem $sourceCount fontes, ideal > 10)');
        }
      }
    });

    if (issues.isEmpty) return 'Base de mana equilibrada';
    return issues.join('. ');
  }

  /// Gera descrição da análise do deck
  Map<String, dynamic> generateAnalysis() {
    final avgCMC = calculateAverageCMC();
    final typeCounts = countCardTypes();
    final detectedArchetype = detectArchetype();
    final manaAnalysis = analyzeManaBase();

    // Calcular total_cards considerando quantity
    int totalCards = 0;
    for (final card in cards) {
      totalCards += (card['quantity'] as int?) ?? 1;
    }

    return {
      'detected_archetype': detectedArchetype,
      'average_cmc': avgCMC.toStringAsFixed(2),
      'type_distribution': typeCounts,
      'total_cards': totalCards,
      'mana_curve_assessment': _assessManaCurve(avgCMC, detectedArchetype),
      'mana_base_assessment': manaAnalysis['assessment'],
      'archetype_confidence':
          _calculateConfidence(avgCMC, typeCounts, detectedArchetype),
    };
  }

  String _assessManaCurve(double avgCMC, String archetype) {
    switch (archetype) {
      case 'aggro':
        if (avgCMC > 2.5)
          return 'ALERTA: Curva muito alta para Aggro. Ideal: < 2.5';
        if (avgCMC < 1.8) return 'BOA: Curva agressiva ideal';
        return 'OK: Curva aceitável para Aggro';
      case 'control':
        if (avgCMC < 2.5)
          return 'ALERTA: Curva muito baixa para Control. Ideal: > 3.0';
        return 'BOA: Curva adequada para Control';
      case 'midrange':
        if (avgCMC < 2.3 || avgCMC > 3.8)
          return 'ALERTA: Curva fora do ideal para Midrange (2.5-3.5)';
        return 'BOA: Curva equilibrada para Midrange';
      default:
        return 'OK: Curva dentro de parâmetros aceitáveis';
    }
  }

  String _calculateConfidence(
      double avgCMC, Map<String, int> counts, String archetype) {
    // Confidence baseada em quão bem o deck se encaixa no arquétipo
    final totalNonLands = cards.length - (counts['lands'] ?? 0);
    if (totalNonLands < 20) return 'baixa';

    final creatureRatio = (counts['creatures'] ?? 0) / totalNonLands;

    switch (archetype) {
      case 'aggro':
        if (avgCMC < 2.2 && creatureRatio > 0.5) return 'alta';
        if (avgCMC < 2.8 && creatureRatio > 0.35) return 'média';
        return 'baixa';
      case 'control':
        if (avgCMC > 3.2 && creatureRatio < 0.2) return 'alta';
        return 'média';
      default:
        return 'média';
    }
  }
}

class DeckThemeProfile {
  final String theme;
  final String confidence;
  final double matchScore;
  final List<String> coreCards;

  const DeckThemeProfile({
    required this.theme,
    required this.confidence,
    required this.matchScore,
    required this.coreCards,
  });

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'confidence': confidence,
        'match_score': matchScore,
        'core_cards': coreCards,
      };
}

Future<DeckThemeProfile> _detectThemeProfile(
  List<Map<String, dynamic>> cards, {
  required List<String> commanders,
  required Pool pool,
}) async {
  int qty(Map<String, dynamic> c) => (c['quantity'] as int?) ?? 1;
  
  // Buscar insights do meta para todas as cartas do deck (batch query)
  final cardNames = cards.map((c) => c['name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
  final metaInsights = <String, Map<String, dynamic>>{};
  
  if (cardNames.isNotEmpty) {
    try {
      final result = await pool.execute(
        Sql.named('SELECT card_name, usage_count, common_archetypes, learned_role FROM card_meta_insights WHERE LOWER(card_name) IN (${List.generate(cardNames.length, (i) => 'LOWER(@name$i)').join(', ')})'),
        parameters: {for (var i = 0; i < cardNames.length; i++) 'name$i': cardNames[i]},
      );
      for (final row in result) {
        final name = (row[0] as String).toLowerCase();
        metaInsights[name] = {
          'usage_count': row[1] as int? ?? 0,
          'common_archetypes': row[2] is List ? (row[2] as List).cast<String>() : <String>[],
          'learned_role': row[3] as String? ?? '',
        };
      }
    } catch (e) {
      // Se falhar, continua com heurísticas
      print('[_detectThemeProfile] Falha ao buscar meta insights: $e');
    }
  }

  final commanderLower = commanders.map((e) => e.toLowerCase()).toSet();

  var totalNonLands = 0;
  var artifactCount = 0;
  var enchantmentCount = 0;
  var instantSorceryCount = 0;
  var tokenReferences = 0;
  var reanimatorReferences = 0;
  var aristocratReferences = 0;
  var voltronReferences = 0;
  var landfallReferences = 0;
  var wheelReferences = 0;
  var staxReferences = 0;

  // Tribal: track creature subtypes for tribe concentration
  final creatureSubtypes = <String, int>{};
  
  // Armazenar dados das cartas para análise de impacto posterior
  final cardData = <Map<String, dynamic>>[];

  // PRIMEIRA PASSAGEM: contar temas e coletar dados
  for (final c in cards) {
    final name = (c['name'] as String?) ?? '';
    if (name.isEmpty) continue;
    final typeLine = ((c['type_line'] as String?) ?? '').toLowerCase();
    final oracle = ((c['oracle_text'] as String?) ?? '').toLowerCase();
    final q = qty(c);

    final isLand = typeLine.contains('land');
    if (!isLand) totalNonLands += q;

    // Guardar para análise de impacto
    cardData.add({
      'name': name,
      'typeLine': typeLine,
      'oracle': oracle,
      'quantity': q,
      'isLand': isLand,
    });

    // --- Tipo-based counts ---
    if (!isLand && typeLine.contains('artifact')) artifactCount += q;
    if (!isLand && typeLine.contains('enchantment')) enchantmentCount += q;
    if (!isLand &&
        (typeLine.contains('instant') || typeLine.contains('sorcery'))) {
      instantSorceryCount += q;
    }

    // --- Token theme ---
    if (oracle.contains('create') && oracle.contains('token')) {
      tokenReferences += q;
    }
    if (oracle.contains('populate') ||
        (oracle.contains('whenever') && oracle.contains('token'))) {
      tokenReferences += q;
    }

    // --- Reanimator theme ---
    if ((oracle.contains('return') && oracle.contains('from') && oracle.contains('graveyard')) ||
        oracle.contains('reanimate') ||
        oracle.contains('unearth') ||
        (oracle.contains('put') && oracle.contains('graveyard') && oracle.contains('onto the battlefield'))) {
      reanimatorReferences += q;
    }

    // --- Aristocrats theme (sacrifice + death triggers) ---
    if ((oracle.contains('sacrifice') && (oracle.contains('whenever') || oracle.contains('you may'))) ||
        (oracle.contains('when') && oracle.contains('dies')) ||
        oracle.contains('drain')) {
      aristocratReferences += q;
    }

    // --- Voltron theme (auras, equipment, commander damage focus) ---
    if (typeLine.contains('equipment') ||
        (typeLine.contains('aura') && oracle.contains('enchant creature')) ||
        oracle.contains('double strike') ||
        oracle.contains('hexproof') ||
        (oracle.contains('equipped creature') && oracle.contains('+')) ||
        (oracle.contains('enchanted creature') && oracle.contains('+'))) {
      voltronReferences += q;
    }

    // --- Landfall theme ---
    if (oracle.contains('landfall') ||
        (oracle.contains('whenever') && oracle.contains('land') && oracle.contains('enters'))) {
      landfallReferences += q;
    }

    // --- Wheels theme (discard hand + draw) ---
    if ((oracle.contains('each player') && oracle.contains('discards') && oracle.contains('draws')) ||
        (oracle.contains('discard') && oracle.contains('hand') && oracle.contains('draw')) ||
        (oracle.contains('whenever') && oracle.contains('draws a card'))) {
      wheelReferences += q;
    }

    // --- Stax theme (tax, restrict, slow down) ---
    if (oracle.contains('each opponent') && (oracle.contains('can\'t') || oracle.contains('pays') || oracle.contains('sacrifices')) ||
        (oracle.contains('nonland permanent') && oracle.contains('doesn\'t untap')) ||
        (oracle.contains('players can\'t') && (oracle.contains('cast') || oracle.contains('search')))) {
      staxReferences += q;
    }

    // --- Tribal: track creature subtypes ---
    if (typeLine.contains('creature')) {
      final dashIndex = typeLine.indexOf('—');
      if (dashIndex != -1) {
        final subtypes = typeLine.substring(dashIndex + 1).trim().split(RegExp(r'\s+'));
        for (final st in subtypes) {
          if (st.isNotEmpty && st != 'creature') {
            creatureSubtypes[st] = (creatureSubtypes[st] ?? 0) + q;
          }
        }
      }
    }
  }

  // Determine dominant creature tribe
  String? dominantTribe;
  int tribalCount = 0;
  if (creatureSubtypes.isNotEmpty) {
    final sorted = creatureSubtypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    dominantTribe = sorted.first.key;
    tribalCount = sorted.first.value;
  }

  String theme;
  double score;

  if (totalNonLands <= 0) {
    theme = 'generic';
    score = 0.0;
  } else {
    // Score each theme and pick the strongest
    final themeScores = <String, double>{
      'artifacts': artifactCount / totalNonLands >= 0.30
          ? artifactCount / totalNonLands
          : 0.0,
      'enchantments': enchantmentCount / totalNonLands >= 0.30
          ? enchantmentCount / totalNonLands
          : 0.0,
      'spellslinger': instantSorceryCount / totalNonLands >= 0.35
          ? instantSorceryCount / totalNonLands
          : 0.0,
      'tokens': tokenReferences / totalNonLands >= 0.15
          ? tokenReferences / totalNonLands
          : 0.0,
      'reanimator': reanimatorReferences / totalNonLands >= 0.12
          ? reanimatorReferences / totalNonLands
          : 0.0,
      'aristocrats': aristocratReferences / totalNonLands >= 0.12
          ? aristocratReferences / totalNonLands
          : 0.0,
      'voltron': voltronReferences / totalNonLands >= 0.15
          ? voltronReferences / totalNonLands
          : 0.0,
      'landfall': landfallReferences / totalNonLands >= 0.10
          ? landfallReferences / totalNonLands
          : 0.0,
      'wheels': wheelReferences / totalNonLands >= 0.10
          ? wheelReferences / totalNonLands
          : 0.0,
      'stax': staxReferences / totalNonLands >= 0.10
          ? staxReferences / totalNonLands
          : 0.0,
      'tribal': tribalCount / totalNonLands >= 0.25
          ? tribalCount / totalNonLands
          : 0.0,
    };

    // Pick highest scoring theme (sem reduzir lista vazia)
    MapEntry<String, double>? best;
    for (final entry in themeScores.entries) {
      if (best == null || entry.value > best.value) {
        best = entry;
      }
    }

    if (best != null && best.value > 0.0) {
      theme = best.key == 'tribal' && dominantTribe != null
          ? 'tribal-$dominantTribe'
          : best.key;
      score = best.value;
    } else {
      theme = 'generic';
      score = 0.0;
    }
  }

  final confidence = score >= 0.35
      ? 'alta'
      : (score >= 0.20 ? 'média' : (score >= 0.10 ? 'baixa' : 'baixa'));

  // SEGUNDA PASSAGEM: Análise de IMPACTO para identificar core_cards
  // Core = cartas que, se removidas, enfraquecem significativamente o tema
  final core = <String, int>{}; // name -> impact score

  for (final c in cardData) {
    final name = c['name'] as String;
    final nameLower = name.toLowerCase();
    final typeLine = c['typeLine'] as String;
    final oracle = c['oracle'] as String;
    final q = c['quantity'] as int;
    final isLand = c['isLand'] as bool;

    if (isLand) continue;

    var impactScore = 0;

    // 0. META INSIGHTS: dados reais de uso em decks competitivos
    final insight = metaInsights[nameLower];
    if (insight != null) {
      final usageCount = insight['usage_count'] as int;
      final archetypes = insight['common_archetypes'] as List<String>;
      final learnedRole = insight['learned_role'] as String;
      
      // Uso alto no meta = carta forte (escala: clamped 5-40)
      if (usageCount > 0) {
        impactScore += (usageCount * 1.0).clamp(5, 40).round();
      }
      
      // Se a carta é comum no arquétipo que o deck está usando = boost
      final themeSimplified = theme.replaceAll('tribal-', '');
      for (final arch in archetypes) {
        if (arch.contains(themeSimplified) || themeSimplified.contains(arch)) {
          impactScore += 20;
          break;
        }
      }
      
      // Role específico que combina com o tema
      if ((theme == 'spellslinger' && learnedRole.contains('counter')) ||
          (theme == 'reanimator' && learnedRole.contains('reanimate')) ||
          (theme == 'artifacts' && learnedRole.contains('artifact')) ||
          (theme.startsWith('tribal') && learnedRole.contains('tribal'))) {
        impactScore += 15;
      }
    }

    // 1. Comandantes = sempre core (impacto máximo)
    if (commanderLower.contains(nameLower)) {
      impactScore += 100;
    }

    // 2. 4 cópias = usuário priorizou esta carta
    if (q >= 4) {
      impactScore += 15;
    }

    // 3. LORD/ANTHEM: dá bonus para OUTROS do mesmo tipo
    // Detecta padrões como "other X get +1/+1", "X you control get +1/+1"
    if (oracle.contains('get +') || oracle.contains('gets +')) {
      // Verifica se menciona o tipo tribal dominante
      if (dominantTribe != null && oracle.contains(dominantTribe)) {
        impactScore += 40; // Lord do tribal = alto impacto
      }
      // Ou se é um anthem genérico para criaturas
      if (oracle.contains('creatures you control') && oracle.contains('+')) {
        impactScore += 25;
      }
    }

    // 4. PAYOFF: carta que escala com o tema
    // Tokens: "whenever a token", "for each token"
    if (theme.contains('token')) {
      if (oracle.contains('whenever') && oracle.contains('token')) {
        impactScore += 35;
      }
      if (oracle.contains('for each') && oracle.contains('token')) {
        impactScore += 35;
      }
      if (oracle.contains('double') && oracle.contains('token')) {
        impactScore += 50; // Doubling Season effect
      }
    }

    // Aristocrats: "whenever a creature dies", "whenever you sacrifice"
    if (theme == 'aristocrats') {
      if (oracle.contains('whenever') && oracle.contains('dies')) {
        impactScore += 35;
      }
      if (oracle.contains('whenever') && oracle.contains('sacrifice')) {
        impactScore += 35;
      }
      if (oracle.contains('drain') || oracle.contains('each opponent loses')) {
        impactScore += 30;
      }
    }

    // Reanimator: "return from graveyard", "reanimate"
    if (theme == 'reanimator') {
      if (oracle.contains('return') && oracle.contains('graveyard') && oracle.contains('battlefield')) {
        impactScore += 35;
      }
    }

    // Spellslinger: "whenever you cast", "copy", "storm"
    if (theme == 'spellslinger') {
      if (oracle.contains('whenever you cast') && (oracle.contains('instant') || oracle.contains('sorcery'))) {
        impactScore += 35;
      }
      if (oracle.contains('copy') && oracle.contains('spell')) {
        impactScore += 30;
      }
      if (oracle.contains('storm')) {
        impactScore += 40;
      }
    }

    // Landfall: "landfall", "whenever a land enters"
    if (theme == 'landfall') {
      if (oracle.contains('landfall')) {
        impactScore += 35;
      }
    }

    // Voltron: equipment matters, aura matters
    if (theme == 'voltron') {
      if (oracle.contains('equipped creature') && oracle.contains('+')) {
        impactScore += 30;
      }
      if (oracle.contains('enchanted creature') && oracle.contains('+')) {
        impactScore += 30;
      }
      if (oracle.contains('double strike') || oracle.contains('hexproof')) {
        impactScore += 25;
      }
    }

    // 5. TRIBAL: carta É do tipo dominante + tem habilidade tribal
    if (theme.startsWith('tribal-') && dominantTribe != null) {
      final isTribalType = typeLine.contains(dominantTribe);
      final mentionsTribe = oracle.contains(dominantTribe);
      
      if (isTribalType && mentionsTribe) {
        // É do tipo E menciona o tipo no texto = alto valor tribal
        impactScore += 35;
      } else if (mentionsTribe && !isTribalType) {
        // Não é do tipo mas menciona = suporte tribal (ex: Kindred spells)
        impactScore += 25;
      }
      
      // Cartas que dizem "choose a creature type" ou similar
      if (oracle.contains('creature type') && oracle.contains('choose')) {
        impactScore += 20;
      }
    }

    // 6. Artifacts matter
    if (theme == 'artifacts') {
      if (oracle.contains('whenever') && oracle.contains('artifact')) {
        impactScore += 30;
      }
      if (oracle.contains('for each artifact')) {
        impactScore += 35;
      }
    }

    // 7. Enchantments matter
    if (theme == 'enchantments') {
      if (oracle.contains('whenever') && oracle.contains('enchantment')) {
        impactScore += 30;
      }
      if (oracle.contains('constellation')) {
        impactScore += 35;
      }
    }

    // 8. Wheels
    if (theme == 'wheels') {
      if (oracle.contains('whenever') && oracle.contains('draws')) {
        impactScore += 35;
      }
      if (oracle.contains('discard') && oracle.contains('hand') && oracle.contains('draw')) {
        impactScore += 40;
      }
    }

    // 9. Stax: key pieces
    if (theme == 'stax') {
      if (oracle.contains('can\'t') || oracle.contains('doesn\'t untap')) {
        impactScore += 30;
      }
    }

    // Threshold: só adiciona ao core se impacto >= 25
    if (impactScore >= 25) {
      core[name] = impactScore;
    }
  }

  // Ordenar core por impacto (maior primeiro), pegar top 10
  final sortedCore = core.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  
  final coreCards = sortedCore.take(10).map((e) => e.key).toList();

  return DeckThemeProfile(
    theme: theme,
    confidence: confidence,
    matchScore: score,
    coreCards: coreCards,
  );
}

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return methodNotAllowed();
  }

  try {
    String? userId;
    try {
      userId = context.read<String>();
    } catch (_) {
      userId = null;
    }

    final body = await context.request.json() as Map<String, dynamic>;
    final deckId = body['deck_id'] as String?;
    final archetype = body['archetype'] as String?;
    final bracketRaw = body['bracket'];
    final parsedBracket =
      bracketRaw is int ? bracketRaw : int.tryParse('${bracketRaw ?? ''}');
    final parsedKeepTheme = body['keep_theme'] as bool?;
    final hasBracketOverride = body.containsKey('bracket');
    final hasKeepThemeOverride = body.containsKey('keep_theme');

    _optimizeRequestCount++;

    if (deckId == null || archetype == null) {
      return badRequest('deck_id and archetype are required');
    }

    // 1. Fetch Deck Data
    final pool = context.read<Pool>();

    // Memória de preferências do usuário (se autenticado):
    // aplica default somente quando o request não enviar override explícito.
    final userPreferences = await _loadUserAiPreferences(
      pool: pool,
      userId: userId,
    );
    final bracket = hasBracketOverride
      ? parsedBracket
      : (userPreferences['preferred_bracket'] as int? ?? parsedBracket);
    final keepTheme = hasKeepThemeOverride
      ? (parsedKeepTheme ?? true)
      : (userPreferences['keep_theme_default'] as bool? ?? true);

    // Get Deck Info
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format FROM decks WHERE id = @id'),
      parameters: {'id': deckId},
    );

    if (deckResult.isEmpty) {
      return notFound('Deck not found');
    }

    final deckRow = deckResult[0];
    final deckFormatRaw = deckRow[1] as String?;
    final deckFormat = (deckFormatRaw ?? '').toLowerCase().trim();
    if (deckFormat.isEmpty) {
      return internalServerError('Deck format is missing');
    }

    // Get Cards with CMC for analysis
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, dc.is_commander, dc.quantity, c.type_line, c.mana_cost, c.colors,
               COALESCE(
                 (SELECT SUM(
                   CASE 
                     WHEN m[1] ~ '^[0-9]+\$' THEN m[1]::int
                     WHEN m[1] IN ('W','U','B','R','G','C') THEN 1
                     WHEN m[1] = 'X' THEN 0
                     ELSE 1
                   END
                 ) FROM regexp_matches(c.mana_cost, '\\{([^}]+)\\}', 'g') AS m(m)),
                 0
               ) as cmc,
               c.oracle_text,
               c.color_identity,
               c.id::text
        FROM deck_cards dc 
        JOIN cards c ON c.id = dc.card_id 
        WHERE dc.deck_id = @id
      '''),
      parameters: {'id': deckId},
    );

    final deckSignature = _buildDeckSignature(cardsResult);
    final cacheKey = _buildOptimizeCacheKey(
      deckId: deckId,
      archetype: archetype,
      bracket: bracket,
      keepTheme: keepTheme,
      deckSignature: deckSignature,
    );

    final cachedResponse = await _loadOptimizeCache(
      pool: pool,
      cacheKey: cacheKey,
    );
    if (cachedResponse != null) {
      cachedResponse['cache'] = {
        'hit': true,
        'cache_key': cacheKey,
      };
      cachedResponse['preferences'] = {
        'memory_applied': !hasBracketOverride || !hasKeepThemeOverride,
        'keep_theme': keepTheme,
        'preferred_bracket': userPreferences['preferred_bracket'],
      };
      return Response.json(body: cachedResponse);
    }

    final commanders = <String>[];
    final otherCards = <String>[];
    final allCardData = <Map<String, dynamic>>[];
    final deckColors = <String>{};
    final commanderColorIdentity = <String>{};
    var currentTotalCards = 0;
    final originalCountsById = <String, int>{};

    for (final row in cardsResult) {
      final name = row[0] as String;
      final isCmdr = row[1] as bool;
      final quantity = (row[2] as int?) ?? 1;
      final typeLine = (row[3] as String?) ?? '';
      final manaCost = (row[4] as String?) ?? '';
      final colors = (row[5] as List?)?.cast<String>() ?? [];
      final cmc = (row[6] as num?)?.toDouble() ?? 0.0;
      final oracleText = (row[7] as String?) ?? '';
      final colorIdentity =
          (row[8] as List?)?.cast<String>() ?? const <String>[];
      final cardId = row[9] as String;

      currentTotalCards += quantity;
      originalCountsById[cardId] = (originalCountsById[cardId] ?? 0) + quantity;

      // Coletar cores do deck
      deckColors.addAll(colors);

      final cardData = {
        'name': name,
        'type_line': typeLine,
        'mana_cost': manaCost,
        'colors': colors,
        'color_identity': colorIdentity,
        'cmc': cmc,
        'is_commander': isCmdr,
        'oracle_text': oracleText,
        'quantity': quantity,
        'card_id': cardId,
      };

      allCardData.add(cardData);

      if (isCmdr) {
        commanders.add(name);
        commanderColorIdentity.addAll(
          normalizeColorIdentity(
              colorIdentity.isNotEmpty ? colorIdentity : colors),
        );
      } else {
        // Incluir texto da carta para a IA analisar sinergia real
        // Truncar texto muito longo para economizar tokens
        final cleanText = oracleText.replaceAll('\n', ' ').trim();
        final truncatedText = cleanText.length > 150
            ? '${cleanText.substring(0, 147)}...'
            : cleanText;

        if (truncatedText.isNotEmpty) {
          otherCards.add('$name (Type: $typeLine, Text: $truncatedText)');
        } else {
          otherCards.add('$name (Type: $typeLine)');
        }
      }
    }

    // 1.5 Análise de Arquétipo e Tema do Deck
    final analyzer = DeckArchetypeAnalyzer(allCardData, deckColors.toList());
    final deckAnalysis = analyzer.generateAnalysis();
    final themeProfile = await _detectThemeProfile(
      allCardData,
      commanders: commanders,
      pool: pool,
    );

    // Usar arquétipo passado pelo usuário
    final targetArchetype = archetype;

    // 2. Otimização via DeckOptimizerService (IA + RAG)
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      // Mock response for development
      return Response.json(body: {
        'removals': ['Basic Land', 'Weak Card'],
        'additions': ['Sol Ring', 'Arcane Signet'],
        'reasoning':
            'Mock optimization (No API Key): Adicionando staples recomendados.',
        'deck_analysis': deckAnalysis,
        'constraints': {
          'keep_theme': keepTheme,
        },
        'theme': themeProfile.toJson(),
        'is_mock': true
      });
    }

    final optimizer = DeckOptimizerService(apiKey, db: pool);

    // Preparar dados para o otimizador
    final deckData = {
      'cards': allCardData,
      'colors': deckColors.toList(),
    };

    Map<String, dynamic> jsonResponse;
    try {
      final maxTotal =
          deckFormat == 'commander' ? 100 : (deckFormat == 'brawl' ? 60 : null);

      // Modo auto: se o deck está incompleto e é Commander/Brawl, completar primeiro.
      if (maxTotal != null && currentTotalCards < maxTotal) {
        if (commanders.isEmpty) {
          return Response.json(
            statusCode: HttpStatus.badRequest,
            body: {
              'error':
                  'Selecione um comandante antes de completar um deck $deckFormat.'
            },
          );
        }

        // Loop seguro: simula adições em um deck virtual e re-chama a IA até fechar.
        final maxIterations = 4;
        final virtualDeck = List<Map<String, dynamic>>.from(allCardData);
        final virtualCountsById = Map<String, int>.from(originalCountsById);
        final virtualCountsByName = <String, int>{};
        for (final card in virtualDeck) {
          final name = ((card['name'] as String?) ?? '').trim().toLowerCase();
          if (name.isEmpty) continue;
          final quantity = (card['quantity'] as int?) ?? 1;
          virtualCountsByName[name] = (virtualCountsByName[name] ?? 0) + quantity;
        }

        final addedCountsById = <String, int>{};
        final blockedByBracketAll = <Map<String, dynamic>>[];
        final filteredByIdentityAll = <String>[];
        final invalidAll = <String>[];
        final aiSuggestedNames = <String>{};

        var aiStageUsed = false;
        var deterministicStageUsed = false;
        var guaranteedBasicsStageUsed = false;

        var iterations = 0;
        var virtualTotal = currentTotalCards;
        while (iterations < maxIterations && virtualTotal < maxTotal) {
          iterations++;
          final missingNow = maxTotal - virtualTotal;

          Map<String, dynamic> iterResponse;
          try {
            iterResponse = await optimizer.completeDeck(
              deckData: {
                'cards': virtualDeck,
                'colors': deckColors.toList(),
              },
              commanders: commanders,
              targetArchetype: targetArchetype,
              targetAdditions: missingNow,
              bracket: bracket,
              keepTheme: keepTheme,
              detectedTheme: themeProfile.theme,
              coreCards: themeProfile.coreCards,
            );
          } catch (e) {
            Log.w(
              'Falha no completeDeck da IA; aplicando fallback determinístico. '
              'iteration=$iterations missing=$missingNow error=$e',
            );
            break;
          }

          final rawAdditions =
              (iterResponse['additions'] as List?)?.cast<String>() ?? const [];
          if (rawAdditions.isEmpty) break;
            aiStageUsed = true;

          // Sanitiza
          final sanitized =
              rawAdditions.map(CardValidationService.sanitizeCardName).toList();
            aiSuggestedNames.addAll(
            sanitized
              .where((name) => name.trim().isNotEmpty)
              .map((name) => name.trim().toLowerCase()),
            );

          // Valida existência no DB
          final validationService = CardValidationService(pool);
          final validation =
              await validationService.validateCardNames(sanitized);
          invalidAll.addAll(
              (validation['invalid'] as List?)?.cast<String>() ?? const []);

          final validList =
              (validation['valid'] as List).cast<Map<String, dynamic>>();
          final validNames =
              validList.map((v) => (v['name'] as String)).toList();
          if (validNames.isEmpty) break;

          // Carrega dados completos para filtro (type/oracle/colors/identity/id)
          final additionsInfoResult = await pool.execute(
            Sql.named('''
              SELECT id::text, name, type_line, oracle_text, colors, color_identity
              FROM cards
              WHERE name = ANY(@names)
            '''),
            parameters: {'names': validNames},
          );
          if (additionsInfoResult.isEmpty) break;

          final candidates = additionsInfoResult.map((r) {
            final id = r[0] as String;
            final name = r[1] as String;
            final typeLine = r[2] as String? ?? '';
            final oracle = r[3] as String? ?? '';
            final colors = (r[4] as List?)?.cast<String>() ?? const <String>[];
            final identity =
                (r[5] as List?)?.cast<String>() ?? const <String>[];
            return {
              'card_id': id,
              'name': name,
              'type_line': typeLine,
              'oracle_text': oracle,
              'colors': colors,
              'color_identity': identity,
            };
          }).toList();

          // Filtro por identidade do comandante
          final identityAllowed = <Map<String, dynamic>>[];
          for (final c in candidates) {
            final identity = ((c['color_identity'] as List).cast<String>());
            final colors = ((c['colors'] as List).cast<String>());
            final ok = isWithinCommanderIdentity(
              cardIdentity: identity.isNotEmpty ? identity : colors,
              commanderIdentity: commanderColorIdentity,
            );
            if (!ok) {
              filteredByIdentityAll.add(c['name'] as String);
              continue;
            }
            identityAllowed.add(c);
          }
          if (identityAllowed.isEmpty) break;

          // Filtro de bracket (intermediário)
          final bracketAllowed = <Map<String, dynamic>>[];
          if (bracket != null) {
            final decision = applyBracketPolicyToAdditions(
              bracket: bracket,
              currentDeckCards: virtualDeck,
              additionsCardsData: identityAllowed.map((c) {
                return {
                  'name': c['name'],
                  'type_line': c['type_line'],
                  'oracle_text': c['oracle_text'],
                  'quantity': 1,
                };
              }),
            );
            blockedByBracketAll.addAll(decision.blocked);
            final allowedSet =
                decision.allowed.map((e) => e.toLowerCase()).toSet();
            for (final c in identityAllowed) {
              final n = (c['name'] as String).toLowerCase();
              if (allowedSet.contains(n)) bracketAllowed.add(c);
            }
          } else {
            bracketAllowed.addAll(identityAllowed);
          }
          if (bracketAllowed.isEmpty) break;

          // Aplica no deck virtual respeitando regras de cópias:
          // - non-basic: 1 cópia (não adiciona se já existe)
          // - basic: pode repetir
          var addedThisIter = 0;
          for (final c in bracketAllowed) {
            if (virtualTotal >= maxTotal) break;
            final id = c['card_id'] as String;
            final name = c['name'] as String;
            final typeLine = (c['type_line'] as String).toLowerCase();
            final isBasic = typeLine.contains('basic land');
            final nameLower = name.toLowerCase();
            final maxCopies = _maxCopiesForFormat(
              deckFormat: deckFormat,
              typeLine: typeLine,
              name: name,
            );

            if (!isBasic && (virtualCountsByName[nameLower] ?? 0) >= maxCopies) {
              continue;
            }

            if ((virtualCountsById[id] ?? 0) > 0 && (virtualCountsByName[nameLower] ?? 0) >= maxCopies) {
              continue;
            }

            virtualCountsById[id] = (virtualCountsById[id] ?? 0) + 1;
            virtualCountsByName[nameLower] = (virtualCountsByName[nameLower] ?? 0) + 1;
            addedCountsById[id] = (addedCountsById[id] ?? 0) + 1;
            virtualTotal += 1;
            addedThisIter += 1;

            final existingIndex = virtualDeck.indexWhere(
              (e) => (e['card_id'] as String?) == id,
            );
            if (existingIndex == -1) {
              virtualDeck.add({
                'card_id': id,
                'name': name,
                'type_line': c['type_line'],
                'oracle_text': c['oracle_text'],
                'colors': c['colors'],
                'color_identity': c['color_identity'],
                'quantity': 1,
                'is_commander': false,
                'mana_cost': '',
                'cmc': 0.0,
              });
            } else {
              final existing = virtualDeck[existingIndex];
              virtualDeck[existingIndex] = {
                ...existing,
                'quantity': (existing['quantity'] as int? ?? 1) + 1,
              };
            }
          }

          // Sem progresso => para e deixa fallback completar (básicos)
          if (addedThisIter == 0) break;
        }

        // Fallback final: INTELIGENTE — calcula quantos terrenos vs spells faltam
        // Em vez de simplesmente jogar lands, analisa a proporção ideal
        if (virtualTotal < maxTotal) {
          var missing = maxTotal - virtualTotal;
          
          // Calcular terrenos atuais no deck virtual
          var currentLands = 0;
          for (final c in virtualDeck) {
            final typeLine = ((c['type_line'] as String?) ?? '').toLowerCase();
            if (typeLine.contains('land')) {
              currentLands += (c['quantity'] as int?) ?? 1;
            }
          }
          
          // Proporção ideal de terrenos: ~36-38 para Commander
          // Ajustar por CMC médio do deck
          final nonLandCards = virtualDeck.where((c) {
            final t = ((c['type_line'] as String?) ?? '').toLowerCase();
            return !t.contains('land');
          }).toList();
          
          double avgCmc = 0;
          if (nonLandCards.isNotEmpty) {
            avgCmc = nonLandCards.fold<double>(0, (sum, c) {
              return sum + ((c['cmc'] as num?)?.toDouble() ?? 0.0);
            }) / nonLandCards.length;
          }
          
          // Terrenos ideais baseados no CMC médio:
          // CMC < 2.0 → 32 lands | CMC 2.0-3.0 → 35 | CMC 3.0-4.0 → 37 | CMC > 4.0 → 39
          final idealLands = avgCmc < 2.0 ? 32 : (avgCmc < 3.0 ? 35 : (avgCmc < 4.0 ? 37 : 39));
          final landsNeeded = (idealLands - currentLands).clamp(0, missing);
          final spellsNeeded = missing - landsNeeded;
          
          Log.d('Complete fallback inteligente:');
          Log.d('  Cartas faltando: $missing | Lands atuais: $currentLands | Ideal: $idealLands');
          Log.d('  Lands a adicionar: $landsNeeded | Spells a adicionar: $spellsNeeded');
          
          // Adicionar spells primeiro (via busca no DB por cartas sinérgicas)
          if (spellsNeeded > 0) {
            try {
              final existingNames = virtualDeck
                  .map((c) => ((c['name'] as String?) ?? '').toLowerCase())
                  .toSet();
              
              final synergySpells = await _findSynergyReplacements(
                pool: pool,
                optimizer: optimizer,
                commanders: commanders,
                commanderColorIdentity: commanderColorIdentity,
                targetArchetype: targetArchetype,
                bracket: bracket,
                keepTheme: keepTheme,
                detectedTheme: themeProfile.theme,
                coreCards: themeProfile.coreCards,
                missingCount: spellsNeeded,
                removedCards: const [], // não estamos substituindo, estamos adicionando
                excludeNames: existingNames,
                allCardData: virtualDeck,
              );

              var selectedSpells = synergySpells;
              if (selectedSpells.isEmpty) {
                final universalFallback = await _loadUniversalCommanderFallbacks(
                  pool: pool,
                  excludeNames: existingNames,
                  limit: spellsNeeded,
                );
                if (universalFallback.isNotEmpty) {
                  Log.d(
                      '  Synergy replacements vazios; aplicando fallback universal (${universalFallback.length} cartas).');
                  selectedSpells = universalFallback;
                }
              }
              
              for (final spell in selectedSpells) {
                if (virtualTotal >= maxTotal) break;
                final id = spell['id'] as String;
                final name = spell['name'] as String;
                final nameLower = name.toLowerCase();
                final maxCopies = _maxCopiesForFormat(
                  deckFormat: deckFormat,
                  typeLine: '',
                  name: name,
                );
                
                if ((virtualCountsByName[nameLower] ?? 0) >= maxCopies) {
                  continue;
                }
                
                virtualCountsById[id] = 1;
                virtualCountsByName[nameLower] =
                    (virtualCountsByName[nameLower] ?? 0) + 1;
                addedCountsById[id] = (addedCountsById[id] ?? 0) + 1;
                virtualTotal += 1;
                
                virtualDeck.add({
                  'card_id': id,
                  'name': name,
                  'type_line': '',
                  'oracle_text': '',
                  'colors': <String>[],
                  'color_identity': <String>[],
                  'quantity': 1,
                  'is_commander': false,
                  'mana_cost': '',
                  'cmc': 0.0,
                });
              }
              Log.d('  Spells não-terreno adicionadas: ${selectedSpells.length}');
            } catch (e) {
              Log.w('Falha ao buscar spells sinérgicas: $e');
            }
          }
          
          // Depois adicionar lands para o restante
          if (virtualTotal < maxTotal) {
            final currentLandsAfterSpells = virtualDeck.fold<int>(0, (sum, c) {
              final t = ((c['type_line'] as String?) ?? '').toLowerCase();
              if (t.contains('land')) {
                return sum + ((c['quantity'] as int?) ?? 1);
              }
              return sum;
            });

            var landsToAdd = (idealLands - currentLandsAfterSpells).clamp(0, maxTotal - virtualTotal);
            final basicNames = _basicLandNamesForIdentity(commanderColorIdentity);
            final basicsWithIds = await _loadBasicLandIds(pool, basicNames);
            if (basicsWithIds.isNotEmpty) {
              final keys = basicsWithIds.keys.toList();
              var i = 0;
              while (landsToAdd > 0) {
                final name = keys[i % keys.length];
                final id = basicsWithIds[name]!;
                virtualCountsById[id] = (virtualCountsById[id] ?? 0) + 1;
                addedCountsById[id] = (addedCountsById[id] ?? 0) + 1;
                virtualTotal += 1;
                landsToAdd--;
                i++;
              }
            }
          }

          // Se ainda faltar após atingir alvo de lands, preencher com cartas não-terreno
          // competitivas do banco (evita deck degenerado de básicos).
          if (virtualTotal < maxTotal) {
            final remaining = maxTotal - virtualTotal;
            final existingNames = virtualDeck
                .map((c) => ((c['name'] as String?) ?? '').toLowerCase())
                .toSet();

            final fillers = await _loadGuaranteedNonBasicFillers(
              pool: pool,
              currentDeckCards: virtualDeck,
              targetArchetype: targetArchetype,
              commanderColorIdentity: commanderColorIdentity,
              bracket: bracket,
              excludeNames: existingNames,
              preferredNames: aiSuggestedNames,
              limit: remaining,
            );
            if (fillers.isNotEmpty) deterministicStageUsed = true;

            for (final filler in fillers) {
              if (virtualTotal >= maxTotal) break;
              final id = filler['id'] as String;
              final name = filler['name'] as String;
              final nameLower = name.toLowerCase();
              final maxCopies = _maxCopiesForFormat(
                deckFormat: deckFormat,
                typeLine: filler['type_line'] as String? ?? '',
                name: name,
              );

              if ((virtualCountsByName[nameLower] ?? 0) >= maxCopies) {
                continue;
              }

              virtualCountsById[id] = (virtualCountsById[id] ?? 0) + 1;
              virtualCountsByName[nameLower] = (virtualCountsByName[nameLower] ?? 0) + 1;
              addedCountsById[id] = (addedCountsById[id] ?? 0) + 1;
              virtualTotal += 1;

              final existingIndex = virtualDeck.indexWhere(
                (e) => (e['card_id'] as String?) == id,
              );

              if (existingIndex == -1) {
                virtualDeck.add({
                  'card_id': id,
                  'name': name,
                  'type_line': filler['type_line'] ?? '',
                  'oracle_text': filler['oracle_text'] ?? '',
                  'colors': filler['colors'] ?? <String>[],
                  'color_identity': filler['color_identity'] ?? <String>[],
                  'quantity': 1,
                  'is_commander': false,
                  'mana_cost': '',
                  'cmc': 0.0,
                });
              } else {
                final existing = virtualDeck[existingIndex];
                virtualDeck[existingIndex] = {
                  ...existing,
                  'quantity': (existing['quantity'] as int? ?? 1) + 1,
                };
              }
            }
          }

          // Garantia local de fechamento do tamanho do deck.
          // Se ainda faltar, completa com básicos dentro da identidade.
          if (virtualTotal < maxTotal) {
            final basicNames = _basicLandNamesForIdentity(commanderColorIdentity);
            final basicsWithIds = await _loadBasicLandIds(pool, basicNames);
            if (basicsWithIds.isNotEmpty) {
              guaranteedBasicsStageUsed = true;
              final keys = basicsWithIds.keys.toList();
              var i = 0;
              while (virtualTotal < maxTotal) {
                final name = keys[i % keys.length];
                final id = basicsWithIds[name]!;

                virtualCountsById[id] = (virtualCountsById[id] ?? 0) + 1;
                virtualCountsByName[name.toLowerCase()] =
                    (virtualCountsByName[name.toLowerCase()] ?? 0) + 1;
                addedCountsById[id] = (addedCountsById[id] ?? 0) + 1;
                virtualTotal += 1;
                i++;
              }
            }
          }
        }

        // Constrói resposta "complete" final (aggregated)
        final additionsDetailed = <Map<String, dynamic>>[];
        for (final entry in addedCountsById.entries) {
          additionsDetailed.add({
            'card_id': entry.key,
            'quantity': entry.value,
          });
        }

        final addedTotal = additionsDetailed.fold<int>(
          0,
          (sum, item) => sum + ((item['quantity'] as int?) ?? 0),
        );

        final targetTotal = maxTotal - currentTotalCards;
        final addedNameById = <String, String>{};
        if (additionsDetailed.isNotEmpty) {
          final addIds = additionsDetailed
              .map((e) => e['card_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
          final addRows = await pool.execute(
            Sql.named('SELECT id::text, name FROM cards WHERE id = ANY(@ids)'),
            parameters: {'ids': addIds},
          );
          for (final row in addRows) {
            addedNameById[row[0] as String] = row[1] as String;
          }
        }

        final basicAdded = additionsDetailed.fold<int>(0, (sum, item) {
          final id = item['card_id']?.toString() ?? '';
          final name = (addedNameById[id] ?? '').trim().toLowerCase();
          final qty = (item['quantity'] as int?) ?? 0;
          if (_isBasicLandName(name)) return sum + qty;
          return sum;
        });

        final nonBasicAdded = addedTotal - basicAdded;

        Map<String, dynamic>? qualityError;
        if (addedTotal < targetTotal) {
          qualityError = {
            'code': 'COMPLETE_QUALITY_PARTIAL',
            'message':
                'Não foi possível completar o deck com qualidade mínima: adições insuficientes.',
            'target_additions': targetTotal,
            'added_total': addedTotal,
            'basic_added': basicAdded,
            'non_basic_added': nonBasicAdded,
          };
        } else if (targetTotal >= 40 && basicAdded > 50) {
          qualityError = {
            'code': 'COMPLETE_QUALITY_BASIC_OVERFLOW',
            'message':
                'Complete com excesso de terrenos básicos para montagem competitiva.',
            'target_additions': targetTotal,
            'added_total': addedTotal,
            'basic_added': basicAdded,
            'non_basic_added': nonBasicAdded,
          };
        } else if (targetTotal >= 40 && nonBasicAdded == 0) {
          qualityError = {
            'code': 'COMPLETE_QUALITY_DEGENERATE',
            'message':
                'Complete degenerado: apenas terrenos básicos foram sugeridos para preencher o deck.',
            'target_additions': targetTotal,
            'added_total': addedTotal,
            'basic_added': basicAdded,
            'non_basic_added': nonBasicAdded,
          };
        }

        jsonResponse = {
          'mode': 'complete',
          'target_additions': maxTotal - currentTotalCards,
          'iterations': iterations,
          'additions_detailed': additionsDetailed,
          'reasoning': (virtualTotal >= maxTotal)
              ? 'Deck completado com cartas sinérgicas ao arquétipo $targetArchetype, priorizando sinergia com o Commander e a proporção ideal de terrenos/spells.'
              : 'Deck parcialmente completado; algumas sugestões foram bloqueadas/filtradas.',
          'warnings': {
            if (invalidAll.isNotEmpty) 'invalid_cards': invalidAll,
            if (filteredByIdentityAll.isNotEmpty)
              'filtered_by_color_identity': {
                'removed_additions': filteredByIdentityAll,
              },
            if (blockedByBracketAll.isNotEmpty)
              'blocked_by_bracket': {
                'blocked_additions': blockedByBracketAll,
              },
          },
          'consistency_slo': {
            'completed_target': addedTotal >= targetTotal,
            'ai_stage_used': aiStageUsed,
            'deterministic_stage_used': deterministicStageUsed,
            'guaranteed_basics_stage_used': guaranteedBasicsStageUsed,
            'added_total': addedTotal,
            'target_total': targetTotal,
            'non_basic_added': nonBasicAdded,
            'basic_added': basicAdded,
          },
          if (qualityError != null) 'quality_error': qualityError,
        };
      } else {
        jsonResponse = await optimizer.optimizeDeck(
          deckData: deckData,
          commanders: commanders,
          targetArchetype: targetArchetype,
          bracket: bracket,
          keepTheme: keepTheme,
          detectedTheme: themeProfile.theme,
          coreCards: themeProfile.coreCards,
        );
        jsonResponse['mode'] ??= 'optimize';
      }
    } catch (e, stackTrace) {
      Log.e('Optimization failed: $e\nStack trace:\n$stackTrace');
      final message = e.toString();
      if (message.contains('Bad state: No element')) {
        return internalServerError('Optimization failed');
      }
      return internalServerError('Optimization failed', details: e);
    }

    jsonResponse = _normalizeOptimizePayload(
      jsonResponse,
      defaultMode: 'optimize',
    );

    // Se o modo complete já veio “determinístico” (com card_id/quantity),
    // devolve diretamente sem passar pelo fluxo antigo de validação por nomes.
    if (jsonResponse['mode'] == 'complete' &&
        jsonResponse['additions_detailed'] is List) {
      final qualityError = jsonResponse['quality_error'];
      if (qualityError is Map) {
        return Response.json(
          statusCode: HttpStatus.unprocessableEntity,
          body: {
            'error':
                'Complete mode não atingiu qualidade mínima para montagem competitiva.',
            'quality_error': qualityError,
            'mode': 'complete',
            'target_additions': jsonResponse['target_additions'],
          },
        );
      }

      final rawAdditionsDetailed = (jsonResponse['additions_detailed'] as List)
          .whereType<Map>()
          .map((m) {
            final mm = m.cast<String, dynamic>();
            return {
              'card_id': mm['card_id']?.toString(),
              'quantity': mm['quantity'] as int? ?? 1,
            };
          })
          .where((m) => (m['card_id'] as String?)?.isNotEmpty ?? false)
          .toList();

      final ids = rawAdditionsDetailed.map((e) => e['card_id'] as String).toList();
      final cardInfoById = <String, Map<String, String>>{};
      var additionsDetailed = <Map<String, dynamic>>[];
      Map<String, dynamic>? postAnalysisComplete;
      
      if (ids.isNotEmpty) {
        final r = await pool.execute(
          Sql.named('SELECT id::text, name, type_line FROM cards WHERE id = ANY(@ids)'),
          parameters: {'ids': ids},
        );
        for (final row in r) {
          cardInfoById[row[0] as String] = {
            'name': row[1] as String,
            'type_line': (row[2] as String?) ?? '',
          };
        }

        // Colapsa por NOME (não por printing/card_id), aplicando limite de cópias por formato.
        final aggregatedByName = <String, Map<String, dynamic>>{};
        for (final entry in rawAdditionsDetailed) {
          final cardId = entry['card_id'] as String;
          final cardInfo = cardInfoById[cardId];
          if (cardInfo == null) continue;

          final name = cardInfo['name'] ?? '';
          final typeLine = cardInfo['type_line'] ?? '';
          if (name.trim().isEmpty) continue;

          final maxCopies = _maxCopiesForFormat(
            deckFormat: deckFormat,
            typeLine: typeLine,
            name: name,
          );

          final existing = aggregatedByName[name.toLowerCase()];
          final currentQty = (existing?['quantity'] as int?) ?? 0;
          final incomingQty = (entry['quantity'] as int?) ?? 1;
          final allowedToAdd = (maxCopies - currentQty).clamp(0, incomingQty);
          if (allowedToAdd <= 0) continue;

          if (existing == null) {
            aggregatedByName[name.toLowerCase()] = {
              'card_id': cardId,
              'quantity': allowedToAdd,
              'name': name,
              'type_line': typeLine,
            };
          } else {
            aggregatedByName[name.toLowerCase()] = {
              ...existing,
              'quantity': currentQty + allowedToAdd,
            };
          }
        }

        additionsDetailed = aggregatedByName.values
            .map((e) => {
                  'card_id': e['card_id'],
                  'quantity': e['quantity'],
                  'name': e['name'],
                })
            .toList();
        
        // === Gerar post_analysis para modo complete ===
        try {
          // 1. Buscar dados completos das cartas adicionadas
          final additionsDataResult = await pool.execute(
            Sql.named('''
              SELECT name, type_line, mana_cost, colors, 
                     COALESCE(
                       (SELECT SUM(
                         CASE 
                           WHEN m[1] ~ '^[0-9]+\$' THEN m[1]::int
                           WHEN m[1] IN ('W','U','B','R','G','C') THEN 1
                           WHEN m[1] = 'X' THEN 0
                           ELSE 1
                         END
                       ) FROM regexp_matches(mana_cost, '\\{([^}]+)\\}', 'g') AS m(m)),
                       0
                     ) as cmc,
                     oracle_text
              FROM cards 
              WHERE id = ANY(@ids)
            '''),
            parameters: {'ids': ids},
          );
          
          final additionsData = additionsDataResult
              .map((row) => {
                    'name': (row[0] as String?) ?? '',
                    'type_line': (row[1] as String?) ?? '',
                    'mana_cost': (row[2] as String?) ?? '',
                    'colors': (row[3] as List?)?.cast<String>() ?? [],
                    'cmc': (row[4] as num?)?.toDouble() ?? 0.0,
                    'oracle_text': (row[5] as String?) ?? '',
                  })
              .toList();
          
          // 2. Criar deck virtual (original + adições)
          final virtualDeck = List<Map<String, dynamic>>.from(allCardData);
          
          // Expandir adições pelo quantity
          for (final add in additionsDetailed) {
            final qty = add['quantity'] as int;
            final data = additionsData.firstWhere(
              (d) => (d['name'] as String).toLowerCase() ==
                  ((add['name'] as String?) ?? '').toLowerCase(),
              orElse: () => {
                'name': add['name'] ?? '',
                'type_line': '',
                'mana_cost': '',
                'colors': <String>[],
                'cmc': 0.0,
                'oracle_text': ''
              },
            );
            for (var i = 0; i < qty; i++) {
              virtualDeck.add(data);
            }
          }
          
          // 3. Rodar análise no deck virtual
          final postAnalyzer = DeckArchetypeAnalyzer(virtualDeck, deckColors.toList());
          postAnalysisComplete = postAnalyzer.generateAnalysis();
        } catch (e) {
          Log.w('Falha ao gerar post_analysis para modo complete: $e');
        }
      }

      final responseBody = {
        'mode': 'complete',
        'constraints': {
          'keep_theme': keepTheme,
        },
        'theme': themeProfile.toJson(),
        'bracket': bracket,
        'target_additions': jsonResponse['target_additions'],
        'iterations': jsonResponse['iterations'],
        'additions': additionsDetailed
          .map((e) => e['name'] ?? e['card_id'])
            .toList(),
        'additions_detailed': additionsDetailed
            .map((e) => {
                  'card_id': e['card_id'],
                  'quantity': e['quantity'],
              'name': e['name'],
                })
            .toList(),
        'removals': const <String>[],
        'removals_detailed': const <Map<String, dynamic>>[],
        'reasoning': jsonResponse['reasoning'] ?? '',
        'deck_analysis': deckAnalysis,
        'post_analysis': postAnalysisComplete,
        'validation_warnings': const <String>[],
      };

      final warnings = (jsonResponse['warnings'] is Map)
          ? (jsonResponse['warnings'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      if (warnings.isNotEmpty) {
        responseBody['warnings'] = warnings;
      }

      return Response.json(body: responseBody);
    }

    // Validar cartas sugeridas pela IA

    // Validar cartas sugeridas pela IA
    final validationService = CardValidationService(pool);

    List<String> removals = [];
    List<String> additions = [];
    var emptySuggestionFallbackTriggered = false;
    var emptySuggestionFallbackApplied = false;
    String? emptySuggestionFallbackReason;
    var emptySuggestionFallbackCandidateCount = 0;
    var emptySuggestionFallbackReplacementCount = 0;
    var emptySuggestionFallbackPairCount = 0;

    final parsedSuggestions = parseOptimizeSuggestions(jsonResponse);
    removals = parsedSuggestions['removals'] as List<String>;
    additions = parsedSuggestions['additions'] as List<String>;
    final recognizedSuggestionFormat =
      parsedSuggestions['recognized_format'] as bool? ?? false;

    final deckNamesLower = allCardData
      .map((c) => ((c['name'] as String?) ?? '').toLowerCase())
      .where((n) => n.isNotEmpty)
      .toSet();
    final commanderLower = commanders.map((c) => c.toLowerCase()).toSet();
    final coreLower =
      themeProfile.coreCards.map((c) => c.toLowerCase()).toSet();
    final blockedByTheme = <String>[];

    final isComplete = jsonResponse['mode'] == 'complete';

    if (removals.isEmpty && additions.isEmpty && !isComplete) {
      emptySuggestionFallbackTriggered = true;
      _emptySuggestionFallbackTriggeredCount++;
      final fallbackRemovalCandidates = <String>[];
      final seenLower = <String>{};

      void collectCandidates({required bool preferNonLand}) {
        for (final card in allCardData) {
          final name = ((card['name'] as String?) ?? '').trim();
          if (name.isEmpty) continue;

          final lower = name.toLowerCase();
          if (seenLower.contains(lower)) continue;
          if (commanderLower.contains(lower)) continue;
          if (coreLower.contains(lower)) continue;

          final typeLine =
              ((card['type_line'] as String?) ?? '').toLowerCase();
          final isLand = typeLine.contains('land');
          if (preferNonLand && isLand) continue;

          seenLower.add(lower);
          fallbackRemovalCandidates.add(name);
          if (fallbackRemovalCandidates.length >= 2) break;
        }
      }

      collectCandidates(preferNonLand: true);
      if (fallbackRemovalCandidates.isEmpty) {
        collectCandidates(preferNonLand: false);
      }
      emptySuggestionFallbackCandidateCount = fallbackRemovalCandidates.length;

      if (fallbackRemovalCandidates.isNotEmpty) {
        final replacements = await _findSynergyReplacements(
          pool: pool,
          optimizer: optimizer,
          commanders: commanders,
          commanderColorIdentity: commanderColorIdentity,
          targetArchetype: targetArchetype,
          bracket: bracket,
          keepTheme: keepTheme,
          detectedTheme: themeProfile.theme,
          coreCards: themeProfile.coreCards,
          missingCount: fallbackRemovalCandidates.length,
          removedCards: fallbackRemovalCandidates,
          excludeNames: deckNamesLower,
          allCardData: allCardData,
        );
        emptySuggestionFallbackReplacementCount = replacements.length;

        if (replacements.isNotEmpty) {
          final fallbackAdditions = replacements
              .map((r) => (r['name'] as String?)?.trim() ?? '')
              .where((n) => n.isNotEmpty)
              .toList();

          final pairCount = fallbackRemovalCandidates.length < fallbackAdditions.length
              ? fallbackRemovalCandidates.length
              : fallbackAdditions.length;
          emptySuggestionFallbackPairCount = pairCount;

          if (pairCount > 0) {
            removals = fallbackRemovalCandidates.take(pairCount).toList();
            additions = fallbackAdditions.take(pairCount).toList();
            emptySuggestionFallbackApplied = true;
            _emptySuggestionFallbackAppliedCount++;
            emptySuggestionFallbackReason =
                'IA retornou sugestões vazias; aplicado fallback heurístico orientado a sinergia.';
            Log.i(
                '✅ [AI Optimize] Fallback aplicado com $pairCount swap(s) após retorno vazio da IA.');
          }
        }
      }

      if (!emptySuggestionFallbackApplied) {
        if (fallbackRemovalCandidates.isEmpty) {
          _emptySuggestionFallbackNoCandidateCount++;
          emptySuggestionFallbackReason =
              'IA retornou sugestões vazias e o deck não possui candidatas seguras para remoção.';
        } else if (emptySuggestionFallbackReplacementCount == 0) {
          _emptySuggestionFallbackNoReplacementCount++;
          emptySuggestionFallbackReason =
              'IA retornou sugestões vazias e não foi possível encontrar substitutas válidas no fallback.';
        } else {
        emptySuggestionFallbackReason =
            'IA retornou sugestões vazias e não foi possível gerar fallback seguro.';
        }
      }
    }

    // WARN: Se parsing resultou em listas vazias, logar para diagnóstico
    if (removals.isEmpty && additions.isEmpty && !isComplete) {
      if (recognizedSuggestionFormat) {
        Log.d(
            'ℹ️ [AI Optimize] Payload reconhecido, mas sem sugestões úteis (provável filtro/retorno vazio). Keys: ${jsonResponse.keys.toList()}');
      } else {
        Log.w(
            '⚠️ [AI Optimize] IA retornou formato não reconhecido. Keys: ${jsonResponse.keys.toList()}');
      }
    }

    // Suporte ao modo "complete"
    if (isComplete) {
      removals = [];
      // Quando veio do loop, preferimos additions_detailed.
      final fromDetailed = (jsonResponse['additions_detailed'] as List?)
          ?.whereType<Map>()
          .toList();
      if (fromDetailed != null && fromDetailed.isNotEmpty) {
        additions = fromDetailed
            .map((m) => (m['name'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } else {
        additions = (jsonResponse['additions'] as List?)?.cast<String>() ?? [];
      }
    }

    // GARANTIR EQUILÍBRIO NUMÉRICO (Regra de Ouro)
    if (!isComplete) {
      final minCount = removals.length < additions.length
          ? removals.length
          : additions.length;

      if (removals.length != additions.length) {
        Log.w(
          '⚠️ [AI Optimize] Ajustando desequilíbrio: -${removals.length} / +${additions.length} -> $minCount',
        );
        removals = removals.take(minCount).toList();
        additions = additions.take(minCount).toList();
      }
    }

    var sanitizedRemovals =
        removals.map(CardValidationService.sanitizeCardName).toList();
    var sanitizedAdditions =
        additions.map(CardValidationService.sanitizeCardName).toList();

    // Remoções devem existir no deck (evita no-ops e contagem final errada).
    sanitizedRemovals = sanitizedRemovals
        .where((n) => deckNamesLower.contains(n.toLowerCase()))
        .toList();

    // Nunca remover comandantes.
    sanitizedRemovals = sanitizedRemovals
        .where((n) => !commanderLower.contains(n.toLowerCase()))
        .toList();

    // Se o usuário pediu "otimizar", mas mantendo o tema, bloqueia remoções de core.
    if (keepTheme) {
      sanitizedRemovals = sanitizedRemovals.where((n) {
        final isCore = coreLower.contains(n.toLowerCase());
        if (isCore) blockedByTheme.add(n);
        return !isCore;
      }).toList();
    }

    // Em modo optimize (swaps), evita sugerir adicionar algo que já existe (no-op).
    if (!isComplete) {
      sanitizedAdditions = sanitizedAdditions
          .where((n) => !deckNamesLower.contains(n.toLowerCase()))
          .toList();
    }

    // Re-balancear após filtros.
    if (!isComplete) {
      final minCount = sanitizedRemovals.length < sanitizedAdditions.length
          ? sanitizedRemovals.length
          : sanitizedAdditions.length;
      sanitizedRemovals = sanitizedRemovals.take(minCount).toList();
      sanitizedAdditions = sanitizedAdditions.take(minCount).toList();
    }

    // Validar todas as cartas sugeridas
    final allSuggestions = [...sanitizedRemovals, ...sanitizedAdditions];
    final validation =
        await validationService.validateCardNames(allSuggestions);
    final validList =
        (validation['valid'] as List).cast<Map<String, dynamic>>();
    final validByNameLower = <String, Map<String, dynamic>>{};
    for (final v in validList) {
      final n = (v['name'] as String).toLowerCase();
      validByNameLower[n] = v;
    }

    // Filtrar apenas cartas válidas e remover duplicatas
    var validRemovals = sanitizedRemovals
        .where((name) {
          return (validation['valid'] as List).any((card) =>
              (card['name'] as String).toLowerCase() == name.toLowerCase());
        })
        .toSet()
        .toList();

    // No modo complete, preservamos repetição (para básicos) e ordem.
    // No modo optimize (swaps), mantemos set para evitar duplicatas.
    var validAdditions = sanitizedAdditions.where((name) {
      return (validation['valid'] as List).any((card) =>
          (card['name'] as String).toLowerCase() == name.toLowerCase());
    }).toList();
    if (!isComplete) {
      validAdditions = validAdditions.toSet().toList();
    }

    // DEBUG: Log quantidades antes dos filtros avançados
    Log.d('Antes dos filtros de cor/bracket:');
    Log.d('  validRemovals.length = ${validRemovals.length}');
    Log.d('  validAdditions.length = ${validAdditions.length}');
    
    // Filtrar adições ilegais para Commander/Brawl (identidade de cor do comandante).
    // Observação: para colorless commander (identity vazia), apenas cartas colorless passam.
    final filteredByColorIdentity = <String>[];
    if (commanders.isNotEmpty && validAdditions.isNotEmpty) {
      final additionsIdentityResult = await pool.execute(
        Sql.named('''
            SELECT name, color_identity, colors
            FROM cards
            WHERE name = ANY(@names)
          '''),
        parameters: {'names': validAdditions},
      );

      final identityByName = <String, List<String>>{};
      for (final row in additionsIdentityResult) {
        final name = (row[0] as String).toLowerCase();
        final colorIdentity =
            (row[1] as List?)?.cast<String>() ?? const <String>[];
        final colors = (row[2] as List?)?.cast<String>() ?? const <String>[];
        final identity = (colorIdentity.isNotEmpty ? colorIdentity : colors);
        identityByName[name] = identity;
      }

      validAdditions = validAdditions.where((name) {
        final identity = identityByName[name.toLowerCase()] ?? const <String>[];
        final ok = isWithinCommanderIdentity(
          cardIdentity: identity,
          commanderIdentity: commanderColorIdentity,
        );
        if (!ok) filteredByColorIdentity.add(name);
        return ok;
      }).toList();
    }

    // Bracket policy (intermediário): bloqueia cartas "acima do bracket" baseado no deck atual.
    // Aplica somente em Commander/Brawl, quando bracket foi enviado.
    final blockedByBracket = <Map<String, dynamic>>[];
    if (bracket != null && commanders.isNotEmpty && validAdditions.isNotEmpty) {
      // Dados atuais do deck (já temos oracle/type em allCardData + quantity)
      final additionsInfoResult = await pool.execute(
        Sql.named('''
            SELECT name, type_line, oracle_text
            FROM cards
            WHERE name = ANY(@names)
          '''),
        parameters: {'names': validAdditions},
      );
      final additionsInfo = additionsInfoResult
          .map((r) => {
                'name': r[0] as String,
                'type_line': r[1] as String? ?? '',
                'oracle_text': r[2] as String? ?? '',
                'quantity': 1,
              })
          .toList();

      final decision = applyBracketPolicyToAdditions(
        bracket: bracket,
        currentDeckCards: allCardData,
        additionsCardsData: additionsInfo,
      );

      blockedByBracket.addAll(decision.blocked);
      // Modo complete pode conter repetição; para a decisão, usamos os nomes únicos do "allowed"
      // e depois re-aplicamos mantendo repetição quando possível.
      final allowedSet = decision.allowed.map((e) => e.toLowerCase()).toSet();
      validAdditions = validAdditions
          .where((n) => allowedSet.contains(n.toLowerCase()))
          .toList();
    }

    // Top-up determinístico no modo complete:
    // se depois de validações/filtros ainda faltarem cartas para atingir o target, completa com básicos.
    final additionsDetailed = <Map<String, dynamic>>[];
    if (isComplete) {
      final targetAdditions = (jsonResponse['target_additions'] as int?) ?? 0;
      final desired =
          targetAdditions > 0 ? targetAdditions : validAdditions.length;

      // Agrega as adições atuais por nome (quantidade 1 por ocorrência)
      final countsByName = <String, int>{};
      final basicNamesLower = _basicLandNamesForIdentity(commanderColorIdentity)
          .map((e) => e.toLowerCase())
          .toSet();
      for (final n in validAdditions) {
        final lower = n.toLowerCase();
        final current = countsByName[n] ?? 0;
        final isBasic = basicNamesLower.contains(lower) || lower == 'wastes';
        if (!isBasic &&
            (deckFormat.toLowerCase() == 'commander' ||
                deckFormat.toLowerCase() == 'brawl') &&
            current >= 1) {
          continue;
        }
        countsByName[n] = current + 1;
      }

      // Se faltar, adiciona básicos para preencher
      var missing = desired - countsByName.values.fold<int>(0, (a, b) => a + b);
      Map<String, String> basicsWithIds = const {};
      if (missing > 0) {
        final basicNames = _basicLandNamesForIdentity(commanderColorIdentity);
        basicsWithIds = await _loadBasicLandIds(pool, basicNames);

        if (basicsWithIds.isNotEmpty) {
          final keys = basicsWithIds.keys.toList();
          var i = 0;
          while (missing > 0) {
            final name = keys[i % keys.length];
            countsByName[name] = (countsByName[name] ?? 0) + 1;
            missing--;
            i++;
          }
        }
      }

      // Converte para additions_detailed com card_id/quantity
      for (final entry in countsByName.entries) {
        final v = validByNameLower[entry.key.toLowerCase()];
        final id = v?['id']?.toString() ?? basicsWithIds[entry.key]?.toString();
        final name = v?['name']?.toString() ?? entry.key;
        if (id == null || id.isEmpty) continue;
        additionsDetailed.add({
          'name': name,
          'card_id': id,
          'quantity': entry.value,
        });
      }

      // Mantém additions como lista simples (única) para UI; o app aplica via additions_detailed.
      validAdditions =
          additionsDetailed.map((e) => e['name'] as String).toList();
    }

    // Re-aplicar equilíbrio após validação
    // FILOSOFIA: Quando additions < removals, a IA deve SUGERIR NOVAS CARTAS
    // de sinergia — NÃO preencher com lands genéricos. O propósito é OTIMIZAR.
    if (!isComplete && validRemovals.length != validAdditions.length) {
      Log.d('Re-balanceamento pós-filtros:');
      Log.d('  Antes: removals=${validRemovals.length}, additions=${validAdditions.length}');
      
      if (validAdditions.length < validRemovals.length) {
        // CORREÇÃO REAL: Re-consultar a IA para cartas substitutas
        final missingCount = validRemovals.length - validAdditions.length;
        Log.d('  Faltam $missingCount adições - consultando IA para substitutas sinérgicas');
        
        // Montar lista de cartas a excluir (já existentes + já sugeridas + filtradas)
        final excludeNames = <String>{
          ...deckNamesLower,
          ...validAdditions.map((n) => n.toLowerCase()),
          ...filteredByColorIdentity.map((n) => n.toLowerCase()),
        };
        
        // Categorias das cartas removidas para pedir substitutas do mesmo tipo funcional
        final removedButUnmatched = validRemovals.sublist(validAdditions.length);
        
        try {
          final replacementResult = await _findSynergyReplacements(
            pool: pool,
            optimizer: optimizer,
            commanders: commanders,
            commanderColorIdentity: commanderColorIdentity,
            targetArchetype: targetArchetype,
            bracket: bracket,
            keepTheme: keepTheme,
            detectedTheme: themeProfile.theme,
            coreCards: themeProfile.coreCards,
            missingCount: missingCount,
            removedCards: removedButUnmatched,
            excludeNames: excludeNames,
            allCardData: allCardData,
          );
          
          if (replacementResult.isNotEmpty) {
            for (final replacement in replacementResult) {
              final name = replacement['name'] as String;
              final id = replacement['id'] as String;
              validAdditions.add(name);
              validByNameLower[name.toLowerCase()] = {
                'id': id,
                'name': name,
              };
            }
            Log.d('  IA sugeriu ${replacementResult.length} substitutas sinérgicas');
          }
          
          // Se AINDA faltar (IA não conseguiu preencher tudo), agora sim fallback com basics
          if (validAdditions.length < validRemovals.length) {
            final stillMissing = validRemovals.length - validAdditions.length;
            Log.d('  Ainda faltam $stillMissing - fallback com básicos');
            final basicNames = _basicLandNamesForIdentity(commanderColorIdentity);
            final basicsWithIds = await _loadBasicLandIds(pool, basicNames);
            if (basicsWithIds.isNotEmpty) {
              final keys = basicsWithIds.keys.toList();
              var i = 0;
              for (var j = 0; j < stillMissing; j++) {
                final name = keys[i % keys.length];
                validAdditions.add(name);
                if (!validByNameLower.containsKey(name.toLowerCase())) {
                  validByNameLower[name.toLowerCase()] = {
                    'id': basicsWithIds[name],
                    'name': name,
                  };
                }
                i++;
              }
            } else {
              validRemovals = validRemovals.take(validAdditions.length).toList();
            }
          }
        } catch (e) {
          Log.w('Falha ao buscar substitutas IA: $e - usando fallback');
          // Fallback: truncar remoções para não perder cartas
          validRemovals = validRemovals.take(validAdditions.length).toList();
        }
      } else {
        // Mais adições que remoções: truncar adições
        validAdditions = validAdditions.take(validRemovals.length).toList();
      }
      
      Log.d('  Depois: removals=${validRemovals.length}, additions=${validAdditions.length}');
    }

    // --- VERIFICAÇÃO PÓS-OTIMIZAÇÃO (Virtual Deck Analysis) ---
    // Simular o deck como ficaria se as mudanças fossem aplicadas e re-analisar
    Map<String, dynamic>? postAnalysis;
    List<String> validationWarnings = [];

    // ═══════════════════════════════════════════════════════════
    // VALIDAÇÃO PÓS-PROCESSAMENTO: Color Identity + EDHREC + Tema
    // ═══════════════════════════════════════════════════════════

    // 1. Color Identity Warning (se IA sugeriu cartas inválidas)
    if (filteredByColorIdentity.isNotEmpty) {
      validationWarnings.add(
        '⚠️ ${filteredByColorIdentity.length} carta(s) sugerida(s) pela IA foram removidas por violar a identidade de cor do commander: ${filteredByColorIdentity.take(3).join(", ")}${filteredByColorIdentity.length > 3 ? "..." : ""}');
    }

    // 2. Validação EDHREC: verificar se additions têm sinergia comprovada
    EdhrecCommanderData? edhrecValidationData;
    List<String> additionsNotInEdhrec = [];
    if (commanders.isNotEmpty && validAdditions.isNotEmpty) {
      try {
        final edhrecService = optimizer.edhrecService;
        edhrecValidationData = await edhrecService.fetchCommanderData(commanders.firstOrNull ?? "");
        
        if (edhrecValidationData != null && edhrecValidationData.topCards.isNotEmpty) {
          for (final addition in validAdditions) {
            final card = edhrecValidationData.findCard(addition);
            if (card == null) {
              additionsNotInEdhrec.add(addition);
            }
          }
          
          if (additionsNotInEdhrec.isNotEmpty) {
            final percent = (additionsNotInEdhrec.length / validAdditions.length * 100).toStringAsFixed(0);
            if (additionsNotInEdhrec.length > validAdditions.length * 0.5) {
              validationWarnings.add(
                '⚠️ ${additionsNotInEdhrec.length} ($percent%) das cartas sugeridas NÃO aparecem nos dados EDHREC de ${commanders.firstOrNull ?? ""}. Isso pode indicar baixa sinergia: ${additionsNotInEdhrec.take(3).join(", ")}${additionsNotInEdhrec.length > 3 ? "..." : ""}');
            } else if (additionsNotInEdhrec.length >= 3) {
              validationWarnings.add(
                '💡 ${additionsNotInEdhrec.length} carta(s) sugerida(s) não estão nos dados EDHREC - podem ser inovadoras ou de baixa sinergia.');
            }
          }
        }
      } catch (e) {
        Log.w('EDHREC validation failed (non-blocking): $e');
      }
    }

    // 3. Comparação de Tema: verificar se tema detectado corresponde aos temas EDHREC
    if (edhrecValidationData != null && edhrecValidationData.themes.isNotEmpty) {
      final detectedThemeLower = targetArchetype.toLowerCase();
      final edhrecThemesLower = edhrecValidationData.themes.map((t) => t.toLowerCase()).toList();
      
      // Verificar se o tema detectado tem correspondência nos temas EDHREC
      bool themeMatch = false;
      for (final edhrecTheme in edhrecThemesLower) {
        if (detectedThemeLower.contains(edhrecTheme) || 
            edhrecTheme.contains(detectedThemeLower)) {
          themeMatch = true;
          break;
        }
      }
      
      if (!themeMatch) {
        validationWarnings.add(
          '� Tema detectado "$targetArchetype" não corresponde aos temas populares do EDHREC (${edhrecValidationData.themes.take(3).join(", ")}). O sistema está usando abordagem HÍBRIDA: 70% cartas EDHREC + 30% cartas do seu tema para respeitar sua ideia.');
      }
    }

    if (validAdditions.isNotEmpty) {
      try {
        // 1. Buscar dados completos das cartas sugeridas (para análise de mana/tipo)
        // Usar nomes corretos do DB (via validByNameLower) para evitar problemas de case
        final correctedAdditionNames = validAdditions
            .map((n) {
              final v = validByNameLower[n.toLowerCase()];
              return (v?['name'] as String?) ?? n;
            })
            .toList();
        final additionsDataResult = await pool.execute(
          Sql.named('''
              SELECT name, type_line, mana_cost, colors, 
                     COALESCE(
                       (SELECT SUM(
                         CASE 
                           WHEN m[1] ~ '^[0-9]+\$' THEN m[1]::int
                           WHEN m[1] IN ('W','U','B','R','G','C') THEN 1
                           WHEN m[1] = 'X' THEN 0
                           ELSE 1
                         END
                       ) FROM regexp_matches(mana_cost, '\\{([^}]+)\\}', 'g') AS m(m)),
                       0
                     ) as cmc,
                     oracle_text
              FROM cards 
              WHERE LOWER(name) = ANY(@names)
            '''),
          parameters: {'names': correctedAdditionNames.map((n) => n.toLowerCase()).toList()},
        );

        final additionsData = additionsDataResult
            .map((row) => {
                  'name': (row[0] as String?) ?? '',
                  'type_line': (row[1] as String?) ?? '',
                  'mana_cost': (row[2] as String?) ?? '',
                  'colors': (row[3] as List?)?.cast<String>() ?? [],
                  'cmc': (row[4] as num?)?.toDouble() ?? 0.0,
                  'oracle_text': (row[5] as String?) ?? '',
                })
            .toList();

        // 2. Criar Deck Virtual (Clone do atual - Remoções + Adições)
        final virtualDeck = List<Map<String, dynamic>>.from(allCardData);

        // Remover cartas sugeridas (pelo nome, case-insensitive)
        final removalNamesLower = validRemovals.map((n) => n.toLowerCase()).toSet();
        virtualDeck.removeWhere((c) => removalNamesLower.contains(((c['name'] as String?) ?? '').toLowerCase()));

        // Adicionar novas cartas
        virtualDeck.addAll(additionsData);

        // 3. Rodar Análise no Deck Virtual
        final postAnalyzer =
            DeckArchetypeAnalyzer(virtualDeck, deckColors.toList());
        postAnalysis = postAnalyzer.generateAnalysis();

        // 4. Comparar Antes vs Depois — VALIDAÇÃO QUALITATIVA REAL
        final preManaAssessment = deckAnalysis['mana_base_assessment'] as String? ?? '';
        final postManaAssessment = postAnalysis['mana_base_assessment'] as String? ?? '';
        final preManaIssues = preManaAssessment.contains('Falta mana');
        final postManaIssues = postManaAssessment.contains('Falta mana');

        if (!preManaIssues && postManaIssues) {
          validationWarnings.add(
              '⚠️ ATENÇÃO: As sugestões da IA podem piorar sua base de mana.');
        }

        final preAvgCmc = deckAnalysis['average_cmc'] as String? ?? '0';
        final postAvgCmc = postAnalysis['average_cmc'] as String? ?? '0';
        final preCurve = double.tryParse(preAvgCmc) ?? 0.0;
        final postCurve = double.tryParse(postAvgCmc) ?? 0.0;

        if (targetArchetype.toLowerCase() == 'aggro' && postCurve > preCurve) {
          validationWarnings.add(
              '⚠️ ATENÇÃO: O deck está ficando mais lento (CMC aumentou), o que é ruim para Aggro.');
        }

        // 5. ANÁLISE DE QUALIDADE DAS TROCAS (Power Level Assessment)
        final preTypes = deckAnalysis['type_distribution'] as Map<String, dynamic>? ?? {};
        final postTypes = postAnalysis['type_distribution'] as Map<String, dynamic>? ?? {};
        
        // Verificar se a otimização não desbalanceou a distribuição de tipos
        final preLands = (preTypes['lands'] as int?) ?? 0;
        final postLands = (postTypes['lands'] as int?) ?? 0;
        if (postLands < preLands - 3) {
          validationWarnings.add(
            '⚠️ A otimização removeu muitos terrenos ($preLands → $postLands). Isso pode causar problemas de mana.');
        }
        
        // Verificar se a curva melhorou para o arquétipo
        if (targetArchetype.toLowerCase() == 'control' && postCurve < preCurve - 0.5) {
          validationWarnings.add(
            '💡 O CMC médio diminuiu significativamente ($preAvgCmc → $postAvgCmc). Para Control, isso pode remover respostas de custo alto que são importantes.');
        }
        
        // Gerar resumo de melhoria
        final improvements = <String>[];
        if (postCurve < preCurve && targetArchetype.toLowerCase() != 'control') {
          improvements.add('CMC médio otimizado: $preAvgCmc → $postAvgCmc');
        }
        if (preManaIssues && !postManaIssues) {
          improvements.add('Base de mana corrigida');
        }
        if ((postTypes['instants'] as int? ?? 0) > (preTypes['instants'] as int? ?? 0)) {
          improvements.add('Mais interação instant-speed adicionada');
        }
        
        if (improvements.isNotEmpty) {
          postAnalysis['improvements'] = improvements;
        }

        // ═══════════════════════════════════════════════════════════
        // 6. VALIDAÇÃO AUTOMÁTICA (Monte Carlo + Funcional + Critic IA)
        // ═══════════════════════════════════════════════════════════
        try {
          final validator = OptimizationValidator(openAiKey: apiKey);
          final validationReport = await validator.validate(
            originalDeck: allCardData,
            optimizedDeck: virtualDeck,
            removals: validRemovals,
            additions: validAdditions,
            commanders: commanders,
            archetype: targetArchetype,
          );

          postAnalysis['validation'] = validationReport.toJson();

          // Adicionar warnings do validador
          for (final w in validationReport.warnings) {
            validationWarnings.add(w);
          }

          // Se reprovado, alertar
          if (validationReport.verdict == 'reprovado') {
            validationWarnings.insert(0,
                '🚫 VALIDAÇÃO: As trocas sugeridas NÃO passaram na validação automática (score: ${validationReport.score}/100).');
          }

          Log.d('Validation score: ${validationReport.score}/100 verdict: ${validationReport.verdict}');
        } catch (validationError) {
          Log.w('Validation failed (non-blocking): $validationError');
          // Validação é enhancement, não deve bloquear a resposta
        }
      } catch (e) {
        Log.e('Erro na verificação pós-otimização: $e');
      }
    }

    // Preparar resposta com avisos sobre cartas inválidas
    final invalidCards = validation['invalid'] as List<String>;
    final suggestions = validation['suggestions'] as Map<String, List<String>>;

    Map<String, dynamic>? persistedFallbackAggregate;
    try {
      await _recordOptimizeFallbackTelemetry(
        pool: pool,
        userId: userId,
        deckId: deckId,
        mode: jsonResponse['mode']?.toString() ?? 'optimize',
        recognizedFormat: recognizedSuggestionFormat,
        triggered: emptySuggestionFallbackTriggered,
        applied: emptySuggestionFallbackApplied,
        noCandidate: emptySuggestionFallbackTriggered &&
            emptySuggestionFallbackCandidateCount == 0,
        noReplacement: emptySuggestionFallbackTriggered &&
            emptySuggestionFallbackCandidateCount > 0 &&
            emptySuggestionFallbackReplacementCount == 0,
        candidateCount: emptySuggestionFallbackCandidateCount,
        replacementCount: emptySuggestionFallbackReplacementCount,
        pairCount: emptySuggestionFallbackPairCount,
      );
      persistedFallbackAggregate =
          await _loadPersistedEmptyFallbackAggregate(pool);
    } catch (e) {
      Log.w('Persisted fallback telemetry unavailable: $e');
    }

    final preCmc =
        double.tryParse('${deckAnalysis['average_cmc'] ?? '0'}') ?? 0.0;
    final postCmc = postAnalysis == null
        ? preCmc
        : (double.tryParse('${postAnalysis['average_cmc'] ?? preCmc}') ??
            preCmc);

    final responseBody = {
      'mode': jsonResponse['mode'],
      'constraints': {
        'keep_theme': keepTheme,
      },
      'cache': {
        'hit': false,
        'cache_key': cacheKey,
      },
      'preferences': {
        'memory_applied': !hasBracketOverride || !hasKeepThemeOverride,
        'keep_theme': keepTheme,
        'preferred_bracket': userPreferences['preferred_bracket'],
      },
      'theme': themeProfile.toJson(),
      'removals': validRemovals,
      'additions': validAdditions,
      'reasoning': _normalizeReasoning(jsonResponse['reasoning']),
      'deck_analysis': deckAnalysis,
      'post_analysis':
          postAnalysis, // Retorna a análise futura para o front mostrar
      'validation_warnings': validationWarnings,
      'bracket': bracket,
      'target_additions': jsonResponse['target_additions'],
      'optimize_diagnostics': {
        'empty_suggestions_fallback': {
          'triggered': emptySuggestionFallbackTriggered,
          'applied': emptySuggestionFallbackApplied,
          'candidate_count': emptySuggestionFallbackCandidateCount,
          'replacement_count': emptySuggestionFallbackReplacementCount,
          'pair_count': emptySuggestionFallbackPairCount,
        },
        'empty_suggestions_fallback_aggregate': _buildEmptyFallbackAggregate(),
        if (persistedFallbackAggregate != null)
          'empty_suggestions_fallback_aggregate_persisted':
              persistedFallbackAggregate,
      },
      // Validação EDHREC
      if (edhrecValidationData != null) 'edhrec_validation': {
        'commander': commanders.firstOrNull ?? "",
        'deck_count': edhrecValidationData.deckCount,
        'themes': edhrecValidationData.themes,
        'additions_validated': validAdditions.length - additionsNotInEdhrec.length,
        'additions_not_in_edhrec': additionsNotInEdhrec,
      },
    };

    // Gerar additions_detailed apenas para cartas com card_id válido
    responseBody['additions_detailed'] = isComplete
        ? additionsDetailed
            .whereType<Map<String, dynamic>>()
            .map((entry) {
              final name = entry['name']?.toString() ?? '';
              final cardId = entry['card_id']?.toString() ?? '';
              if (name.isEmpty || cardId.isEmpty) return null;
              return _buildRecommendationDetail(
                type: 'add',
                name: name,
                cardId: cardId,
                quantity: (entry['quantity'] as int?) ?? 1,
                targetArchetype: targetArchetype,
                confidenceLevel: themeProfile.confidence,
                cmcBefore: preCmc,
                cmcAfter: postCmc,
                keepTheme: keepTheme,
              );
            })
            .where((e) => e != null)
            .toList()
        : validAdditions
            .map((name) {
              final v = validByNameLower[name.toLowerCase()];
              if (v == null || v['id'] == null) return null;
              return _buildRecommendationDetail(
                type: 'add',
                name: '${v['name']}',
                cardId: '${v['id']}',
                quantity: 1,
                targetArchetype: targetArchetype,
                confidenceLevel: themeProfile.confidence,
                cmcBefore: preCmc,
                cmcAfter: postCmc,
                keepTheme: keepTheme,
              );
            })
            .where((e) => e != null)
            .toList();

    // Gerar removals_detailed apenas para cartas com card_id válido
    responseBody['removals_detailed'] = validRemovals
        .map((name) {
          final v = validByNameLower[name.toLowerCase()];
          if (v == null || v['id'] == null) return null;
          return _buildRecommendationDetail(
            type: 'remove',
            name: '${v['name']}',
            cardId: '${v['id']}',
            quantity: 1,
            targetArchetype: targetArchetype,
            confidenceLevel: themeProfile.confidence,
            cmcBefore: preCmc,
            cmcAfter: postCmc,
            keepTheme: keepTheme,
          );
        })
        .where((e) => e != null)
        .toList();

    responseBody['recommendations'] = [
      ...(responseBody['removals_detailed'] as List),
      ...(responseBody['additions_detailed'] as List),
    ];

    // CRÍTICO: Balancear additions/removals detailed para manter contagem igual
    final addDet = responseBody['additions_detailed'] as List;
    final remDet = responseBody['removals_detailed'] as List;
    
    // DEBUG: Log detalhado para rastrear desbalanceamentos
    Log.d('Balanceamento final:');
    Log.d('  validAdditions.length = ${validAdditions.length}');
    Log.d('  validRemovals.length = ${validRemovals.length}');
    Log.d('  additions_detailed.length = ${addDet.length}');
    Log.d('  removals_detailed.length = ${remDet.length}');
    Log.d('  mode = ${jsonResponse['mode']}');
    
    // Verificar cartas que NÃO foram mapeadas para card_id
    if (addDet.length != validAdditions.length) {
      Log.w('Algumas adições não foram mapeadas para card_id!');
      for (final name in validAdditions) {
        final v = validByNameLower[name.toLowerCase()];
        if (v == null || v['id'] == null) {
          Log.w('  Carta sem card_id: "$name" (key: "${name.toLowerCase()}")');
        }
      }
    }
    
    // BALANCEAMENTO FINAL (detailed) - Agora as listas já devem estar equilibradas
    // pós re-chamada à IA. Este bloco só age se o detailed ainda tiver gap.
    if (addDet.length < remDet.length && !isComplete) {
      final missingDetailed = remDet.length - addDet.length;
      Log.d('  Gap em detailed: faltam $missingDetailed - construindo de validAdditions');
      
      // Tentar construir detailed para adições que ainda não estão nele
      final existingNames = addDet.map((e) => (e as Map)['name']?.toString().toLowerCase() ?? '').toSet();
      final newDetailed = <Map<String, dynamic>>[];
      for (final name in validAdditions) {
        if (existingNames.contains(name.toLowerCase())) continue;
        final v = validByNameLower[name.toLowerCase()];
        if (v != null && v['id'] != null) {
          newDetailed.add({
            'name': v['name'] ?? name,
            'card_id': v['id'],
            'quantity': 1,
          });
          existingNames.add(name.toLowerCase());
        }
      }
      if (newDetailed.isNotEmpty) {
        responseBody['additions_detailed'] = [...addDet, ...newDetailed];
      }
      
      // Se AINDA faltar, truncar remoções como último recurso
      final finalAddDet2 = responseBody['additions_detailed'] as List;
      if (finalAddDet2.length < remDet.length) {
        responseBody['removals_detailed'] = remDet.take(finalAddDet2.length).toList();
        responseBody['removals'] = validRemovals.take(finalAddDet2.length).toList();
      }
    } else if (addDet.length > remDet.length && !isComplete) {
      Log.d('  Truncando adições extras');
      responseBody['additions_detailed'] = addDet.take(remDet.length).toList();
      responseBody['additions'] = validAdditions.take(remDet.length).toList();
    }
    
    // Log final
    final finalAddDet = responseBody['additions_detailed'] as List;
    final finalRemDet = responseBody['removals_detailed'] as List;
    Log.d('  Final: additions_detailed=${finalAddDet.length}, removals_detailed=${finalRemDet.length}');

    final warnings = <String, dynamic>{};

    // Adicionar avisos se houver cartas inválidas
    if (invalidCards.isNotEmpty) {
      warnings.addAll({
        'invalid_cards': invalidCards,
        'message':
            'Algumas cartas sugeridas pela IA não foram encontradas e foram removidas',
        'suggestions': suggestions,
      });
    }

    // Adicionar avisos se houver cartas filtradas por identidade de cor
    if (filteredByColorIdentity.isNotEmpty) {
      warnings['filtered_by_color_identity'] = {
        'commander_identity': commanderColorIdentity.toList(),
        'removed_additions': filteredByColorIdentity,
        'message':
            'Algumas adições sugeridas pela IA foram removidas por estarem fora da identidade de cor do comandante.',
      };
    }

    if (blockedByBracket.isNotEmpty) {
      warnings['blocked_by_bracket'] = {
        'bracket': bracket,
        'blocked_additions': blockedByBracket,
        'message':
            'Algumas adições sugeridas foram bloqueadas por exceder limites do bracket.',
      };
    }

    if (blockedByTheme.isNotEmpty) {
      warnings['blocked_by_theme'] = {
        'keep_theme': keepTheme,
        'blocked_removals': blockedByTheme,
        'message':
            'Algumas remoções sugeridas foram bloqueadas para preservar o tema do deck.',
      };
    }

    if (emptySuggestionFallbackReason != null) {
      warnings['empty_suggestions_handling'] = {
        'recognized_format': recognizedSuggestionFormat,
        'fallback_applied': emptySuggestionFallbackApplied,
        'message': emptySuggestionFallbackReason,
      };
    }

    if (warnings.isNotEmpty) {
      responseBody['warnings'] = warnings;
    }

    try {
      await _saveOptimizeCache(
        pool: pool,
        cacheKey: cacheKey,
        userId: userId,
        deckId: deckId,
        deckSignature: deckSignature,
        payload: responseBody,
      );
      await _saveUserAiPreferences(
        pool: pool,
        userId: userId,
        preferredArchetype: targetArchetype,
        preferredBracket: bracket,
        keepThemeDefault: keepTheme,
        preferredColors: commanderColorIdentity.toList(),
      );
    } catch (e) {
      Log.w('Falha ao persistir cache/preferências de optimize: $e');
    }

    return Response.json(body: responseBody);
  } catch (e, stackTrace) {
    Log.e('handler: $e\nStack trace:\n$stackTrace');
    return internalServerError('Failed to optimize deck', details: e);
  }
}

Map<String, dynamic> _normalizeOptimizePayload(
  Map<String, dynamic> payload, {
  required String defaultMode,
}) {
  final normalized = Map<String, dynamic>.from(payload);
  normalized['mode'] = _resolveOptimizeMode(normalized, defaultMode);
  normalized['reasoning'] = _normalizeReasoning(normalized['reasoning']);
  return normalized;
}

String _resolveOptimizeMode(Map<String, dynamic> payload, String defaultMode) {
  final rawCandidates = [
    payload['mode'],
    payload['modde'],
    payload['type'],
    payload['operation_mode'],
    payload['strategy_mode'],
  ];

  for (final raw in rawCandidates) {
    if (raw is! String) continue;
    final normalized = raw.trim().toLowerCase();
    if (normalized.contains('complete')) return 'complete';
    if (normalized.contains('opt')) return 'optimize';
  }

  if (payload['additions_detailed'] is List) {
    final additionsDetailed = payload['additions_detailed'] as List;
    if (additionsDetailed.isNotEmpty) return 'complete';
  }

  return defaultMode;
}

Map<String, dynamic> parseOptimizeSuggestions(Map<String, dynamic> payload) {
  final removals = <String>[];
  final additions = <String>[];
  var recognizedFormat = false;

  final collections = [
    payload['swaps'],
    payload['swap'],
    payload['changes'],
    payload['suggestions'],
    payload['recommendations'],
    payload['replacements'],
  ];

  for (final collection in collections) {
    if (collection is! List) continue;
    recognizedFormat = true;
    for (final entry in collection) {
      if (entry is String) {
        final raw = entry.trim();
        if (raw.isEmpty) continue;
        final arrows = ['->', '=>', '→'];
        String? left;
        String? right;
        for (final arrow in arrows) {
          if (!raw.contains(arrow)) continue;
          final parts = raw.split(arrow);
          if (parts.length >= 2) {
            left = parts.first.trim();
            right = parts.sublist(1).join(arrow).trim();
          }
          break;
        }
        if ((left ?? '').isNotEmpty) removals.add(left!);
        if ((right ?? '').isNotEmpty) additions.add(right!);
        continue;
      }

      if (entry is! Map) continue;
      final map = entry.cast<dynamic, dynamic>();
      final nested = map['swap'] ?? map['change'] ?? map['suggestion'];
      final sourceMap = nested is Map ? nested.cast<dynamic, dynamic>() : map;

      final outRaw = sourceMap['out'] ??
          sourceMap['remove'] ??
          sourceMap['from'] ??
          map['out'] ??
          map['remove'] ??
          map['from'];
      final inRaw = sourceMap['in'] ??
          sourceMap['add'] ??
          sourceMap['to'] ??
          map['in'] ??
          map['add'] ??
          map['to'];

      final out = outRaw?.toString().trim() ?? '';
      final inCard = inRaw?.toString().trim() ?? '';

      if (out.isNotEmpty) removals.add(out);
      if (inCard.isNotEmpty) additions.add(inCard);
    }

    if (removals.isNotEmpty || additions.isNotEmpty) {
      return {
        'removals': removals,
        'additions': additions,
        'recognized_format': true,
      };
    }
  }

  final rawRemovals = payload['removals'];
  final rawAdditions = payload['additions'];

  if (rawRemovals is List) {
    recognizedFormat = true;
    removals.addAll(rawRemovals
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty));
  } else if (rawRemovals is String && rawRemovals.trim().isNotEmpty) {
    recognizedFormat = true;
    removals.add(rawRemovals.trim());
  } else if (payload.containsKey('removals')) {
    recognizedFormat = true;
  }

  if (rawAdditions is List) {
    recognizedFormat = true;
    additions.addAll(rawAdditions
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty));
  } else if (rawAdditions is String && rawAdditions.trim().isNotEmpty) {
    recognizedFormat = true;
    additions.add(rawAdditions.trim());
  } else if (payload.containsKey('additions')) {
    recognizedFormat = true;
  }

  return {
    'removals': removals,
    'additions': additions,
    'recognized_format': recognizedFormat,
  };
}

String _normalizeReasoning(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

String _buildDeckSignature(List<ResultRow> cardsResult) {
  final entries = <String>[];
  for (final row in cardsResult) {
    final cardId = row[9].toString();
    final quantity = (row[2] as int?) ?? 1;
    entries.add('$cardId:$quantity');
  }
  entries.sort();
  return entries.join('|');
}

String _buildOptimizeCacheKey({
  required String deckId,
  required String archetype,
  required int? bracket,
  required bool keepTheme,
  required String deckSignature,
}) {
  final base = [
    'optimize',
    deckId,
    archetype.toLowerCase().trim(),
    '${bracket ?? 'none'}',
    keepTheme ? 'keep' : 'free',
    deckSignature,
  ].join('::');
  return 'v2:${_stableHash(base)}';
}

String _stableHash(String value) {
  var hash = 2166136261;
  for (final code in value.codeUnits) {
    hash ^= code;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}

Future<Map<String, dynamic>?> _loadOptimizeCache({
  required Pool pool,
  required String cacheKey,
}) async {
  final result = await pool.execute(
    Sql.named('''
      SELECT payload
      FROM ai_optimize_cache
      WHERE cache_key = @cache_key
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1
    '''),
    parameters: {
      'cache_key': cacheKey,
    },
  );

  if (result.isEmpty) return null;
  final payload = result.first[0];
  if (payload is Map<String, dynamic>) return Map<String, dynamic>.from(payload);
  if (payload is Map) return payload.cast<String, dynamic>();
  return null;
}

Future<void> _saveOptimizeCache({
  required Pool pool,
  required String cacheKey,
  required String? userId,
  required String deckId,
  required String deckSignature,
  required Map<String, dynamic> payload,
}) async {
  await pool.execute(
    Sql.named('''
      INSERT INTO ai_optimize_cache (
        cache_key,
        user_id,
        deck_id,
        deck_signature,
        payload,
        expires_at
      ) VALUES (
        @cache_key,
        CAST(@user_id AS uuid),
        CAST(@deck_id AS uuid),
        @deck_signature,
        @payload,
        NOW() + INTERVAL '6 hours'
      )
      ON CONFLICT (cache_key)
      DO UPDATE SET
        user_id = EXCLUDED.user_id,
        deck_id = EXCLUDED.deck_id,
        deck_signature = EXCLUDED.deck_signature,
        payload = EXCLUDED.payload,
        expires_at = EXCLUDED.expires_at,
        created_at = NOW()
    '''),
    parameters: {
      'cache_key': cacheKey,
      'user_id': userId,
      'deck_id': deckId,
      'deck_signature': deckSignature,
      'payload': payload,
    },
  );

  await pool.execute('''
    DELETE FROM ai_optimize_cache
    WHERE expires_at <= NOW()
  ''');
}

Future<Map<String, dynamic>> _loadUserAiPreferences({
  required Pool pool,
  required String? userId,
}) async {
  if (userId == null || userId.isEmpty) {
    return const {
      'preferred_bracket': null,
      'keep_theme_default': true,
    };
  }

  final result = await pool.execute(
    Sql.named('''
      SELECT preferred_archetype, preferred_bracket, keep_theme_default
      FROM ai_user_preferences
      WHERE user_id = CAST(@user_id AS uuid)
      LIMIT 1
    '''),
    parameters: {
      'user_id': userId,
    },
  );

  if (result.isEmpty) {
    return const {
      'preferred_bracket': null,
      'keep_theme_default': true,
    };
  }

  final row = result.first;
  return {
    'preferred_archetype': row[0] as String?,
    'preferred_bracket': row[1] as int?,
    'keep_theme_default': row[2] as bool? ?? true,
  };
}

Future<void> _saveUserAiPreferences({
  required Pool pool,
  required String? userId,
  required String preferredArchetype,
  required int? preferredBracket,
  required bool keepThemeDefault,
  required List<String> preferredColors,
}) async {
  if (userId == null || userId.isEmpty) return;

  await pool.execute(
    Sql.named('''
      INSERT INTO ai_user_preferences (
        user_id,
        preferred_archetype,
        preferred_bracket,
        keep_theme_default,
        preferred_colors,
        updated_at
      ) VALUES (
        CAST(@user_id AS uuid),
        @preferred_archetype,
        @preferred_bracket,
        @keep_theme_default,
        @preferred_colors,
        NOW()
      )
      ON CONFLICT (user_id)
      DO UPDATE SET
        preferred_archetype = EXCLUDED.preferred_archetype,
        preferred_bracket = EXCLUDED.preferred_bracket,
        keep_theme_default = EXCLUDED.keep_theme_default,
        preferred_colors = EXCLUDED.preferred_colors,
        updated_at = NOW()
    '''),
    parameters: {
      'user_id': userId,
      'preferred_archetype': preferredArchetype,
      'preferred_bracket': preferredBracket,
      'keep_theme_default': keepThemeDefault,
      'preferred_colors': preferredColors,
    },
  );
}

Map<String, dynamic> _buildRecommendationDetail({
  required String type,
  required String name,
  required String cardId,
  required int quantity,
  required String targetArchetype,
  required String confidenceLevel,
  required double cmcBefore,
  required double cmcAfter,
  required bool keepTheme,
}) {
  final confidenceScore = _confidenceScoreFromLevel(confidenceLevel);
  final action = type == 'add' ? 'entrada' : 'saída';
  final curveDelta = (cmcAfter - cmcBefore).toStringAsFixed(2);

  return {
    'type': type,
    'name': name,
    'card_id': cardId,
    'quantity': quantity,
    'reason':
        'Sugestão de $action para alinhar o deck ao plano ${targetArchetype.toLowerCase()} e melhorar consistência geral.',
    'confidence': {
      'level': confidenceLevel,
      'score': confidenceScore,
    },
    'impact_estimate': {
      'curve': 'ΔCMC $curveDelta',
      'consistency': keepTheme ? 'alta' : 'média',
      'synergy': type == 'add' ? 'melhora' : 'ajuste',
      'legality': 'mantida',
    },
  };
}

double _confidenceScoreFromLevel(String level) {
  switch (level.toLowerCase()) {
    case 'alta':
    case 'high':
      return 0.9;
    case 'média':
    case 'media':
    case 'medium':
      return 0.7;
    default:
      return 0.5;
  }
}

Future<void> _recordOptimizeFallbackTelemetry({
  required Pool pool,
  required String? userId,
  required String? deckId,
  required String mode,
  required bool recognizedFormat,
  required bool triggered,
  required bool applied,
  required bool noCandidate,
  required bool noReplacement,
  required int candidateCount,
  required int replacementCount,
  required int pairCount,
}) async {
  await pool.execute(
    Sql.named('''
      INSERT INTO ai_optimize_fallback_telemetry (
        user_id,
        deck_id,
        mode,
        recognized_format,
        triggered,
        applied,
        no_candidate,
        no_replacement,
        candidate_count,
        replacement_count,
        pair_count
      ) VALUES (
        CAST(@user_id AS uuid),
        CAST(@deck_id AS uuid),
        @mode,
        @recognized_format,
        @triggered,
        @applied,
        @no_candidate,
        @no_replacement,
        @candidate_count,
        @replacement_count,
        @pair_count
      )
    '''),
    parameters: {
      'user_id': userId,
      'deck_id': deckId,
      'mode': mode,
      'recognized_format': recognizedFormat,
      'triggered': triggered,
      'applied': applied,
      'no_candidate': noCandidate,
      'no_replacement': noReplacement,
      'candidate_count': candidateCount,
      'replacement_count': replacementCount,
      'pair_count': pairCount,
    },
  );
}

Future<Map<String, dynamic>> _loadPersistedEmptyFallbackAggregate(
    Pool pool) async {
  final result = await pool.execute('''
    SELECT
      COUNT(*)::int AS total_requests,
      SUM(CASE WHEN triggered THEN 1 ELSE 0 END)::int AS triggered_count,
      SUM(CASE WHEN applied THEN 1 ELSE 0 END)::int AS applied_count,
      SUM(CASE WHEN no_candidate THEN 1 ELSE 0 END)::int AS no_candidate_count,
      SUM(CASE WHEN no_replacement THEN 1 ELSE 0 END)::int AS no_replacement_count,
      COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours')::int AS total_requests_24h,
      SUM(CASE WHEN triggered AND created_at >= NOW() - INTERVAL '24 hours' THEN 1 ELSE 0 END)::int AS triggered_count_24h,
      SUM(CASE WHEN applied AND created_at >= NOW() - INTERVAL '24 hours' THEN 1 ELSE 0 END)::int AS applied_count_24h,
      SUM(CASE WHEN no_candidate AND created_at >= NOW() - INTERVAL '24 hours' THEN 1 ELSE 0 END)::int AS no_candidate_count_24h,
      SUM(CASE WHEN no_replacement AND created_at >= NOW() - INTERVAL '24 hours' THEN 1 ELSE 0 END)::int AS no_replacement_count_24h
    FROM ai_optimize_fallback_telemetry
  ''');

  if (result.isEmpty) {
    return {
      'all_time': {
        'request_count': 0,
        'triggered_count': 0,
        'applied_count': 0,
        'no_candidate_count': 0,
        'no_replacement_count': 0,
        'trigger_rate': 0.0,
        'apply_rate': 0.0,
      },
      'last_24h': {
        'request_count': 0,
        'triggered_count': 0,
        'applied_count': 0,
        'no_candidate_count': 0,
        'no_replacement_count': 0,
        'trigger_rate': 0.0,
        'apply_rate': 0.0,
      },
    };
  }

  final row = result.first.toColumnMap();

  final allRequests = _toInt(row['total_requests']);
  final allTriggered = _toInt(row['triggered_count']);
  final allApplied = _toInt(row['applied_count']);
  final allNoCandidate = _toInt(row['no_candidate_count']);
  final allNoReplacement = _toInt(row['no_replacement_count']);

  final requests24h = _toInt(row['total_requests_24h']);
  final triggered24h = _toInt(row['triggered_count_24h']);
  final applied24h = _toInt(row['applied_count_24h']);
  final noCandidate24h = _toInt(row['no_candidate_count_24h']);
  final noReplacement24h = _toInt(row['no_replacement_count_24h']);

  return {
    'all_time': {
      'request_count': allRequests,
      'triggered_count': allTriggered,
      'applied_count': allApplied,
      'no_candidate_count': allNoCandidate,
      'no_replacement_count': allNoReplacement,
      'trigger_rate': allRequests > 0 ? allTriggered / allRequests : 0.0,
      'apply_rate': allTriggered > 0 ? allApplied / allTriggered : 0.0,
    },
    'last_24h': {
      'request_count': requests24h,
      'triggered_count': triggered24h,
      'applied_count': applied24h,
      'no_candidate_count': noCandidate24h,
      'no_replacement_count': noReplacement24h,
      'trigger_rate': requests24h > 0 ? triggered24h / requests24h : 0.0,
      'apply_rate': triggered24h > 0 ? applied24h / triggered24h : 0.0,
    },
  };
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

bool _isBasicLandName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized == 'plains' ||
      normalized == 'island' ||
      normalized == 'swamp' ||
      normalized == 'mountain' ||
      normalized == 'forest' ||
      normalized == 'wastes';
}

int _maxCopiesForFormat({
  required String deckFormat,
  required String typeLine,
  required String name,
}) {
  final normalizedFormat = deckFormat.toLowerCase();
  final normalizedType = typeLine.toLowerCase();
  final normalizedName = name.trim().toLowerCase();

  final isBasicLand =
      normalizedType.contains('basic land') || normalizedName == 'wastes';
  if (isBasicLand) return 999;

  if (normalizedFormat == 'commander' || normalizedFormat == 'brawl') {
    return 1;
  }

  return 4;
}

List<String> _basicLandNamesForIdentity(Set<String> identity) {
  if (identity.isEmpty) return const ['Wastes'];
  final names = <String>[];
  if (identity.contains('W')) names.add('Plains');
  if (identity.contains('U')) names.add('Island');
  if (identity.contains('B')) names.add('Swamp');
  if (identity.contains('R')) names.add('Mountain');
  if (identity.contains('G')) names.add('Forest');
  return names.isEmpty ? const ['Wastes'] : names;
}

Future<Map<String, String>> _loadBasicLandIds(
    Pool pool, List<String> names) async {
  if (names.isEmpty) return const {};
  final result = await pool.execute(
    Sql.named('''
      SELECT name, id::text
      FROM cards
      WHERE name = ANY(@names)
        AND type_line LIKE 'Basic Land%'
      ORDER BY name ASC
    '''),
    parameters: {'names': names},
  );
  final map = <String, String>{};
  for (final row in result) {
    final n = row[0] as String;
    final id = row[1] as String;
    map[n] = id;
  }
  return map;
}

Future<List<Map<String, dynamic>>> _loadUniversalCommanderFallbacks({
  required Pool pool,
  required Set<String> excludeNames,
  required int limit,
}) async {
  if (limit <= 0) return const [];

  const preferred = <String>[
    'Sol Ring',
    'Arcane Signet',
    'Command Tower',
    'Mind Stone',
    'Wayfarer\'s Bauble',
    'Swiftfoot Boots',
    'Lightning Greaves',
    'Swords to Plowshares',
    'Path to Exile',
    'Beast Within',
    'Generous Gift',
    'Counterspell',
    'Negate',
    'Ponder',
    'Preordain',
    'Fact or Fiction',
    'Read the Bones',
    'Cultivate',
    'Kodama\'s Reach',
    'Farseek',
    'Nature\'s Lore',
    'Three Visits',
  ];

  final filteredPreferred = preferred
      .where((name) => !excludeNames.contains(name.toLowerCase()))
      .toList();
  if (filteredPreferred.isEmpty) return const [];

  final result = await pool.execute(
    Sql.named('''
      SELECT id::text, name
      FROM cards
      WHERE name = ANY(@names)
      ORDER BY edhrec_rank ASC NULLS LAST, name ASC
      LIMIT @limit
    '''),
    parameters: {
      'names': filteredPreferred,
      'limit': limit,
    },
  );

  return result
      .map((row) => {
            'id': row[0] as String,
            'name': row[1] as String,
          })
      .toList();
}

String _inferFunctionalRole({
  required String name,
  required String typeLine,
  required String oracleText,
}) {
  final n = name.toLowerCase();
  final t = typeLine.toLowerCase();
  final o = oracleText.toLowerCase();

  final isRampByText =
      o.contains('add {') ||
      o.contains('add one mana') ||
      o.contains('search your library for a basic land') ||
      o.contains('search your library for a land');
  final isRampByName =
      n.contains('signet') || n.contains('talisman') || n.contains('sol ring');
  if (isRampByText || isRampByName) return 'ramp';

  if (o.contains('draw a card') || o.contains('draw two cards') || o.contains('draw three cards')) {
    return 'draw';
  }

  if ((o.contains('destroy target') || o.contains('exile target')) &&
      (o.contains('creature') ||
          o.contains('artifact') ||
          o.contains('enchantment') ||
          o.contains('permanent'))) {
    return 'removal';
  }

  if (o.contains('counter target') || o.contains('counterspell')) {
    return 'interaction';
  }

  if (o.contains('you win the game') || o.contains('each opponent loses')) {
    return 'wincon';
  }

  if (o.contains('whenever') || o.contains('at the beginning of') || o.contains('sacrifice')) {
    return 'engine';
  }

  if (t.contains('creature')) return 'engine';
  return 'utility';
}

Map<String, int> _buildSlotNeedsForDeck({
  required List<Map<String, dynamic>> currentDeckCards,
  required String targetArchetype,
}) {
  final archetype = targetArchetype.toLowerCase();
  final baseTargets = <String, int>{
    'ramp': 10,
    'draw': 10,
    'removal': 8,
    'interaction': 6,
    'engine': 8,
    'wincon': 4,
    'utility': 8,
  };

  if (archetype.contains('control')) {
    baseTargets['draw'] = 12;
    baseTargets['removal'] = 10;
    baseTargets['interaction'] = 8;
    baseTargets['wincon'] = 3;
  } else if (archetype.contains('aggro')) {
    baseTargets['ramp'] = 8;
    baseTargets['draw'] = 8;
    baseTargets['engine'] = 10;
    baseTargets['wincon'] = 6;
  } else if (archetype.contains('combo')) {
    baseTargets['ramp'] = 11;
    baseTargets['draw'] = 12;
    baseTargets['interaction'] = 8;
    baseTargets['wincon'] = 5;
  }

  final current = <String, int>{
    'ramp': 0,
    'draw': 0,
    'removal': 0,
    'interaction': 0,
    'engine': 0,
    'wincon': 0,
    'utility': 0,
  };

  var nonLandTotal = 0;
  for (final c in currentDeckCards) {
    final typeLine = ((c['type_line'] as String?) ?? '').toLowerCase();
    if (typeLine.contains('land')) continue;

    final qty = (c['quantity'] as int?) ?? 1;
    final role = _inferFunctionalRole(
      name: (c['name'] as String?) ?? '',
      typeLine: (c['type_line'] as String?) ?? '',
      oracleText: (c['oracle_text'] as String?) ?? '',
    );
    current[role] = (current[role] ?? 0) + qty;
    nonLandTotal += qty;
  }

  final needs = <String, int>{};
  for (final entry in baseTargets.entries) {
    final deficit = entry.value - (current[entry.key] ?? 0);
    needs[entry.key] = deficit > 0 ? deficit : 0;
  }

  if (nonLandTotal < 58) {
    final missingNonLand = 58 - nonLandTotal;
    needs['utility'] = (needs['utility'] ?? 0) + missingNonLand;
  }

  return needs;
}

Future<List<Map<String, dynamic>>> _loadDeterministicSlotFillers({
  required Pool pool,
  required List<Map<String, dynamic>> currentDeckCards,
  required String targetArchetype,
  required Set<String> commanderColorIdentity,
  required int? bracket,
  required Set<String> excludeNames,
  Set<String>? preferredNames,
  required int limit,
}) async {
  if (limit <= 0) return const [];

  final slotNeeds = _buildSlotNeedsForDeck(
    currentDeckCards: currentDeckCards,
    targetArchetype: targetArchetype,
  );

  final candidates = await _loadCompetitiveNonLandFillers(
    pool: pool,
    commanderColorIdentity: commanderColorIdentity,
    bracket: bracket,
    excludeNames: excludeNames,
    limit: limit < 80 ? 240 : (limit * 4),
  );

  if (candidates.isEmpty) return const [];

  final scored = candidates.map((c) {
    final name = (c['name'] as String?) ?? '';
    final typeLine = (c['type_line'] as String?) ?? '';
    final oracle = (c['oracle_text'] as String?) ?? '';
    final role = _inferFunctionalRole(
      name: name,
      typeLine: typeLine,
      oracleText: oracle,
    );

    final primaryNeed = slotNeeds[role] ?? 0;
    final utilityNeed = slotNeeds['utility'] ?? 0;
    final fromAiSuggestion =
      (preferredNames ?? const <String>{}).contains(name.toLowerCase());
    final aiBoost = fromAiSuggestion ? 35 : 0;
    final score =
      primaryNeed * 100 + (role == 'utility' ? utilityNeed * 10 : 0) + aiBoost;

    return {
      ...c,
      '_role': role,
      '_score': score,
    };
  }).toList();

  scored.sort((a, b) {
    final scoreA = (a['_score'] as int?) ?? 0;
    final scoreB = (b['_score'] as int?) ?? 0;
    final byScore = scoreB.compareTo(scoreA);
    if (byScore != 0) return byScore;
    final nameA = (a['name'] as String?) ?? '';
    final nameB = (b['name'] as String?) ?? '';
    return nameA.compareTo(nameB);
  });

  return scored.take(limit).map((e) {
    return {
      'id': e['id'],
      'name': e['name'],
      'type_line': e['type_line'],
      'oracle_text': e['oracle_text'],
      'colors': e['colors'],
      'color_identity': e['color_identity'],
    };
  }).toList();
}

Future<List<Map<String, dynamic>>> _loadMetaInsightFillers({
  required Pool pool,
  required Set<String> commanderColorIdentity,
  required Set<String> excludeNames,
  required int limit,
}) async {
  if (limit <= 0) return const [];

  final identity = commanderColorIdentity.toList();
  final result = await pool.execute(
    Sql.named('''
      SELECT c.id::text, c.name, c.type_line, c.oracle_text, c.colors, c.color_identity
      FROM card_meta_insights mi
      JOIN cards c ON LOWER(c.name) = LOWER(mi.card_name)
      LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = 'commander'
      WHERE (cl.status = 'legal' OR cl.status = 'restricted' OR cl.status IS NULL)
        AND LOWER(c.name) NOT IN (SELECT LOWER(unnest(@exclude::text[])))
        AND c.type_line NOT ILIKE '%land%'
        AND c.name NOT LIKE 'A-%'
        AND c.name NOT LIKE '\_%' ESCAPE '\\'
        AND c.name NOT LIKE '%World Champion%'
        AND c.name NOT LIKE '%Heroes of the Realm%'
        AND (
          (
            c.color_identity IS NOT NULL
            AND (
              c.color_identity <@ @identity::text[]
              OR c.color_identity = '{}'
            )
          )
          OR (
            c.color_identity IS NULL
            AND (
              c.colors <@ @identity::text[]
              OR c.colors = '{}'
              OR c.colors IS NULL
            )
          )
        )
      ORDER BY mi.meta_deck_count DESC, mi.usage_count DESC, c.name ASC
      LIMIT @limit
    '''),
    parameters: {
      'exclude': excludeNames.toList(),
      'identity': identity,
      'limit': limit,
    },
  );

  return result
      .map((row) => {
            'id': row[0] as String,
            'name': row[1] as String,
            'type_line': (row[2] as String?) ?? '',
            'oracle_text': (row[3] as String?) ?? '',
            'colors': (row[4] as List?)?.cast<String>() ?? const <String>[],
            'color_identity':
                (row[5] as List?)?.cast<String>() ?? const <String>[],
          })
      .toList();
}

Future<List<Map<String, dynamic>>> _loadGuaranteedNonBasicFillers({
  required Pool pool,
  required List<Map<String, dynamic>> currentDeckCards,
  required String targetArchetype,
  required Set<String> commanderColorIdentity,
  required int? bracket,
  required Set<String> excludeNames,
  required Set<String> preferredNames,
  required int limit,
}) async {
  if (limit <= 0) return const [];

  final aggregated = <Map<String, dynamic>>[];
  final seen = <String>{};

  void addUnique(Iterable<Map<String, dynamic>> items) {
    for (final item in items) {
      final name = ((item['name'] as String?) ?? '').trim().toLowerCase();
      if (name.isEmpty || seen.contains(name)) continue;
      seen.add(name);
      aggregated.add(item);
      if (aggregated.length >= limit) return;
    }
  }

  final withBracket = await _loadDeterministicSlotFillers(
    pool: pool,
    currentDeckCards: currentDeckCards,
    targetArchetype: targetArchetype,
    commanderColorIdentity: commanderColorIdentity,
    bracket: bracket,
    excludeNames: excludeNames,
    preferredNames: preferredNames,
    limit: limit,
  );
  addUnique(withBracket);

  if (aggregated.length < limit) {
    final noBracket = await _loadDeterministicSlotFillers(
      pool: pool,
      currentDeckCards: currentDeckCards,
      targetArchetype: targetArchetype,
      commanderColorIdentity: commanderColorIdentity,
      bracket: null,
      excludeNames: excludeNames.union(seen),
      preferredNames: preferredNames,
      limit: limit - aggregated.length,
    );
    addUnique(noBracket);
  }

  if (aggregated.length < limit) {
    final metaFillers = await _loadMetaInsightFillers(
      pool: pool,
      commanderColorIdentity: commanderColorIdentity,
      excludeNames: excludeNames.union(seen),
      limit: limit - aggregated.length,
    );
    addUnique(metaFillers);
  }

  return aggregated.take(limit).toList();
}

Future<List<Map<String, dynamic>>> _loadCompetitiveNonLandFillers({
  required Pool pool,
  required Set<String> commanderColorIdentity,
  required int? bracket,
  required Set<String> excludeNames,
  required int limit,
}) async {
  if (limit <= 0) return const [];

  final identity = commanderColorIdentity.toList();
  final result = await pool.execute(
    Sql.named('''
      SELECT c.id::text, c.name, c.type_line, c.oracle_text, c.colors, c.color_identity
      FROM cards c
      LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = 'commander'
      WHERE (cl.status = 'legal' OR cl.status = 'restricted' OR cl.status IS NULL)
        AND LOWER(c.name) NOT IN (SELECT LOWER(unnest(@exclude::text[])))
        AND c.type_line NOT ILIKE '%land%'
        AND c.name NOT LIKE 'A-%'
        AND c.name NOT LIKE '\_%' ESCAPE '\'
        AND c.name NOT LIKE '%World Champion%'
        AND c.name NOT LIKE '%Heroes of the Realm%'
        AND c.oracle_text IS NOT NULL
        -- Removido filtro de LENGTH para permitir cartas com texto curto
        AND (
          (
            c.color_identity IS NOT NULL
            AND (
              c.color_identity <@ @identity::text[]
              OR c.color_identity = '{}'
            )
          )
          OR (
            c.color_identity IS NULL
            AND (
              c.colors <@ @identity::text[]
              OR c.colors = '{}'
              OR c.colors IS NULL
            )
          )
        )
      ORDER BY c.name ASC
      LIMIT 600
    '''),
    parameters: {
      'exclude': excludeNames.toList(),
      'identity': identity,
    },
  );

  var candidates = result
      .map((row) => {
            'id': row[0] as String,
            'name': row[1] as String,
            'type_line': (row[2] as String?) ?? '',
            'oracle_text': (row[3] as String?) ?? '',
            'colors': (row[4] as List?)?.cast<String>() ?? const <String>[],
            'color_identity':
                (row[5] as List?)?.cast<String>() ?? const <String>[],
          })
      .toList();

  // Fallback: se pool ficou pequeno, adicionar staples universais (ramp/draw/removal)
  if (candidates.length < limit) {
    final stapleNames = [
      'Sol Ring', 'Arcane Signet', 'Mind Stone', 'Fellwar Stone',
      'Swiftfoot Boots', 'Lightning Greaves', 'Command Tower',
      'Demonic Tutor', 'Vampiric Tutor', 'Rhystic Study', 'Necropotence',
      'Cyclonic Rift', 'Swords to Plowshares', 'Anguished Unmaking',
      'Beast Within', 'Nature''s Claim', 'Counterspell', 'Mana Drain',
      'Fact or Fiction', 'Ponder', 'Preordain', 'Brainstorm',
      'Signet', 'Talisman', 'Dark Ritual', 'Reanimate', 'Animate Dead',
      'Eternal Witness', 'Regrowth', 'Hero''s Downfall', 'Mortify',
      'Path to Exile', 'Generous Gift', 'Chaos Warp', 'Krosan Grip',
      'Disenchant', 'Return to Nature', 'Mana Leak', 'Force of Will',
      'Force of Negation', 'Teferi''s Protection', 'Toxic Deluge',
      'Blasphemous Act', 'Boardwipe', 'Draw', 'Ramp', 'Removal'
    ];
    final stapleResult = await pool.execute(
      Sql.named('''
        SELECT c.id::text, c.name, c.type_line, c.oracle_text, c.colors, c.color_identity
        FROM cards c
        LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = 'commander'
        WHERE (cl.status = 'legal' OR cl.status = 'restricted' OR cl.status IS NULL)
          AND LOWER(c.name) IN (SELECT LOWER(unnest(@names::text[])))
          AND (
            c.color_identity <@ @identity::text[]
            OR c.color_identity = '{}'
          )
      '''),
      parameters: {
        'names': stapleNames,
        'identity': identity,
      },
    );
    final stapleCandidates = stapleResult
        .map((row) => {
              'id': row[0] as String,
              'name': row[1] as String,
              'type_line': (row[2] as String?) ?? '',
              'oracle_text': (row[3] as String?) ?? '',
              'colors': (row[4] as List?)?.cast<String>() ?? const <String>[],
              'color_identity':
                  (row[5] as List?)?.cast<String>() ?? const <String>[],
            })
        .where((c) => !excludeNames.contains((c['name'] as String).toLowerCase()))
        .toList();
    candidates.addAll(stapleCandidates);
    // Log explicito
    if (candidates.isEmpty) {
      print('[COMPLETE FILLER] Pool vazio, fallback para staples universais.');
    } else if (stapleCandidates.isNotEmpty) {
      print('[COMPLETE FILLER] Pool expandido com staples universais: ${stapleCandidates.length}');
    }
  }

  if (bracket != null && candidates.isNotEmpty) {
    final decision = applyBracketPolicyToAdditions(
      bracket: bracket,
      currentDeckCards: const [],
      additionsCardsData: candidates.map((c) {
        return {
          'name': c['name'],
          'type_line': c['type_line'],
          'oracle_text': c['oracle_text'],
          'quantity': 1,
        };
      }),
    );
    final allowedSet = decision.allowed.map((e) => e.toLowerCase()).toSet();
    final filtered = candidates
        .where((c) => allowedSet.contains((c['name'] as String).toLowerCase()))
        .toList();

    // Se o filtro do bracket zerar tudo nesta etapa de emergência,
    // preferimos manter pool válido (identidade/legalidade) para evitar
    // completar com básicos em excesso.
    if (filtered.isNotEmpty) {
      candidates = filtered;
    }
  }

  return candidates.take(limit).toList();
}

/// Busca cartas substitutas sinérgicas quando filtros de cor/bracket
/// removeram adições sugeridas pela IA.
///
/// FILOSOFIA: A otimização existe para MELHORAR o deck.
/// Quando uma carta é filtrada, o correto é pedir à IA outra carta
/// que cumpra o mesmo papel funcional, não preencher com lands.
///
/// Fluxo:
/// 1. Contexto: quais cartas foram removidas do deck (e suas categorias)
/// 2. Query ao DB: buscar cartas dentro da identidade de cor, com sinergia
/// 3. Fallback: re-consultar a IA se o DB não tiver boas opções
Future<List<Map<String, dynamic>>> _findSynergyReplacements({
  required Pool pool,
  required DeckOptimizerService optimizer,
  required List<String> commanders,
  required Set<String> commanderColorIdentity,
  required String targetArchetype,
  required int? bracket,
  required bool keepTheme,
  required String? detectedTheme,
  required List<String>? coreCards,
  required int missingCount,
  required List<String> removedCards,
  required Set<String> excludeNames,
  required List<Map<String, dynamic>> allCardData,
}) async {
  final results = <Map<String, dynamic>>[];

  List<String> defaultNeedsForArchetype(String archetype) {
    final normalized = archetype.toLowerCase();
    if (normalized.contains('control')) {
      return const ['removal', 'draw', 'ramp', 'protection', 'utility'];
    }
    if (normalized.contains('aggro')) {
      return const ['creature', 'ramp', 'draw', 'removal', 'utility'];
    }
    if (normalized.contains('combo')) {
      return const ['draw', 'tutor', 'ramp', 'protection', 'utility'];
    }
    if (normalized.contains('stax')) {
      return const ['ramp', 'removal', 'protection', 'utility'];
    }
    if (normalized.contains('tribal')) {
      return const ['creature', 'draw', 'ramp', 'removal', 'utility'];
    }
    return const ['ramp', 'draw', 'removal', 'creature', 'utility'];
  }
  
  // Passo 1: Analisar os tipos funcionais das cartas que foram removidas
  // para saber QUE TIPO de carta precisamos substituir
  final functionalNeeds = <String>[]; // ex: 'draw', 'removal', 'ramp', etc.
  if (removedCards.isNotEmpty) {
    final removedTypesResult = await pool.execute(
      Sql.named('''
      SELECT name, type_line, oracle_text, color_identity
      FROM cards
      WHERE name = ANY(@names)
    '''),
      parameters: {'names': removedCards},
    );

    for (final row in removedTypesResult) {
      final oracle = ((row[2] as String?) ?? '').toLowerCase();
      final typeLine = ((row[1] as String?) ?? '').toLowerCase();

      if (oracle.contains('draw') || oracle.contains('cards')) {
        functionalNeeds.add('draw');
      } else if (oracle.contains('destroy') ||
          oracle.contains('exile') ||
          oracle.contains('counter')) {
        functionalNeeds.add('removal');
      } else if ((oracle.contains('add') && oracle.contains('mana')) ||
          typeLine.contains('land')) {
        functionalNeeds.add('ramp');
      } else if (typeLine.contains('creature')) {
        functionalNeeds.add('creature');
      } else if (typeLine.contains('artifact')) {
        functionalNeeds.add('artifact');
      } else {
        functionalNeeds.add('utility');
      }
    }
  }
  
  // Passo 2: Buscar cartas do DB que combinem com o commander e preencham o gap
  // Priorizamos cartas populares (por rank EDHREC implícito na query) dentro da identidade
  final colorIdentityArr = commanderColorIdentity.toList();
  
  // Query inteligente: buscar cartas dentro da identidade de cor,
  // que não estejam no deck nem na lista de exclusão,
  // legais em commander, ordenadas por popularidade
  final candidatesResult = await pool.execute(
    Sql.named('''
      SELECT c.id::text, c.name, c.type_line, c.oracle_text, c.color_identity
      FROM cards c
      LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = 'commander'
      WHERE (cl.status = 'legal' OR cl.status = 'restricted' OR cl.status IS NULL)
        AND LOWER(c.name) NOT IN (SELECT LOWER(unnest(@exclude::text[])))
        AND c.type_line NOT LIKE 'Basic Land%'
        AND c.name NOT LIKE 'A-%'
        AND c.name NOT LIKE '\_%' ESCAPE '\\'
        AND c.name NOT LIKE '%World Champion%'
        AND c.name NOT LIKE '%Heroes of the Realm%'
        AND c.oracle_text IS NOT NULL
        AND LENGTH(TRIM(c.oracle_text)) > 0
        AND (
          c.color_identity <@ @identity::text[]
          OR c.color_identity = '{}'
          OR c.color_identity IS NULL
        )
      ORDER BY c.edhrec_rank ASC NULLS LAST, c.name ASC
      LIMIT 300
    '''),
    parameters: {
      'exclude': excludeNames.toList(),
      'identity': colorIdentityArr,
    },
  );
  
  // Filtrar e selecionar as melhores cartas baseado nas necessidades funcionais
  final candidatePool = <Map<String, dynamic>>[];
  for (final row in candidatesResult) {
    final id = row[0] as String;
    final name = row[1] as String;
    final typeLine = ((row[2] as String?) ?? '').toLowerCase();
    final oracle = ((row[3] as String?) ?? '').toLowerCase();
    final identity = (row[4] as List?)?.cast<String>() ?? const <String>[];
    
    // Verificar identidade de cor (double check)
    if (!isWithinCommanderIdentity(
      cardIdentity: identity,
      commanderIdentity: commanderColorIdentity,
    )) continue;
    
    candidatePool.add({
      'id': id,
      'name': name,
      'type_line': typeLine,
      'oracle_text': oracle,
    });
  }
  
  // Passo 3: Selecionar as melhores cartas priorizando as necessidades funcionais
  final usedNames = <String>{};
  
  final needs = functionalNeeds.isNotEmpty
      ? functionalNeeds
      : defaultNeedsForArchetype(targetArchetype);

  // Primeiro: tentar preencher necessidades funcionais específicas
  for (var i = 0; i < missingCount && i < needs.length; i++) {
    final need = needs[i];
    Map<String, dynamic>? best;
    
    for (final candidate in candidatePool) {
      final name = (candidate['name'] as String).toLowerCase();
      if (usedNames.contains(name)) continue;
      
      final oracle = candidate['oracle_text'] as String;
      final typeLine = candidate['type_line'] as String;
      
      final matches = switch (need) {
        'draw' => oracle.contains('draw') || oracle.contains('cards'),
        'removal' => oracle.contains('destroy') || oracle.contains('exile') || oracle.contains('counter'),
        'ramp' => oracle.contains('add') && oracle.contains('mana') || typeLine.contains('land'),
        'tutor' => oracle.contains('search your library') && !oracle.contains('land'),
        'protection' => oracle.contains('hexproof') || oracle.contains('indestructible') || oracle.contains('ward'),
        'creature' => typeLine.contains('creature'),
        'artifact' => typeLine.contains('artifact'),
        _ => true, // utility: qualquer carta boa serve
      };
      
      if (matches) {
        best = candidate;
        break;
      }
    }
    
    if (best != null) {
      results.add({'id': best['id'], 'name': best['name']});
      usedNames.add((best['name'] as String).toLowerCase());
    }
  }
  
  // Se ainda faltam cartas, pegar as próximas melhores do pool (por EDHREC rank)
  if (results.length < missingCount) {
    for (final candidate in candidatePool) {
      if (results.length >= missingCount) break;
      final name = (candidate['name'] as String).toLowerCase();
      if (usedNames.contains(name)) continue;
      
      results.add({'id': candidate['id'], 'name': candidate['name']});
      usedNames.add(name);
    }
  }
  
  return results;
}
