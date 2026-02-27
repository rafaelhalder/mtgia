import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../lib/database.dart';

/// Sincroniza cartas e legalidades do MTGJSON para o Postgres.
///
/// Uso:
/// - `dart run bin/sync_cards.dart`                 -> incremental (sets novos)
/// - `dart run bin/sync_cards.dart --full`          -> full sync (AtomicCards.json)
/// - `dart run bin/sync_cards.dart --full --force`  -> força re-download
/// - `dart run bin/sync_cards.dart --since-days=60` -> fallback de janela
///
/// Otimizações vs versão anterior:
/// - SetList.json baixado 1x e reutilizado (antes: 2x)
/// - Legalities com prepared statement seguro (antes: string interpolation)
/// - Incremental: carrega APENAS card IDs do set (antes: todos 33k+)
/// - Progresso com timing detalhado
const _metaUrl = 'https://mtgjson.com/api/v5/Meta.json';
const _setListUrl = 'https://mtgjson.com/api/v5/SetList.json';
const _atomicCardsUrl = 'https://mtgjson.com/api/v5/AtomicCards.json';
const _atomicCardsFileName = 'AtomicCards.json';

/// Tamanho do batch para envio paralelo ao Postgres.
/// 500 = bom equilíbrio entre throughput e uso de memória.
const _batchSize = 500;

/// Concorrência maxima por batch para evitar pico de queries simultaneas.
const _dbBatchConcurrency = 24;

/// Timeout e tentativas para downloads HTTP externos.
const _httpTimeout = Duration(seconds: 45);
const _httpMaxRetries = 3;

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_cards.dart - Sincroniza cartas e legalidades (MTGJSON) para o Postgres

Uso:
  dart run bin/sync_cards.dart                Sync incremental (sets novos desde ultimo sync)
  dart run bin/sync_cards.dart --full         Full sync via AtomicCards.json
  dart run bin/sync_cards.dart --full --force Forca download e reprocessa tudo

Opcoes:
  --full           Executa sincronizacao completa (AtomicCards.json)
  --force          Forca re-download do AtomicCards.json
  --since-days=<N> Janela (dias) para fallback quando nao existe checkpoint (default: 45)
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

    // Baixa SetList.json UMA VEZ e reutiliza
    final setListData = await _fetchSetListData();
    await _syncSetsFromData(pool, setListData);

    final meta = await _fetchMtgJsonMeta();
    final remoteVersion = (meta['version'] ?? '').toString().trim();
    final remoteDate = (meta['date'] ?? '').toString().trim();

    final lastVersion = await _getSyncState(pool, 'mtgjson_meta_version');
    final lastSyncAtStr = await _getSyncState(pool, 'cards_last_sync_at');
    final lastSyncAt =
        lastSyncAtStr != null ? DateTime.tryParse(lastSyncAtStr) : null;

    if (!force && lastVersion != null && lastVersion == remoteVersion) {
      print(
          '✅ MTGJSON ja esta atualizado (version=$remoteVersion). Nada a fazer.');
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
      // FULL SYNC
      final atomicFile = await _downloadAtomicCards(force: force);
      final sw = Stopwatch()..start();

      final decoded =
          jsonDecode(await atomicFile.readAsString()) as Map<String, dynamic>;
      final cardsMap = decoded['data'] as Map<String, dynamic>;
      print(
          '📂 JSON parseado em ${sw.elapsedMilliseconds}ms (${cardsMap.length} entradas)');

      sw.reset();
      processedCards = await pool.runTx((session) async {
        return _upsertCardsFromAtomic(session, cardsMap);
      });
      print('🃏 Cards concluido em ${sw.elapsedMilliseconds}ms');

      sw.reset();
      processedLegalities = await pool.runTx((session) async {
        return _upsertLegalitiesFromAtomic(session, cardsMap);
      });
      print('⚖️  Legalities concluido em ${sw.elapsedMilliseconds}ms');
    } else {
      // INCREMENTAL SYNC
      final setCodes =
          _getNewSetCodesSinceFromData(setListData, effectiveLastSyncAt);
      if (setCodes.isEmpty) {
        print(
            '✅ Nenhum set novo desde ${effectiveLastSyncAt.toIso8601String()}.');
        processedCards = 0;
        processedLegalities = 0;
      } else {
        print('🆕 Sets novos (${setCodes.length}): ${setCodes.join(', ')}');
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

    await _logSync(pool,
        syncType: 'cards',
        status: 'success',
        recordsInserted: (afterCards - beforeCards).clamp(0, 1 << 31),
        recordsUpdated:
            (processedCards - (afterCards - beforeCards)).clamp(0, 1 << 31),
        recordsDeleted: 0,
        startedAt: startedAt,
        finishedAt: DateTime.now());
    await _logSync(pool,
        syncType: 'card_legalities',
        status: 'success',
        recordsInserted:
            (afterLegalities - beforeLegalities).clamp(0, 1 << 31),
        recordsUpdated:
            (processedLegalities - (afterLegalities - beforeLegalities))
                .clamp(0, 1 << 31),
        recordsDeleted: 0,
        startedAt: startedAt,
        finishedAt: DateTime.now());

    final elapsed = DateTime.now().difference(startedAt);
    print('✅ Sync concluido em ${elapsed.inSeconds}s.');
    print('  - Cards: $processedCards processadas (total $afterCards)');
    print(
        '  - Legalities: $processedLegalities processadas (total $afterLegalities)');
  } catch (e) {
    await _logSync(pool,
        syncType: 'cards',
        status: 'failed',
        recordsInserted: 0,
        recordsUpdated: 0,
        recordsDeleted: 0,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        errorMessage: e.toString());
    rethrow;
  } finally {
    await db.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INFRAESTRUTURA
// ═══════════════════════════════════════════════════════════════════════

Future<void> _ensureSyncStateTable(Pool pool) async {
  await pool.execute(Sql.named('''
    CREATE TABLE IF NOT EXISTS sync_state (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    )
  '''));
}

Future<void> _ensureCardsColorIdentity(Pool pool) async {
  await pool.execute(Sql.named(
      'ALTER TABLE cards ADD COLUMN IF NOT EXISTS color_identity TEXT[]'));
  await pool.execute(Sql.named(
      'CREATE INDEX IF NOT EXISTS idx_cards_color_identity ON cards USING GIN (color_identity)'));
}

Future<void> _ensureSetsTable(Pool pool) async {
  await pool.execute(Sql.named('''
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
  '''));
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
  await pool.execute(Sql.named('''
    INSERT INTO sync_state (key, value) VALUES (@key, @value)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP
  '''), parameters: {'key': key, 'value': value});
}

Future<int> _count(Pool pool, String table) async {
  final res = await pool.execute(Sql.named('SELECT count(*)::int FROM $table'));
  return (res.first[0] as int?) ?? 0;
}

Future<http.Response> _httpGetWithRetry(
  Uri uri, {
  required String label,
}) async {
  Object? lastError;

  for (var attempt = 1; attempt <= _httpMaxRetries; attempt++) {
    try {
      final response = await http.get(uri).timeout(_httpTimeout);
      if (response.statusCode == 200) {
        return response;
      }

      final retryable = response.statusCode == 429 || response.statusCode >= 500;
      final message =
          'Falha ao baixar $label: status=${response.statusCode} (tentativa $attempt/$_httpMaxRetries)';

      if (!retryable || attempt == _httpMaxRetries) {
        throw Exception(message);
      }

      print('⚠️  $message; tentando novamente...');
      await Future.delayed(Duration(seconds: attempt * 2));
    } on TimeoutException catch (e) {
      lastError = e;
      if (attempt == _httpMaxRetries) break;
      print(
          '⚠️  Timeout em $label (tentativa $attempt/$_httpMaxRetries); tentando novamente...');
      await Future.delayed(Duration(seconds: attempt * 2));
    } on SocketException catch (e) {
      lastError = e;
      if (attempt == _httpMaxRetries) break;
      print(
          '⚠️  Erro de rede em $label (tentativa $attempt/$_httpMaxRetries); tentando novamente...');
      await Future.delayed(Duration(seconds: attempt * 2));
    }
  }

  throw Exception('Falha ao baixar $label apos $_httpMaxRetries tentativas: $lastError');
}

Future<void> _runWithConcurrency<T>(
  List<T> items,
  Future<void> Function(T item) task, {
  int concurrency = _dbBatchConcurrency,
}) async {
  if (items.isEmpty) return;

  var nextIndex = 0;
  Future<void> worker() async {
    while (true) {
      if (nextIndex >= items.length) return;
      final currentIndex = nextIndex;
      nextIndex++;
      await task(items[currentIndex]);
    }
  }

  final workers = List.generate(
    concurrency.clamp(1, items.length),
    (_) => worker(),
  );
  await Future.wait(workers);
}

Future<void> _logSync(Pool pool, {
  required String syncType,
  required String status,
  required int recordsInserted,
  required int recordsUpdated,
  required int recordsDeleted,
  required DateTime startedAt,
  required DateTime finishedAt,
  String? errorMessage,
}) async {
  try {
    await pool.execute(Sql.named('''
      INSERT INTO sync_log (
        sync_type, format, records_updated, records_inserted, records_deleted,
        status, error_message, started_at, finished_at
      ) VALUES (
        @syncType, NULL, @updated, @inserted, @deleted,
        @status, @error, @startedAt, @finishedAt
      )
    '''), parameters: {
      'syncType': syncType,
      'updated': recordsUpdated,
      'inserted': recordsInserted,
      'deleted': recordsDeleted,
      'status': status,
      'error': errorMessage,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
    });
  } catch (_) {}
}

int? _parseSinceDays(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--since-days=')) {
      final parsed = int.tryParse(arg.split('=').last.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// DOWNLOAD / FETCH
// ═══════════════════════════════════════════════════════════════════════

Future<Map<String, dynamic>> _fetchMtgJsonMeta() async {
  final res = await _httpGetWithRetry(
    Uri.parse(_metaUrl),
    label: 'Meta.json',
  );
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  return decoded['data'] as Map<String, dynamic>;
}

/// Baixa SetList.json UMA VEZ e retorna a lista.
Future<List<dynamic>> _fetchSetListData() async {
  print('⬇️  Baixando SetList.json...');
  final res = await _httpGetWithRetry(
    Uri.parse(_setListUrl),
    label: 'SetList.json',
  );
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  return decoded['data'] as List<dynamic>;
}

/// Filtra sets novos a partir dos dados ja em memoria (sem novo download).
List<String> _getNewSetCodesSinceFromData(
    List<dynamic> setListData, DateTime since) {
  final cutoff = since.subtract(const Duration(days: 2));
  final codes = <String>[];
  for (final item in setListData) {
    if (item is! Map) continue;
    final code = item['code']?.toString();
    final releaseDateStr = item['releaseDate']?.toString();
    if (code == null || releaseDateStr == null) continue;
    final releaseDate = DateTime.tryParse(releaseDateStr);
    if (releaseDate != null && releaseDate.isAfter(cutoff)) {
      codes.add(code);
    }
  }
  codes.sort();
  return codes;
}

Future<Map<String, dynamic>> _fetchSetJson(String setCode) async {
  print('⬇️  Baixando set $setCode...');
  final res = await _httpGetWithRetry(
    Uri.parse('https://mtgjson.com/api/v5/$setCode.json'),
    label: '$setCode.json',
  );
  final decoded =
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  return decoded['data'] as Map<String, dynamic>;
}

Future<File> _downloadAtomicCards({required bool force}) async {
  final file = File(_atomicCardsFileName);
  if (!force && await file.exists()) {
    final size = await file.length();
    print(
        '📁 Usando cache local: $_atomicCardsFileName (${(size / 1024 / 1024).toStringAsFixed(1)}MB)');
    return file;
  }
  print('⬇️  Baixando $_atomicCardsUrl (pode demorar ~1min)...');
  final res = await _httpGetWithRetry(
    Uri.parse(_atomicCardsUrl),
    label: 'AtomicCards.json',
  );
  await file.writeAsBytes(res.bodyBytes);
  print(
      '✅ Download concluido (${(res.bodyBytes.length / 1024 / 1024).toStringAsFixed(1)}MB)');
  return file;
}

// ═══════════════════════════════════════════════════════════════════════
// SYNC DE SETS
// ═══════════════════════════════════════════════════════════════════════

Future<void> _syncSetsFromData(Pool pool, List<dynamic> setListData) async {
  print('📋 Sincronizando ${setListData.length} sets...');
  await pool.runTx((session) async {
    final stmt = await session.prepare('''
      INSERT INTO sets (code, name, release_date, type, block, is_online_only, is_foreign_only, updated_at)
      VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, CURRENT_TIMESTAMP)
      ON CONFLICT (code) DO UPDATE SET
        name = EXCLUDED.name, release_date = EXCLUDED.release_date,
        type = EXCLUDED.type, block = EXCLUDED.block,
        is_online_only = EXCLUDED.is_online_only, is_foreign_only = EXCLUDED.is_foreign_only,
        updated_at = CURRENT_TIMESTAMP
    ''');
    try {
      for (final item in setListData) {
        if (item is! Map) continue;
        final code = item['code']?.toString().trim();
        final name = item['name']?.toString().trim();
        if (code == null || code.isEmpty || name == null || name.isEmpty) continue;

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

// ═══════════════════════════════════════════════════════════════════════
// UPSERT DE CARDS
// ═══════════════════════════════════════════════════════════════════════

/// Full sync: processa AtomicCards com prepared statement em batches.
Future<int> _upsertCardsFromAtomic(
    Session session, Map<String, dynamic> cardsMap) async {
  print('🃏 Upsert de ${cardsMap.length} cards (batches de $_batchSize)...');

  final stmt = await session.prepare('''
    INSERT INTO cards (
      scryfall_id, name, mana_cost, type_line, oracle_text,
      colors, color_identity, image_url, set_code, rarity
    ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10)
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
    // Extrai todas as rows primeiro (evita misturar I/O com CPU)
    final rows = <List<Object?>>[];
    for (final entry in cardsMap.entries) {
      final row = _extractCardRow(entry.key, entry.value as List<dynamic>);
      if (row != null) rows.add(row);
    }

    // Envia em batches paralelos para o Postgres
    for (var i = 0; i < rows.length; i += _batchSize) {
      final end = (i + _batchSize).clamp(0, rows.length);
      final batch = rows.sublist(i, end);
      await _runWithConcurrency(batch, (row) async {
        await stmt.run(row);
      });
      processed += batch.length;
      stdout.write('\r  ... $processed / ${rows.length}');
    }
  } finally {
    await stmt.dispose();
  }

  stdout.writeln('\r  ✅ $processed cards                ');
  return processed;
}

/// Incremental: processa cartas de um set em batch.
Future<int> _upsertCardsFromSet(
    Session session, List<Map<String, dynamic>> cards, String setCode) async {
  print('🃏 Upsert de ${cards.length} cards (set=$setCode)...');

  final stmt = await session.prepare('''
    INSERT INTO cards (
      scryfall_id, name, mana_cost, type_line, oracle_text,
      colors, color_identity, image_url, set_code, rarity,
      collector_number, foil
    ) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12)
    ON CONFLICT (scryfall_id) DO UPDATE SET
      name = EXCLUDED.name,
      mana_cost = EXCLUDED.mana_cost,
      type_line = EXCLUDED.type_line,
      oracle_text = EXCLUDED.oracle_text,
      colors = EXCLUDED.colors,
      color_identity = EXCLUDED.color_identity,
      image_url = EXCLUDED.image_url,
      set_code = EXCLUDED.set_code,
      rarity = EXCLUDED.rarity,
      collector_number = COALESCE(EXCLUDED.collector_number, cards.collector_number),
      foil = COALESCE(EXCLUDED.foil, cards.foil)
  ''');

  var processed = 0;
  try {
    final rows = <List<Object?>>[];
    for (final card in cards) {
      final ids = card['identifiers'] as Map<String, dynamic>?;
      final oracleId = ids?['scryfallOracleId']?.toString();
      if (oracleId == null || oracleId.isEmpty) continue;

      final name = card['name']?.toString();
      if (name == null || name.isEmpty) continue;

      final colors =
          (card['colors'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final colorIdentity =
          (card['colorIdentity'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];

      final encodedName = Uri.encodeQueryComponent(name);
      final setParam = setCode.isNotEmpty ? '&set=$setCode' : '';
      final imageUrl =
          'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

      // MTGJSON: "number" = collector number, "hasFoil"/"hasNonFoil" para foil status
      final collectorNumber = card['number']?.toString();
      final hasFoil = card['hasFoil'] as bool?;
      final hasNonFoil = card['hasNonFoil'] as bool?;
      // Se só tem foil (e não tem non-foil) → foil=true
      // Se só tem non-foil (e não tem foil) → foil=false
      // Se tem ambos → null (pode ser qualquer um)
      bool? foil;
      if (hasFoil == true && hasNonFoil != true) {
        foil = true;
      } else if (hasNonFoil == true && hasFoil != true) {
        foil = false;
      }

      rows.add([
        oracleId, name, card['manaCost']?.toString(),
        card['type']?.toString(), card['text']?.toString(),
        colors, colorIdentity, imageUrl, setCode,
        card['rarity']?.toString(),
        collectorNumber, foil,
      ]);
    }

    for (var i = 0; i < rows.length; i += _batchSize) {
      final end = (i + _batchSize).clamp(0, rows.length);
      final batch = rows.sublist(i, end);
      await _runWithConcurrency(batch, (row) async {
        await stmt.run(row);
      });
      processed += batch.length;
    }
  } finally {
    await stmt.dispose();
  }
  return processed;
}

/// Extrai dados de uma carta do AtomicCards.
List<Object?>? _extractCardRow(String cardName, List<dynamic> printings) {
  Map<String, dynamic>? chosen;
  for (final p in printings) {
    if (p is! Map<String, dynamic>) continue;
    final ids = p['identifiers'] as Map<String, dynamic>?;
    if (ids?['scryfallOracleId'] != null &&
        (ids!['scryfallOracleId'] as String).isNotEmpty) {
      chosen = p;
      break;
    }
  }
  if (chosen == null) return null;

  final ids = chosen['identifiers'] as Map<String, dynamic>?;
  final oracleId = ids?['scryfallOracleId'] as String?;
  if (oracleId == null || oracleId.isEmpty) return null;

  final name = (chosen['name'] ?? cardName).toString();
  final manaCost = chosen['manaCost']?.toString();
  final typeLine = chosen['type']?.toString();
  final oracleText = chosen['text']?.toString();
  final colors =
      (chosen['colors'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
  final colorIdentity =
      (chosen['colorIdentity'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
  final setCode =
      (chosen['printings'] as List?)?.cast<dynamic>().firstOrNull?.toString();
  final rarity = chosen['rarity']?.toString();

  final encodedName = Uri.encodeQueryComponent(name);
  final setParam =
      setCode != null && setCode.isNotEmpty ? '&set=$setCode' : '';
  final imageUrl =
      'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

  return [
    oracleId, name, manaCost, typeLine, oracleText,
    colors, colorIdentity, imageUrl, setCode, rarity,
  ];
}

// ═══════════════════════════════════════════════════════════════════════
// UPSERT DE LEGALITIES
// ═══════════════════════════════════════════════════════════════════════

/// Full sync: legalidades com prepared statement em batches.
Future<int> _upsertLegalitiesFromAtomic(
    Session session, Map<String, dynamic> cardsMap) async {
  print('⚖️  Upsert de legalidades (batches de $_batchSize)...');

  // Carrega mapa oracleId -> internal UUID (1x)
  final cardIdMap = await _loadCardIdMap(session);

  final stmt = await session.prepare('''
    INSERT INTO card_legalities (card_id, format, status)
    VALUES (\$1, \$2, \$3)
    ON CONFLICT (card_id, format) DO UPDATE SET status = EXCLUDED.status
  ''');

  var processed = 0;
  try {
    // Pré-monta todas as rows
    final rows = <List<Object?>>[];
    for (final cardPrintings in cardsMap.values) {
      final cardList = cardPrintings as List<dynamic>;
      if (cardList.isEmpty) continue;
      final first = cardList.first;
      if (first is! Map<String, dynamic>) continue;

      final ids = first['identifiers'] as Map<String, dynamic>?;
      final oracleId = ids?['scryfallOracleId'] as String?;
      final legalities = first['legalities'] as Map<String, dynamic>?;
      if (oracleId == null || legalities == null) continue;

      final internalId = cardIdMap[oracleId];
      if (internalId == null) continue;

      for (final entry in legalities.entries) {
        rows.add([internalId, entry.key, entry.value.toString().toLowerCase()]);
      }
    }

    // Envia em batches paralelos
    for (var i = 0; i < rows.length; i += _batchSize) {
      final end = (i + _batchSize).clamp(0, rows.length);
      final batch = rows.sublist(i, end);
      await _runWithConcurrency(batch, (row) async {
        await stmt.run(row);
      });
      processed += batch.length;
      if (processed % 20000 < _batchSize) {
        stdout.write('\r  ... $processed / ${rows.length} legalidades');
      }
    }
  } finally {
    await stmt.dispose();
  }

  stdout.writeln('\r  ✅ $processed legalidades                ');
  return processed;
}

/// Incremental: legalidades de um set em batch.
/// Carrega APENAS os card IDs relevantes (nao todos 33k+).
Future<int> _upsertLegalitiesFromSet(
    Session session, List<Map<String, dynamic>> cards) async {
  // Coleta oracle IDs deste set
  final oracleIds = <String>{};
  for (final card in cards) {
    final ids = card['identifiers'] as Map<String, dynamic>?;
    final oid = ids?['scryfallOracleId']?.toString();
    if (oid != null && oid.isNotEmpty) oracleIds.add(oid);
  }
  if (oracleIds.isEmpty) return 0;

  // Carrega APENAS os IDs internos necessarios
  final cardIdMap = await _loadCardIdMapForOracleIds(session, oracleIds);

  final stmt = await session.prepare('''
    INSERT INTO card_legalities (card_id, format, status)
    VALUES (\$1, \$2, \$3)
    ON CONFLICT (card_id, format) DO UPDATE SET status = EXCLUDED.status
  ''');

  var processed = 0;
  try {
    final rows = <List<Object?>>[];
    for (final card in cards) {
      final ids = card['identifiers'] as Map<String, dynamic>?;
      final oracleId = ids?['scryfallOracleId']?.toString();
      if (oracleId == null) continue;
      final internalId = cardIdMap[oracleId];
      if (internalId == null) continue;

      final legalities = card['legalities'] as Map<String, dynamic>?;
      if (legalities == null) continue;

      for (final entry in legalities.entries) {
        rows.add([internalId, entry.key, entry.value.toString().toLowerCase()]);
      }
    }

    for (var i = 0; i < rows.length; i += _batchSize) {
      final end = (i + _batchSize).clamp(0, rows.length);
      final batch = rows.sublist(i, end);
      await _runWithConcurrency(batch, (row) async {
        await stmt.run(row);
      });
      processed += batch.length;
    }
  } finally {
    await stmt.dispose();
  }
  return processed;
}

/// Carrega TODOS os oracle_id -> internal_id (para full sync).
Future<Map<String, String>> _loadCardIdMap(Session session) async {
  final result = await session.execute(
    Sql.named('SELECT scryfall_id::text, id::text FROM cards'),
  );
  final map = <String, String>{};
  for (final row in result) {
    map[row[0] as String] = row[1] as String;
  }
  return map;
}

/// Carrega APENAS os oracle_id -> internal_id de um conjunto especifico.
Future<Map<String, String>> _loadCardIdMapForOracleIds(
    Session session, Set<String> oracleIds) async {
  if (oracleIds.isEmpty) return {};
  final result = await session.execute(
    Sql.named(
        'SELECT scryfall_id::text, id::text FROM cards WHERE scryfall_id = ANY(@ids)'),
    parameters: {'ids': oracleIds.toList()},
  );
  final map = <String, String>{};
  for (final row in result) {
    map[row[0] as String] = row[1] as String;
  }
  return map;
}

extension _FirstOrNullList<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}