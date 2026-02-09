import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

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

  return _listPublicDecks(context);
}

/// GET /community/decks?search=&format=&page=1&limit=20
/// Lista decks públicos para exploração da comunidade.
Future<Response> _listPublicDecks(RequestContext context) async {
  try {
    final conn = context.read<Pool>();
    final params = context.request.uri.queryParameters;

    final search = params['search']?.trim();
    final format = params['format']?.trim().toLowerCase();
    final page = int.tryParse(params['page'] ?? '') ?? 1;
    final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 50);
    final offset = (page - 1) * limit;

    // Build WHERE clauses
    final whereParts = <String>['d.is_public = true'];
    final sqlParams = <String, dynamic>{
      'lim': limit,
      'off': offset,
    };

    if (search != null && search.isNotEmpty) {
      whereParts.add(
          '(LOWER(d.name) LIKE @search OR LOWER(COALESCE(d.description,\'\')) LIKE @search)');
      sqlParams['search'] = '%${search.toLowerCase()}%';
    }
    if (format != null && format.isNotEmpty) {
      whereParts.add('LOWER(d.format) = @format');
      sqlParams['format'] = format;
    }

    final whereClause = whereParts.join(' AND ');

    // Count total
    final countResult = await conn.execute(
      Sql.named('SELECT COUNT(*)::int FROM decks d WHERE $whereClause'),
      parameters: sqlParams,
    );
    final total = (countResult.first[0] as int?) ?? 0;

    // Fetch decks
    final sql = '''
      SELECT
        d.id,
        d.name,
        d.format,
        d.description,
        d.synergy_score,
        d.created_at,
        u.username as owner_username,
        cmd.commander_name,
        cmd.commander_image_url,
        COALESCE(SUM(dc.quantity), 0)::int as card_count
      FROM decks d
      JOIN users u ON u.id = d.user_id
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
      WHERE $whereClause
      GROUP BY d.id, u.username, cmd.commander_name, cmd.commander_image_url
      ORDER BY d.created_at DESC
      LIMIT @lim OFFSET @off
    ''';

    final result = await conn.execute(
      Sql.named(sql),
      parameters: sqlParams,
    );

    final decks = result.map((row) {
      final map = row.toColumnMap();
      if (map['created_at'] is DateTime) {
        map['created_at'] = (map['created_at'] as DateTime).toIso8601String();
      }
      map['commander_image_url'] =
          _normalizeScryfallImageUrl(map['commander_image_url']?.toString());
      return map;
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
      body: {'error': 'Failed to list public decks: $e'},
    );
  }
}
