import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/color_identity.dart';
import '../../../lib/card_validation_service.dart';
import '../../../lib/ai/otimizacao.dart';
import '../../../lib/ai/optimization_validator.dart';
import '../../../lib/ai/edhrec_service.dart';
import '../../../lib/logger.dart';
import '../../../lib/edh_bracket_policy.dart';

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

    // Pick highest scoring theme
    final best = themeScores.entries.reduce(
        (a, b) => a.value >= b.value ? a : b);

    if (best.value > 0.0) {
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
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final deckId = body['deck_id'] as String?;
    final archetype = body['archetype'] as String?;
    final bracketRaw = body['bracket'];
    final bracket =
        bracketRaw is int ? bracketRaw : int.tryParse('${bracketRaw ?? ''}');
    final keepTheme = body['keep_theme'] as bool? ?? true;

    if (deckId == null || archetype == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'deck_id and archetype are required'},
      );
    }

    // 1. Fetch Deck Data
    final pool = context.read<Pool>();

    // Get Deck Info
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format FROM decks WHERE id = @id'),
      parameters: {'id': deckId},
    );

    if (deckResult.isEmpty) {
      return Response.json(
          statusCode: HttpStatus.notFound, body: {'error': 'Deck not found'});
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
      final deckFormat = (deckResult.first[1] as String).toLowerCase();
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

        final addedCountsById = <String, int>{};
        final blockedByBracketAll = <Map<String, dynamic>>[];
        final filteredByIdentityAll = <String>[];
        final invalidAll = <String>[];

        var iterations = 0;
        var virtualTotal = currentTotalCards;
        while (iterations < maxIterations && virtualTotal < maxTotal) {
          iterations++;
          final missingNow = maxTotal - virtualTotal;

          final iterResponse = await optimizer.completeDeck(
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

          final rawAdditions =
              (iterResponse['additions'] as List?)?.cast<String>() ?? const [];
          if (rawAdditions.isEmpty) break;

          // Sanitiza
          final sanitized =
              rawAdditions.map(CardValidationService.sanitizeCardName).toList();

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

            if (!isBasic) {
              // Já existe?
              if ((virtualCountsById[id] ?? 0) > 0) continue;
            }

            virtualCountsById[id] = (virtualCountsById[id] ?? 0) + 1;
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
              
              for (final spell in synergySpells) {
                if (virtualTotal >= maxTotal) break;
                final id = spell['id'] as String;
                final name = spell['name'] as String;
                
                if ((virtualCountsById[id] ?? 0) > 0) continue; // já existe
                
                virtualCountsById[id] = 1;
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
              Log.d('  Spells sinérgicas adicionadas: ${synergySpells.length}');
            } catch (e) {
              Log.w('Falha ao buscar spells sinérgicas: $e');
            }
          }
          
          // Depois adicionar lands para o restante
          if (virtualTotal < maxTotal) {
            var landsToAdd = maxTotal - virtualTotal;
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
        }

        // Constrói resposta "complete" final (aggregated)
        final additionsDetailed = <Map<String, dynamic>>[];
        for (final entry in addedCountsById.entries) {
          additionsDetailed.add({
            'card_id': entry.key,
            'quantity': entry.value,
          });
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
        jsonResponse['mode'] = 'optimize';
      }
    } catch (e, stackTrace) {
      Log.e('Optimization failed: $e\nStack trace:\n$stackTrace');
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'Optimization failed', 'details': e.toString()},
      );
    }

    // Se o modo complete já veio “determinístico” (com card_id/quantity),
    // devolve diretamente sem passar pelo fluxo antigo de validação por nomes.
    if (jsonResponse['mode'] == 'complete' &&
        jsonResponse['additions_detailed'] is List) {
      final additionsDetailed = (jsonResponse['additions_detailed'] as List)
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

      final ids = additionsDetailed.map((e) => e['card_id'] as String).toList();
      final namesById = <String, String>{};
      Map<String, dynamic>? postAnalysisComplete;
      
      if (ids.isNotEmpty) {
        final r = await pool.execute(
          Sql.named('SELECT id::text, name FROM cards WHERE id = ANY(@ids)'),
          parameters: {'ids': ids},
        );
        for (final row in r) {
          namesById[row[0] as String] = row[1] as String;
        }
        
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
            final cardId = add['card_id'] as String;
            final qty = add['quantity'] as int;
            final data = additionsData.firstWhere(
              (d) => (d['name'] as String).toLowerCase() == (namesById[cardId] ?? '').toLowerCase(),
              orElse: () => {'name': namesById[cardId] ?? '', 'type_line': '', 'mana_cost': '', 'colors': <String>[], 'cmc': 0.0, 'oracle_text': ''},
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
            .map((e) => namesById[e['card_id'] as String] ?? e['card_id'])
            .toList(),
        'additions_detailed': additionsDetailed
            .map((e) => {
                  'card_id': e['card_id'],
                  'quantity': e['quantity'],
                  'name': namesById[e['card_id'] as String],
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

    // Suporte ao formato "swaps" (retornado pelo prompt.md)
    if (jsonResponse.containsKey('swaps')) {
      final swaps = jsonResponse['swaps'] as List;
      for (var swap in swaps) {
        if (swap is Map) {
          final out = (swap['out'] as String?) ?? '';
          final inCard = (swap['in'] as String?) ?? '';
          if (out.isNotEmpty) removals.add(out);
          if (inCard.isNotEmpty) additions.add(inCard);
        }
      }
    }
    // Suporte ao formato "changes" (alternativo)
    else if (jsonResponse.containsKey('changes')) {
      final changes = jsonResponse['changes'] as List;
      for (var change in changes) {
        if (change is Map) {
          final rem = (change['remove'] as String?) ?? '';
          final add = (change['add'] as String?) ?? '';
          if (rem.isNotEmpty) removals.add(rem);
          if (add.isNotEmpty) additions.add(add);
        }
      }
    }
    // Suporte ao formato "suggestions" (fallback genérico)
    else if (jsonResponse.containsKey('suggestions')) {
      final suggestions = jsonResponse['suggestions'] as List;
      for (var sug in suggestions) {
        if (sug is Map) {
          final out = (sug['out'] ?? sug['remove'] ?? '') as String;
          final inCard = (sug['in'] ?? sug['add'] ?? '') as String;
          if (out.isNotEmpty) removals.add(out);
          if (inCard.isNotEmpty) additions.add(inCard);
        }
      }
    } else {
      // Fallback para formato antigo
      removals = (jsonResponse['removals'] as List?)?.cast<String>() ?? [];
      additions = (jsonResponse['additions'] as List?)?.cast<String>() ?? [];
    }

    // WARN: Se parsing resultou em listas vazias, logar para diagnóstico
    final isComplete = jsonResponse['mode'] == 'complete';
    if (removals.isEmpty && additions.isEmpty && !isComplete) {
      Log.w('⚠️ [AI Optimize] IA retornou formato não reconhecido. Keys: ${jsonResponse.keys.toList()}');
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

    final deckNamesLower = allCardData
        .map((c) => ((c['name'] as String?) ?? '').toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    final commanderLower = commanders.map((c) => c.toLowerCase()).toSet();
    final coreLower =
        themeProfile.coreCards.map((c) => c.toLowerCase()).toSet();
    final blockedByTheme = <String>[];

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
      for (final n in validAdditions) {
        countsByName[n] = (countsByName[n] ?? 0) + 1;
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

    final responseBody = {
      'mode': jsonResponse['mode'],
      'constraints': {
        'keep_theme': keepTheme,
      },
      'theme': themeProfile.toJson(),
      'removals': validRemovals,
      'additions': validAdditions,
      'reasoning': jsonResponse['reasoning'],
      'deck_analysis': deckAnalysis,
      'post_analysis':
          postAnalysis, // Retorna a análise futura para o front mostrar
      'validation_warnings': validationWarnings,
      'bracket': bracket,
      'target_additions': jsonResponse['target_additions'],
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
        : validAdditions
            .map((name) {
              final v = validByNameLower[name.toLowerCase()];
              if (v == null || v['id'] == null) return null;
              return {'name': v['name'], 'card_id': v['id'], 'quantity': 1};
            })
            .where((e) => e != null)
            .toList();

    // Gerar removals_detailed apenas para cartas com card_id válido
    responseBody['removals_detailed'] = validRemovals
        .map((name) {
          final v = validByNameLower[name.toLowerCase()];
          if (v == null || v['id'] == null) return null;
          return {'name': v['name'], 'card_id': v['id']};
        })
        .where((e) => e != null)
        .toList();

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

    if (warnings.isNotEmpty) {
      responseBody['warnings'] = warnings;
    }

    return Response.json(body: responseBody);
  } catch (e) {
    Log.e('handler: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
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
  
  // Passo 1: Analisar os tipos funcionais das cartas que foram removidas
  // para saber QUE TIPO de carta precisamos substituir
  final removedTypesResult = await pool.execute(
    Sql.named('''
      SELECT name, type_line, oracle_text, color_identity
      FROM cards
      WHERE name = ANY(@names)
    '''),
    parameters: {'names': removedCards},
  );
  
  final functionalNeeds = <String>[]; // ex: 'draw', 'removal', 'ramp', etc.
  for (final row in removedTypesResult) {
    final oracle = ((row[2] as String?) ?? '').toLowerCase();
    final typeLine = ((row[1] as String?) ?? '').toLowerCase();
    
    if (oracle.contains('draw') || oracle.contains('cards')) {
      functionalNeeds.add('draw');
    } else if (oracle.contains('destroy') || oracle.contains('exile') || oracle.contains('counter')) {
      functionalNeeds.add('removal');
    } else if ((oracle.contains('add') && oracle.contains('mana')) || typeLine.contains('land')) {
      functionalNeeds.add('ramp');
    } else if (typeLine.contains('creature')) {
      functionalNeeds.add('creature');
    } else if (typeLine.contains('artifact')) {
      functionalNeeds.add('artifact');
    } else {
      functionalNeeds.add('utility');
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
      WHERE (cl.status IS NULL OR cl.status = 'legal' OR cl.status = 'restricted')
        AND LOWER(c.name) NOT IN (SELECT LOWER(unnest(@exclude::text[])))
        AND c.type_line NOT LIKE 'Basic Land%'
        AND (
          c.color_identity <@ @identity::text[]
          OR c.color_identity = '{}'
          OR c.color_identity IS NULL
        )
      ORDER BY c.edhrec_rank ASC NULLS LAST
      LIMIT 50
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
  
  // Primeiro: tentar preencher necessidades funcionais específicas
  for (var i = 0; i < missingCount && i < functionalNeeds.length; i++) {
    final need = functionalNeeds[i];
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
