import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET  /trades/:id           → Detalhe do trade
/// PUT  /trades/:id           → (não usado diretamente, sub-rotas respond/status)
///
/// Rotas especiais tratadas por id:
///   id == "<uuid>"   → detalhe do trade
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method == HttpMethod.get) {
    return _getTradeDetail(context, id);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _getTradeDetail(RequestContext context, String id) async {
  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();

    // Buscar trade
    final tradeResult = await pool.execute(Sql.named('''
      SELECT
        t.id, t.status, t.type, t.message,
        t.payment_amount, t.payment_currency,
        t.delivery_method, t.payment_method,
        t.tracking_code, t.created_at, t.updated_at,
        s.id as sender_id, s.username as sender_username, s.display_name as sender_display_name, s.avatar_url as sender_avatar,
        r.id as receiver_id, r.username as receiver_username, r.display_name as receiver_display_name, r.avatar_url as receiver_avatar
      FROM trade_offers t
      JOIN users s ON s.id = t.sender_id
      JOIN users r ON r.id = t.receiver_id
      WHERE t.id = @tradeId
    '''), parameters: {'tradeId': id});

    if (tradeResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Trade não encontrado'},
      );
    }

    final trade = tradeResult.first.toColumnMap();

    // Verificar permissão (sender ou receiver)
    if (trade['sender_id'] != userId && trade['receiver_id'] != userId) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Sem permissão para ver este trade'},
      );
    }

    // Buscar items com dados da carta
    final itemsResult = await pool.execute(Sql.named('''
      SELECT
        ti.id, ti.direction, ti.quantity, ti.agreed_price,
        ti.owner_id, ti.binder_item_id,
        bi.condition, bi.is_foil,
        c.id as card_id, c.name as card_name, c.image_url as card_image_url,
        c.set_code as card_set_code, c.mana_cost as card_mana_cost,
        c.rarity as card_rarity
      FROM trade_items ti
      JOIN user_binder_items bi ON bi.id = ti.binder_item_id
      JOIN cards c ON c.id = bi.card_id
      WHERE ti.trade_offer_id = @tradeId
      ORDER BY ti.direction, c.name
    '''), parameters: {'tradeId': id});

    final myItems = <Map<String, dynamic>>[];
    final theirItems = <Map<String, dynamic>>[];

    for (final row in itemsResult) {
      final m = row.toColumnMap();
      final item = {
        'id': m['id'],
        'binder_item_id': m['binder_item_id'],
        'direction': m['direction'],
        'quantity': m['quantity'],
        'agreed_price': m['agreed_price'] != null
            ? double.tryParse(m['agreed_price'].toString())
            : null,
        'condition': m['condition'],
        'is_foil': m['is_foil'],
        'card': {
          'id': m['card_id'],
          'name': m['card_name'],
          'image_url': m['card_image_url'],
          'set_code': m['card_set_code'],
          'mana_cost': m['card_mana_cost'],
          'rarity': m['card_rarity'],
        },
      };

      // Organizar pela perspectiva do viewer
      if (m['owner_id'] == userId) {
        myItems.add(item);
      } else {
        theirItems.add(item);
      }
    }

    // Buscar mensagens (últimas 50)
    final msgsResult = await pool.execute(Sql.named('''
      SELECT
        tm.id, tm.sender_id, tm.message, tm.attachment_url, tm.attachment_type, tm.created_at,
        u.username as sender_username
      FROM trade_messages tm
      JOIN users u ON u.id = tm.sender_id
      WHERE tm.trade_offer_id = @tradeId
      ORDER BY tm.created_at ASC
      LIMIT 50
    '''), parameters: {'tradeId': id});

    final messages = msgsResult.map((row) {
      final m = row.toColumnMap();
      if (m['created_at'] is DateTime) {
        m['created_at'] = (m['created_at'] as DateTime).toIso8601String();
      }
      return {
        'id': m['id'],
        'sender_id': m['sender_id'],
        'sender_username': m['sender_username'],
        'message': m['message'],
        'attachment_url': m['attachment_url'],
        'attachment_type': m['attachment_type'],
        'created_at': m['created_at'],
      };
    }).toList();

    // Buscar histórico de status
    final historyResult = await pool.execute(Sql.named('''
      SELECT
        tsh.id, tsh.old_status, tsh.new_status, tsh.notes, tsh.created_at,
        u.username as changed_by_username
      FROM trade_status_history tsh
      JOIN users u ON u.id = tsh.changed_by
      WHERE tsh.trade_offer_id = @tradeId
      ORDER BY tsh.created_at ASC
    '''), parameters: {'tradeId': id});

    final history = historyResult.map((row) {
      final m = row.toColumnMap();
      if (m['created_at'] is DateTime) {
        m['created_at'] = (m['created_at'] as DateTime).toIso8601String();
      }
      return {
        'id': m['id'],
        'old_status': m['old_status'],
        'new_status': m['new_status'],
        'notes': m['notes'],
        'changed_by_username': m['changed_by_username'],
        'created_at': m['created_at'],
      };
    }).toList();

    // Montar response
    for (final k in ['created_at', 'updated_at']) {
      if (trade[k] is DateTime) trade[k] = (trade[k] as DateTime).toIso8601String();
    }
    if (trade['payment_amount'] != null) {
      trade['payment_amount'] = double.tryParse(trade['payment_amount'].toString());
    }

    return Response.json(body: {
      'id': trade['id'],
      'status': trade['status'],
      'type': trade['type'],
      'message': trade['message'],
      'payment_amount': trade['payment_amount'],
      'payment_currency': trade['payment_currency'],
      'payment_method': trade['payment_method'],
      'delivery_method': trade['delivery_method'],
      'tracking_code': trade['tracking_code'],
      'sender': {
        'id': trade['sender_id'],
        'username': trade['sender_username'],
        'display_name': trade['sender_display_name'],
        'avatar_url': trade['sender_avatar'],
      },
      'receiver': {
        'id': trade['receiver_id'],
        'username': trade['receiver_username'],
        'display_name': trade['receiver_display_name'],
        'avatar_url': trade['receiver_avatar'],
      },
      'my_items': myItems,
      'their_items': theirItems,
      'messages': messages,
      'status_history': history,
      'created_at': trade['created_at'],
      'updated_at': trade['updated_at'],
    });
  } catch (e) {
    print('[ERROR] Erro ao buscar trade: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao buscar trade'},
    );
  }
}
