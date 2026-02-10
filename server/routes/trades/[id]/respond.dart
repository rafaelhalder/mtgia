import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/notification_service.dart';

/// PUT /trades/:id/respond → Aceitar ou recusar trade
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final body = await context.request.json() as Map<String, dynamic>;

    final action = body['action'] as String?;
    if (action == null || !['accept', 'decline'].contains(action)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'action deve ser "accept" ou "decline"'},
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

    // Só o receiver pode responder
    if (trade['receiver_id'] != userId) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Apenas o destinatário pode aceitar/recusar'},
      );
    }

    // Só se o status for pending
    if (trade['status'] != 'pending') {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Trade não está pendente (status atual: ${trade['status']})'},
      );
    }

    final newStatus = action == 'accept' ? 'accepted' : 'declined';

    await pool.runTx((session) async {
      await session.execute(Sql.named('''
        UPDATE trade_offers SET status = @newStatus, updated_at = CURRENT_TIMESTAMP
        WHERE id = @id
      '''), parameters: {'id': id, 'newStatus': newStatus});

      await session.execute(Sql.named('''
        INSERT INTO trade_status_history (trade_offer_id, old_status, new_status, changed_by, notes)
        VALUES (@id, 'pending', @newStatus, @userId, @notes)
      '''), parameters: {
        'id': id,
        'newStatus': newStatus,
        'userId': userId,
        'notes': action == 'accept' ? 'Proposta aceita' : 'Proposta recusada',
      });
    });

    // 🔔 Notificação: trade aceito/recusado → notificar o sender
    final responderInfo = await pool.execute(
      Sql.named('SELECT username, display_name FROM users WHERE id = @id'),
      parameters: {'id': userId},
    );
    final responderName = responderInfo.isNotEmpty
        ? (responderInfo.first.toColumnMap()['display_name'] ??
            responderInfo.first.toColumnMap()['username']) as String
        : 'Alguém';
    final senderId = trade['sender_id'] as String;
    await NotificationService.create(
      pool: pool,
      userId: senderId,
      type: action == 'accept' ? 'trade_accepted' : 'trade_declined',
      title: action == 'accept'
          ? '$responderName aceitou sua proposta de trade'
          : '$responderName recusou sua proposta de trade',
      referenceId: id,
    );

    return Response.json(body: {
      'id': id,
      'status': newStatus,
      'message': action == 'accept' ? 'Trade aceito!' : 'Trade recusado.',
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao responder trade: $e'},
    );
  }
}
