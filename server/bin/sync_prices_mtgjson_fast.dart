// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Sync de preços via MTGJSON - VERSÃO OTIMIZADA v2
///
/// Mudanças da v2 (fix OOM crash com AllIdentifiers.json ~400MB):
/// - Usa `jq` para extrair dados de AllIdentifiers sem carregar tudo em memória
/// - Fallback para parse direto com tratamento de OOM explícito
/// - Sempre salva snapshot em price_history
///
/// Estratégia:
/// 1. Baixa AllPricesToday.json para disco (~30MB)
/// 2. Baixa AllIdentifiers.json para disco (~400MB) se necessário
/// 3. Extrai name+setCode via jq (streaming, sem OOM) ou fallback memória
/// 4. Match com cartas do banco (name + set_code)
/// 5. INSERT em tabela temp + UPDATE com JOIN
/// 6. Snapshot em price_history
///
/// Uso:
///   dart run bin/sync_prices_mtgjson_fast.dart
///   dart run bin/sync_prices_mtgjson_fast.dart --force-download
///   dart run bin/sync_prices_mtgjson_fast.dart --dry-run
Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_prices_mtgjson_fast.dart - Sync de preços OTIMIZADO via MTGJSON (v2)

Uso:
  dart run bin/sync_prices_mtgjson_fast.dart

Opções:
  --force-download  Força re-download dos JSONs mesmo se existirem
  --max-age-hours=N Só re-baixa se cache tiver mais de N horas (default: 20)
  --dry-run         Não grava no banco
  --help            Mostra esta ajuda

Notas:
  - Usa jq (se disponível) para parsear AllIdentifiers sem OOM
  - Se jq não estiver instalado: apt-get install -y jq
  - Fallback para parse em memória (precisa ~2GB RAM)
''');
    return;
  }

  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final connection = await Connection.open(
    Endpoint(
      host: env['DB_HOST'] ?? 'localhost',
      port: int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432,
      database: env['DB_NAME'] ?? 'mtg_builder',
      username: env['DB_USER'] ?? 'postgres',
      password: env['DB_PASS'],
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  final forceDownload = args.contains('--force-download');
  final dryRun = args.contains('--dry-run');
  final maxAgeHours = _parseIntArg(args, '--max-age-hours=') ?? 20;

  stdout.writeln(
    '💲 Sync de preços MTGJSON v2 (dryRun=$dryRun, maxAgeHours=$maxAgeHours)',
  );

  try {
    // Diretório de cache
    final cacheDir = Directory('cache');
    if (!cacheDir.existsSync()) cacheDir.createSync();

    // ── 1) Baixa AllPricesToday.json (~30MB) ──
    final pricesFile = File('cache/AllPricesToday.json');
    if (_shouldDownload(pricesFile, forceDownload, maxAgeHours)) {
      stdout.writeln('📥 Baixando AllPricesToday.json...');
      await _downloadFile(
        'https://mtgjson.com/api/v5/AllPricesToday.json',
        pricesFile,
      );
    } else {
      final age =
          DateTime.now().difference(pricesFile.lastModifiedSync()).inHours;
      stdout.writeln('📁 Usando cache AllPricesToday.json (${age}h atrás)');
    }

    // ── 2) Baixa AllIdentifiers.json (~400MB) ──
    final identFile = File('cache/AllIdentifiers.json');
    if (_shouldDownload(identFile, forceDownload, maxAgeHours)) {
      stdout.writeln('📥 Baixando AllIdentifiers.json (~400MB)...');
      await _downloadFile(
        'https://mtgjson.com/api/v5/AllIdentifiers.json',
        identFile,
      );
    } else {
      final age =
          DateTime.now().difference(identFile.lastModifiedSync()).inHours;
      stdout.writeln('📁 Usando cache AllIdentifiers.json (${age}h atrás)');
    }

    stdout.writeln('⏱️  Download: ${sw.elapsed.inSeconds}s');

    // ── 3) Parse AllPricesToday.json (~30MB, seguro para memória) ──
    stdout.writeln('📖 Parseando AllPricesToday.json...');
    final pricesJson =
        jsonDecode(await pricesFile.readAsString()) as Map<String, dynamic>;
    final pricesData = pricesJson['data'] as Map<String, dynamic>? ?? {};
    stdout.writeln('   ${pricesData.length} UUIDs com preços');

    // ── 4) Extrair name+setCode do AllIdentifiers (streaming com jq) ──
    stdout.writeln('📖 Extraindo name/setCode do AllIdentifiers...');
    final uuidToNameSet = <String, (String name, String setCode)>{};
    final wantedUuids = pricesData.keys.toSet();

    await _parseIdentifiers(identFile, wantedUuids, uuidToNameSet);
    stdout.writeln('   ${uuidToNameSet.length} UUIDs resolvidos');
    stdout.writeln('⏱️  Parse: ${sw.elapsed.inSeconds}s');

    // ── 5) Carregar cartas do banco ──
    stdout.writeln('📖 Carregando cartas do banco...');
    final cardsInDb = await connection.execute(
      "SELECT id::text, LOWER(name) as name, LOWER(set_code) as set_code FROM cards WHERE name IS NOT NULL AND set_code IS NOT NULL",
    );
    final cardMap = <String, String>{}; // "name|set_code" → card_id
    for (final row in cardsInDb) {
      cardMap['${row[1]}|${row[2]}'] = row[0] as String;
    }
    stdout.writeln('   ${cardMap.length} cartas no banco');

    // ── 6) Match e preparação dos dados ──
    stdout.writeln('🔄 Preparando dados...');
    final rows = <(String cardId, double price)>[];
    var noMatch = 0;
    var noPrice = 0;
    var notInDb = 0;

    for (final entry in pricesData.entries) {
      final uuid = entry.key;
      final priceInfo = entry.value as Map<String, dynamic>? ?? {};

      final nameSet = uuidToNameSet[uuid];
      if (nameSet == null) {
        noMatch++;
        continue;
      }

      final (name, setCode) = nameSet;
      final key = '${name.toLowerCase()}|${setCode.toLowerCase()}';
      final cardId = cardMap[key];
      if (cardId == null) {
        notInDb++;
        continue;
      }

      final price = _extractUsdPrice(priceInfo);
      if (price == null) {
        noPrice++;
        continue;
      }

      rows.add((cardId, price));
    }

    stdout.writeln('   ✅ ${rows.length} com preço válido para cards no banco');
    stdout.writeln('   ⚠️ $noMatch sem match no AllIdentifiers');
    stdout.writeln('   ⚠️ $notInDb match mas não existem no banco');
    stdout.writeln('   ⚠️ $noPrice sem preço USD');
    stdout.writeln('⏱️  Preparação: ${sw.elapsed.inSeconds}s');

    if (dryRun) {
      stdout.writeln('🏁 Dry-run concluído. Nada gravado.');
      return;
    }

    if (rows.isEmpty) {
      stdout.writeln('⚠️ Nenhum registro para atualizar.');
      return;
    }

    // ── 7) Tabela temporária + INSERT batch ──
    stdout.writeln('🗄️  Criando tabela temporária...');
    await connection.execute('DROP TABLE IF EXISTS tmp_mtgjson_prices');
    await connection.execute('''
      CREATE TEMP TABLE tmp_mtgjson_prices (
        card_id UUID NOT NULL,
        price DECIMAL(10,2) NOT NULL
      )
    ''');

    stdout.writeln('📤 Inserindo na tabela temporária...');
    const batchSize = 1000;
    var inserted = 0;

    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(i, (i + batchSize).clamp(0, rows.length));
      final values = <String>[];
      final params = <String, dynamic>{};

      for (var j = 0; j < batch.length; j++) {
        final (cardId, price) = batch[j];
        final idx = i + j;
        values.add('(@cid$idx::uuid, @p$idx::decimal)');
        params['cid$idx'] = cardId;
        params['p$idx'] = price;
      }

      await connection.execute(
        Sql.named(
          'INSERT INTO tmp_mtgjson_prices (card_id, price) VALUES ${values.join(', ')}',
        ),
        parameters: params,
      );

      inserted += batch.length;
      if (inserted % 5000 == 0) {
        stdout.writeln('   Inserido: $inserted/${rows.length}');
      }
    }

    stdout.writeln('   Total inserido: $inserted');

    // ── 8) UPDATE com JOIN ──
    stdout.writeln('🔄 Atualizando tabela cards...');
    final updateResult = await connection.execute('''
      UPDATE cards c
      SET
        price = t.price,
        price_updated_at = NOW()
      FROM tmp_mtgjson_prices t
      WHERE c.id = t.card_id
    ''');
    stdout.writeln('✅ Cards atualizados: ${updateResult.affectedRows}');
    stdout.writeln('⏱️  Update: ${sw.elapsed.inSeconds}s');

    // ── 9) Snapshot em price_history ──
    stdout.writeln('📊 Salvando snapshot diário em price_history...');
    try {
      final historyResult = await connection.execute('''
        INSERT INTO price_history (card_id, price_date, price_usd)
        SELECT id, CURRENT_DATE, price
        FROM cards
        WHERE price IS NOT NULL AND price > 0
        ON CONFLICT (card_id, price_date)
        DO UPDATE SET price_usd = EXCLUDED.price_usd
      ''');
      stdout.writeln(
        '   ✅ price_history: ${historyResult.affectedRows} registros',
      );
    } catch (e) {
      stderr.writeln('   ⚠️ price_history não atualizado: $e');
    }

    stdout.writeln('⏱️  Total: ${sw.elapsed.inSeconds}s');

    // Cleanup
    await connection.execute('DROP TABLE IF EXISTS tmp_mtgjson_prices');
  } catch (e, st) {
    stderr.writeln('❌ Erro: $e');
    stderr.writeln(st);
  } finally {
    await connection.close();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Extrai name+setCode do AllIdentifiers.json para os UUIDs desejados.
///
/// Tenta usar `jq` (streaming, memory-safe).
/// Fallback: carrega em memória (precisa ~2GB RAM).
Future<void> _parseIdentifiers(
  File identFile,
  Set<String> wantedUuids,
  Map<String, (String, String)> result,
) async {
  // Tentativa 1: jq (streaming, não usa memória do Dart)
  if (await _tryJqParse(identFile, wantedUuids, result)) {
    return;
  }

  // Tentativa 2: carregar em memória (pode OOM em containers com < 2GB)
  stdout.writeln('   ⚠️ jq não disponível. Carregando em memória...');
  stdout.writeln('   💡 Para evitar OOM futuro: apt-get install -y jq');
  try {
    final content = await identFile.readAsString();
    stdout.writeln(
      '   Arquivo lido (${(content.length / 1024 / 1024).toStringAsFixed(0)}MB). Parseando...',
    );

    final json = jsonDecode(content) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>? ?? {};
    stdout.writeln('   ${data.length} entries no AllIdentifiers');

    for (final uuid in wantedUuids) {
      final cardInfo = data[uuid] as Map<String, dynamic>?;
      if (cardInfo == null) continue;

      final name = (cardInfo['name'] as String?)?.trim();
      final setCode = (cardInfo['setCode'] as String?)?.trim();
      if (name != null &&
          name.isNotEmpty &&
          setCode != null &&
          setCode.isNotEmpty) {
        result[uuid] = (name, setCode);
      }
    }
  } catch (e) {
    stderr.writeln('   ❌ Erro ao parsear AllIdentifiers: $e');
    stderr.writeln(
      '   💡 Instale jq: docker exec <container> apt-get install -y jq',
    );
    rethrow;
  }
}

/// Usa jq para streaming parse (não carrega JSON na memória do Dart).
Future<bool> _tryJqParse(
  File identFile,
  Set<String> wantedUuids,
  Map<String, (String, String)> result,
) async {
  try {
    final jqCheck = await Process.run('which', ['jq']);
    if (jqCheck.exitCode != 0) return false;

    stdout.writeln('   Usando jq para extrair dados (memory-safe)...');

    final process = await Process.start('jq', [
      '-r',
      '.data | to_entries[] | [.key, (.value.name // ""), (.value.setCode // "")] | @tsv',
      identFile.path,
    ]);

    var parsed = 0;
    var matched = 0;
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      parsed++;
      final parts = line.split('\t');
      if (parts.length >= 3) {
        final uuid = parts[0].trim();
        if (wantedUuids.contains(uuid)) {
          final name = parts[1].trim();
          final setCode = parts[2].trim();
          if (name.isNotEmpty && setCode.isNotEmpty) {
            result[uuid] = (name, setCode);
            matched++;
          }
        }
      }
      if (parsed % 100000 == 0) {
        stdout.writeln('   jq: $parsed linhas processadas, $matched matches');
      }
    }

    // Captura stderr do jq
    final stderrOutput = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;

    if (exitCode != 0) {
      stderr.writeln('   ⚠️ jq exit=$exitCode: $stderrOutput');
      return false;
    }

    stdout.writeln('   jq: $parsed total, $matched matches');
    return true;
  } catch (e) {
    stderr.writeln('   ⚠️ jq failed: $e');
    return false;
  }
}

/// Baixa arquivo com progresso
Future<void> _downloadFile(String url, File file) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = 'ManaLoom/1.0';

    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    var downloaded = 0;
    var lastPercent = -1;

    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;

      if (contentLength > 0) {
        final percent = (downloaded * 100 / contentLength).floor();
        if (percent != lastPercent && percent % 10 == 0) {
          stdout.writeln(
            '   $percent% (${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB)',
          );
          lastPercent = percent;
        }
      }
    }

    await sink.close();
    stdout.writeln(
      '   ✅ Download: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB',
    );
  } finally {
    client.close();
  }
}

/// Extrai preço USD
double? _extractUsdPrice(Map<String, dynamic> priceData) {
  final paper = priceData['paper'] as Map<String, dynamic>? ?? {};
  var price = _getPriceFrom(paper, 'tcgplayer');
  return price ?? _getPriceFrom(paper, 'cardkingdom');
}

double? _getPriceFrom(Map<String, dynamic> paper, String provider) {
  final data = paper[provider] as Map<String, dynamic>? ?? {};
  final retail = data['retail'] as Map<String, dynamic>? ?? {};

  final normal = retail['normal'] as Map<String, dynamic>? ?? {};
  if (normal.isNotEmpty) {
    final price = _getLatestPrice(normal);
    if (price != null) return price;
  }

  final foil = retail['foil'] as Map<String, dynamic>? ?? {};
  if (foil.isNotEmpty) return _getLatestPrice(foil);

  return null;
}

double? _getLatestPrice(Map<String, dynamic> pricesByDate) {
  if (pricesByDate.isEmpty) return null;
  final sorted = pricesByDate.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  final value = sorted.first.value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _shouldDownload(File file, bool forceDownload, int maxAgeHours) {
  if (forceDownload) return true;
  if (!file.existsSync()) return true;
  final age = DateTime.now().difference(file.lastModifiedSync());
  return age.inHours >= maxAgeHours;
}

int? _parseIntArg(List<String> args, String prefix) {
  for (final a in args) {
    if (a.startsWith(prefix)) {
      return int.tryParse(a.substring(prefix.length).trim());
    }
  }
  return null;
}
