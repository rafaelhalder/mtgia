import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/auth_service.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  return _getUserProfile(context, id);
}

/// GET /community/users/:id
/// Retorna perfil público de um usuário (sem email/senha).
/// Inclui: username, display_name, avatar_url, contadores de seguidores,
/// decks públicos, e se o visitante autenticado segue esse usuário.
Future<Response> _getUserProfile(RequestContext context, String userId) async {
  try {
    final conn = context.read<Pool>();

    // Idempotente: garante colunas de perfil
    await conn.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT'));
    await conn.execute(Sql.named(
        'ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT'));

    // Buscar usuário
    final userResult = await conn.execute(
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
        WHERE u.id = @userId
      '''),
      parameters: {'userId': userId},
    );

    if (userResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'User not found.'},
      );
    }

    final user = userResult.first.toColumnMap();
    if (user['created_at'] is DateTime) {
      user['created_at'] = (user['created_at'] as DateTime).toIso8601String();
    }
    user.remove('email');
    user.remove('password_hash');

    // Checar se o visitante segue esse usuário (se estiver autenticado)
    bool isFollowing = false;
    final authHeader = context.request.headers['Authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      final token = authHeader.substring(7);
      final authService = AuthService();
      final payload = authService.verifyToken(token);
      if (payload != null) {
        final viewerId = payload['userId'] as String;
        final followResult = await conn.execute(
          Sql.named('''
            SELECT 1 FROM user_follows
            WHERE follower_id = @viewerId AND following_id = @userId
          '''),
          parameters: {'viewerId': viewerId, 'userId': userId},
        );
        isFollowing = followResult.isNotEmpty;
        user['is_own_profile'] = viewerId == userId;
      }
    }
    user['is_following'] = isFollowing;

    // Buscar decks públicos do usuário
    final decksResult = await conn.execute(
      Sql.named('''
        SELECT
          d.id,
          d.name,
          d.format,
          d.description,
          d.synergy_score,
          d.created_at,
          COALESCE(SUM(dc.quantity), 0)::int as card_count,
          cmd.commander_name,
          COALESCE(cmd.commander_image_url, first_card.first_image_url) as commander_image_url
        FROM decks d
        LEFT JOIN LATERAL (
          SELECT
            c.name as commander_name,
            c.image_url as commander_image_url
          FROM deck_cards dc_cmd
          JOIN cards c ON c.id = dc_cmd.card_id
          WHERE dc_cmd.deck_id = d.id
            AND dc_cmd.is_commander = true
          LIMIT 1
        ) cmd ON true
        LEFT JOIN LATERAL (
          SELECT c.image_url as first_image_url
          FROM deck_cards dc_fc
          JOIN cards c ON c.id = dc_fc.card_id
          WHERE dc_fc.deck_id = d.id
            AND c.image_url IS NOT NULL
            AND c.image_url != ''
          ORDER BY dc_fc.quantity DESC, c.name
          LIMIT 1
        ) first_card ON true
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE d.user_id = @userId AND d.is_public = true
        GROUP BY d.id, cmd.commander_name, cmd.commander_image_url, first_card.first_image_url
        ORDER BY d.created_at DESC
        LIMIT 50
      '''),
      parameters: {'userId': userId},
    );

    final decks = decksResult.map((row) {
      final m = row.toColumnMap();
      if (m['created_at'] is DateTime) {
        m['created_at'] = (m['created_at'] as DateTime).toIso8601String();
      }
      return m;
    }).toList();

    return Response.json(body: {
      'user': user,
      'public_decks': decks,
    });
  } catch (e) {
    print('[ERROR] Internal server error: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error'},
    );
  }
}
