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
    return trimmed.replaceAllMapped(
      RegExp(r'([?&]set=)([^&]+)'),
      (m) => '${m.group(1)}${m.group(2)!.toLowerCase()}',
    );
  }
}

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final pool = context.read<Pool>();
  final hasSets = await _hasTable(pool, 'sets');

  final params = context.request.uri.queryParameters;
  final name = params['name']?.trim();
  final limit = int.tryParse(params['limit'] ?? '50') ?? 50;

  if (name == null || name.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'name é obrigatório'},
    );
  }

  final sql = hasSets
      ? '''
        SELECT
          c.id::text,
          c.scryfall_id::text,
          c.name,
          c.mana_cost,
          c.type_line,
          c.oracle_text,
          c.colors,
          c.color_identity,
          c.image_url,
          c.set_code,
          s.name AS set_name,
          s.release_date AS set_release_date,
          c.rarity,
          c.price,
          c.price_updated_at
        FROM cards c
        LEFT JOIN sets s ON s.code = c.set_code
        WHERE LOWER(c.name) = LOWER(@name)
        ORDER BY s.release_date DESC NULLS LAST, c.set_code ASC
        LIMIT @limit
      '''
      : '''
        SELECT
          c.id::text,
          c.scryfall_id::text,
          c.name,
          c.mana_cost,
          c.type_line,
          c.oracle_text,
          c.colors,
          c.color_identity,
          c.image_url,
          c.set_code,
          c.rarity,
          c.price,
          c.price_updated_at
        FROM cards c
        WHERE LOWER(c.name) = LOWER(@name)
        ORDER BY c.set_code ASC
        LIMIT @limit
      ''';

  final result = await pool.execute(
    Sql.named(sql),
    parameters: {'name': name, 'limit': limit},
  );

  final data = result.map((row) {
    final m = row.toColumnMap();
    final imageUrl = _normalizeScryfallImageUrl(m['image_url']?.toString());
    return {
      'id': m['id'],
      'scryfall_id': m['scryfall_id'],
      'name': m['name'],
      'mana_cost': m['mana_cost'],
      'type_line': m['type_line'],
      'oracle_text': m['oracle_text'],
      'colors': m['colors'],
      'color_identity': m['color_identity'],
      'image_url': imageUrl,
      'set_code': m['set_code'],
      if (hasSets) 'set_name': m['set_name'],
      if (hasSets)
        'set_release_date': (m['set_release_date'] as DateTime?)
            ?.toIso8601String()
            .split('T')
            .first,
      'rarity': m['rarity'],
      'price': m['price'],
      'price_updated_at':
          (m['price_updated_at'] as DateTime?)?.toIso8601String(),
    };
  }).toList();

  return Response.json(
    body: {
      'name': name,
      'total_returned': data.length,
      'data': data,
    },
  );
}

Future<bool> _hasTable(Pool pool, String tableName) async {
  try {
    final result = await pool.execute(
      Sql.named('SELECT to_regclass(@name)::text'),
      parameters: {'name': 'public.$tableName'},
    );
    final value = result.isNotEmpty ? result.first[0] : null;
    return value != null;
  } catch (_) {
    return false;
  }
}
