// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Backfill do price_history com dados históricos do MTGJson
///
/// Baixa AllPrices.json (90 dias de histórico) e extrai APENAS
/// os últimos N dias (padrão: 7) para popular a tabela price_history.
/// Isso permite que o Market (movers) funcione imediatamente
/// sem esperar múltiplos dias de sync.
///
/// Uso:
///   dart run bin/backfill_price_history.dart              # últimos 7 dias
///   dart run bin/backfill_price_history.dart --days=3      # últimos 3 dias
///   dart run bin/backfill_price_history.dart --days=30     # últimos 30 dias
///   dart run bin/backfill_price_history.dart --dry-run     # não grava
Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
backfill_price_history.dart - Backfill de histórico de preços via MTGJson

Uso:
  dart run bin/backfill_price_history.dart

Opções:
  --days=N            Número de dias passados a importar (default: 7)
  --force-download    Força re-download do AllPrices.json
  --max-age-hours=N   Só re-baixa se cache tiver mais de N horas (default: 20)
  --dry-run           Não grava no banco
  --help              Mostra esta ajuda

O arquivo AllPrices.json (~1.1GB) contém 90 dias de preços para TODAS as cartas.
Este script extrai apenas os dias solicitados e insere no price_history.
Usa AllIdentifiers.json (cache) para mapear UUID → nome/set.
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
  final days = _parseIntArg(args, '--days=') ?? 7;

  stdout.writeln('📊 Backfill price_history - últimos $days dias, dryRun=$dryRun');

  try {
    // Diretório de cache
    final cacheDir = Directory('cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync();
    }

    // 1) Baixa AllPrices.json (90 dias de histórico)
    final pricesFile = File('cache/AllPrices.json');
    if (_shouldDownload(pricesFile, forceDownload, maxAgeHours)) {
      stdout.writeln('📥 Baixando AllPrices.json (~1.1GB, pode demorar)...');
      await _downloadFile(
        'https://mtgjson.com/api/v5/AllPrices.json',
        pricesFile,
      );
    } else {
      final age = DateTime.now().difference(pricesFile.lastModifiedSync()).inHours;
      stdout.writeln('📁 Usando cache: AllPrices.json (${age}h atrás)');
    }

    // 2) AllIdentifiers.json (para mapear UUID → nome/set)
    final identFile = File('cache/AllIdentifiers.json');
    if (_shouldDownload(identFile, forceDownload, maxAgeHours)) {
      stdout.writeln('📥 Baixando AllIdentifiers.json (~400MB)...');
      await _downloadFile(
        'https://mtgjson.com/api/v5/AllIdentifiers.json',
        identFile,
      );
    } else {
      final age = DateTime.now().difference(identFile.lastModifiedSync()).inHours;
      stdout.writeln('📁 Usando cache: AllIdentifiers.json (${age}h atrás)');
    }

    stdout.writeln('⏱️  Download: ${sw.elapsed.inSeconds}s');

    // 3) Parse AllIdentifiers (para mapeamento UUID → nome/set)
    stdout.writeln('📖 Parseando AllIdentifiers.json...');
    final identJson = jsonDecode(await identFile.readAsString()) as Map<String, dynamic>;
    final identData = identJson['data'] as Map<String, dynamic>? ?? {};
    stdout.writeln('   ${identData.length} cards no AllIdentifiers');

    // 4) Parse AllPrices.json
    stdout.writeln('📖 Parseando AllPrices.json (grande, aguarde)...');
    final pricesJson = jsonDecode(await pricesFile.readAsString()) as Map<String, dynamic>;
    final pricesData = pricesJson['data'] as Map<String, dynamic>? ?? {};
    stdout.writeln('   ${pricesData.length} UUIDs com preços');
    stdout.writeln('⏱️  Parse: ${sw.elapsed.inSeconds}s');

    // 5) Calcular datas-alvo (últimos N dias, excluindo hoje pois já temos)
    final today = DateTime.now();
    final targetDates = <String>{};
    for (var i = 1; i <= days; i++) {
      final d = today.subtract(Duration(days: i));
      targetDates.add(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
    stdout.writeln('📅 Datas-alvo: ${targetDates.toList()..sort()}');

    // 6) Extrair preços históricos para as datas-alvo
    stdout.writeln('🔄 Extraindo preços históricos...');

    // Estrutura: { "nome_lower|set_code" : { "2026-02-08": 5.99, ... } }
    final historicalPrices = <String, Map<String, double>>{};
    var processedUuids = 0;
    var matchedUuids = 0;

    for (final entry in pricesData.entries) {
      processedUuids++;
      final uuid = entry.key;
      final priceInfo = entry.value as Map<String, dynamic>? ?? {};

      // Busca nome/set no AllIdentifiers
      final cardInfo = identData[uuid] as Map<String, dynamic>?;
      if (cardInfo == null) continue;

      final name = (cardInfo['name'] as String?)?.trim();
      final setCode = (cardInfo['setCode'] as String?)?.toLowerCase().trim();
      if (name == null || name.isEmpty || setCode == null || setCode.isEmpty) continue;

      // Extrai preços das datas-alvo
      final datePrices = _extractHistoricalPrices(priceInfo, targetDates);
      if (datePrices.isEmpty) continue;

      matchedUuids++;
      final key = '${name.toLowerCase()}|$setCode';

      // Merge (pode ter múltiplos UUIDs para mesma carta — pega o primeiro)
      historicalPrices.putIfAbsent(key, () => {});
      for (final dp in datePrices.entries) {
        historicalPrices[key]!.putIfAbsent(dp.key, () => dp.value);
      }

      if (processedUuids % 50000 == 0) {
        stdout.writeln('   Processado: $processedUuids/${pricesData.length} (matched: $matchedUuids)');
      }
    }

    stdout.writeln('   ✅ $matchedUuids UUIDs com preços em ${historicalPrices.length} cartas únicas');
    stdout.writeln('⏱️  Extração: ${sw.elapsed.inSeconds}s');

    if (dryRun) {
      // Mostra sample
      var count = 0;
      for (final e in historicalPrices.entries.take(5)) {
        stdout.writeln('   Sample: ${e.key} → ${e.value}');
        count++;
      }
      stdout.writeln('🏁 Dry-run concluído. $count samples mostrados. Nada gravado.');
      return;
    }

    // 7) Criar tabela temporária para bulk insert + JOIN
    stdout.writeln('🗄️  Criando tabela temporária...');
    await connection.execute('DROP TABLE IF EXISTS tmp_price_backfill');
    await connection.execute('''
      CREATE TEMP TABLE tmp_price_backfill (
        name TEXT NOT NULL,
        set_code TEXT NOT NULL,
        price_date DATE NOT NULL,
        price_usd DECIMAL(10,2) NOT NULL
      )
    ''');

    // 8) Inserir em batches
    stdout.writeln('📤 Inserindo dados históricos na tabela temporária...');
    final allRows = <(String name, String setCode, String date, double price)>[];

    for (final entry in historicalPrices.entries) {
      final parts = entry.key.split('|');
      final name = parts[0];
      final setCode = parts[1];

      for (final dp in entry.value.entries) {
        allRows.add((name, setCode, dp.key, dp.value));
      }
    }

    stdout.writeln('   Total de registros a inserir: ${allRows.length}');

    const batchSize = 1000;
    var inserted = 0;

    for (var i = 0; i < allRows.length; i += batchSize) {
      final batch = allRows.sublist(i, (i + batchSize).clamp(0, allRows.length));

      final values = <String>[];
      final params = <String, dynamic>{};

      for (var j = 0; j < batch.length; j++) {
        final (name, setCode, date, price) = batch[j];
        final idx = i + j;
        values.add('(@n$idx, @s$idx, @d$idx::date, @p$idx)');
        params['n$idx'] = name;
        params['s$idx'] = setCode;
        params['d$idx'] = date;
        params['p$idx'] = price;
      }

      await connection.execute(
        Sql.named('INSERT INTO tmp_price_backfill (name, set_code, price_date, price_usd) VALUES ${values.join(', ')}'),
        parameters: params,
      );

      inserted += batch.length;
      if (inserted % 10000 == 0 || inserted == allRows.length) {
        stdout.writeln('   Inserido: $inserted/${allRows.length}');
      }
    }

    stdout.writeln('⏱️  Insert temp: ${sw.elapsed.inSeconds}s');

    // 9) Índice para acelerar JOIN
    stdout.writeln('📊 Criando índice...');
    await connection.execute('''
      CREATE INDEX idx_tmp_backfill ON tmp_price_backfill (name, set_code)
    ''');

    // 10) INSERT no price_history via JOIN com cards
    stdout.writeln('🔄 Inserindo no price_history via JOIN...');
    final insertResult = await connection.execute('''
      INSERT INTO price_history (card_id, price_date, price_usd)
      SELECT c.id, t.price_date, t.price_usd
      FROM tmp_price_backfill t
      JOIN cards c ON LOWER(c.name) = t.name AND LOWER(c.set_code) = t.set_code
      ON CONFLICT (card_id, price_date)
      DO UPDATE SET price_usd = EXCLUDED.price_usd
    ''');

    stdout.writeln('✅ price_history: ${insertResult.affectedRows} registros inseridos/atualizados');

    // 11) Verificar datas disponíveis
    final datesResult = await connection.execute('''
      SELECT price_date, COUNT(*) as cnt 
      FROM price_history 
      GROUP BY price_date 
      ORDER BY price_date DESC 
      LIMIT 10
    ''');
    stdout.writeln('\n📅 Datas no price_history:');
    for (final row in datesResult) {
      stdout.writeln('   ${row[0]} → ${row[1]} cartas');
    }

    // Cleanup
    await connection.execute('DROP TABLE IF EXISTS tmp_price_backfill');

    stdout.writeln('\n🏁 Backfill concluído em ${sw.elapsed.inSeconds}s');
    stdout.writeln('💡 O Market (/market/movers) agora deve funcionar!');

  } catch (e, st) {
    stderr.writeln('❌ Erro: $e');
    stderr.writeln(st);
  } finally {
    await connection.close();
  }
}

/// Extrai preços históricos para as datas-alvo
/// Estrutura: paper.tcgplayer.retail.normal = {"2026-02-09": 5.99, "2026-02-08": 5.50}
Map<String, double> _extractHistoricalPrices(
  Map<String, dynamic> priceData,
  Set<String> targetDates,
) {
  final result = <String, double>{};
  final paper = priceData['paper'] as Map<String, dynamic>? ?? {};

  // Tenta tcgplayer primeiro, depois cardkingdom
  for (final provider in ['tcgplayer', 'cardkingdom']) {
    final providerData = paper[provider] as Map<String, dynamic>? ?? {};
    final retail = providerData['retail'] as Map<String, dynamic>? ?? {};
    final normal = retail['normal'] as Map<String, dynamic>? ?? {};

    if (normal.isNotEmpty) {
      for (final dateEntry in normal.entries) {
        if (targetDates.contains(dateEntry.key)) {
          final value = dateEntry.value;
          double? price;
          if (value is num) {
            price = value.toDouble();
          } else if (value is String) {
            price = double.tryParse(value);
          }
          if (price != null && price > 0) {
            result.putIfAbsent(dateEntry.key, () => price!);
          }
        }
      }
      if (result.isNotEmpty) return result;
    }

    // Foil fallback
    final foil = retail['foil'] as Map<String, dynamic>? ?? {};
    if (foil.isNotEmpty) {
      for (final dateEntry in foil.entries) {
        if (targetDates.contains(dateEntry.key)) {
          final value = dateEntry.value;
          double? price;
          if (value is num) {
            price = value.toDouble();
          } else if (value is String) {
            price = double.tryParse(value);
          }
          if (price != null && price > 0) {
            result.putIfAbsent(dateEntry.key, () => price!);
          }
        }
      }
      if (result.isNotEmpty) return result;
    }
  }

  return result;
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
        if (percent != lastPercent && percent % 5 == 0) {
          stdout.writeln('   $percent% (${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB)');
          lastPercent = percent;
        }
      }
    }

    await sink.close();
    stdout.writeln('   ✅ Download concluído: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB');
  } finally {
    client.close();
  }
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
      final v = a.substring(prefix.length).trim();
      return int.tryParse(v);
    }
  }
  return null;
}
