import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/card_validation_service.dart';
import 'otimizacao.dart';

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
  Map<String, int> countCardTypes() {
    final counts = <String, int>{
      'creatures': 0,
      'instants': 0,
      'sorceries': 0,
      'enchantments': 0,
      'artifacts': 0,
      'planeswalkers': 0,
      'lands': 0,
    };
    
    for (final card in cards) {
      final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
      
      // Sistema de prioridade: cada carta é contada apenas uma vez em seu tipo principal
      // Prioridade: Land > Creature > Planeswalker > Instant > Sorcery > Artifact > Enchantment
      if (typeLine.contains('land')) {
        counts['lands'] = counts['lands']! + 1;
      } else if (typeLine.contains('creature')) {
        counts['creatures'] = counts['creatures']! + 1;
      } else if (typeLine.contains('planeswalker')) {
        counts['planeswalkers'] = counts['planeswalkers']! + 1;
      } else if (typeLine.contains('instant')) {
        counts['instants'] = counts['instants']! + 1;
      } else if (typeLine.contains('sorcery')) {
        counts['sorceries'] = counts['sorceries']! + 1;
      } else if (typeLine.contains('artifact')) {
        counts['artifacts'] = counts['artifacts']! + 1;
      } else if (typeLine.contains('enchantment')) {
        counts['enchantments'] = counts['enchantments']! + 1;
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
    final instantSorceryRatio = ((typeCounts['instants'] ?? 0) + (typeCounts['sorceries'] ?? 0)) / totalNonLands;
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
    if (avgCMC >= 2.5 && avgCMC <= 3.5 && creatureRatio >= 0.25 && creatureRatio <= 0.45) {
      return 'midrange';
    }
    
    // Default to midrange se não se encaixar em nenhuma categoria
    return 'midrange';
  }
  
  /// Gera descrição da análise do deck
  Map<String, dynamic> generateAnalysis() {
    final avgCMC = calculateAverageCMC();
    final typeCounts = countCardTypes();
    final detectedArchetype = detectArchetype();
    
    return {
      'detected_archetype': detectedArchetype,
      'average_cmc': avgCMC.toStringAsFixed(2),
      'type_distribution': typeCounts,
      'total_cards': cards.length,
      'mana_curve_assessment': _assessManaCurve(avgCMC, detectedArchetype),
      'archetype_confidence': _calculateConfidence(avgCMC, typeCounts, detectedArchetype),
    };
  }
  
  String _assessManaCurve(double avgCMC, String archetype) {
    switch (archetype) {
      case 'aggro':
        if (avgCMC > 2.5) return 'ALERTA: Curva muito alta para Aggro. Ideal: < 2.5';
        if (avgCMC < 1.8) return 'BOA: Curva agressiva ideal';
        return 'OK: Curva aceitável para Aggro';
      case 'control':
        if (avgCMC < 2.5) return 'ALERTA: Curva muito baixa para Control. Ideal: > 3.0';
        return 'BOA: Curva adequada para Control';
      case 'midrange':
        if (avgCMC < 2.3 || avgCMC > 3.8) return 'ALERTA: Curva fora do ideal para Midrange (2.5-3.5)';
        return 'BOA: Curva equilibrada para Midrange';
      default:
        return 'OK: Curva dentro de parâmetros aceitáveis';
    }
  }
  
  String _calculateConfidence(double avgCMC, Map<String, int> counts, String archetype) {
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

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final deckId = body['deck_id'] as String?;
    final archetype = body['archetype'] as String?;

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
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Deck not found'});
    }
    
    final deckName = deckResult.first[0] as String;
    final deckFormat = deckResult.first[1] as String;

    // Get Cards with CMC for analysis
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, dc.is_commander, c.type_line, c.mana_cost, c.colors,
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
               ) as cmc
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
    int landCount = 0;

    for (final row in cardsResult) {
      final name = row[0] as String;
      final isCmdr = row[1] as bool;
      final typeLine = (row[2] as String?) ?? '';
      final manaCost = (row[3] as String?) ?? '';
      final colors = (row[4] as List?)?.cast<String>() ?? [];
      final cmc = (row[5] as num?)?.toDouble() ?? 0.0;
      
      // Coletar cores do deck
      deckColors.addAll(colors);
      
      final cardData = {
        'name': name,
        'type_line': typeLine,
        'mana_cost': manaCost,
        'colors': colors,
        'cmc': cmc,
        'is_commander': isCmdr,
      };
      
      allCardData.add(cardData);
      
      if (isCmdr) {
        commanders.add(name);
      } else {
        otherCards.add(name);
        if (typeLine.toLowerCase().contains('land')) {
          landCount++;
        }
      }
    }

    // 1.5 Análise de Arquétipo do Deck (Mantido para estatísticas do frontend)
    final analyzer = DeckArchetypeAnalyzer(allCardData, deckColors.toList());
    final deckAnalysis = analyzer.generateAnalysis();

    // 2. Carregar API Key e instanciar serviço de otimização
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      // Mock response for development quando não há API key
      return Response.json(body: {
        'removals': ['Basic Land', 'Weak Card'],
        'additions': ['Sol Ring', 'Arcane Signet'],
        'reasoning': 'Mock optimization para arquétipo $archetype: Adicionando staples recomendados.',
        'deck_analysis': deckAnalysis,
        'is_mock': true
      });
    }

    // 3. Preparar dados do deck para o serviço de otimização
    final deckData = {
      'cards': allCardData,
      'colors': deckColors.toList(),
      'name': deckName,
      'format': deckFormat,
      'land_count': landCount,
    };

    // 4. Instanciar e chamar o DeckOptimizerService
    final optimizerService = DeckOptimizerService(apiKey);
    
    Map<String, dynamic> optimizationResult;
    try {
      optimizationResult = await optimizerService.optimizeDeck(
        deckData: deckData,
        commanders: commanders,
        targetArchetype: archetype,
      );
    } on Exception catch (e) {
      // Tratamento de erros do Scryfall ou OpenAI
      print('Erro no serviço de otimização: $e');
      return Response.json(
        statusCode: HttpStatus.serviceUnavailable,
        body: {
          'error': 'Falha no serviço de otimização. Por favor, tente novamente.',
          'details': e.toString(),
          'deck_analysis': deckAnalysis,
        },
      );
    }

    // 5. Validar cartas sugeridas pela IA contra o banco de dados
    final validationService = CardValidationService(pool);
    
    final removals = (optimizationResult['removals'] as List?)?.cast<String>() ?? [];
    final additions = (optimizationResult['additions'] as List?)?.cast<String>() ?? [];
    
    final sanitizedRemovals = removals.map(CardValidationService.sanitizeCardName).toList();
    final sanitizedAdditions = additions.map(CardValidationService.sanitizeCardName).toList();
    
    // Validar todas as cartas sugeridas
    final allSuggestions = [...sanitizedRemovals, ...sanitizedAdditions];
    final validation = await validationService.validateCardNames(allSuggestions);
    
    // Filtrar apenas cartas válidas e remover duplicatas
    final validRemovals = sanitizedRemovals.where((name) {
      return (validation['valid'] as List).any((card) => 
        (card['name'] as String).toLowerCase() == name.toLowerCase()
      );
    }).toSet().toList();
    
    final validAdditions = sanitizedAdditions.where((name) {
      return (validation['valid'] as List).any((card) => 
        (card['name'] as String).toLowerCase() == name.toLowerCase()
      );
    }).toSet().toList();
    
    // 6. Preparar resposta final
    final invalidCards = validation['invalid'] as List<String>;
    final suggestions = validation['suggestions'] as Map<String, List<String>>;
    
    final responseBody = <String, dynamic>{
      'removals': validRemovals,
      'additions': validAdditions,
      'reasoning': optimizationResult['reasoning'] ?? 'Otimização baseada em análise estatística e sinergias do comandante.',
      'deck_analysis': deckAnalysis,
    };
    
    // Adicionar avisos se houver cartas inválidas
    if (invalidCards.isNotEmpty) {
      responseBody['warnings'] = {
        'invalid_cards': invalidCards,
        'message': 'Algumas cartas sugeridas pela IA não foram encontradas e foram removidas',
        'suggestions': suggestions,
      };
    }
    
    return Response.json(body: responseBody);

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}
