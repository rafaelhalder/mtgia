import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../lib/database.dart';

/// Sincroniza cartas e legalidades do MTGJSON (AtomicCards.json) para o Postgres.
///
/// Uso:
/// - `dart run bin/sync_cards.dart`                 -> incremental (sets novos desde o último sync)
/// - `dart run bin/sync_cards.dart --full`          -> full sync via AtomicCards.json
/// - `dart run bin/sync_cards.dart --full --force`  -> força download + reprocessa tudo
/// - `dart run bin/sync_cards.dart --since-days=60` -> fallback de janela (quando não há checkpoint)
///
/// Requisitos:
/// - `server/.env` configurado (DB_* e ENVIRONMENT)
/// - Banco com schema aplicado (ou rodar `dart run bin/setup_database.dart`)
///
/// Observação:
/// - O script é idempotente (usa UPSERT por `cards.scryfall_id` e `(card_id, format)`).
/// - O arquivo `AtomicCards.json` fica no diretório `server/` (cache local).
const _metaUrl = 'https://mtgjson.com/api/v5/Meta.json';
const _setListUrl = 'https://mtgjson.com/api/v5/SetList.json';
const _atomicCardsUrl = 'https://mtgjson.com/api/v5/AtomicCards.json';
const _atomicCardsFileName = 'AtomicCards.json';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_cards.dart - Sincroniza cartas e legalidades (MTGJSON) para o Postgres

Uso:
  dart run bin/sync_cards.dart                Sync incremental (sets novos desde o último sync)
  dart run bin/sync_cards.dart --full         Full sync via AtomicCards.json
  dart run bin/sync_cards.dart --full --force Força download e reprocessa tudo

Opções:
  --full           Executa sincronização completa (AtomicCards.json)
  --force          Força re-download do AtomicCards.json (modo full) e ignora cache/versão
  --since-days=<N> Janela (dias) usada como fallback no incremental quando não existe checkpoint (default: 45)
  --help           Mostra esta ajuda
''');
    return;
  }

  final force = args.contains('--force') || args.contains('-f');
  final full = args.contains('--full');
  final sinceDays = _parseSinceDays(args) ?? 45;

  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final environment = (env['ENVIRONMENT'] ??
          Platform.environment['ENVIRONMENT'] ??
          'development')
      .toLowerCase();
  print(
      '🔄 Sync de cartas (ENVIRONMENT=$environment)${full ? ' [FULL]' : ' [INCREMENTAL]'}${force ? ' [FORÇADO]' : ''}');

  final db = Database();
  await db.connect();
  final pool = db.connection;

  final startedAt = DateTime.now();
  try {
    await _ensureSyncStateTable(pool);
    await _ensureCardsColorIdentity(pool);
    await _ensureSetsTable(pool);
    await _syncSetsFromSetList(pool);

    final meta = await _fetchMtgJsonMeta();
    final remoteVersion = (meta['version'] ?? '').toString().trim();
    final remoteDate = (meta['date'] ?? '').toString().trim();

    final lastVersion = await _getSyncState(pool, 'mtgjson_meta_version');
    final lastSyncAtStr = await _getSyncState(pool, 'cards_last_sync_at');
    final lastSyncAt =
        lastSyncAtStr != null ? DateTime.tryParse(lastSyncAtStr) : null;

    if (!force && lastVersion != null && lastVersion == remoteVersion) {
      print(
          '✅ MTGJSON já está atualizado (version=$remoteVersion, date=$remoteDate). Nada a fazer.');
      return;
    }

    print(
        '📦 MTGJSON remoto: version=$remoteVersion, date=$remoteDate (local=$lastVersion)');

    final beforeCards = await _count(pool, 'cards');
    final beforeLegalities = await _count(pool, 'card_legalities');

    int processedCards;
    int processedLegalities;

    final hasExistingBase = beforeCards > 0;
    final effectiveLastSyncAt = lastSyncAt ??
        (hasExistingBase && !full
            ? DateTime.now().subtract(Duration(days: sinceDays))
            : null);

    if (full || effectiveLastSyncAt == null) {
      final atomicFile = await _downloadAtomicCards(force: force);
      final decoded =
          jsonDecode(await atomicFile.readAsString()) as Map<String, dynamic>;
      final cardsMap = decoded['data'] as Map<String, dynamic>;

      processedCards = await pool.runTx((session) async {
        return _upsertCardsFromAtomic(session, cardsMap);
      });

      processedLegalities = await pool.runTx((session) async {
        return _upsertLegalitiesFromAtomic(session, cardsMap);
      });
    } else {
      final setCodes = await _getNewSetCodesSince(effectiveLastSyncAt);
      if (setCodes.isEmpty) {
        print(
            '✅ Nenhum set novo detectado desde ${effectiveLastSyncAt.toIso8601String()}. Atualizando apenas checkpoint de versão.');
        processedCards = 0;
        processedLegalities = 0;
      } else {
        print(
            '🆕 Sets novos desde ${effectiveLastSyncAt.toIso8601String()}: ${setCodes.join(', ')}');
        processedCards = 0;
        processedLegalities = 0;

        for (final code in setCodes) {
          final setData = await _fetchSetJson(code);
          final cards =
              (setData['cards'] as List?)?.cast<Map<String, dynamic>>() ??
                  const [];
          if (cards.isEmpty) continue;

          processedCards += await pool.runTx((session) async {
            return _upsertCardsFromSet(session, cards, code);
          });
          processedLegalities += await pool.runTx((session) async {
            return _upsertLegalitiesFromSet(session, cards);
          });
        }
      }
    }

    final afterCards = await _count(pool, 'cards');
    final afterLegalities = await _count(pool, 'card_legalities');

    await _setSyncState(pool, 'mtgjson_meta_version', remoteVersion);
    await _setSyncState(pool, 'mtgjson_meta_date', remoteDate);
    await _setSyncState(
        pool, 'cards_last_sync_at', DateTime.now().toIso8601String());

    await _logSync(
      pool,
      syncType: 'cards',
      status: 'success',
      recordsInserted: (afterCards - beforeCards).clamp(0, 1 << 31),
      recordsUpdated:
          (processedCards - (afterCards - beforeCards)).clamp(0, 1 << 31),
      recordsDeleted: 0,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      errorMessage: null,
    );

    await _logSync(
      pool,
      syncType: 'card_legalities',
      status: 'success',
      recordsInserted: (afterLegalities - beforeLegalities).clamp(0, 1 << 31),
      recordsUpdated:
          (processedLegalities - (afterLegalities - beforeLegalities))
              .clamp(0, 1 << 31),
      recordsDeleted: 0,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      errorMessage: null,
    );

    print('✅ Sync concluído.');
    print('  - Cards: $processedCards processadas (total $afterCards)');
    print(
        '  - Legalities: $processedLegalities processadas (total $afterLegalities)');
  } catch (e) {
    await _logSync(
      pool,
      syncType: 'cards',
      status: 'failed',
      recordsInserted: 0,
      recordsUpdated: 0,
      recordsDeleted: 0,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      errorMessage: e.toString(),
    );
    rethrow;
  } finally {
    await db.close();
  }
}

Future<void> _ensureCardsColorIdentity(Pool pool) async {
  // Idempotente: para bases antigas.
  await pool.execute(Sql.named(
      'ALTER TABLE cards ADD COLUMN IF NOT EXISTS color_identity TEXT[]'));
  await pool.execute(Sql.named(
      'CREATE INDEX IF NOT EXISTS idx_cards_color_identity ON cards USING GIN (color_identity)'));
}

int? _parseSinceDays(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--since-days=')) {
      final value = arg.split('=').last.trim();
      final parsed = int.tryParse(value);
      if (parsed == null || parsed <= 0) return null;
      return parsed;
    }
  }
  return null;
}

Future<Map<String, dynamic>> _fetchMtgJsonMeta() async {
  final res = await http.get(Uri.parse(_metaUrl));
  if (res.statusCode != 200) {
    throw Exception('Falha ao baixar Meta.json: ${res.statusCode}');
  }
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final data = decoded['data'];
  if (data is! Map<String, dynamic>) {
    throw Exception('Meta.json inesperado: campo data inválido');
  }
  return data;
}

Future<List<String>> _getNewSetCodesSince(DateTime since) async {
  final res = await http.get(Uri.parse(_setListUrl));
  if (res.statusCode != 200) {
    throw Exception('Falha ao baixar SetList.json: ${res.statusCode}');
  }
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final data = decoded['data'];
  if (data is! List) {
    throw Exception('SetList.json inesperado: campo data inválido');
  }

  // Pequena folga para não “perder” set por timezone/publicação.
  final cutoff = since.subtract(const Duration(days: 2));

  final codes = <String>[];
  for (final item in data) {
    if (item is! Map) continue;
    final code = item['code']?.toString();
    final releaseDateStr = item['releaseDate']?.toString();
    if (code == null ||
        code.isEmpty ||
        releaseDateStr == null ||
        releaseDateStr.isEmpty) continue;

    final releaseDate = DateTime.tryParse(releaseDateStr);
    if (releaseDate == null) continue;
    if (releaseDate.isAfter(cutoff)) {
      codes.add(code);
    }
  }

  codes.sort();
  return codes;
}

Future<Map<String, dynamic>> _fetchSetJson(String setCode) async {
  final url = 'https://mtgjson.com/api/v5/$setCode.json';
  print('⬇️  Baixando set $setCode...');
  final res = await http.get(Uri.parse(url));
  if (res.statusCode != 200) {
    throw Exception('Falha ao baixar set $setCode: ${res.statusCode}');
  }
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final data = decoded['data'];
  if (data is! Map<String, dynamic>) {
    throw Exception('Set $setCode inesperado: campo data inválido');
  }
  return data;
}

Future<File> _downloadAtomicCards({required bool force}) async {
  final file = File(_atomicCardsFileName);
  if (!force && await file.exists()) {
    print('📁 Usando cache local: $_atomicCardsFileName');
    return file;
  }

  print('⬇️  Baixando $_atomicCardsUrl ...');
  final res = await http.get(Uri.parse(_atomicCardsUrl));
  if (res.statusCode != 200) {
    throw Exception('Falha ao baixar AtomicCards.json: ${res.statusCode}');
  }
  await file.writeAsBytes(res.bodyBytes);
  print(
      '✅ Download concluído: $_atomicCardsFileName (${res.bodyBytes.length} bytes)');
  return file;
}

Future<void> _ensureSyncStateTable(Pool pool) async {
  await pool.execute(
    Sql.named('''
      CREATE TABLE IF NOT EXISTS sync_state (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    '''),
  );
}

Future<void> _ensureSetsTable(Pool pool) async {
  await pool.execute(
    Sql.named('''
      CREATE TABLE IF NOT EXISTS sets (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        release_date DATE,
        type TEXT,
        block TEXT,
        is_online_only BOOLEAN,
        is_foreign_only BOOLEAN,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    '''),
  );
}

Future<void> _syncSetsFromSetList(Pool pool) async {
  final res = await http.get(Uri.parse(_setListUrl));
  if (res.statusCode != 200) {
    throw Exception('Falha ao baixar SetList.json: ${res.statusCode}');
  }
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final data = decoded['data'];
  if (data is! List) {
    throw Exception('SetList.json inesperado: campo data inválido');
  }

  await pool.runTx((session) async {
    final stmt = await session.prepare('''
      INSERT INTO sets (
        code, name, release_date, type, block, is_online_only, is_foreign_only, updated_at
      ) VALUES (
        \$1, \$2, \$3, \$4, \$5, \$6, \$7, CURRENT_TIMESTAMP
      )
      ON CONFLICT (code) DO UPDATE SET
        name = EXCLUDED.name,
        release_date = EXCLUDED.release_date,
        type = EXCLUDED.type,
        block = EXCLUDED.block,
        is_online_only = EXCLUDED.is_online_only,
        is_foreign_only = EXCLUDED.is_foreign_only,
        updated_at = CURRENT_TIMESTAMP
    ''');

    try {
      for (final item in data) {
        if (item is! Map) continue;
        final code = item['code']?.toString().trim();
        final name = item['name']?.toString().trim();
        if (code == null || code.isEmpty || name == null || name.isEmpty)
          continue;

        final releaseDateStr = item['releaseDate']?.toString();
        final releaseDate =
            releaseDateStr != null ? DateTime.tryParse(releaseDateStr) : null;

        await stmt.run([
          code,
          name,
          releaseDate?.toIso8601String().split('T').first,
          item['type']?.toString(),
          item['block']?.toString(),
          item['isOnlineOnly'] as bool?,
          item['isForeignOnly'] as bool?,
        ]);
      }
    } finally {
      await stmt.dispose();
    }
  });
}

Future<String?> _getSyncState(Pool pool, String key) async {
  final result = await pool.execute(
    Sql.named('SELECT value FROM sync_state WHERE key = @key'),
    parameters: {'key': key},
  );
  if (result.isEmpty) return null;
  return result.first[0] as String?;
}

Future<void> _setSyncState(Pool pool, String key, String value) async {
  await pool.execute(
    Sql.named('''
      INSERT INTO sync_state (key, value)
      VALUES (@key, @value)
      ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value,
        updated_at = CURRENT_TIMESTAMP
    '''),
    parameters: {'key': key, 'value': value},
  );
}

Future<int> _count(Pool pool, String table) async {
  final res = await pool.execute(Sql.named('SELECT count(*)::int FROM $table'));
  return (res.first[0] as int?) ?? 0;
}

Future<void> _logSync(
  Pool pool, {
  required String syncType,
  required String status,
  required int recordsUpdated,
  required int recordsInserted,
  required int recordsDeleted,
  required DateTime startedAt,
  required DateTime finishedAt,
  required String? errorMessage,
}) async {
  try {
    await pool.execute(
      Sql.named('''
        INSERT INTO sync_log (
          sync_type, format, records_updated, records_inserted, records_deleted,
          status, error_message, started_at, finished_at
        ) VALUES (
          @syncType, NULL, @updated, @inserted, @deleted,
          @status, @error, @startedAt, @finishedAt
        )
      '''),
      parameters: {
        'syncType': syncType,
        'updated': recordsUpdated,
        'inserted': recordsInserted,
        'deleted': recordsDeleted,
        'status': status,
        'error': errorMessage,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
      },
    );
  } catch (_) {
    // Se a tabela sync_log não existir por algum motivo, não falhar o sync inteiro.
  }
}

Future<int> _upsertCardsFromAtomic(
    Session session, Map<String, dynamic> cardsMap) async {
  print('🃏 Upsert de cards...');

  final stmt = await session.prepare('''
    INSERT INTO cards (
      scryfall_id, name, mana_cost, type_line, oracle_text, colors, color_identity, image_url, set_code, rarity
    ) VALUES (
      \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10
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
  ''');

  var processed = 0;
  try {
    for (final entry in cardsMap.entries) {
      final cardName = entry.key;
      final cardList = entry.value as List;

      // AtomicCards pode ter várias entradas (prints). Pega a primeira com Oracle ID.
      Map<String, dynamic>? chosen;
      for (final cardData in cardList) {
        if (cardData is! Map<String, dynamic>) continue;
        final identifiers = cardData['identifiers'] as Map<String, dynamic>?;
        final oracleId = identifiers?['scryfallOracleId'] as String?;
        if (oracleId != null && oracleId.isNotEmpty) {
          chosen = cardData;
          break;
        }
      }

      if (chosen == null) continue;
      final identifiers = chosen['identifiers'] as Map<String, dynamic>?;
      final oracleId = identifiers?['scryfallOracleId'] as String?;
      if (oracleId == null || oracleId.isEmpty) continue;

      final name = (chosen['name'] ?? cardName).toString();
      final manaCost = chosen['manaCost']?.toString();
      final typeLine = chosen['type']?.toString();
      final oracleText = chosen['text']?.toString();
      final colors =
          (chosen['colors'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final colorIdentity = (chosen['colorIdentity'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];

      final printing =
          (chosen['printings'] as List?)?.cast<dynamic>().firstOrNull;
      final setCode = printing?.toString();
      final rarity = chosen['rarity']?.toString();

      // URL por nome exato com set específico para mostrar a arte correta da edição.
      final encodedName = Uri.encodeQueryComponent(name);
      final setParam = setCode != null && setCode.isNotEmpty ? '&set=$setCode' : '';
      final imageUrl =
          'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

      await stmt.run([
        oracleId,
        name,
        manaCost,
        typeLine,
        oracleText,
        colors,
        colorIdentity,
        imageUrl,
        setCode,
        rarity,
      ]);
      processed++;

      if (processed % 5000 == 0) {
        stdout.write('\r  ... $processed');
      }
    }
  } finally {
    await stmt.dispose();
  }

  stdout.writeln('');
  return processed;
}

Future<int> _upsertCardsFromSet(
    Session session, List<Map<String, dynamic>> cards, String setCode) async {
  print('🃏 Upsert de cards (set=$setCode)...');

  final stmt = await session.prepare('''
    INSERT INTO cards (
      scryfall_id, name, mana_cost, type_line, oracle_text, colors, color_identity, image_url, set_code, rarity
    ) VALUES (
      \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10
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
  ''');

  var processed = 0;
  try {
    for (final card in cards) {
      final identifiers = card['identifiers'] as Map<String, dynamic>?;
      final oracleId = identifiers?['scryfallOracleId']?.toString();
      if (oracleId == null || oracleId.isEmpty) continue;

      final name = card['name']?.toString();
      if (name == null || name.isEmpty) continue;

      final manaCost = card['manaCost']?.toString();
      final typeLine = card['type']?.toString();
      final oracleText = card['text']?.toString();
      final colors =
          (card['colors'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final colorIdentity =
          (card['colorIdentity'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final rarity = card['rarity']?.toString();

      final encodedName = Uri.encodeQueryComponent(name);
      final setParam = setCode.isNotEmpty ? '&set=$setCode' : '';
      final imageUrl =
          'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

      await stmt.run([
        oracleId,
        name,
        manaCost,
        typeLine,
        oracleText,
        colors,
        colorIdentity,
        imageUrl,
        setCode,
        rarity,
      ]);
      processed++;
    }
  } finally {
    await stmt.dispose();
  }

  return processed;
}

Future<int> _upsertLegalitiesFromAtomic(
    Session session, Map<String, dynamic> cardsMap) async {
  print('⚖️  Upsert de legalidades...');

  // 1) Carregar mapa oracleId -> internal card id
  final idResult = await session.execute(
    Sql.named('SELECT scryfall_id::text, id::text FROM cards'),
  );
  final cardIdMap = <String, String>{};
  for (final row in idResult) {
    final oracleId = row[0] as String;
    final internalId = row[1] as String;
    cardIdMap[oracleId] = internalId;
  }

  // 2) Montar batch SQL (bem mais rápido do que 1 insert por linha).
  const batchSize = 2500;
  final buffer = <String, String>{};
  var processed = 0;

  Future<void> flush() async {
    if (buffer.isEmpty) return;
    final valuesStr = buffer.values.join(',');
    await session.execute(
      Sql.named('''
        INSERT INTO card_legalities (card_id, format, status)
        VALUES $valuesStr
        ON CONFLICT (card_id, format) DO UPDATE SET
          status = EXCLUDED.status
      '''),
    );
    buffer.clear();
  }

  for (final cardPrintings in cardsMap.values) {
    final cardList = cardPrintings as List<dynamic>;
    if (cardList.isEmpty) continue;

    final first = cardList.first;
    if (first is! Map<String, dynamic>) continue;

    final identifiers = first['identifiers'] as Map<String, dynamic>?;
    final oracleId = identifiers?['scryfallOracleId'] as String?;
    final legalities = first['legalities'] as Map<String, dynamic>?;

    if (oracleId == null || legalities == null) continue;
    final internalId = cardIdMap[oracleId];
    if (internalId == null) continue;

    for (final entry in legalities.entries) {
      final format = entry.key.toString().replaceAll("'", "''");
      final status = entry.value.toString().toLowerCase().replaceAll("'", "''");
      buffer['$internalId|$format'] = "('$internalId', '$format', '$status')";
      processed++;

      if (buffer.length >= batchSize) {
        await flush();
        stdout.write('\r  ... $processed');
      }
    }
  }

  await flush();
  stdout.writeln('');
  return processed;
}

Future<int> _upsertLegalitiesFromSet(
    Session session, List<Map<String, dynamic>> cards) async {
  print('⚖️  Upsert de legalidades (set)...');

  final idResult = await session.execute(
    Sql.named('SELECT scryfall_id::text, id::text FROM cards'),
  );
  final cardIdMap = <String, String>{};
  for (final row in idResult) {
    cardIdMap[row[0] as String] = row[1] as String;
  }

  const batchSize = 2500;
  final buffer = <String, String>{};
  var processed = 0;

  Future<void> flush() async {
    if (buffer.isEmpty) return;
    final valuesStr = buffer.values.join(',');
    await session.execute(
      Sql.named('''
        INSERT INTO card_legalities (card_id, format, status)
        VALUES $valuesStr
        ON CONFLICT (card_id, format) DO UPDATE SET
          status = EXCLUDED.status
      '''),
    );
    buffer.clear();
  }

  for (final card in cards) {
    final identifiers = card['identifiers'] as Map<String, dynamic>?;
    final oracleId = identifiers?['scryfallOracleId']?.toString();
    if (oracleId == null || oracleId.isEmpty) continue;
    final internalId = cardIdMap[oracleId];
    if (internalId == null) continue;

    final legalities = card['legalities'] as Map<String, dynamic>?;
    if (legalities == null) continue;

    for (final entry in legalities.entries) {
      final format = entry.key.toString().replaceAll("'", "''");
      final status = entry.value.toString().toLowerCase().replaceAll("'", "''");
      buffer['$internalId|$format'] = "('$internalId', '$format', '$status')";
      processed++;
      if (buffer.length >= batchSize) {
        await flush();
      }
    }
  }

  await flush();
  return processed;
}

extension _FirstOrNullList<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
