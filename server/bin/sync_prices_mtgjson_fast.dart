// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Sync de preços via MTGJSON - VERSÃO OTIMIZADA
///
/// Estratégia:
/// 1. Baixa AllPricesToday.json para disco (se não existir ou --force)
/// 2. Baixa AllIdentifiers.json para disco (se não existir ou --force)
/// 3. Cria tabela temporária no banco
/// 4. Insere dados em BATCH (1000 por vez)
/// 5. UPDATE com JOIN (uma única query!)
///
/// Uso:
///   dart run bin/sync_prices_mtgjson_fast.dart
///   dart run bin/sync_prices_mtgjson_fast.dart --force-download
///   dart run bin/sync_prices_mtgjson_fast.dart --dry-run
Future<void> main(List<String> args) async {
  final sw = Stopwatch()..start();

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_prices_mtgjson_fast.dart - Sync de preços OTIMIZADO via MTGJSON

Uso:
  dart run bin/sync_prices_mtgjson_fast.dart

Opções:
  --force-download  Força re-download dos JSONs mesmo se existirem
  --max-age-hours=N Só re-baixa se cache tiver mais de N horas (default: 20)
  --dry-run         Não grava no banco
  --help            Mostra esta ajuda

Exemplos:
  # Primeira execução (baixa tudo ~500MB)
  dart run bin/sync_prices_mtgjson_fast.dart

  # Execuções seguintes (usa cache se < 20h)
  dart run bin/sync_prices_mtgjson_fast.dart

  # Forçar re-download
  dart run bin/sync_prices_mtgjson_fast.dart --force-download

  # Só re-baixa se cache > 12 horas
  dart run bin/sync_prices_mtgjson_fast.dart --max-age-hours=12
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

  stdout.writeln('💲 Sync de preços MTGJSON (FAST) - dryRun=$dryRun, maxAgeHours=$maxAgeHours');

  try {
    // Diretório de cache
    final cacheDir = Directory('cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync();
    }

    // 1) Baixa AllPricesToday.json
    final pricesFile = File('cache/AllPricesToday.json');
    if (_shouldDownload(pricesFile, forceDownload, maxAgeHours)) {
      stdout.writeln('📥 Baixando AllPricesToday.json...');
      await _downloadFile(
        'https://mtgjson.com/api/v5/AllPricesToday.json',
        pricesFile,
      );
    } else {
      final age = DateTime.now().difference(pricesFile.lastModifiedSync()).inHours;
      stdout.writeln('📁 Usando cache: AllPricesToday.json (${age}h atrás)');
    }

    // 2) Baixa AllIdentifiers.json
    final identFile = File('cache/AllIdentifiers.json');
    if (_shouldDownload(identFile, forceDownload, maxAgeHours)) {
      stdout.writeln('📥 Baixando AllIdentifiers.json (grande, ~400MB)...');
      await _downloadFile(
        'https://mtgjson.com/api/v5/AllIdentifiers.json',
        identFile,
      );
    } else {
      final age = DateTime.now().difference(identFile.lastModifiedSync()).inHours;
      stdout.writeln('📁 Usando cache: AllIdentifiers.json (${age}h atrás)');
    }

    stdout.writeln('⏱️  Download: ${sw.elapsed.inSeconds}s');

    // 3) Parse dos JSONs
    stdout.writeln('📖 Parseando AllIdentifiers.json...');
    final identJson = jsonDecode(await identFile.readAsString()) as Map<String, dynamic>;
    final identData = identJson['data'] as Map<String, dynamic>? ?? {};
    stdout.writeln('   ${identData.length} cards no AllIdentifiers');

    stdout.writeln('📖 Parseando AllPricesToday.json...');
    final pricesJson = jsonDecode(await pricesFile.readAsString()) as Map<String, dynamic>;
    final pricesData = pricesJson['data'] as Map<String, dynamic>? ?? {};
    stdout.writeln('   ${pricesData.length} UUIDs com preços');

    stdout.writeln('⏱️  Parse: ${sw.elapsed.inSeconds}s');

    // 4) Cria tabela temporária
    stdout.writeln('🗄️  Criando tabela temporária...');
    await connection.execute('DROP TABLE IF EXISTS tmp_mtgjson_prices');
    await connection.execute('''
      CREATE TEMP TABLE tmp_mtgjson_prices (
        name TEXT NOT NULL,
        set_code TEXT NOT NULL,
        price DECIMAL(10,2) NOT NULL
      )
    ''');

    // 5) Prepara dados para inserção em batch
    stdout.writeln('🔄 Preparando dados...');
    final rows = <(String name, String setCode, double price)>[];

    for (final entry in pricesData.entries) {
      final uuid = entry.key;
      final priceInfo = entry.value as Map<String, dynamic>? ?? {};

      // Busca nome/set no AllIdentifiers
      final cardInfo = identData[uuid] as Map<String, dynamic>?;
      if (cardInfo == null) continue;

      final name = (cardInfo['name'] as String?)?.trim();
      final setCode = (cardInfo['setCode'] as String?)?.toLowerCase().trim();
      if (name == null || name.isEmpty || setCode == null || setCode.isEmpty) continue;

      // Extrai preço USD
      final price = _extractUsdPrice(priceInfo);
      if (price == null) continue;

      rows.add((name, setCode, price));
    }

    stdout.writeln('   ${rows.length} registros com preço válido');
    stdout.writeln('⏱️  Preparação: ${sw.elapsed.inSeconds}s');

    if (dryRun) {
      stdout.writeln('🏁 Dry-run concluído. Nada gravado.');
      return;
    }

    // 6) Insere em batches de 1000
    stdout.writeln('📤 Inserindo na tabela temporária...');
    const batchSize = 1000;
    var inserted = 0;

    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(i, (i + batchSize).clamp(0, rows.length));
      
      // Monta VALUES para inserção em massa
      final values = <String>[];
      final params = <String, dynamic>{};
      
      for (var j = 0; j < batch.length; j++) {
        final (name, setCode, price) = batch[j];
        final idx = i + j;
        values.add('(@name$idx, @set$idx, @price$idx)');
        params['name$idx'] = name;
        params['set$idx'] = setCode;
        params['price$idx'] = price;
      }

      await connection.execute(
        Sql.named('INSERT INTO tmp_mtgjson_prices (name, set_code, price) VALUES ${values.join(', ')}'),
        parameters: params,
      );

      inserted += batch.length;
      if (inserted % 10000 == 0) {
        stdout.writeln('   Inserido: $inserted/${rows.length}');
      }
    }

    stdout.writeln('   Total inserido: $inserted');
    stdout.writeln('⏱️  Insert: ${sw.elapsed.inSeconds}s');

    // 7) Cria índice para acelerar JOIN
    stdout.writeln('📊 Criando índice...');
    await connection.execute('''
      CREATE INDEX idx_tmp_prices_name_set ON tmp_mtgjson_prices (LOWER(name), set_code)
    ''');

    // 8) UPDATE com JOIN (uma única query!)
    stdout.writeln('🔄 Atualizando tabela cards...');
    final updateResult = await connection.execute('''
      UPDATE cards c
      SET 
        price = t.price,
        price_updated_at = NOW()
      FROM tmp_mtgjson_prices t
      WHERE LOWER(c.name) = LOWER(t.name)
        AND LOWER(c.set_code) = t.set_code
    ''');

    stdout.writeln('✅ Cards atualizados: ${updateResult.affectedRows}');
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

/// Extrai preço USD do objeto de preços
double? _extractUsdPrice(Map<String, dynamic> priceData) {
  final paper = priceData['paper'] as Map<String, dynamic>? ?? {};

  // tcgplayer primeiro
  var price = _getPriceFrom(paper, 'tcgplayer');
  if (price != null) return price;

  // cardkingdom fallback
  price = _getPriceFrom(paper, 'cardkingdom');
  if (price != null) return price;

  return null;
}

double? _getPriceFrom(Map<String, dynamic> paper, String provider) {
  final data = paper[provider] as Map<String, dynamic>? ?? {};
  final retail = data['retail'] as Map<String, dynamic>? ?? {};

  // Normal primeiro
  final normal = retail['normal'] as Map<String, dynamic>? ?? {};
  if (normal.isNotEmpty) {
    final price = _getLatestPrice(normal);
    if (price != null) return price;
  }

  // Foil fallback
  final foil = retail['foil'] as Map<String, dynamic>? ?? {};
  if (foil.isNotEmpty) {
    return _getLatestPrice(foil);
  }

  return null;
}

double? _getLatestPrice(Map<String, dynamic> pricesByDate) {
  if (pricesByDate.isEmpty) return null;
  final sorted = pricesByDate.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
  final value = sorted.first.value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Verifica se deve baixar o arquivo
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
