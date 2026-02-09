import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  switch (context.request.method) {
    case HttpMethod.post:
      return _followUser(context, id);
    case HttpMethod.delete:
      return _unfollowUser(context, id);
    case HttpMethod.get:
      return _checkFollowing(context, id);
    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

/// POST /users/:id/follow — seguir um usuário
Future<Response> _followUser(RequestContext context, String targetId) async {
  try {
    final conn = context.read<Pool>();
    final userId = context.read<String>(); // injetado pelo authMiddleware

    if (userId == targetId) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'You cannot follow yourself.'},
      );
    }

    // Verificar se o alvo existe
    final userExists = await conn.execute(
      Sql.named('SELECT 1 FROM users WHERE id = @id'),
      parameters: {'id': targetId},
    );
    if (userExists.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'User not found.'},
      );
    }

    // Inserir follow (ON CONFLICT ignora duplicatas)
    await conn.execute(
      Sql.named('''
        INSERT INTO user_follows (follower_id, following_id)
        VALUES (@follower, @following)
        ON CONFLICT (follower_id, following_id) DO NOTHING
      '''),
      parameters: {'follower': userId, 'following': targetId},
    );

    // Retornar contadores atualizados
    final counts = await _getFollowCounts(conn, targetId);

    return Response.json(
      statusCode: HttpStatus.ok,
      body: {
        'message': 'Now following user.',
        'is_following': true,
        ...counts,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error', 'details': '$e'},
    );
  }
}

/// DELETE /users/:id/follow — deixar de seguir
Future<Response> _unfollowUser(RequestContext context, String targetId) async {
  try {
    final conn = context.read<Pool>();
    final userId = context.read<String>();

    await conn.execute(
      Sql.named('''
        DELETE FROM user_follows
        WHERE follower_id = @follower AND following_id = @following
      '''),
      parameters: {'follower': userId, 'following': targetId},
    );

    final counts = await _getFollowCounts(conn, targetId);

    return Response.json(body: {
      'message': 'Unfollowed user.',
      'is_following': false,
      ...counts,
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error', 'details': '$e'},
    );
  }
}

/// GET /users/:id/follow — checar se o autenticado segue o alvo
Future<Response> _checkFollowing(
    RequestContext context, String targetId) async {
  try {
    final conn = context.read<Pool>();
    final userId = context.read<String>();

    final result = await conn.execute(
      Sql.named('''
        SELECT 1 FROM user_follows
        WHERE follower_id = @follower AND following_id = @following
      '''),
      parameters: {'follower': userId, 'following': targetId},
    );

    final counts = await _getFollowCounts(conn, targetId);

    return Response.json(body: {
      'is_following': result.isNotEmpty,
      ...counts,
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error', 'details': '$e'},
    );
  }
}

Future<Map<String, dynamic>> _getFollowCounts(
    Pool conn, String userId) async {
  final result = await conn.execute(
    Sql.named('''
      SELECT
        (SELECT COUNT(*)::int FROM user_follows WHERE following_id = @id) as follower_count,
        (SELECT COUNT(*)::int FROM user_follows WHERE follower_id = @id) as following_count
    '''),
    parameters: {'id': userId},
  );
  final m = result.first.toColumnMap();
  return {
    'follower_count': m['follower_count'] ?? 0,
    'following_count': m['following_count'] ?? 0,
  };
}
