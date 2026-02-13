import 'dart:convert';
import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';

Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method == HttpMethod.post) {
    return _generateRecommendations(context, deckId);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _generateRecommendations(RequestContext context, String deckId) async {
  final pool = context.read<Pool>();
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final apiKey = env['OPENAI_API_KEY'];

  try {
    // ─── 1. Buscar dados do deck ──────────────────────────────
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format, description FROM decks WHERE id = @deckId'),
      parameters: {'deckId': deckId},
    );

    if (deckResult.isEmpty) {
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Deck not found'});
    }

    final deck = deckResult.first.toColumnMap();
    final deckName = deck['name'] as String? ?? '';
    final format = deck['format'] as String? ?? 'commander';
    final description = deck['description'] as String? ?? '';

    // ─── 2. Buscar cartas do deck com detalhes ────────────────
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, c.type_line, c.oracle_text, c.mana_cost, c.colors, 
               dc.quantity, dc.is_commander,
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
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
      '''),
      parameters: {'deckId': deckId},
    );

    // ─── 3. Analisar o deck ───────────────────────────────────
    final deckCards = <Map<String, dynamic>>[];
    final deckCardNames = <String>{};
    final deckColors = <String>{};
    int totalCards = 0;
    int landCount = 0;
    int creatureCount = 0;
    int nonLandCards = 0;
    double totalCMC = 0;
    int rampCount = 0;
    int drawCount = 0;
    int removalCount = 0;
    int boardWipeCount = 0;
    int protectionCount = 0;

    for (final row in cardsResult) {
      final name = row[0] as String;
      final typeLine = (row[1] as String?) ?? '';
      final oracleText = ((row[2] as String?) ?? '').toLowerCase();
      final manaCost = (row[3] as String?) ?? '';
      final colors = (row[4] as List?)?.cast<String>() ?? [];
      final quantity = row[5] as int;
      final isCommander = row[6] as bool? ?? false;
      final cmc = (row[7] as num?)?.toDouble() ?? 0;

      deckColors.addAll(colors);
      deckCardNames.add(name.toLowerCase());
      totalCards += quantity;

      deckCards.add({
        'name': name,
        'type_line': typeLine,
        'oracle_text': oracleText,
        'mana_cost': manaCost,
        'colors': colors,
        'quantity': quantity,
        'is_commander': isCommander,
        'cmc': cmc,
      });

      final tl = typeLine.toLowerCase();
      if (tl.contains('land')) {
        landCount += quantity;
      } else {
        nonLandCards += quantity;
        totalCMC += cmc * quantity;
      }
      if (tl.contains('creature')) creatureCount += quantity;

      // Categorias funcionais
      if (oracleText.contains('add {') ||
          (oracleText.contains('search your library for a') && oracleText.contains('land')) ||
          oracleText.contains('put a land card')) {
        rampCount += quantity;
      }
      if (oracleText.contains('draw') && oracleText.contains('card')) {
        drawCount += quantity;
      }
      if (oracleText.contains('destroy target') ||
          oracleText.contains('exile target') ||
          (oracleText.contains('deal') && oracleText.contains('damage to target'))) {
        removalCount += quantity;
      }
      if (oracleText.contains('destroy all') || oracleText.contains('exile all')) {
        boardWipeCount += quantity;
      }
      if (oracleText.contains('hexproof') ||
          oracleText.contains('indestructible') ||
          oracleText.contains('protection from')) {
        protectionCount += quantity;
      }
    }

    final avgCMC = nonLandCards > 0 ? totalCMC / nonLandCards : 0.0;
    final creatureRatio = nonLandCards > 0 ? creatureCount / nonLandCards : 0.0;
    final isCommanderFmt = format.toLowerCase() == 'commander';

    // Detectar arquétipo
    String archetype = 'midrange';
    if (avgCMC < 2.5 && creatureRatio > 0.4) archetype = 'aggro';
    else if (avgCMC > 3.0 && creatureRatio < 0.25) archetype = 'control';
    else if (creatureRatio < 0.3) archetype = 'combo';

    // Calcular power level
    int powerLevel = 5;
    if (rampCount >= 10 && drawCount >= 8 && removalCount >= 6) powerLevel = 7;
    if (rampCount >= 12 && drawCount >= 10 && avgCMC < 2.8) powerLevel = 8;
    if (totalCards < 40) powerLevel = 3;

    // ─── 4. Se tem OpenAI, usar IA ───────────────────────────
    if (apiKey != null && apiKey.isNotEmpty) {
      return _callOpenAI(
        apiKey: apiKey,
        deckName: deckName,
        format: format,
        description: description,
        deckCards: deckCards,
      );
    }

    // ─── 5. FALLBACK INTELIGENTE (sem OpenAI) ────────────────
    //    Analisa lacunas reais e busca cartas do banco nas cores do deck
    final addRecommendations = <Map<String, String>>[];
    final removeRecommendations = <Map<String, String>>[];

    // Filtro de cores: aceita incolores + cores do deck
    final colorFilter = deckColors.isNotEmpty
        ? deckColors.map((c) => "'$c'").join(', ')
        : "'W','U','B','R','G'";

    // Falta de Ramp
    if (rampCount < 10) {
      final cards = await _findCardsForCategory(
        pool: pool,
        oraclePatterns: ["add {%", "search your library for a%land%"],
        colorFilter: colorFilter,
        excludeNames: deckCardNames,
        limit: (10 - rampCount).clamp(1, 5),
        format: format,
      );
      for (final c in cards) {
        addRecommendations.add({
          'card_name': c,
          'reason': 'Ramp — deck tem apenas $rampCount fontes (recomendado: 10+)',
        });
      }
    }

    // Falta de Card Draw
    if (drawCount < 8) {
      final cards = await _findCardsForCategory(
        pool: pool,
        oraclePatterns: ["%draw%card%"],
        colorFilter: colorFilter,
        excludeNames: deckCardNames,
        limit: (8 - drawCount).clamp(1, 4),
        format: format,
      );
      for (final c in cards) {
        addRecommendations.add({
          'card_name': c,
          'reason': 'Card draw — deck tem apenas $drawCount fontes (recomendado: 8+)',
        });
      }
    }

    // Falta de Removal
    if (removalCount < 6) {
      final cards = await _findCardsForCategory(
        pool: pool,
        oraclePatterns: ["destroy target%", "exile target%"],
        colorFilter: colorFilter,
        excludeNames: deckCardNames,
        limit: (6 - removalCount).clamp(1, 4),
        format: format,
      );
      for (final c in cards) {
        addRecommendations.add({
          'card_name': c,
          'reason': 'Remoção — deck tem apenas $removalCount (recomendado: 6+)',
        });
      }
    }

    // Falta de Board Wipes
    if (boardWipeCount < 2) {
      final cards = await _findCardsForCategory(
        pool: pool,
        oraclePatterns: ["destroy all%creature%", "exile all%"],
        colorFilter: colorFilter,
        excludeNames: deckCardNames,
        limit: (3 - boardWipeCount).clamp(1, 2),
        format: format,
      );
      for (final c in cards) {
        addRecommendations.add({
          'card_name': c,
          'reason': 'Board wipe — deck tem apenas $boardWipeCount (recomendado: 2-3)',
        });
      }
    }

    // Falta de Proteção
    if (protectionCount < 3) {
      final cards = await _findCardsForCategory(
        pool: pool,
        oraclePatterns: ["%hexproof%", "%indestructible%"],
        colorFilter: colorFilter,
        excludeNames: deckCardNames,
        limit: (3 - protectionCount).clamp(1, 2),
        format: format,
      );
      for (final c in cards) {
        addRecommendations.add({
          'card_name': c,
          'reason': 'Proteção — deck tem apenas $protectionCount fontes',
        });
      }
    }

    // Falta de terrenos (Commander)
    if (isCommanderFmt && landCount < 34) {
      addRecommendations.add({
        'card_name': 'Command Tower',
        'reason': 'Terreno essencial — deck tem apenas $landCount terrenos (recomendado: 35-38)',
      });
    }

    // Se o deck está bem, sugerir staples de alto impacto
    if (addRecommendations.isEmpty) {
      final staples = await _findStaples(
        pool: pool,
        colorFilter: colorFilter,
        excludeNames: deckCardNames,
        format: format,
        limit: 3,
      );
      for (final c in staples) {
        addRecommendations.add({
          'card_name': c,
          'reason': 'Staple de alto impacto para $format',
        });
      }
    }

    // ─── Identificar cartas fracas para remover ───────────────
    for (final card in deckCards) {
      if (removeRecommendations.length >= 3) break;
      final tl = (card['type_line'] as String).toLowerCase();
      if (tl.contains('land') || card['is_commander'] == true) continue;
      final cmc = (card['cmc'] as num).toDouble();

      if (archetype == 'aggro' && cmc > 5) {
        removeRecommendations.add({
          'card_name': card['name'] as String,
          'reason': 'CMC ${cmc.toInt()} é alto para aggro — considere alternativas mais baratas',
        });
      } else if (archetype == 'control' && cmc <= 1 && creatureRatio > 0.3) {
        final oracle = card['oracle_text'] as String;
        if (!oracle.contains('draw') && !oracle.contains('counter') && !oracle.contains('destroy')) {
          removeRecommendations.add({
            'card_name': card['name'] as String,
            'reason': 'Criatura fraca para control — slot melhor usado com remoção/draw',
          });
        }
      }
    }

    // Terrenos básicos em excesso em deck multicolor
    if (deckColors.length >= 3 && landCount > 38) {
      final basicLands = deckCards.where((c) {
        final tl = (c['type_line'] as String).toLowerCase();
        return tl.contains('basic land');
      }).toList();
      if (basicLands.isNotEmpty && removeRecommendations.length < 5) {
        removeRecommendations.add({
          'card_name': basicLands.last['name'] as String,
          'reason': 'Terreno básico em excesso — trocar por terreno utilitário ou dual',
        });
      }
    }

    // ─── Montar resposta ──────────────────────────────────────
    final analysis = StringBuffer();
    analysis.write('Deck "$deckName" ($format) — Arquétipo: $archetype. ');
    analysis.write('CMC médio: ${avgCMC.toStringAsFixed(1)}. ');
    analysis.write('$totalCards cartas ($landCount terrenos, $creatureCount criaturas). ');
    if (rampCount < 8) analysis.write('⚠️ Ramp insuficiente. ');
    if (drawCount < 8) analysis.write('⚠️ Card draw baixo. ');
    if (removalCount < 5) analysis.write('⚠️ Pouca remoção. ');

    return Response.json(body: {
      'archetype': archetype,
      'power_level': powerLevel,
      'analysis': analysis.toString(),
      'recommendations': {
        'add': addRecommendations.take(5).toList(),
        'remove': removeRecommendations.take(5).toList(),
      },
      'statistics': {
        'total_cards': totalCards,
        'lands': landCount,
        'creatures': creatureCount,
        'ramp_sources': rampCount,
        'card_draw': drawCount,
        'removal': removalCount,
        'board_wipes': boardWipeCount,
        'protection': protectionCount,
        'average_cmc': avgCMC.toStringAsFixed(2),
      },
      'colors': deckColors.toList(),
      'source': 'heuristic',
      'message': 'Análise baseada em heurísticas — configure OPENAI_API_KEY para IA generativa.',
    });

  } catch (e) {
    print('[ERROR] Failed to generate recommendations: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to generate recommendations: $e'},
    );
  }
}

/// Busca cartas reais do banco que preenchem uma categoria funcional
Future<List<String>> _findCardsForCategory({
  required Pool pool,
  required List<String> oraclePatterns,
  required String colorFilter,
  required Set<String> excludeNames,
  required int limit,
  required String format,
}) async {
  try {
    final orClauses = oraclePatterns
        .map((p) => "LOWER(c.oracle_text) LIKE '${p.toLowerCase()}'")
        .join(' OR ');

    final result = await pool.execute(
      Sql('''
        SELECT DISTINCT c.name FROM cards c
        LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = '${format.toLowerCase()}'
        WHERE ($orClauses)
          AND (c.colors = '{}' OR c.colors && ARRAY[$colorFilter])
          AND (cl.id IS NULL OR cl.status = 'legal')
          AND c.type_line NOT ILIKE '%land%'
        ORDER BY c.name
        LIMIT ${limit + 10}
      '''),
    );

    final candidates = <String>[];
    for (final row in result) {
      final name = row[0] as String;
      if (!excludeNames.contains(name.toLowerCase())) {
        candidates.add(name);
        if (candidates.length >= limit) break;
      }
    }
    return candidates;
  } catch (e) {
    print('[WARN] _findCardsForCategory error: $e');
    return [];
  }
}

/// Busca staples genéricos de alto impacto
Future<List<String>> _findStaples({
  required Pool pool,
  required String colorFilter,
  required Set<String> excludeNames,
  required String format,
  required int limit,
}) async {
  try {
    final result = await pool.execute(
      Sql('''
        SELECT DISTINCT c.name FROM cards c
        LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = '${format.toLowerCase()}'
        WHERE (c.colors = '{}' OR c.colors && ARRAY[$colorFilter])
          AND (cl.id IS NULL OR cl.status = 'legal')
          AND c.rarity IN ('rare', 'mythic')
          AND c.type_line NOT ILIKE '%basic%land%'
        ORDER BY c.name
        LIMIT ${limit + 20}
      '''),
    );

    final candidates = <String>[];
    for (final row in result) {
      final name = row[0] as String;
      if (!excludeNames.contains(name.toLowerCase())) {
        candidates.add(name);
        if (candidates.length >= limit) break;
      }
    }
    return candidates;
  } catch (e) {
    print('[WARN] _findStaples error: $e');
    return [];
  }
}

/// Caminho com OpenAI (quando apiKey está configurada)
Future<Response> _callOpenAI({
  required String apiKey,
  required String deckName,
  required String format,
  required String description,
  required List<Map<String, dynamic>> deckCards,
}) async {
  final cardList = deckCards.map((c) => "${c['quantity']}x ${c['name']}").join(', ');

  final prompt = '''
    You are a professional Magic: The Gathering deck builder expert.
    Analyze the following deck and provide recommendations.
    
    Deck Name: $deckName
    Format: $format
    Description: $description
    Cards: $cardList
    
    Task:
    1. Identify the deck's archetype and main strategy.
    2. Suggest 5 cards to ADD that improve synergy or cover weaknesses.
    3. Suggest 5 cards to REMOVE that are weak or don't fit.
    4. Rate the deck's power level (1-10) for casual play.
    
    Output strictly in JSON format:
    {
      "archetype": "string",
      "power_level": number,
      "analysis": "string (brief summary)",
      "recommendations": {
        "add": [ {"card_name": "string", "reason": "string"} ],
        "remove": [ {"card_name": "string", "reason": "string"} ]
      }
    }
  ''';

  final response = await http.post(
    Uri.parse('https://api.openai.com/v1/chat/completions'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: jsonEncode({
      'model': 'gpt-3.5-turbo',
      'messages': [
        {'role': 'system', 'content': 'You are a helpful assistant that outputs JSON.'},
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
    }),
  );

  if (response.statusCode != 200) {
    return Response.json(
      statusCode: response.statusCode,
      body: {'error': 'OpenAI API Error: ${response.body}'},
    );
  }

  final aiData = jsonDecode(utf8.decode(response.bodyBytes));
  final content = aiData['choices'][0]['message']['content'];

  try {
    final recommendations = jsonDecode(content);
    return Response.json(body: recommendations);
  } catch (e) {
    print('[ERROR] Failed to parse OpenAI recommendations: $e');
    return Response.json(body: {'raw_response': content});
  }
}
