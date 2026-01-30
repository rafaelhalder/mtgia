import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../lib/deck_rules_service.dart';
import '../../lib/logger.dart';

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
    final result = await conn.execute(
      Sql.named('''
        SELECT 
          d.id, 
          d.name, 
          d.format, 
          d.description, 
          d.synergy_score, 
          d.created_at,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE d.user_id = @userId
        GROUP BY d.id
        ORDER BY d.created_at DESC
      '''),
      parameters: {'userId': userId},
    );
    Log.d('✅ Query executada. Encontrados ${result.length} decks.');

    final decks = result.map((row) {
      final map = row.toColumnMap();
      if (map['created_at'] is DateTime) {
        map['created_at'] = (map['created_at'] as DateTime).toIso8601String();
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
      body: {'error': 'Failed to list decks: $e'},
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
  final cards = body['cards'] as List? ??
      []; // Ex: [{'card_id': 'uuid', 'quantity': 2, 'is_commander': false}]

  if (name == null || format == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Fields name and format are required.'},
    );
  }

  final conn = context.read<Pool>();

  // 3. Usar uma transação para garantir a consistência dos dados
  try {
    final newDeck = await conn.runTx((session) async {
      // Insere o deck e obtém o ID gerado
      final deckResult = await session.execute(
        Sql.named(
          'INSERT INTO decks (user_id, name, format, description) VALUES (@userId, @name, @format, @desc) RETURNING id, name, format, created_at',
        ),
        parameters: {
          'userId': userId,
          'name': name,
          'format': format,
          'desc': body['description'] as String?,
        },
      );

      final deckMap = deckResult.first.toColumnMap();
      if (deckMap['created_at'] is DateTime) {
        deckMap['created_at'] =
            (deckMap['created_at'] as DateTime).toIso8601String();
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
    return Response.json(
        statusCode: HttpStatus.badRequest, body: {'error': e.message});
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to create deck: $e'},
    );
  }
}
