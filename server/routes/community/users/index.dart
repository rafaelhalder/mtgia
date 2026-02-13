import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  return _searchUsers(context);
}

/// GET /community/users?q=<query>&page=1&limit=20
/// Busca usuários por username ou display_name.
Future<Response> _searchUsers(RequestContext context) async {
  final params = context.request.uri.queryParameters;
  final query = params['q']?.trim();
  final page = int.tryParse(params['page'] ?? '') ?? 1;
  final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 50);
  final offset = (page - 1) * limit;

  if (query == null || query.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Query parameter "q" is required.'},
    );
  }

  try {
    final conn = context.read<Pool>();

    // Idempotente: garante colunas de perfil
    await conn.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT'));
    await conn.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT'));

    // Count
    final countResult = await conn.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM users
        WHERE LOWER(username) LIKE @search
           OR LOWER(COALESCE(display_name, '')) LIKE @search
      '''),
      parameters: {'search': '%${query.toLowerCase()}%'},
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Fetch users with follower counts
    final result = await conn.execute(
      Sql.named('''
        SELECT
          u.id,
          u.username,
          u.display_name,
          u.avatar_url,
          u.created_at,
          (SELECT COUNT(*)::int FROM user_follows WHERE following_id = u.id) as follower_count,
          (SELECT COUNT(*)::int FROM user_follows WHERE follower_id = u.id) as following_count,
          (SELECT COUNT(*)::int FROM decks WHERE user_id = u.id AND is_public = true) as public_deck_count
        FROM users u
        WHERE LOWER(u.username) LIKE @search
           OR LOWER(COALESCE(u.display_name, '')) LIKE @search
        ORDER BY u.username ASC
        LIMIT @lim OFFSET @off
      '''),
      parameters: {
        'search': '%${query.toLowerCase()}%',
        'lim': limit,
        'off': offset,
      },
    );

    final users = result.map((row) {
      final m = row.toColumnMap();
      if (m['created_at'] is DateTime) {
        m['created_at'] = (m['created_at'] as DateTime).toIso8601String();
      }
      // Nunca expor email ou password_hash
      m.remove('email');
      m.remove('password_hash');
      return m;
    }).toList();

    return Response.json(body: {
      'data': users,
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
