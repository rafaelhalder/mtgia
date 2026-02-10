import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
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
  final safeLimit = limit.clamp(1, 200);
  final syncFromScryfall = params['sync'] == 'true';

  if (name == null || name.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'name é obrigatório'},
    );
  }

  // Busca local
  var data = await _queryPrintings(pool, name, safeLimit, hasSets);

  // Se sync=true e encontrou poucas edições, busca do Scryfall
  if (syncFromScryfall && data.length <= 1) {
    try {
      final imported = await _syncPrintingsFromScryfall(pool, name);
      if (imported > 0) {
        // Re-query com as edições importadas
        data = await _queryPrintings(pool, name, safeLimit, hasSets);
      }
    } catch (e) {
      stderr.writeln('[printings/sync] Erro: $e');
    }
  }

  return Response.json(
    body: {
      'name': name,
      'total_returned': data.length,
      'data': data,
    },
  );
}

/// Faz a query de printings no banco local
Future<List<Map<String, dynamic>>> _queryPrintings(
  Pool pool,
  String name,
  int limit,
  bool hasSets,
) async {

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
          c.price_updated_at,
          c.collector_number,
          c.foil
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
          c.price_updated_at,
          c.collector_number,
          c.foil
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
    return <String, dynamic>{
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
      'collector_number': m['collector_number'],
      'foil': m['foil'],
    };
  }).toList();

  return data;
}

/// Busca todas as printings de uma carta no Scryfall e importa no banco
Future<int> _syncPrintingsFromScryfall(Pool pool, String name) async {
  // 1. Buscar a carta principal no Scryfall
  final encoded = Uri.encodeQueryComponent(name.trim());
  final uri = Uri.parse(
    'https://api.scryfall.com/cards/named?fuzzy=$encoded',
  );

  final response = await http.get(uri, headers: {
    'Accept': 'application/json',
    'User-Agent': 'MTGDeckBuilder/1.0',
  });

  if (response.statusCode != 200) return 0;

  final card = jsonDecode(response.body) as Map<String, dynamic>;
  final printsUri = card['prints_search_uri'] as String?;
  if (printsUri == null) return 0;

  // 2. Buscar todas as printings
  final printsResponse = await http.get(
    Uri.parse(printsUri),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'MTGDeckBuilder/1.0',
    },
  );

  if (printsResponse.statusCode != 200) return 0;

  final body = jsonDecode(printsResponse.body) as Map<String, dynamic>;
  final printings = (body['data'] as List?)?.whereType<Map<String, dynamic>>() ?? [];

  // Filtrar: só paper, sem art_series, sem tokens
  final filtered = printings.where((p) {
    final games = p['games'] as List?;
    final isPaper = games?.contains('paper') ?? false;
    final layout = p['layout']?.toString() ?? '';
    return isPaper && layout != 'art_series' && layout != 'token';
  }).take(30).toList();

  var imported = 0;

  for (final p in filtered) {
    final oracleId = p['oracle_id'] as String?;
    if (oracleId == null || oracleId.isEmpty) continue;

    final cardName = p['name']?.toString() ?? '';
    final manaCost = p['mana_cost']?.toString();
    final typeLine = p['type_line']?.toString();
    final oracleText = p['oracle_text']?.toString();
    final setCode = p['set']?.toString();
    final rarity = p['rarity']?.toString();
    final cmc = p['cmc']?.toString();

    final colors = <String>[];
    if (p['colors'] is List) {
      for (final c in p['colors'] as List) {
        colors.add(c.toString());
      }
    }

    final colorIdentity = <String>[];
    if (p['color_identity'] is List) {
      for (final c in p['color_identity'] as List) {
        colorIdentity.add(c.toString());
      }
    }

    final encodedCardName = Uri.encodeQueryComponent(cardName);
    final setParam = setCode != null && setCode.isNotEmpty ? '&set=$setCode' : '';
    final imageUrl =
        'https://api.scryfall.com/cards/named?exact=$encodedCardName$setParam&format=image';

    try {
      await pool.execute(
        Sql.named('''
          INSERT INTO cards (scryfall_id, name, mana_cost, type_line, oracle_text,
                             colors, color_identity, image_url, set_code, rarity, cmc)
          VALUES (
            @oracle_id::uuid, @name, @mana_cost, @type_line, @oracle_text,
            @colors::text[], @color_identity::text[], @image_url, @set_code, @rarity,
            @cmc::decimal
          )
          ON CONFLICT (scryfall_id) DO NOTHING
        '''),
        parameters: {
          'oracle_id': oracleId,
          'name': cardName,
          'mana_cost': manaCost,
          'type_line': typeLine,
          'oracle_text': oracleText,
          'colors': colors,
          'color_identity': colorIdentity,
          'image_url': imageUrl,
          'set_code': setCode,
          'rarity': rarity,
          'cmc': cmc != null ? double.tryParse(cmc) ?? 0.0 : 0.0,
        },
      );
      imported++;
    } catch (e) {
      stderr.writeln('[printings/sync] Insert error ($cardName/$setCode): $e');
    }
  }

  // Garantir que os sets existam
  for (final p in filtered) {
    final setCode = p['set']?.toString();
    final setName = p['set_name']?.toString();
    final releasedAt = p['released_at']?.toString();
    if (setCode == null || setCode.isEmpty) continue;

    try {
      await pool.execute(
        Sql.named('''
          INSERT INTO sets (code, name, release_date)
          VALUES (@code, @name, @release_date::date)
          ON CONFLICT (code) DO NOTHING
        '''),
        parameters: {
          'code': setCode,
          'name': setName ?? setCode.toUpperCase(),
          'release_date': releasedAt,
        },
      );
    } catch (_) {
      // Ignore set insertion errors
    }
  }

  return imported;
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
