import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../lib/notification_service.dart';

/// GET  /trades  → Listar trades do usuário
/// POST /trades  → Criar proposta de trade
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method == HttpMethod.get) return _listTrades(context);
  if (method == HttpMethod.post) return _createTrade(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

// ─── POST /trades ───────────────────────────────────────────────
Future<Response> _createTrade(RequestContext context) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final body = await context.request.json() as Map<String, dynamic>;

    final receiverId = body['receiver_id'] as String?;
    final type = body['type'] as String? ?? 'trade';
    final message = body['message'] as String?;
    final myItems = (body['my_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final requestedItems = (body['requested_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final paymentAmount = body['payment_amount'];
    final paymentMethod = body['payment_method'] as String?;

    // Validações básicas
    if (receiverId == null || receiverId.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'receiver_id é obrigatório'},
      );
    }
    if (receiverId == userId) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Não é possível fazer trade consigo mesmo'},
      );
    }
    if (!['trade', 'sale', 'mixed'].contains(type)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Tipo inválido. Use: trade, sale, mixed'},
      );
    }
    if (myItems.isEmpty && requestedItems.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'A proposta deve ter pelo menos 1 item'},
      );
    }
    if (type == 'trade' && (myItems.isEmpty || requestedItems.isEmpty)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Troca pura exige itens de ambos os lados'},
      );
    }

    // Verificar que o receiver existe
    final recvCheck = await pool.execute(
      Sql.named('SELECT id FROM users WHERE id = @id'),
      parameters: {'id': receiverId},
    );
    if (recvCheck.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Usuário destinatário não encontrado'},
      );
    }

    // Validar my_items em batch (pertence ao sender, for_trade ou for_sale)
    {
      final myBinderIds = <String>[];
      for (final item in myItems) {
        final biId = item['binder_item_id'] as String?;
        if (biId == null) {
          return Response.json(
            statusCode: HttpStatus.badRequest,
            body: {'error': 'binder_item_id obrigatório em my_items'},
          );
        }
        myBinderIds.add(biId);
      }

      if (myBinderIds.isNotEmpty) {
        final check = await pool.execute(
          Sql.named('''
            SELECT id, for_trade, for_sale FROM user_binder_items
            WHERE id = ANY(@ids::uuid[]) AND user_id = @userId
          '''),
          parameters: {'ids': myBinderIds, 'userId': userId},
        );
        final foundMap = <String, Map<String, dynamic>>{};
        for (final row in check) {
          final m = row.toColumnMap();
          foundMap[m['id'] as String] = m;
        }
        for (final biId in myBinderIds) {
          if (!foundMap.containsKey(biId)) {
            return Response.json(
              statusCode: HttpStatus.forbidden,
              body: {'error': 'Item $biId não pertence a você ou não existe'},
            );
          }
          final row = foundMap[biId]!;
          if (row['for_trade'] != true && row['for_sale'] != true) {
            return Response.json(
              statusCode: HttpStatus.badRequest,
              body: {'error': 'Item $biId não está marcado para troca/venda'},
            );
          }
        }
      }
    }

    // Validar requested_items em batch (pertence ao receiver, for_trade ou for_sale)
    {
      final reqBinderIds = <String>[];
      for (final item in requestedItems) {
        final biId = item['binder_item_id'] as String?;
        if (biId == null) {
          return Response.json(
            statusCode: HttpStatus.badRequest,
            body: {'error': 'binder_item_id obrigatório em requested_items'},
          );
        }
        reqBinderIds.add(biId);
      }

      if (reqBinderIds.isNotEmpty) {
        final check = await pool.execute(
          Sql.named('''
            SELECT id, for_trade, for_sale FROM user_binder_items
            WHERE id = ANY(@ids::uuid[]) AND user_id = @receiverId
          '''),
          parameters: {'ids': reqBinderIds, 'receiverId': receiverId},
        );
        final foundMap = <String, Map<String, dynamic>>{};
        for (final row in check) {
          final m = row.toColumnMap();
          foundMap[m['id'] as String] = m;
        }
        for (final biId in reqBinderIds) {
          if (!foundMap.containsKey(biId)) {
            return Response.json(
              statusCode: HttpStatus.badRequest,
              body: {'error': 'Item $biId não pertence ao destinatário ou não existe'},
            );
          }
          final row = foundMap[biId]!;
          if (row['for_trade'] != true && row['for_sale'] != true) {
            return Response.json(
              statusCode: HttpStatus.badRequest,
              body: {'error': 'Item $biId do destinatário não está disponível para troca/venda'},
            );
          }
        }
      }
    }

    // Criar trade em transação
    final tradeResult = await pool.runTx((session) async {
      // 1. Inserir trade_offers
      final offerResult = await session.execute(Sql.named('''
        INSERT INTO trade_offers (sender_id, receiver_id, type, message, payment_amount, payment_method)
        VALUES (@senderId, @receiverId, @type, @message, @paymentAmount, @paymentMethod)
        RETURNING id, status, type, message, payment_amount, payment_currency, created_at
      '''), parameters: {
        'senderId': userId,
        'receiverId': receiverId,
        'type': type,
        'message': message,
        'paymentAmount': paymentAmount != null ? double.tryParse(paymentAmount.toString()) : null,
        'paymentMethod': paymentMethod,
      });
      final offer = offerResult.first.toColumnMap();
      final tradeId = offer['id'] as String;

      // 2. Inserir my_items (direction: offering)
      for (final item in myItems) {
        await session.execute(Sql.named('''
          INSERT INTO trade_items (trade_offer_id, binder_item_id, owner_id, direction, quantity, agreed_price)
          VALUES (@tradeId, @binderId, @ownerId, 'offering', @qty, @price)
        '''), parameters: {
          'tradeId': tradeId,
          'binderId': item['binder_item_id'],
          'ownerId': userId,
          'qty': item['quantity'] as int? ?? 1,
          'price': item['agreed_price'] != null ? double.tryParse(item['agreed_price'].toString()) : null,
        });
      }

      // 3. Inserir requested_items (direction: requesting)
      for (final item in requestedItems) {
        await session.execute(Sql.named('''
          INSERT INTO trade_items (trade_offer_id, binder_item_id, owner_id, direction, quantity, agreed_price)
          VALUES (@tradeId, @binderId, @ownerId, 'requesting', @qty, @price)
        '''), parameters: {
          'tradeId': tradeId,
          'binderId': item['binder_item_id'],
          'ownerId': receiverId,
          'qty': item['quantity'] as int? ?? 1,
          'price': item['agreed_price'] != null ? double.tryParse(item['agreed_price'].toString()) : null,
        });
      }

      // 4. Registrar no histórico
      await session.execute(Sql.named('''
        INSERT INTO trade_status_history (trade_offer_id, old_status, new_status, changed_by, notes)
        VALUES (@tradeId, NULL, 'pending', @userId, 'Proposta criada')
      '''), parameters: {'tradeId': tradeId, 'userId': userId});

      if (offer['created_at'] is DateTime) {
        offer['created_at'] = (offer['created_at'] as DateTime).toIso8601String();
      }

      return {
        'id': tradeId,
        'status': offer['status'],
        'type': offer['type'],
        'message': offer['message'],
        'payment_amount': offer['payment_amount'] != null
            ? double.tryParse(offer['payment_amount'].toString())
            : null,
        'payment_currency': offer['payment_currency'],
        'my_items_count': myItems.length,
        'requested_items_count': requestedItems.length,
        'created_at': offer['created_at'],
      };
    });

    // 🔔 Notificação: proposta de trade recebida
    final senderInfo = await pool.execute(
      Sql.named('SELECT username, display_name FROM users WHERE id = @id'),
      parameters: {'id': userId},
    );
    final senderName = senderInfo.isNotEmpty
        ? (senderInfo.first.toColumnMap()['display_name'] ??
            senderInfo.first.toColumnMap()['username']) as String
        : 'Alguém';
    await NotificationService.create(
      pool: pool,
      userId: receiverId,
      type: 'trade_offer_received',
      title: '$senderName enviou uma proposta de trade',
      body: message,
      referenceId: tradeResult['id'] as String?,
    );

    return Response.json(statusCode: HttpStatus.created, body: tradeResult);
  } catch (e) {
    print('[ERROR] _createTrade: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro interno ao criar trade'},
    );
  }
}

// ─── GET /trades ────────────────────────────────────────────────
Future<Response> _listTrades(RequestContext context) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final params = context.request.uri.queryParameters;

    final status = params['status'];
    final role = params['role'] ?? 'all'; // sender, receiver, all
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '20') ?? 20).clamp(1, 50);
    final offset = (page - 1) * limit;

    final whereParts = <String>[];
    final filterParams = <String, dynamic>{'userId': userId};

    // Role filter
    if (role == 'sender') {
      whereParts.add('t.sender_id = @userId');
    } else if (role == 'receiver') {
      whereParts.add('t.receiver_id = @userId');
    } else {
      whereParts.add('(t.sender_id = @userId OR t.receiver_id = @userId)');
    }

    // Status filter
    if (status != null && status.isNotEmpty) {
      whereParts.add('t.status = @status');
      filterParams['status'] = status;
    }

    final where = whereParts.join(' AND ');

    // Count
    final countResult = await pool.execute(
      Sql.named('SELECT COUNT(*)::int FROM trade_offers t WHERE $where'),
      parameters: filterParams,
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Fetch
    final result = await pool.execute(Sql.named('''
      SELECT
        t.id, t.status, t.type, t.message,
        t.payment_amount, t.payment_currency,
        t.tracking_code, t.delivery_method,
        t.created_at, t.updated_at,
        s.id as sender_id, s.username as sender_username, s.display_name as sender_display_name,
        r.id as receiver_id, r.username as receiver_username, r.display_name as receiver_display_name,
        (SELECT COUNT(*) FROM trade_items ti WHERE ti.trade_offer_id = t.id AND ti.direction = 'offering')::int as offering_count,
        (SELECT COUNT(*) FROM trade_items ti WHERE ti.trade_offer_id = t.id AND ti.direction = 'requesting')::int as requesting_count,
        (SELECT COUNT(*) FROM trade_messages tm WHERE tm.trade_offer_id = t.id)::int as message_count
      FROM trade_offers t
      JOIN users s ON s.id = t.sender_id
      JOIN users r ON r.id = t.receiver_id
      WHERE $where
      ORDER BY t.updated_at DESC
      LIMIT @lim OFFSET @off
    '''), parameters: {...filterParams, 'lim': limit, 'off': offset});

    final trades = result.map((row) {
      final m = row.toColumnMap();
      for (final k in ['created_at', 'updated_at']) {
        if (m[k] is DateTime) m[k] = (m[k] as DateTime).toIso8601String();
      }
      if (m['payment_amount'] != null) {
        m['payment_amount'] = double.tryParse(m['payment_amount'].toString());
      }
      return {
        'id': m['id'],
        'status': m['status'],
        'type': m['type'],
        'message': m['message'],
        'payment_amount': m['payment_amount'],
        'payment_currency': m['payment_currency'],
        'tracking_code': m['tracking_code'],
        'delivery_method': m['delivery_method'],
        'sender': {
          'id': m['sender_id'],
          'username': m['sender_username'],
          'display_name': m['sender_display_name'],
        },
        'receiver': {
          'id': m['receiver_id'],
          'username': m['receiver_username'],
          'display_name': m['receiver_display_name'],
        },
        'offering_count': m['offering_count'],
        'requesting_count': m['requesting_count'],
        'message_count': m['message_count'],
        'created_at': m['created_at'],
        'updated_at': m['updated_at'],
      };
    }).toList();

    return Response.json(body: {
      'data': trades,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] _listTrades: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro interno ao listar trades'},
    );
  }
}
