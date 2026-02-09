import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// POST /cards/resolve
///
/// Busca uma carta pelo nome. Se não existir no banco local, consulta a
/// Scryfall API (fuzzy search), insere a carta + legalities no banco e
/// retorna o resultado. Isso torna o sistema "self-healing" — qualquer
/// carta reconhecida pelo OCR que ainda não esteja na DB é importada
/// automaticamente na hora.
///
/// Body: { "name": "Lightning Bolt" }
/// Response 200: { "source": "local"|"scryfall", "data": [...] }
/// Response 404: { "error": "..." }
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final pool = context.read<Pool>();

  // Parse body
  final bodyStr = await context.request.body();
  if (bodyStr.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Body vazio. Envie {"name": "Card Name"}'},
    );
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(bodyStr) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'JSON inválido'},
    );
  }

  final name = (body['name'] as String?)?.trim();
  if (name == null || name.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Campo "name" é obrigatório'},
    );
  }

  try {
    // ─── 1) Busca local (nome exato, case-insensitive) ───
    final localExact = await _searchLocal(pool, name, exact: true);
    if (localExact.isNotEmpty) {
      return Response.json(body: {
        'source': 'local',
        'name': localExact.first['name'],
        'total_returned': localExact.length,
        'data': localExact,
      });
    }

    // ─── 2) Busca local (ILIKE fuzzy) ───
    final localFuzzy = await _searchLocal(pool, name, exact: false);
    if (localFuzzy.isNotEmpty) {
      return Response.json(body: {
        'source': 'local',
        'name': localFuzzy.first['name'],
        'total_returned': localFuzzy.length,
        'data': localFuzzy,
      });
    }

    // ─── 3) Fallback: Scryfall fuzzy search ───
    final scryfallCard = await _fetchFromScryfall(name);
    if (scryfallCard == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {
          'error': 'Carta "$name" não encontrada nem localmente nem no Scryfall',
        },
      );
    }

    // ─── 4) Insere a carta no banco ───
    final insertedCards = await _insertScryfallCard(pool, scryfallCard);

    // ─── 5) Insere legalities ───
    await _insertLegalities(pool, insertedCards, scryfallCard);

    // ─── 6) Retorna as cartas inseridas ───
    // Refaz a busca local para retornar com formato normalizado
    final freshData = await _searchLocal(
      pool,
      scryfallCard['name'] as String,
      exact: true,
    );

    return Response.json(body: {
      'source': 'scryfall',
      'name': scryfallCard['name'],
      'total_returned': freshData.length,
      'data': freshData,
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro ao resolver carta', 'details': e.toString()},
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Busca local no PostgreSQL
// ───────────────────────────────────────────────────────────────────────────────

Future<List<Map<String, dynamic>>> _searchLocal(
  Pool pool,
  String name, {
  required bool exact,
}) async {
  final hasSets = await _hasTable(pool, 'sets');

  final condition =
      exact ? 'LOWER(c.name) = LOWER(@name)' : 'c.name ILIKE @name';
  final paramValue = exact ? name : '%$name%';

  final sql = hasSets
      ? '''
    SELECT
      c.id::text, c.scryfall_id::text, c.name, c.mana_cost, c.type_line,
      c.oracle_text, c.colors, c.color_identity, c.image_url, c.set_code,
      s.name AS set_name, s.release_date AS set_release_date,
      c.rarity, c.price, c.price_updated_at
    FROM cards c
    LEFT JOIN sets s ON s.code = c.set_code
    WHERE $condition
    ORDER BY s.release_date DESC NULLS LAST, c.set_code ASC
    LIMIT 50
  '''
      : '''
    SELECT
      c.id::text, c.scryfall_id::text, c.name, c.mana_cost, c.type_line,
      c.oracle_text, c.colors, c.color_identity, c.image_url, c.set_code,
      c.rarity, c.price, c.price_updated_at
    FROM cards c
    WHERE $condition
    ORDER BY c.set_code ASC
    LIMIT 50
  ''';

  final result = await pool.execute(
    Sql.named(sql),
    parameters: {'name': paramValue},
  );

  return result.map((row) {
    final m = row.toColumnMap();
    return {
      'id': m['id'],
      'scryfall_id': m['scryfall_id'],
      'name': m['name'],
      'mana_cost': m['mana_cost'],
      'type_line': m['type_line'],
      'oracle_text': m['oracle_text'],
      'colors': m['colors'],
      'color_identity': m['color_identity'],
      'image_url': _normalizeScryfallImageUrl(m['image_url']?.toString()),
      'set_code': m['set_code'],
      if (m.containsKey('set_name')) 'set_name': m['set_name'],
      if (m.containsKey('set_release_date'))
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
}

// ───────────────────────────────────────────────────────────────────────────────
// Scryfall API
// ───────────────────────────────────────────────────────────────────────────────

/// Busca a carta na Scryfall usando fuzzy search.
/// Retorna o JSON completo da Scryfall ou null se não encontrou.
Future<Map<String, dynamic>?> _fetchFromScryfall(String name) async {
  // Scryfall rate limit: max 10 req/s — uma chamada por resolve é ok.
  final encoded = Uri.encodeQueryComponent(name);
  final url = 'https://api.scryfall.com/cards/named?fuzzy=$encoded';

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json', 'User-Agent': 'MTGDeckBuilder/1.0'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    // Se fuzzy não achou com 404, tenta search
    if (response.statusCode == 404) {
      return _fetchFromScryfallSearch(name);
    }

    return null;
  } catch (_) {
    return null;
  }
}

/// Fallback: busca textual na Scryfall (para nomes parciais/com erro)
Future<Map<String, dynamic>?> _fetchFromScryfallSearch(String name) async {
  final encoded = Uri.encodeQueryComponent(name);
  final url = 'https://api.scryfall.com/cards/search?q=$encoded&order=name&unique=cards';

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json', 'User-Agent': 'MTGDeckBuilder/1.0'},
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List?;
    if (data == null || data.isEmpty) return null;

    // Retorna o primeiro resultado (mais relevante)
    return data.first as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Inserção no banco
// ───────────────────────────────────────────────────────────────────────────────

/// Insere a carta da Scryfall no banco local. Se a carta já existir
/// (por oracle_id), faz um UPDATE nos campos para manter dados frescos.
///
/// A Scryfall retorna UMA printing específica. Também busca todas as
/// printings da mesma carta (via prints_search_uri) para importar todas.
Future<List<Map<String, dynamic>>> _insertScryfallCard(
  Pool pool,
  Map<String, dynamic> scryfallCard,
) async {
  final oracleId = scryfallCard['oracle_id'] as String?;
  if (oracleId == null || oracleId.isEmpty) return [];

  // Buscar todas as printings desta carta
  final allPrintings = await _fetchAllPrintings(scryfallCard);

  final inserted = <Map<String, dynamic>>[];

  for (final card in allPrintings) {
    final cardOracleId = card['oracle_id'] as String?;
    if (cardOracleId == null || cardOracleId.isEmpty) continue;

    final cardName = card['name']?.toString() ?? '';
    final manaCost = card['mana_cost']?.toString();
    final typeLine = card['type_line']?.toString();
    final oracleText = card['oracle_text']?.toString();
    final setCode = card['set']?.toString();
    final rarity = card['rarity']?.toString();

    // Colors
    final colors = <String>[];
    if (card['colors'] is List) {
      for (final c in card['colors'] as List) {
        colors.add(c.toString());
      }
    }

    // Color identity
    final colorIdentity = <String>[];
    if (card['color_identity'] is List) {
      for (final c in card['color_identity'] as List) {
        colorIdentity.add(c.toString());
      }
    }

    // Image URL: preferir Scryfall redirect
    final encodedName = Uri.encodeQueryComponent(cardName);
    final setParam =
        setCode != null && setCode.isNotEmpty ? '&set=$setCode' : '';
    final imageUrl =
        'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

    // CMC
    final cmc = card['cmc']?.toString();

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
          ON CONFLICT (scryfall_id) DO UPDATE SET
            name = EXCLUDED.name,
            mana_cost = EXCLUDED.mana_cost,
            type_line = EXCLUDED.type_line,
            oracle_text = EXCLUDED.oracle_text,
            colors = EXCLUDED.colors,
            color_identity = EXCLUDED.color_identity,
            image_url = EXCLUDED.image_url,
            set_code = EXCLUDED.set_code,
            rarity = EXCLUDED.rarity
        '''),
        parameters: {
          'oracle_id': cardOracleId,
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
      inserted.add(card);
    } catch (e) {
      // Se INSERT falhou (ex: constraint violation), ignora e continua
      // Isso pode acontecer se dois resolves concorrentes tentam a mesma carta
      stderr.writeln('[resolve] Erro ao inserir ${cardName} ($setCode): $e');
    }
  }

  // Também insere/atualiza o set se não existir
  await _ensureSet(pool, scryfallCard);

  return inserted;
}

/// Busca todas as printings de uma carta via Scryfall (prints_search_uri).
/// Retorna no máximo 20 printings para não sobrecarregar.
Future<List<Map<String, dynamic>>> _fetchAllPrintings(
  Map<String, dynamic> scryfallCard,
) async {
  final printsUri = scryfallCard['prints_search_uri'] as String?;
  if (printsUri == null) return [scryfallCard];

  try {
    final response = await http.get(
      Uri.parse(printsUri),
      headers: {'Accept': 'application/json', 'User-Agent': 'MTGDeckBuilder/1.0'},
    );

    if (response.statusCode != 200) return [scryfallCard];

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List?;
    if (data == null || data.isEmpty) return [scryfallCard];

    // Filtra: apenas paper, não digital-only, não art-series
    final filtered = data.whereType<Map<String, dynamic>>().where((card) {
      final games = card['games'] as List?;
      final isPaper = games?.contains('paper') ?? false;
      final layout = card['layout']?.toString() ?? '';
      final isArtSeries = layout == 'art_series';
      final isToken = layout == 'token';
      return isPaper && !isArtSeries && !isToken;
    }).take(30).toList();

    return filtered.isEmpty ? [scryfallCard] : filtered;
  } catch (_) {
    return [scryfallCard];
  }
}

/// Insere as legalities da carta Scryfall
Future<void> _insertLegalities(
  Pool pool,
  List<Map<String, dynamic>> insertedCards,
  Map<String, dynamic> scryfallCard,
) async {
  final legalities = scryfallCard['legalities'] as Map<String, dynamic>?;
  if (legalities == null || legalities.isEmpty) return;

  // Pega o oracle_id para buscar o card_id no banco
  final oracleId = scryfallCard['oracle_id'] as String?;
  if (oracleId == null) return;

  // Busca o card_id principal (primeiro do oracle_id)
  final cardResult = await pool.execute(
    Sql.named('SELECT id::text FROM cards WHERE scryfall_id = @oid::uuid LIMIT 1'),
    parameters: {'oid': oracleId},
  );
  if (cardResult.isEmpty) return;

  final cardId = cardResult.first[0] as String;

  for (final entry in legalities.entries) {
    final format = entry.key;
    final status = entry.value?.toString() ?? 'not_legal';

    // Só insere se for legal, banned ou restricted (ignora not_legal)
    if (status == 'not_legal') continue;

    try {
      await pool.execute(
        Sql.named('''
          INSERT INTO card_legalities (card_id, format, status)
          VALUES (@card_id::uuid, @format, @status)
          ON CONFLICT (card_id, format) DO UPDATE SET status = EXCLUDED.status
        '''),
        parameters: {
          'card_id': cardId,
          'format': format,
          'status': status,
        },
      );
    } catch (_) {
      // Ignora erros em legalities individuais
    }
  }
}

/// Garante que o set da carta existe na tabela sets
Future<void> _ensureSet(Pool pool, Map<String, dynamic> scryfallCard) async {
  final setCode = scryfallCard['set']?.toString();
  final setName = scryfallCard['set_name']?.toString();
  if (setCode == null || setCode.isEmpty) return;

  final hasSets = await _hasTable(pool, 'sets');
  if (!hasSets) return;

  try {
    final releaseDate = scryfallCard['released_at']?.toString();
    final setType = scryfallCard['set_type']?.toString();

    await pool.execute(
      Sql.named('''
        INSERT INTO sets (code, name, release_date, type)
        VALUES (@code, @name, @release_date::date, @type)
        ON CONFLICT (code) DO UPDATE SET
          name = COALESCE(EXCLUDED.name, sets.name),
          release_date = COALESCE(EXCLUDED.release_date, sets.release_date),
          type = COALESCE(EXCLUDED.type, sets.type),
          updated_at = CURRENT_TIMESTAMP
      '''),
      parameters: {
        'code': setCode,
        'name': setName ?? setCode,
        'release_date': releaseDate,
        'type': setType,
      },
    );
  } catch (_) {
    // Ignora erro — set pode já existir ou tabela pode não ter colunas esperadas
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// Helpers
// ───────────────────────────────────────────────────────────────────────────────

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
