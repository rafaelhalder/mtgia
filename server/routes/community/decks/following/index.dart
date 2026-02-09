import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/auth_service.dart';

String? _normalizeScryfallImageUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('https://api.scryfall.com/')) return trimmed;
  try {
    final uri = Uri.parse(trimmed);
    final qp = Map<String, String>.from(uri.queryParameters);
    if (qp['set'] != null) qp['set'] = qp['set']!.toLowerCase();
    final exact = qp['exact'];
    if (uri.path == '/cards/named' && exact != null && exact.contains('//')) {
      final left = exact.split('//').first.trim();
      if (left.isNotEmpty) qp['exact'] = left;
    }
    return uri.replace(queryParameters: qp).toString();
  } catch (_) {
    return trimmed;
  }
}

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  return _getFollowingFeed(context);
}

/// GET /community/decks/following?page=1&limit=20
/// Retorna decks públicos dos usuários que o autenticado segue.
/// Requer JWT (Authorization header).
Future<Response> _getFollowingFeed(RequestContext context) async {
  // Auth manual (comunidade é sem middleware de auth)
  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'Authentication required.'},
    );
  }

  final token = authHeader.substring(7);
  final authService = AuthService();
  final payload = authService.verifyToken(token);
  if (payload == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'Invalid or expired token.'},
    );
  }

  final userId = payload['userId'] as String;

  try {
    final conn = context.read<Pool>();
    final params = context.request.uri.queryParameters;
    final page = int.tryParse(params['page'] ?? '') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 50);
    final offset = (page - 1) * limit;

    // Count total
    final countResult = await conn.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM decks d
        JOIN user_follows uf ON uf.following_id = d.user_id
        WHERE uf.follower_id = @userId
          AND d.is_public = true
      '''),
      parameters: {'userId': userId},
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Fetch decks from followed users
    final result = await conn.execute(
      Sql.named('''
        SELECT
          d.id,
          d.name,
          d.format,
          d.description,
          d.synergy_score,
          d.created_at,
          u.username as owner_username,
          u.id as owner_id,
          cmd.commander_name,
          cmd.commander_image_url,
          COALESCE(SUM(dc.quantity), 0)::int as card_count
        FROM decks d
        JOIN users u ON u.id = d.user_id
        JOIN user_follows uf ON uf.following_id = d.user_id
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
        LEFT JOIN deck_cards dc ON d.id = dc.deck_id
        WHERE uf.follower_id = @userId
          AND d.is_public = true
        GROUP BY d.id, u.username, u.id, cmd.commander_name, cmd.commander_image_url
        ORDER BY d.created_at DESC
        LIMIT @lim OFFSET @off
      '''),
      parameters: {
        'userId': userId,
        'lim': limit,
        'off': offset,
      },
    );

    final decks = result.map((row) {
      final m = row.toColumnMap();
      if (m['created_at'] is DateTime) {
        m['created_at'] = (m['created_at'] as DateTime).toIso8601String();
      }
      m['commander_image_url'] =
          _normalizeScryfallImageUrl(m['commander_image_url']?.toString());
      return m;
    }).toList();

    return Response.json(body: {
      'data': decks,
      'page': page,
      'limit': limit,
      'total': total,
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Internal server error', 'details': '$e'},
    );
  }
}
