import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  return _getFollowing(context, id);
}

/// GET /users/:id/following?page=1&limit=20
/// Lista os usuários que este usuário segue.
Future<Response> _getFollowing(RequestContext context, String userId) async {
  try {
    final conn = context.read<Pool>();
    final params = context.request.uri.queryParameters;
    final page = int.tryParse(params['page'] ?? '') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 50);
    final offset = (page - 1) * limit;

    // Count total following
    final countResult = await conn.execute(
      Sql.named(
          'SELECT COUNT(*)::int FROM user_follows WHERE follower_id = @id'),
      parameters: {'id': userId},
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Fetch following
    final result = await conn.execute(
      Sql.named('''
        SELECT
          u.id,
          u.username,
          u.display_name,
          u.avatar_url,
          uf.created_at as followed_at
        FROM user_follows uf
        JOIN users u ON u.id = uf.following_id
        WHERE uf.follower_id = @userId
        ORDER BY uf.created_at DESC
        LIMIT @lim OFFSET @off
      '''),
      parameters: {
        'userId': userId,
        'lim': limit,
        'off': offset,
      },
    );

    final following = result.map((row) {
      final m = row.toColumnMap();
      if (m['followed_at'] is DateTime) {
        m['followed_at'] = (m['followed_at'] as DateTime).toIso8601String();
      }
      return m;
    }).toList();

    return Response.json(body: {
      'data': following,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    print('[ERROR] Internal server error: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error'},
    );
  }
}
