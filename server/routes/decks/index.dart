import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../lib/deck_schema_support.dart';
import '../../lib/deck_rules_service.dart';
import '../../lib/http_responses.dart';
import '../../lib/logger.dart';
import '../../lib/scryfall_image_url.dart';

Future<Response> onRequest(RequestContext context) async {
  // Este arquivo vai lidar com diferentes métodos HTTP para a rota /decks
  if (context.request.method == HttpMethod.post) {
    return _createDeck(context);
  }

  // Futuramente, podemos adicionar o método GET para listar os decks do usuário
  if (context.request.method == HttpMethod.get) {
    return _listDecks(context);
  }

  return methodNotAllowed();
}

/// Lista os decks do usuário autenticado.
Future<Response> _listDecks(RequestContext context) async {
  Log.d('📥 [GET /decks] Iniciando listagem de decks...');

  try {
    final userId = context.read<String>();
    Log.d('👤 User ID identificado: $userId');

    final conn = context.read<Pool>();
    Log.d('🔌 Conexão com banco obtida.');

    Log.d('🔍 Executando query SELECT...');
    final hasMeta = await hasDeckMetaColumns(conn);
    final hasPricing = await hasDeckPricingColumns(conn);
    final sql = hasMeta
        ? (hasPricing
            ? '''
        SELECT 
          d.id, 
          d.name, 
          d.format, 
          d.description, 
          d.archetype,
          d.bracket,
          d.synergy_score, 
          d.is_public,
          d.pricing_currency,
          d.pricing_total,
          d.pricing_missing_cards,
          d.pricing_updated_at,
          d.created_at,
          cmd.commander_name,
          cmd.commander_image_url,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        LEFT JOIN LATERAL (
          SELECT 
            c.name as commander_name,
            c.image_url as commander_image_url
          FROM deck_cards dc_cmd
          JOIN cards c ON c.id = dc_cmd.card_id
          WHERE dc_cmd.deck_id = d.id
            AND dc_cmd.is_commander = true
          LIMIT 1
        ) cmd ON true
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE d.user_id = @userId
        GROUP BY d.id, cmd.commander_name, cmd.commander_image_url
        ORDER BY d.created_at DESC
      '''
            : '''
        SELECT 
          d.id, 
          d.name, 
          d.format, 
          d.description, 
          d.archetype,
          d.bracket,
          d.synergy_score, 
          d.is_public,
          NULL::text as pricing_currency,
          NULL::numeric as pricing_total,
          0::int as pricing_missing_cards,
          NULL::timestamptz as pricing_updated_at,
          d.created_at,
          cmd.commander_name,
          cmd.commander_image_url,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        LEFT JOIN LATERAL (
          SELECT 
            c.name as commander_name,
            c.image_url as commander_image_url
          FROM deck_cards dc_cmd
          JOIN cards c ON c.id = dc_cmd.card_id
          WHERE dc_cmd.deck_id = d.id
            AND dc_cmd.is_commander = true
          LIMIT 1
        ) cmd ON true
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE d.user_id = @userId
        GROUP BY d.id, cmd.commander_name, cmd.commander_image_url
        ORDER BY d.created_at DESC
      ''')
        : (hasPricing
            ? '''
        SELECT 
          d.id, 
          d.name, 
          d.format, 
          d.description, 
          NULL::text as archetype,
          NULL::int as bracket,
          d.synergy_score, 
          d.is_public,
          d.pricing_currency,
          d.pricing_total,
          d.pricing_missing_cards,
          d.pricing_updated_at,
          d.created_at,
          cmd.commander_name,
          cmd.commander_image_url,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        LEFT JOIN LATERAL (
          SELECT 
            c.name as commander_name,
            c.image_url as commander_image_url
          FROM deck_cards dc_cmd
          JOIN cards c ON c.id = dc_cmd.card_id
          WHERE dc_cmd.deck_id = d.id
            AND dc_cmd.is_commander = true
          LIMIT 1
        ) cmd ON true
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE d.user_id = @userId
        GROUP BY d.id, cmd.commander_name, cmd.commander_image_url
        ORDER BY d.created_at DESC
      '''
            : '''
        SELECT 
          d.id, 
          d.name, 
          d.format, 
          d.description, 
          NULL::text as archetype,
          NULL::int as bracket,
          d.synergy_score, 
          d.is_public,
          NULL::text as pricing_currency,
          NULL::numeric as pricing_total,
          0::int as pricing_missing_cards,
          NULL::timestamptz as pricing_updated_at,
          d.created_at,
          cmd.commander_name,
          cmd.commander_image_url,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        LEFT JOIN LATERAL (
          SELECT 
            c.name as commander_name,
            c.image_url as commander_image_url
          FROM deck_cards dc_cmd
          JOIN cards c ON c.id = dc_cmd.card_id
          WHERE dc_cmd.deck_id = d.id
            AND dc_cmd.is_commander = true
          LIMIT 1
        ) cmd ON true
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE d.user_id = @userId
        GROUP BY d.id, cmd.commander_name, cmd.commander_image_url
        ORDER BY d.created_at DESC
      ''');

    final result = await conn.execute(
      Sql.named(sql),
      parameters: {'userId': userId},
    );
    Log.d('✅ Query executada. Encontrados ${result.length} decks.');

    final decks = result.map((row) {
      final map = row.toColumnMap();
      if (map['created_at'] is DateTime) {
        map['created_at'] = (map['created_at'] as DateTime).toIso8601String();
      }
      if (map['pricing_updated_at'] is DateTime) {
        map['pricing_updated_at'] =
            (map['pricing_updated_at'] as DateTime).toIso8601String();
      }
      map['commander_image_url'] = normalizeScryfallImageUrl(
        map['commander_image_url']?.toString(),
      );
      // PostgreSQL DECIMAL retorna String, converter para double
      final rawPricingTotal = map['pricing_total'];
      if (rawPricingTotal is String) {
        map['pricing_total'] = double.tryParse(rawPricingTotal);
      } else if (rawPricingTotal is num) {
        map['pricing_total'] = rawPricingTotal.toDouble();
      }
      return map;
    }).toList();

    // ── Fetch color identity for each deck (batch) ──────────────
    if (decks.isNotEmpty) {
      try {
        final colorResult = await conn.execute(
          Sql.named('''
            SELECT
              dc.deck_id::text,
              array_agg(DISTINCT unnested ORDER BY unnested) AS color_identity
            FROM deck_cards dc
            JOIN cards c ON c.id = dc.card_id
            CROSS JOIN LATERAL unnest(COALESCE(c.color_identity, '{}')) AS unnested
            WHERE dc.deck_id = ANY(
              SELECT id FROM decks WHERE user_id = @userId
            )
            GROUP BY dc.deck_id
          '''),
          parameters: {'userId': userId},
        );
        final colorMap = <String, List<String>>{};
        for (final row in colorResult) {
          final m = row.toColumnMap();
          final deckId = m['deck_id']?.toString() ?? '';
          final colors = m['color_identity'];
          if (colors is List) {
            colorMap[deckId] = colors.map((e) => e.toString()).toList();
          }
        }
        for (final deck in decks) {
          final deckId = deck['id']?.toString() ?? '';
          deck['color_identity'] = colorMap[deckId] ?? <String>[];
        }
      } catch (e) {
        Log.e('⚠️ Falha ao buscar color_identity: $e');
        // Non-critical — continue without color identity
        for (final deck in decks) {
          deck['color_identity'] = <String>[];
        }
      }
    }

    Log.d('📤 Retornando resposta JSON.');
    return Response.json(body: decks);
  } catch (e, stackTrace) {
    Log.e('❌ Erro crítico em _listDecks: $e');
    Log.e('Stack trace: $stackTrace');
    return internalServerError('Failed to list decks');
  }
}

/// Cria um novo deck para o usuário autenticado.
Future<Response> _createDeck(RequestContext context) async {
  // 1. Obter o ID do usuário (injetado pelo middleware de autenticação)
  final userId = context.read<String>();

  // 2. Ler e validar o corpo da requisição
  final body = await context.request.json();
  final name = body['name'] as String?;
  final format = body['format'] as String?;
  final archetype = body['archetype'] as String?;
  final bracketRaw = body['bracket'];
  final bracket =
      bracketRaw is int ? bracketRaw : int.tryParse('${bracketRaw ?? ''}');
  final isPublic = body['is_public'] == true;
  final cards = body['cards'] as List? ??
      []; // Ex: [{'card_id': 'uuid', 'quantity': 2, 'is_commander': false}]

  if (name == null || format == null) {
    return badRequest('Fields name and format are required.');
  }

  final conn = context.read<Pool>();
  final hasMeta = await hasDeckMetaColumns(conn);

  // 3. Usar uma transação para garantir a consistência dos dados
  try {
    final newDeck = await conn.runTx((session) async {
      // Insere o deck e obtém o ID gerado
      final deckResult = await session.execute(
        Sql.named(
          hasMeta
              ? 'INSERT INTO decks (user_id, name, format, description, archetype, bracket, is_public) VALUES (@userId, @name, @format, @desc, @archetype, @bracket, @isPublic) RETURNING id, name, format, archetype, bracket, is_public, created_at'
              : 'INSERT INTO decks (user_id, name, format, description, is_public) VALUES (@userId, @name, @format, @desc, @isPublic) RETURNING id, name, format, is_public, created_at',
        ),
        parameters: {
          'userId': userId,
          'name': name,
          'format': format,
          'desc': body['description'] as String?,
          'isPublic': isPublic,
          if (hasMeta) 'archetype': archetype,
          if (hasMeta) 'bracket': bracket,
        },
      );

      final deckMap = deckResult.first.toColumnMap();
      if (deckMap['created_at'] is DateTime) {
        deckMap['created_at'] =
            (deckMap['created_at'] as DateTime).toIso8601String();
      }
      if (!hasMeta) {
        deckMap['archetype'] = null;
        deckMap['bracket'] = null;
      }

      final newDeckId = deckMap['id'];

      // Resolver card_id quando veio "name" e agregar num formato único
      final normalizedCards = <Map<String, dynamic>>[];

      for (final card in cards) {
        if (card is! Map) {
          throw Exception('Each card must be an object.');
        }

        String? cardId = card['card_id'] as String?;
        final cardName = card['name'] as String?;
        final quantity = card['quantity'] as int?;
        final isCommander = card['is_commander'] as bool? ?? false;

        if ((cardId == null || cardId.isEmpty) &&
            (cardName == null || cardName.trim().isEmpty)) {
          throw Exception('Each card must have a card_id or name.');
        }
        if (quantity == null || quantity <= 0) {
          throw Exception('Each card must have a positive quantity.');
        }

        if (cardId == null || cardId.isEmpty) {
          final lookup = await session.execute(
            Sql.named(
                'SELECT id::text FROM cards WHERE LOWER(name) = LOWER(@name) LIMIT 1'),
            parameters: {'name': cardName!.trim()},
          );
          if (lookup.isEmpty) {
            throw Exception('Card not found: ${cardName.trim()}');
          }
          cardId = lookup.first[0] as String;
        }

        normalizedCards.add({
          'card_id': cardId,
          'quantity': quantity,
          'is_commander': isCommander,
        });
      }

      await DeckRulesService(session).validateAndThrow(
        format: format.toLowerCase(),
        cards: normalizedCards,
        strict: false,
      );

      // Prepara a inserção das cartas do deck
      final cardInsertSql = Sql.named(
        'INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander) VALUES (@deckId, @cardId, @quantity, @isCommander)',
      );

      for (final card in normalizedCards) {
        await session.execute(cardInsertSql, parameters: {
          'deckId': newDeckId,
          'cardId': card['card_id'],
          'quantity': card['quantity'],
          'isCommander': card['is_commander'] ?? false,
        });
      }

      return deckMap;
    });

    return Response.json(body: newDeck);
  } on DeckRulesException catch (e) {
    print('[ERROR] Failed to create deck: $e');
    return badRequest(e.message);
  } catch (e) {
    print('[ERROR] Failed to create deck: $e');
    return internalServerError('Failed to create deck');
  }
}
