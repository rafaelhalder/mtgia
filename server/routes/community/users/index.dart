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

    // Fetch users with follower counts (batch aggregation, sem subquery por linha)
    final result = await conn.execute(
      Sql.named('''
        WITH paged_users AS (
          SELECT
            u.id,
            u.username,
            u.display_name,
            u.avatar_url,
            u.created_at
          FROM users u
          WHERE LOWER(u.username) LIKE @search
             OR LOWER(COALESCE(u.display_name, '')) LIKE @search
          ORDER BY u.username ASC
          LIMIT @lim OFFSET @off
        ),
        follower_counts AS (
          SELECT uf.following_id AS user_id, COUNT(*)::int AS follower_count
          FROM user_follows uf
          WHERE uf.following_id IN (SELECT id FROM paged_users)
          GROUP BY uf.following_id
        ),
        following_counts AS (
          SELECT uf.follower_id AS user_id, COUNT(*)::int AS following_count
          FROM user_follows uf
          WHERE uf.follower_id IN (SELECT id FROM paged_users)
          GROUP BY uf.follower_id
        ),
        public_deck_counts AS (
          SELECT d.user_id, COUNT(*)::int AS public_deck_count
          FROM decks d
          WHERE d.is_public = true
            AND d.user_id IN (SELECT id FROM paged_users)
          GROUP BY d.user_id
        )
        SELECT
          pu.id,
          pu.username,
          pu.display_name,
          pu.avatar_url,
          pu.created_at,
          COALESCE(fc.follower_count, 0) AS follower_count,
          COALESCE(flc.following_count, 0) AS following_count,
          COALESCE(pdc.public_deck_count, 0) AS public_deck_count
        FROM paged_users pu
        LEFT JOIN follower_counts fc ON fc.user_id = pu.id
        LEFT JOIN following_counts flc ON flc.user_id = pu.id
        LEFT JOIN public_deck_counts pdc ON pdc.user_id = pu.id
        ORDER BY pu.username ASC
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
