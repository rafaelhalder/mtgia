import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../lib/deck_rules_service.dart';
import '../../lib/logger.dart';

String? _normalizeScryfallImageUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('https://api.scryfall.com/')) return trimmed;

  try {
    final uri = Uri.parse(trimmed);
    final qp = Map<String, String>.from(uri.queryParameters);

    if (qp['set'] != null) qp['set'] = qp['set']!.toLowerCase();

    final exact = qp['exact'];
    if (uri.path == '/cards/named' && exact != null && exact.contains('//')) {
      final left = exact.split('//').first.trim();
      if (left.isNotEmpty) qp['exact'] = left;
    }

    return uri.replace(queryParameters: qp).toString();
  } catch (_) {
    return trimmed.replaceAllMapped(
      RegExp(r'([?&]set=)([^&]+)'),
      (m) => '${m.group(1)}${m.group(2)!.toLowerCase()}',
    );
  }
}

bool? _hasDeckMetaColumnsCache;
Future<bool> _hasDeckMetaColumns(Pool pool) async {
  if (_hasDeckMetaColumnsCache != null) return _hasDeckMetaColumnsCache!;
  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'decks'
          AND column_name IN ('archetype', 'bracket')
      '''),
    );
    final count = (result.first[0] as int?) ?? 0;
    _hasDeckMetaColumnsCache = count >= 2;
  } catch (_) {
    _hasDeckMetaColumnsCache = false;
  }
  return _hasDeckMetaColumnsCache!;
}

bool? _hasDeckPricingColumnsCache;
Future<bool> _hasDeckPricingColumns(Pool pool) async {
  if (_hasDeckPricingColumnsCache != null) return _hasDeckPricingColumnsCache!;
  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'decks'
          AND column_name IN ('pricing_currency','pricing_total','pricing_missing_cards','pricing_updated_at')
      '''),
    );
    final count = (result.first[0] as int?) ?? 0;
    _hasDeckPricingColumnsCache = count >= 4;
  } catch (_) {
    _hasDeckPricingColumnsCache = false;
  }
  return _hasDeckPricingColumnsCache!;
}

Future<Response> onRequest(RequestContext context) async {
  // Este arquivo vai lidar com diferentes métodos HTTP para a rota /decks
  if (context.request.method == HttpMethod.post) {
    return _createDeck(context);
  }

  // Futuramente, podemos adicionar o método GET para listar os decks do usuário
  if (context.request.method == HttpMethod.get) {
    return _listDecks(context);
  }

  return Response(statusCode: HttpStatus.methodNotAllowed);
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
    final hasMeta = await _hasDeckMetaColumns(conn);
    final hasPricing = await _hasDeckPricingColumns(conn);
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
      map['commander_image_url'] = _normalizeScryfallImageUrl(
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

    Log.d('📤 Retornando resposta JSON.');
    return Response.json(body: decks);
  } catch (e, stackTrace) {
    Log.e('❌ Erro crítico em _listDecks: $e');
    Log.e('Stack trace: $stackTrace');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to list decks'},
    );
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
  final cards = body['cards'] as List? ??
      []; // Ex: [{'card_id': 'uuid', 'quantity': 2, 'is_commander': false}]

  if (name == null || format == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Fields name and format are required.'},
    );
  }

  final conn = context.read<Pool>();
  final hasMeta = await _hasDeckMetaColumns(conn);

  // 3. Usar uma transação para garantir a consistência dos dados
  try {
    final newDeck = await conn.runTx((session) async {
      // Insere o deck e obtém o ID gerado
      final deckResult = await session.execute(
        Sql.named(
          hasMeta
              ? 'INSERT INTO decks (user_id, name, format, description, archetype, bracket) VALUES (@userId, @name, @format, @desc, @archetype, @bracket) RETURNING id, name, format, archetype, bracket, created_at'
              : 'INSERT INTO decks (user_id, name, format, description) VALUES (@userId, @name, @format, @desc) RETURNING id, name, format, created_at',
        ),
        parameters: {
          'userId': userId,
          'name': name,
          'format': format,
          'desc': body['description'] as String?,
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
    return Response.json(
        statusCode: HttpStatus.badRequest, body: {'error': e.message});
  } catch (e) {
    print('[ERROR] Failed to create deck: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to create deck'},
    );
  }
}
