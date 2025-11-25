import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/card_validation_service.dart';
import '../../../lib/format_staples_service.dart';
import '../../../lib/archetype_counters_service.dart';

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

/// Busca cartas no Scryfall ordenadas por EDHREC (popularidade)
Future<List<String>> _fetchScryfallCards(String query, int limit) async {
  try {
    // Adiciona filtro de commander e remove banidas automaticamente
    final q = query.isEmpty ? 'format:commander -is:banned' : '$query format:commander -is:banned';
    
    final uri = Uri.https('api.scryfall.com', '/cards/search', {
      'q': q,
      'order': 'edhrec',
    });
    
    final response = await http.get(uri);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> cards = data['data'];
      return cards.take(limit).map<String>((c) => c['name'] as String).toList();
    }
  } catch (e) {
    print('Erro ao buscar no Scryfall ($query): $e');
  }
  return [];
}

/// Gera recomendações específicas por arquétipo
/// ATUALIZADO: Agora usa FormatStaplesService para buscar dados dinâmicos do banco/Scryfall
/// Evita hardcoded staples e mantém dados sempre atualizados
Future<Map<String, List<String>>> getArchetypeRecommendations(
  String archetype, 
  List<String> colors,
  Pool pool,
) async {
  final recommendations = <String, List<String>>{
    'staples': [],
    'avoid': [],
    'priority': [],
  };

  final staplesService = FormatStaplesService(pool);

  try {
    // 1. Buscar staples universais do formato (via DB ou Scryfall API)
    final universalStaples = await staplesService.getStaples(
      format: 'commander',
      colors: colors,
      limit: 20,
    );

    if (universalStaples.isNotEmpty) {
      recommendations['staples']!.addAll(
        universalStaples.map((s) => s['name'] as String)
      );
    } else {
      // Fallback mínimo apenas se ambos DB e Scryfall falharem
      recommendations['staples']!.addAll(['Sol Ring', 'Arcane Signet', 'Command Tower']);
    }

    // 2. Buscar staples específicos do arquétipo (via DB ou Scryfall API)
    final archetypeStaples = await staplesService.getStaples(
      format: 'commander',
      colors: colors,
      archetype: archetype.toLowerCase(),
      limit: 15,
    );

    if (archetypeStaples.isNotEmpty) {
      recommendations['staples']!.addAll(
        archetypeStaples.map((s) => s['name'] as String)
      );
    }

    // 3. Lógica específica para Infect (geralmente é Aggro/Combo)
    if (archetype.toLowerCase().contains('infect')) {
      // Busca staples de infect dinamicamente via Scryfall
      final infectStaples = await _fetchScryfallCards('oracle:infect', 15);
      recommendations['staples']!.addAll(infectStaples);

      if (colors.contains('G')) {
        final pumpSpells = await _fetchScryfallCards('function:pump-spell color:G', 10);
        recommendations['priority']!.addAll(pumpSpells);
      }

      recommendations['priority']!.addAll([
        'Protection', 'Evasion (Unblockable/Flying)'
      ]);
      recommendations['avoid']!.addAll([
        'Cartas de lifegain', 'Estratégias lentas', 'Cartas que dependem de dano normal'
      ]);
      return recommendations;
    }

    // 4. Recomendações de "avoid" e "priority" por arquétipo
    // Estas são heurísticas de estratégia, não listas de cartas específicas
    switch (archetype.toLowerCase()) {
      case 'aggro':
        recommendations['avoid']!.addAll([
          'Cartas com CMC > 5', 'Criaturas defensivas', 'Removal lento'
        ]);
        recommendations['priority']!.addAll([
          'Haste enablers', 'Anthems (+1/+1)', 'Card draw rápido'
        ]);
        break;
      case 'control':
        recommendations['avoid']!.addAll([
          'Criaturas vanilla', 'Cartas agressivas sem utilidade'
        ]);
        recommendations['priority']!.addAll([
          'Counters', 'Removal eficiente', 'Card advantage', 'Wipes'
        ]);
        break;
      case 'combo':
        recommendations['avoid']!.addAll([
          'Cartas que não avançam o combo', 'Creatures irrelevantes'
        ]);
        recommendations['priority']!.addAll([
          'Tutors', 'Proteção de combo', 'Card draw', 'Fast mana'
        ]);
        break;
      case 'midrange':
        recommendations['avoid']!.addAll([
          'Cartas muito situacionais', 'Win-more cards'
        ]);
        recommendations['priority']!.addAll([
          'Valor creatures', 'Flexible removal', 'Card advantage engines'
        ]);
        break;
      default:
        break;
    }

    // 5. Buscar staples por categoria (ramp, draw, removal) dinamicamente
    if (colors.isNotEmpty) {
      final rampStaples = await staplesService.getStaplesByCategory(
        format: 'commander',
        category: 'ramp',
        colors: colors,
        limit: 5,
      );
      recommendations['staples']!.addAll(rampStaples);

      final drawStaples = await staplesService.getStaplesByCategory(
        format: 'commander',
        category: 'draw',
        colors: colors,
        limit: 5,
      );
      recommendations['staples']!.addAll(drawStaples);
    }

    // 6. Buscar hate cards para arquétipos comuns (via ArchetypeCountersService)
    final countersService = ArchetypeCountersService(pool);
    final commonArchetypes = ['graveyard', 'artifacts', 'combo', 'tokens'];
    
    for (final oppArchetype in commonArchetypes) {
      final hateCards = await countersService.getHateCards(
        archetype: oppArchetype,
        colors: colors,
        priorityMax: 1, // Apenas hate cards essenciais
      );
      
      if (hateCards.isNotEmpty) {
        recommendations['hate_$oppArchetype'] = hateCards.take(3).toList();
      }
    }

    // Remove duplicatas mantendo a ordem
    recommendations['staples'] = recommendations['staples']!.toSet().toList();

  } catch (e) {
    print('⚠️ Erro ao buscar recomendações dinâmicas: $e');
    // Fallback mínimo em caso de erro
    recommendations['staples']!.addAll(['Sol Ring', 'Arcane Signet', 'Command Tower']);
  }

  return recommendations;
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
               ) as cmc,
               c.oracle_text
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
      final oracleText = (row[6] as String?) ?? '';
      
      // Coletar cores do deck
      deckColors.addAll(colors);
      
      final cardData = {
        'name': name,
        'type_line': typeLine,
        'mana_cost': manaCost,
        'colors': colors,
        'cmc': cmc,
        'is_commander': isCmdr,
        'oracle_text': oracleText,
      };
      
      allCardData.add(cardData);
      
      if (isCmdr) {
        commanders.add(name);
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

        if (typeLine.toLowerCase().contains('land')) {
          landCount++;
        }
      }
    }    // 1.5 Análise de Arquétipo do Deck
    final analyzer = DeckArchetypeAnalyzer(allCardData, deckColors.toList());
    final deckAnalysis = analyzer.generateAnalysis();
    final detectedArchetype = deckAnalysis['detected_archetype'] as String;
    
    // Usar arquétipo passado pelo usuário, mas incluir análise detectada para contexto
    final targetArchetype = archetype;
    final archetypeRecommendations = await getArchetypeRecommendations(
      targetArchetype, 
      deckColors.toList(),
      pool, // Passar pool para busca dinâmica de staples
    );

    // 1.6 Fetch Meta Decks for Context (filtrado por arquétipo)
    String metaContext = "";
    try {
      final metaResult = await pool.execute(
        Sql.named('''
          SELECT archetype, card_list 
          FROM meta_decks 
          WHERE archetype ILIKE @query OR card_list ILIKE @commander
          ORDER BY created_at DESC 
          LIMIT 1
        '''),
        parameters: {
          'query': '%$targetArchetype%',
          'commander': '%${commanders.firstOrNull ?? "Unknown"}%'
        },
      );

      if (metaResult.isNotEmpty) {
        final metaDeckName = metaResult.first[0] as String;
        final metaList = metaResult.first[1] as String;
        final metaSample = metaList.split('\n').take(150).join(', ');
        metaContext = "CONTEXTO DO META (Deck Top Tier encontrado: $metaDeckName): As cartas usadas neste arquétipo incluem: $metaSample...";
      }
    } catch (e) {
      print('Erro ao buscar meta decks: $e');
    }

    // 2. Prepare Prompt with Archetype Context
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final apiKey = env['OPENAI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      // Mock response for development with archetype context
      return Response.json(body: {
        'removals': ['Basic Land', 'Weak Card'],
        'additions': archetypeRecommendations['staples']!.take(2).toList(),
        'reasoning': 'Mock optimization para arquétipo $targetArchetype: Adicionando staples recomendados.',
        'deck_analysis': deckAnalysis,
        'is_mock': true
      });
    }

    final prompt = '''
    Atue como um Juiz e Especialista Pro Player de Magic: The Gathering.
    Estou construindo um deck de formato $deckFormat chamado "$deckName" com Comandante: ${commanders.join(', ')}.
    
    ARQUÉTIPO ALVO: $targetArchetype
    
    ANÁLISE AUTOMÁTICA DO DECK:
    - Arquétipo Detectado: $detectedArchetype
    - CMC Médio: ${deckAnalysis['average_cmc']}
    - Avaliação da Curva: ${deckAnalysis['mana_curve_assessment']}
    - Confiança na Classificação: ${deckAnalysis['archetype_confidence']}
    - Distribuição de Tipos: ${jsonEncode(deckAnalysis['type_distribution'])}
    
    ESTATÍSTICAS ATUAIS:
    - Total de cartas na lista principal: ${otherCards.length}
    - Total de Terrenos (Lands): $landCount
    - Cores do Deck: ${deckColors.join(', ')}
    
    RECOMENDAÇÕES PARA ARQUÉTIPO $targetArchetype:
    - Staples Recomendados: ${archetypeRecommendations['staples']!.join(', ')}
    - Evitar: ${archetypeRecommendations['avoid']!.join(', ')}
    - Prioridades: ${archetypeRecommendations['priority']!.join(', ')}
    
    $metaContext
    
    LISTA COMPLETA DO MEU DECK:
    ${otherCards.join(', ')}
    
    SUA MISSÃO (OTIMIZAÇÃO VIA SUBSTITUIÇÃO DIRETA):
    Você deve identificar pares de troca (Swap). Para cada carta forte que entra, uma carta fraca deve sair.
    
    1. **Identifique Staples Faltantes:** Que cartas essenciais do arquétipo $targetArchetype não estão na lista?
    2. **Encontre o Elo Mais Fraco:** Para cada staple identificada, encontre a carta no deck atual que tem função similar mas é pior, ou que não faz sentido no deck.
    3. **Justifique a Troca:** Por que A é melhor que B neste deck?

    REGRAS CRÍTICAS:
    - **SUBSTITUIÇÃO 1:1:** Gere SEMPRE pares exatos. Nunca adicione sem remover.
    - **PRESERVAR STAPLES:** NUNCA remova staples de formato (Sol Ring, Arcane Signet, Command Tower, etc).
    - **SEM DUPLICATAS:** Não repita cartas.

    Formato JSON estrito:
    {
      "changes": [
        { "remove": "Nome da Carta a Sair", "add": "Nome da Carta a Entrar", "reason": "Motivo curto da troca" },
        ...
      ],
      "reasoning": "Explicação geral da estratégia de otimização adotada."
    }
    ''';

    // 3. Call OpenAI
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'system', 'content': 'You are a helpful MTG deck building assistant that outputs only JSON.'},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
      }),
    );

    if (response.statusCode != 200) {
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'OpenAI API error: ${response.body}'},
      );
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final content = data['choices'][0]['message']['content'] as String;
    
    // Clean up potential markdown code blocks if the model ignores instructions
    final cleanContent = content.replaceAll('```json', '').replaceAll('```', '').trim();
    
    try {
      final jsonResponse = jsonDecode(cleanContent) as Map<String, dynamic>;
      
      // Validar cartas sugeridas pela IA
      final validationService = CardValidationService(pool);
      
      List<String> removals = [];
      List<String> additions = [];

      // Suporte ao novo formato "changes" (pares de troca)
      if (jsonResponse.containsKey('changes')) {
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
      
      // GARANTIR EQUILÍBRIO NUMÉRICO (Regra de Ouro)
      final minCount = removals.length < additions.length ? removals.length : additions.length;
      
      if (removals.length != additions.length) {
        print('⚠️ [AI Optimize] Ajustando desequilíbrio: -${removals.length} / +${additions.length} -> $minCount');
        removals = removals.take(minCount).toList();
        additions = additions.take(minCount).toList();
      }
      
      final sanitizedRemovals = removals.map(CardValidationService.sanitizeCardName).toList();
      final sanitizedAdditions = additions.map(CardValidationService.sanitizeCardName).toList();
      
      // Validar todas as cartas sugeridas
      final allSuggestions = [...sanitizedRemovals, ...sanitizedAdditions];
      final validation = await validationService.validateCardNames(allSuggestions);
      
      // Filtrar apenas cartas válidas e remover duplicatas
      var validRemovals = sanitizedRemovals.where((name) {
        return (validation['valid'] as List).any((card) => 
          (card['name'] as String).toLowerCase() == name.toLowerCase()
        );
      }).toSet().toList();
      
      var validAdditions = sanitizedAdditions.where((name) {
        return (validation['valid'] as List).any((card) => 
          (card['name'] as String).toLowerCase() == name.toLowerCase()
        );
      }).toSet().toList();

      // Re-aplicar equilíbrio após validação
      final finalMinCount = validRemovals.length < validAdditions.length ? validRemovals.length : validAdditions.length;
      if (validRemovals.length != validAdditions.length) {
         validRemovals = validRemovals.take(finalMinCount).toList();
         validAdditions = validAdditions.take(finalMinCount).toList();
      }
      
      // Preparar resposta com avisos sobre cartas inválidas
      final invalidCards = validation['invalid'] as List<String>;
      final suggestions = validation['suggestions'] as Map<String, List<String>>;
      
      final responseBody = {
        'removals': validRemovals,
        'additions': validAdditions,
        'reasoning': jsonResponse['reasoning'],
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
        body: {'error': 'Failed to parse AI response', 'raw': content},
      );
    }

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}
