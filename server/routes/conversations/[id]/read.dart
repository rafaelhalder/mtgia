import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// PUT /conversations/:id/read → Marcar mensagens como lidas
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();

    // Verificar participação
    final convResult = await pool.execute(
      Sql.named('SELECT user_a_id, user_b_id FROM conversations WHERE id = @id'),
      parameters: {'id': id},
    );
    if (convResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Conversa não encontrada'},
      );
    }
    final conv = convResult.first.toColumnMap();
    if (conv['user_a_id'] != userId && conv['user_b_id'] != userId) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Sem permissão'},
      );
    }

    // Marcar como lidas todas as mensagens do OUTRO usuário que ainda não foram lidas
    final result = await pool.execute(
      Sql.named('''
        UPDATE direct_messages
        SET read_at = CURRENT_TIMESTAMP
        WHERE conversation_id = @convId
          AND sender_id != @userId
          AND read_at IS NULL
      '''),
      parameters: {'convId': id, 'userId': userId},
    );

    return Response.json(body: {
      'marked_read': result.affectedRows,
    });
  } catch (e) {
    print('[ERROR] Erro ao marcar como lidas: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao marcar como lidas'},
    );
  }
}
