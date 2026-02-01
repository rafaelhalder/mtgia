import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/color_identity.dart';
import '../../../lib/card_validation_service.dart';
import '../../../lib/ai/otimizacao.dart';
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
  
  /// Analisa a base de mana (Devotion vs Sources)
  Map<String, dynamic> analyzeManaBase() {
    final manaSymbols = {'W': 0, 'U': 0, 'B': 0, 'R': 0, 'G': 0};
    final landSources = {'W': 0, 'U': 0, 'B': 0, 'R': 0, 'G': 0, 'Any': 0};
    
    // 1. Contar símbolos de mana nas cartas (Devotion)
    for (final card in cards) {
      final manaCost = (card['mana_cost'] as String?) ?? '';
      for (final color in manaSymbols.keys) {
        manaSymbols[color] = manaSymbols[color]! + manaCost.split(color).length - 1;
      }
    }
    
    // 2. Contar fontes de mana nos terrenos (Heurística melhorada via Oracle Text)
    for (final card in cards) {
      final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
      if (typeLine.contains('land')) {
        final cardColors = (card['colors'] as List?)?.cast<String>() ?? [];
        final oracleText = ((card['oracle_text'] as String?) ?? '').toLowerCase();
        
        // Detecção de Rainbow Lands via texto (sem hardcode de nomes)
        if (oracleText.contains('add one mana of any color') || 
            oracleText.contains('add one mana of any type')) {
           landSources['Any'] = landSources['Any']! + 1;
        } 
        // Detecção de Fetch Lands (simplificada)
        else if (oracleText.contains('search your library for') && 
                 (oracleText.contains('plains') || oracleText.contains('island') || 
                  oracleText.contains('swamp') || oracleText.contains('mountain') || 
                  oracleText.contains('forest'))) {
           // Fetch lands contam como "Any" das cores que buscam, mas para simplificar a heurística
           // e evitar complexidade excessiva, vamos considerar como "Any" se buscar 2+ tipos,
           // ou contar especificamente se for simples.
           // Por segurança, Fetchs genéricas contam como Any no contexto de correção de cor.
           landSources['Any'] = landSources['Any']! + 1;
        }
        else if (cardColors.isEmpty) {
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
    final totalSymbols = symbols.values.reduce((a, b) => a + b);
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
    final bracketRaw = body['bracket'];
    final bracket = bracketRaw is int ? bracketRaw : int.tryParse('${bracketRaw ?? ''}');

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
          normalizeColorIdentity(colorIdentity.isNotEmpty ? colorIdentity : colors),
        );
      } else {
        // Incluir texto da carta para a IA analisar sinergia real
        // Truncar texto muito longo para economizar tokens
        final cleanText = oracleText.replaceAll('\n', ' ').trim();
        final truncatedText = cleanText.length > 150 ? '${cleanText.substring(0, 147)}...' : cleanText;
        
        if (truncatedText.isNotEmpty) {
          otherCards.add('$name (Type: $typeLine, Text: $truncatedText)');
        } else {
          otherCards.add('$name (Type: $typeLine)');
        }


      }
    }    // 1.5 Análise de Arquétipo do Deck
    final analyzer = DeckArchetypeAnalyzer(allCardData, deckColors.toList());
    final deckAnalysis = analyzer.generateAnalysis();
    
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
        'reasoning': 'Mock optimization (No API Key): Adicionando staples recomendados.',
        'deck_analysis': deckAnalysis,
        'is_mock': true
      });
    }

    final optimizer = DeckOptimizerService(apiKey);
    
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
          );

          final rawAdditions =
              (iterResponse['additions'] as List?)?.cast<String>() ?? const [];
          if (rawAdditions.isEmpty) break;

          // Sanitiza
          final sanitized = rawAdditions
              .map(CardValidationService.sanitizeCardName)
              .toList();

          // Valida existência no DB
          final validationService = CardValidationService(pool);
          final validation = await validationService.validateCardNames(sanitized);
          invalidAll.addAll((validation['invalid'] as List?)?.cast<String>() ?? const []);

          final validList = (validation['valid'] as List)
              .cast<Map<String, dynamic>>();
          final validNames = validList
              .map((v) => (v['name'] as String))
              .toList();
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

        // Fallback final: completa o resto com básicos
        if (virtualTotal < maxTotal) {
          var missing = maxTotal - virtualTotal;
          final basicNames = _basicLandNamesForIdentity(commanderColorIdentity);
          final basicsWithIds = await _loadBasicLandIds(pool, basicNames);
          if (basicsWithIds.isNotEmpty) {
            final keys = basicsWithIds.keys.toList();
            var i = 0;
            while (missing > 0) {
              final name = keys[i % keys.length];
              final id = basicsWithIds[name]!;
              virtualCountsById[id] = (virtualCountsById[id] ?? 0) + 1;
              addedCountsById[id] = (addedCountsById[id] ?? 0) + 1;
              virtualTotal += 1;
              missing--;
              i++;
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
              ? 'Deck completado com base no arquétipo e bracket.'
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
        );
        jsonResponse['mode'] = 'optimize';
      }
    } catch (e) {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'Optimization failed: $e'},
      );
    }

    // Se o modo complete já veio “determinístico” (com card_id/quantity),
    // devolve diretamente sem passar pelo fluxo antigo de validação por nomes.
    if (jsonResponse['mode'] == 'complete' &&
        jsonResponse['additions_detailed'] is List) {
      final additionsDetailed =
          (jsonResponse['additions_detailed'] as List).whereType<Map>().map((m) {
        final mm = m.cast<String, dynamic>();
        return {
          'card_id': mm['card_id']?.toString(),
          'quantity': mm['quantity'] as int? ?? 1,
        };
      }).where((m) => (m['card_id'] as String?)?.isNotEmpty ?? false).toList();

      final ids = additionsDetailed.map((e) => e['card_id'] as String).toList();
      final namesById = <String, String>{};
      if (ids.isNotEmpty) {
        final r = await pool.execute(
          Sql.named('SELECT id::text, name FROM cards WHERE id = ANY(@ids)'),
          parameters: {'ids': ids},
        );
        for (final row in r) {
          namesById[row[0] as String] = row[1] as String;
        }
      }

      final responseBody = {
        'mode': 'complete',
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
        'post_analysis': null,
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
             final out = swap['out'] as String?;
             final inCard = swap['in'] as String?;
             if (out != null && out.isNotEmpty) removals.add(out);
             if (inCard != null && inCard.isNotEmpty) additions.add(inCard);
           }
        }
      }
      // Suporte ao formato "changes" (alternativo)
      else if (jsonResponse.containsKey('changes')) {
        final changes = jsonResponse['changes'] as List;
        for (var change in changes) {
           if (change is Map) {
             removals.add(change['remove'] as String);
             additions.add(change['add'] as String);
           }
        }
      } else {
        // Fallback para formato antigo
        removals = (jsonResponse['removals'] as List?)?.cast<String>() ?? [];
        additions = (jsonResponse['additions'] as List?)?.cast<String>() ?? [];
      }

      // Suporte ao modo "complete"
      final isComplete = jsonResponse['mode'] == 'complete';
      if (isComplete) {
        removals = [];
        // Quando veio do loop, preferimos additions_detailed.
        final fromDetailed =
            (jsonResponse['additions_detailed'] as List?)?.whereType<Map>().toList();
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
        final minCount =
            removals.length < additions.length ? removals.length : additions.length;

        if (removals.length != additions.length) {
          Log.w(
            '⚠️ [AI Optimize] Ajustando desequilíbrio: -${removals.length} / +${additions.length} -> $minCount',
          );
          removals = removals.take(minCount).toList();
          additions = additions.take(minCount).toList();
        }
      }
      
      final sanitizedRemovals = removals.map(CardValidationService.sanitizeCardName).toList();
      final sanitizedAdditions = additions.map(CardValidationService.sanitizeCardName).toList();
      
      // Validar todas as cartas sugeridas
      final allSuggestions = [...sanitizedRemovals, ...sanitizedAdditions];
      final validation = await validationService.validateCardNames(allSuggestions);
      final validList = (validation['valid'] as List).cast<Map<String, dynamic>>();
      final validByNameLower = <String, Map<String, dynamic>>{};
      for (final v in validList) {
        final n = (v['name'] as String).toLowerCase();
        validByNameLower[n] = v;
      }
      
      // Filtrar apenas cartas válidas e remover duplicatas
      var validRemovals = sanitizedRemovals.where((name) {
        return (validation['valid'] as List).any((card) => 
          (card['name'] as String).toLowerCase() == name.toLowerCase()
        );
      }).toSet().toList();
      
      // No modo complete, preservamos repetição (para básicos) e ordem.
      // No modo optimize (swaps), mantemos set para evitar duplicatas.
      var validAdditions = sanitizedAdditions.where((name) {
        return (validation['valid'] as List).any((card) =>
            (card['name'] as String).toLowerCase() == name.toLowerCase());
      }).toList();
      if (!isComplete) {
        validAdditions = validAdditions.toSet().toList();
      }

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
      if (bracket != null &&
          commanders.isNotEmpty &&
          validAdditions.isNotEmpty) {
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
        final desired = targetAdditions > 0 ? targetAdditions : validAdditions.length;

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
          final id =
              v?['id']?.toString() ?? basicsWithIds[entry.key]?.toString();
          final name = v?['name']?.toString() ?? entry.key;
          if (id == null || id.isEmpty) continue;
          additionsDetailed.add({
            'name': name,
            'card_id': id,
            'quantity': entry.value,
          });
        }

        // Mantém additions como lista simples (única) para UI; o app aplica via additions_detailed.
        validAdditions = additionsDetailed.map((e) => e['name'] as String).toList();
      }

      // Re-aplicar equilíbrio após validação
      if (jsonResponse['mode'] != 'complete') {
        final finalMinCount = validRemovals.length < validAdditions.length
            ? validRemovals.length
            : validAdditions.length;
        if (validRemovals.length != validAdditions.length) {
          validRemovals = validRemovals.take(finalMinCount).toList();
          validAdditions = validAdditions.take(finalMinCount).toList();
        }
      }
      
      // --- VERIFICAÇÃO PÓS-OTIMIZAÇÃO (Virtual Deck Analysis) ---
      // Simular o deck como ficaria se as mudanças fossem aplicadas e re-analisar
      Map<String, dynamic>? postAnalysis;
      List<String> validationWarnings = [];
      
      if (validAdditions.isNotEmpty) {
        try {
          // 1. Buscar dados completos das cartas sugeridas (para análise de mana/tipo)
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
              WHERE name = ANY(@names)
            '''),
            parameters: {'names': validAdditions},
          );
          
          final additionsData = additionsDataResult.map((row) => {
            'name': row[0] as String,
            'type_line': row[1] as String,
            'mana_cost': row[2] as String,
            'colors': (row[3] as List?)?.cast<String>() ?? [],
            'cmc': (row[4] as num?)?.toDouble() ?? 0.0,
            'oracle_text': row[5] as String,
          }).toList();

          // 2. Criar Deck Virtual (Clone do atual - Remoções + Adições)
          final virtualDeck = List<Map<String, dynamic>>.from(allCardData);
          
          // Remover cartas sugeridas (pelo nome)
          virtualDeck.removeWhere((c) => validRemovals.contains(c['name']));
          
          // Adicionar novas cartas
          virtualDeck.addAll(additionsData);
          
          // 3. Rodar Análise no Deck Virtual
          final postAnalyzer = DeckArchetypeAnalyzer(virtualDeck, deckColors.toList());
          postAnalysis = postAnalyzer.generateAnalysis();
          
          // 4. Comparar Antes vs Depois (Validação Lógica)
          final preManaIssues = (deckAnalysis['mana_base_assessment'] as String).contains('Falta mana');
          final postManaIssues = (postAnalysis['mana_base_assessment'] as String).contains('Falta mana');
          
          if (!preManaIssues && postManaIssues) {
            validationWarnings.add('⚠️ ATENÇÃO: As sugestões da IA podem piorar sua base de mana.');
          }
          
          final preCurve = double.parse(deckAnalysis['average_cmc'] as String);
          final postCurve = double.parse(postAnalysis['average_cmc'] as String);
          
          if (targetArchetype.toLowerCase() == 'aggro' && postCurve > preCurve) {
             validationWarnings.add('⚠️ ATENÇÃO: O deck está ficando mais lento (CMC aumentou), o que é ruim para Aggro.');
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
        'removals': validRemovals,
        'additions': validAdditions,
        'reasoning': jsonResponse['reasoning'],
        'deck_analysis': deckAnalysis,
        'post_analysis': postAnalysis, // Retorna a análise futura para o front mostrar
        'validation_warnings': validationWarnings,
        'bracket': bracket,
        'target_additions': jsonResponse['target_additions'],
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
      if (addDet.length != remDet.length && jsonResponse['mode'] != 'complete') {
        final minLen = addDet.length < remDet.length ? addDet.length : remDet.length;
        responseBody['additions_detailed'] = addDet.take(minLen).toList();
        responseBody['removals_detailed'] = remDet.take(minLen).toList();
        // Também ajustar as listas simples para UI consistente
        validRemovals = validRemovals.take(minLen).toList();
        validAdditions = validAdditions.take(minLen).toList();
        responseBody['removals'] = validRemovals;
        responseBody['additions'] = validAdditions;
      }
      
      final warnings = <String, dynamic>{};

      // Adicionar avisos se houver cartas inválidas
      if (invalidCards.isNotEmpty) {
        warnings.addAll({
          'invalid_cards': invalidCards,
          'message': 'Algumas cartas sugeridas pela IA não foram encontradas e foram removidas',
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

      if (warnings.isNotEmpty) {
        responseBody['warnings'] = warnings;
      }
      
      return Response.json(body: responseBody);


  } catch (e) {
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

Future<Map<String, String>> _loadBasicLandIds(Pool pool, List<String> names) async {
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
