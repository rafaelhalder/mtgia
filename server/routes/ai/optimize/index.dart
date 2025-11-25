import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/card_validation_service.dart';

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
Future<Map<String, List<String>>> getArchetypeRecommendations(String archetype, List<String> colors) async {
  final recommendations = <String, List<String>>{
    'staples': [],
    'avoid': [],
    'priority': [],
  };
  
  // 1. Staples universais (Via API Scryfall - Sempre atualizado e sem banidas)
  final universalStaples = await _fetchScryfallCards('', 20);
  
  if (universalStaples.isNotEmpty) {
    recommendations['staples']!.addAll(universalStaples);
  } else {
    // Fallback seguro (apenas cartas muito seguras)
    recommendations['staples']!.addAll(['Sol Ring', 'Arcane Signet', 'Command Tower']);
  }
  
  // Lógica específica para Infect (que geralmente é Aggro/Combo)
  if (archetype.toLowerCase().contains('infect')) {
    // Busca staples de infect dinamicamente
    final infectStaples = await _fetchScryfallCards('oracle:infect', 15);
    recommendations['staples']!.addAll(infectStaples);
    
    // Busca pump spells se tiver verde
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

  switch (archetype.toLowerCase()) {
    case 'aggro':
      recommendations['staples']!.addAll([
        'Lightning Greaves', 'Swiftfoot Boots', 
        'Jeska\'s Will', 'Deflecting Swat'
      ]);
      recommendations['avoid']!.addAll([
        'Cartas com CMC > 5', 'Criaturas defensivas', 'Removal lento'
      ]);
      recommendations['priority']!.addAll([
        'Haste enablers', 'Anthems (+1/+1)', 'Card draw rápido'
      ]);
      break;
    case 'control':
      recommendations['staples']!.addAll([
        'Counterspell', 'Swords to Plowshares', 'Path to Exile',
        'Cyclonic Rift', 'Teferi\'s Protection'
      ]);
      recommendations['avoid']!.addAll([
        'Criaturas vanilla', 'Cartas agressivas sem utilidade'
      ]);
      recommendations['priority']!.addAll([
        'Counters', 'Removal eficiente', 'Card advantage', 'Wipes'
      ]);
      break;
    case 'combo':
      recommendations['staples']!.addAll([
        'Demonic Tutor', 'Vampiric Tutor', 'Mystical Tutor',
        'Rhystic Study', 'Necropotence'
      ]);
      recommendations['avoid']!.addAll([
        'Cartas que não avançam o combo', 'Creatures irrelevantes'
      ]);
      recommendations['priority']!.addAll([
        'Tutors', 'Proteção de combo', 'Card draw', 'Fast mana'
      ]);
      break;
    case 'midrange':
      recommendations['staples']!.addAll([
        'Beast Within', 'Chaos Warp', 'Generous Gift',
        'Skullclamp', 'The Great Henge'
      ]);
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
  
  // Adicionar staples por cor
  if (colors.contains('W')) {
    recommendations['staples']!.addAll(['Swords to Plowshares', 'Path to Exile', 'Esper Sentinel']);
  }
  if (colors.contains('U')) {
    recommendations['staples']!.addAll(['Counterspell', 'Cyclonic Rift', 'Rhystic Study']);
  }
  if (colors.contains('B')) {
    recommendations['staples']!.addAll(['Demonic Tutor', 'Toxic Deluge', 'Orcish Bowmasters']);
  }
  if (colors.contains('R')) {
    // Removido Dockside Extortionist (Banido)
    recommendations['staples']!.addAll(['Jeska\'s Will', 'Ragavan, Nimble Pilferer', 'Deflecting Swat']);
  }
  if (colors.contains('G')) {
    recommendations['staples']!.addAll(['Nature\'s Lore', 'Three Visits', 'Birds of Paradise']);
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

    // 1.5 Análise de Arquétipo do Deck
    final analyzer = DeckArchetypeAnalyzer(allCardData, deckColors.toList());
    final deckAnalysis = analyzer.generateAnalysis();
    final detectedArchetype = deckAnalysis['detected_archetype'] as String;
    
    // Usar arquétipo passado pelo usuário, mas incluir análise detectada para contexto
    final targetArchetype = archetype;
    final archetypeRecommendations = await getArchetypeRecommendations(
      targetArchetype, 
      deckColors.toList()
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
    
    SUA MISSÃO (ANÁLISE CONTEXTUAL POR ARQUÉTIPO):
    1. **Análise de Mana Base:** Verifique se a quantidade de terrenos ($landCount) é adequada para o arquétipo $targetArchetype.
       - Aggro: ~30-33 terrenos
       - Midrange: ~34-37 terrenos  
       - Control: ~37-40 terrenos
    2. **Staples do Arquétipo:** Verifique se faltam cartas essenciais ESPECÍFICAS para $targetArchetype (listadas acima).
    3. **Cortes Contextuais:** Remova cartas que NÃO SINERGIZAM com a estratégia $targetArchetype.
       - Para Aggro: Remova cartas lentas (CMC > 4) que não geram valor imediato
       - Para Control: Remova criaturas agressivas sem utilidade defensiva
       - Para Combo: Remova cartas que não avançam a estratégia principal
    
    REGRAS CRÍTICAS:
    - **EQUILÍBRIO NUMÉRICO:** O número de cartas removidas DEVE SER IGUAL ao número de cartas adicionadas.
    - **FOCO NO ARQUÉTIPO:** Toda sugestão deve ser justificada pelo arquétipo $targetArchetype.
    - **EXPLICAÇÃO OBRIGATÓRIA:** O campo "reasoning" deve explicar as trocas no CONTEXTO do arquétipo.
    - **PRESERVAR STAPLES:** NUNCA sugira remover staples de formato (ex: Mana Drain, Fetch Lands, Shock Lands, Tutors, Sol Ring, Mana Crypt) a menos que sejam ilegais no formato.
    - **SEM DUPLICATAS:** Não sugira remover ou adicionar a mesma carta mais de uma vez.
    
    Formato JSON estrito:
    {
      "removals": ["Carta Ruim 1", "Carta Ruim 2", ...],
      "additions": ["Carta Boa 1", "Carta Boa 2", ...],
      "reasoning": "Explicação focada no arquétipo $targetArchetype..."
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
      
      // Sanitizar nomes das cartas (corrigir capitalização, etc)
      final removals = (jsonResponse['removals'] as List?)?.cast<String>() ?? [];
      final additions = (jsonResponse['additions'] as List?)?.cast<String>() ?? [];
      
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
      
      // Preparar resposta com avisos sobre cartas inválidas
      final invalidCards = validation['invalid'] as List<String>;
      final suggestions = validation['suggestions'] as Map<String, List<String>>;
      
      final responseBody = {
        'removals': validRemovals,
        'additions': validAdditions,
        'reasoning': jsonResponse['reasoning'],
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
