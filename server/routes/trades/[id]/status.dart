import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/notification_service.dart';

/// PUT /trades/:id/status → Atualizar status de entrega
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final body = await context.request.json() as Map<String, dynamic>;

    final newStatus = body['status'] as String?;
    final deliveryMethod = body['delivery_method'] as String?;
    final trackingCode = body['tracking_code'] as String?;
    final notes = body['notes'] as String?;

    if (newStatus == null || newStatus.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'status é obrigatório'},
      );
    }

    if (!['shipped', 'delivered', 'completed', 'cancelled', 'disputed'].contains(newStatus)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Status inválido. Use: shipped, delivered, completed, cancelled, disputed'},
      );
    }

    // Buscar trade
    final tradeResult = await pool.execute(Sql.named('''
      SELECT id, sender_id, receiver_id, status
      FROM trade_offers WHERE id = @id
    '''), parameters: {'id': id});

    if (tradeResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Trade não encontrado'},
      );
    }

    final trade = tradeResult.first.toColumnMap();
    final currentStatus = trade['status'] as String;
    final isSender = trade['sender_id'] == userId;
    final isReceiver = trade['receiver_id'] == userId;

    if (!isSender && !isReceiver) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Sem permissão para atualizar este trade'},
      );
    }

    // Validar transições de estado
    final validTransitions = <String, List<String>>{
      'accepted': ['shipped', 'cancelled', 'disputed'],
      'shipped': ['delivered', 'cancelled', 'disputed'],
      'delivered': ['completed', 'disputed'],
      'pending': ['cancelled'],
    };

    final allowed = validTransitions[currentStatus] ?? [];
    if (!allowed.contains(newStatus)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'Transição inválida: $currentStatus → $newStatus',
          'allowed_transitions': allowed,
        },
      );
    }

    // Validar quem pode fazer o quê
    if (newStatus == 'shipped' && !isSender) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Apenas o remetente pode marcar como enviado'},
      );
    }
    if (newStatus == 'delivered' && !isReceiver) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Apenas o destinatário pode confirmar recebimento'},
      );
    }

    // Atualizar
    await pool.runTx((session) async {
      final setClauses = <String>['status = @newStatus', 'updated_at = CURRENT_TIMESTAMP'];
      final params = <String, dynamic>{'id': id, 'newStatus': newStatus};

      if (deliveryMethod != null) {
        setClauses.add('delivery_method = @deliveryMethod');
        params['deliveryMethod'] = deliveryMethod;
      }
      if (trackingCode != null) {
        setClauses.add('tracking_code = @trackingCode');
        params['trackingCode'] = trackingCode;
      }

      await session.execute(Sql.named('''
        UPDATE trade_offers SET ${setClauses.join(', ')} WHERE id = @id
      '''), parameters: params);

      await session.execute(Sql.named('''
        INSERT INTO trade_status_history (trade_offer_id, old_status, new_status, changed_by, notes)
        VALUES (@id, @oldStatus, @newStatus, @userId, @notes)
      '''), parameters: {
        'id': id,
        'oldStatus': currentStatus,
        'newStatus': newStatus,
        'userId': userId,
        'notes': notes ?? 'Status atualizado para $newStatus',
      });
    });

    // 🔔 Notificação: status do trade atualizado → notificar a outra parte
    final notifyType = 'trade_$newStatus'; // trade_shipped, trade_delivered, trade_completed
    final validNotifTypes = ['trade_shipped', 'trade_delivered', 'trade_completed'];
    if (validNotifTypes.contains(notifyType)) {
      final changerInfo = await pool.execute(
        Sql.named('SELECT username, display_name FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
      final changerName = changerInfo.isNotEmpty
          ? (changerInfo.first.toColumnMap()['display_name'] ??
              changerInfo.first.toColumnMap()['username']) as String
          : 'Alguém';
      final notifyUserId = isSender
          ? trade['receiver_id'] as String
          : trade['sender_id'] as String;
      final statusLabels = {
        'trade_shipped': 'marcou o trade como enviado',
        'trade_delivered': 'confirmou o recebimento do trade',
        'trade_completed': 'finalizou o trade',
      };
      await NotificationService.create(
        pool: pool,
        userId: notifyUserId,
        type: notifyType,
        title: '$changerName ${statusLabels[notifyType]}',
        referenceId: id,
      );
    }

    return Response.json(body: {
      'id': id,
      'old_status': currentStatus,
      'status': newStatus,
      'message': 'Status atualizado para $newStatus',
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao atualizar status: $e'},
    );
  }
}
