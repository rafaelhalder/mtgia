import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /notifications → Listar notificações do usuário
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final params = context.request.uri.queryParameters;
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '30') ?? 30).clamp(1, 50);
    final offset = (page - 1) * limit;
    final unreadOnly = params['unread_only'] == 'true';

    final whereClause = unreadOnly
        ? 'user_id = @userId AND read_at IS NULL'
        : 'user_id = @userId';

    // Count
    final countResult = await pool.execute(
      Sql.named('SELECT COUNT(*)::int FROM notifications WHERE $whereClause'),
      parameters: {'userId': userId},
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // List
    final result = await pool.execute(
      Sql.named('''
        SELECT id, type, reference_id, title, body, read_at, created_at
        FROM notifications
        WHERE $whereClause
        ORDER BY created_at DESC
        LIMIT @lim OFFSET @off
      '''),
      parameters: {'userId': userId, 'lim': limit, 'off': offset},
    );

    final notifications = result.map((row) {
      final m = row.toColumnMap();
      for (final k in ['read_at', 'created_at']) {
        if (m[k] is DateTime) m[k] = (m[k] as DateTime).toIso8601String();
      }
      return {
        'id': m['id'],
        'type': m['type'],
        'reference_id': m['reference_id'],
        'title': m['title'],
        'body': m['body'],
        'read_at': m['read_at'],
        'created_at': m['created_at'],
      };
    }).toList();

    return Response.json(body: {
      'data': notifications,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] Erro ao listar notificações: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao listar notificações'},
    );
  }
}
