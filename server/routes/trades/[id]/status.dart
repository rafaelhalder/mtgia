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

    // Validar transições de estado (checagem prévia para mensagem de erro amigável)
    final validTransitions = <String, List<String>>{
      'accepted': ['shipped', 'cancelled', 'disputed'],
      'shipped': ['delivered', 'cancelled', 'disputed'],
      'delivered': ['completed', 'disputed'],
      'pending': ['cancelled'],
    };

    // Buscar trade com lock atômico — atualizar apenas se a transição é válida
    late final String currentStatus;
    late final bool isSender;
    late final bool isReceiver;
    late final Map<String, dynamic> trade;

    final updated = await pool.runTx((session) async {
      // SELECT FOR UPDATE garante lock exclusivo dentro da transação
      final tradeResult = await session.execute(Sql.named('''
        SELECT id, sender_id, receiver_id, status, type
        FROM trade_offers WHERE id = @id FOR UPDATE
      '''), parameters: {'id': id});

      if (tradeResult.isEmpty) return 'not_found';

      trade = tradeResult.first.toColumnMap();
      currentStatus = trade['status'] as String;
      isSender = trade['sender_id'] == userId;
      isReceiver = trade['receiver_id'] == userId;

      if (!isSender && !isReceiver) return 'forbidden';

      final allowed = validTransitions[currentStatus] ?? [];
      if (!allowed.contains(newStatus)) return 'invalid_transition';

      // Validar quem pode fazer o quê
      // Em vendas (sale): receiver é o vendedor que envia, sender é o comprador que recebe
      // Em trocas (trade/mixed): ambos enviam e recebem, qualquer participante pode marcar
      final tradeType = trade['type'] as String? ?? 'trade';

      if (newStatus == 'shipped') {
        if (tradeType == 'sale') {
          // Venda: quem envia é o receiver (dono dos itens solicitados)
          if (!isReceiver) return 'only_receiver_ship_sale';
        } else {
          // Troca/Misto: qualquer participante pode marcar envio
          // (ambos precisam enviar seus itens)
        }
      }
      if (newStatus == 'delivered') {
        if (tradeType == 'sale') {
          // Venda: quem confirma recebimento é o sender (comprador)
          if (!isSender) return 'only_sender_deliver_sale';
        } else {
          // Troca/Misto: qualquer participante pode confirmar recebimento
        }
      }

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

      return 'ok';
    });

    // Tratar resultado da transação
    switch (updated) {
      case 'not_found':
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'error': 'Trade não encontrado'},
        );
      case 'forbidden':
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'Sem permissão para atualizar este trade'},
        );
      case 'invalid_transition':
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {
            'error': 'Transição inválida: $currentStatus → $newStatus',
            'allowed_transitions': validTransitions[currentStatus] ?? [],
          },
        );
      case 'only_sender_ship':
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'Apenas o remetente pode marcar como enviado'},
        );
      case 'only_receiver_deliver':
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'Apenas o destinatário pode confirmar recebimento'},
        );
      case 'only_receiver_ship_sale':
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'Em vendas, apenas o vendedor (quem recebeu a proposta) pode marcar como enviado'},
        );
      case 'only_sender_deliver_sale':
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'Em vendas, apenas o comprador (quem criou a proposta) pode confirmar recebimento'},
        );
    }

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
    print('[ERROR] Erro ao atualizar status trade $id: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro interno ao atualizar status'},
    );
  }
}
