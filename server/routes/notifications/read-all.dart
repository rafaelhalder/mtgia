import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// PUT /notifications/read-all → Marcar todas as notificações como lidas
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();

    final result = await pool.execute(
      Sql.named('''
        UPDATE notifications
        SET read_at = CURRENT_TIMESTAMP
        WHERE user_id = @userId AND read_at IS NULL
      '''),
      parameters: {'userId': userId},
    );

    return Response.json(body: {
      'marked_read': result.affectedRows,
    });
  } catch (e) {
    print('[ERROR] Erro ao marcar todas como lidas: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao marcar todas como lidas'},
    );
  }
}
