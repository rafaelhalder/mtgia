import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Sincroniza preços USD das cartas via Scryfall e guarda no banco.
///
/// Importante:
/// - No nosso schema, `cards.scryfall_id` guarda o `oracle_id` da Scryfall.
/// - A API `/cards/collection` aceita `oracle_id` e retorna `oracle_id`+`prices`.
/// - Salvamos em `cards.price` + `cards.price_updated_at`.
///
/// Uso:
///   dart run bin/sync_prices.dart
///   dart run bin/sync_prices.dart --limit=500
///   dart run bin/sync_prices.dart --all
///   dart run bin/sync_prices.dart --stale-hours=6
///   dart run bin/sync_prices.dart --dry-run
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_prices.dart - Atualiza preços (USD) via Scryfall

Uso:
  dart run bin/sync_prices.dart

Opções:
  --limit=<N>        Limite de cartas por execução (default: 500)
  --stale-hours=<N>  Atualiza apenas se price_updated_at for NULL ou mais velho que N horas (default: 24)
  --all              Considera todas as cartas (default: somente cartas usadas em decks)
  --dry-run          Não grava no banco (só mostra estatísticas)
  --help             Mostra esta ajuda
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

  final limit = _parseIntArg(args, '--limit=') ?? 500;
  final staleHours = _parseIntArg(args, '--stale-hours=') ?? 24;
  final all = args.contains('--all');
  final dryRun = args.contains('--dry-run');

  stdout.writeln(
    '💲 Sync de preços (limit=$limit, staleHours=$staleHours, all=$all, dryRun=$dryRun)',
  );

  try {
    // Seleciona apenas cartas com oracle_id e preço ausente/velho.
    // Default: apenas cartas usadas em decks (deck_cards).
    final result = await connection.execute(
      Sql.named('''
        SELECT
          c.scryfall_id::text as oracle_id
        FROM cards c
        ${all ? '' : 'JOIN (SELECT DISTINCT card_id FROM deck_cards) dc ON dc.card_id = c.id'}
        WHERE c.scryfall_id IS NOT NULL
          AND (
            c.price_updated_at IS NULL
            OR c.price_updated_at < NOW() - make_interval(hours => @staleHours)
          )
        ORDER BY c.price_updated_at NULLS FIRST
        LIMIT @limit
      '''),
      parameters: {
        'limit': limit,
        'staleHours': staleHours,
      },
    );

    final oracleIds =
        result.map((r) => (r[0] as String).trim()).where((s) => s.isNotEmpty);
    final list = oracleIds.toList();
    stdout.writeln('🔎 Cartas selecionadas para atualizar: ${list.length}');
    if (list.isEmpty) return;

    const batchSize = 75;
    var updated = 0;
    var missing = 0;
    var failedBatches = 0;

    for (var i = 0; i < list.length; i += batchSize) {
      final batch = list.sublist(i, (i + batchSize).clamp(0, list.length));
      final ok = await _updateBatch(
        connection: connection,
        oracleIds: batch,
        dryRun: dryRun,
      );
      if (ok == null) {
        failedBatches++;
      } else {
        updated += ok.updated;
        missing += ok.missing;
      }

      // Respeita rate limit do Scryfall (10 req/s). Aqui é conservador.
      await Future.delayed(const Duration(milliseconds: 250));
    }

    stdout.writeln(
      '✅ Concluído. updated=$updated, missingPrice=$missing, failedBatches=$failedBatches',
    );
  } finally {
    await connection.close();
  }
}

int? _parseIntArg(List<String> args, String prefix) {
  for (final a in args) {
    if (a.startsWith(prefix)) {
      final v = a.substring(prefix.length).trim();
      final n = int.tryParse(v);
      return n;
    }
  }
  return null;
}

class _BatchStats {
  final int updated;
  final int missing;
  _BatchStats({required this.updated, required this.missing});
}

Future<_BatchStats?> _updateBatch({
  required Connection connection,
  required List<String> oracleIds,
  required bool dryRun,
}) async {
  final identifiers = oracleIds.map((id) => {'oracle_id': id}).toList();

  final response = await http.post(
    Uri.parse('https://api.scryfall.com/cards/collection'),
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'ManaLoom/1.0 (https://github.com)',
    },
    body: jsonEncode({'identifiers': identifiers}),
  );

  if (response.statusCode != 200) {
    stderr.writeln('❌ Scryfall error: ${response.statusCode}');
    stderr.writeln('Body: ${response.body}');
    return null;
  }

  final data =
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  final found = (data['data'] as List?)?.whereType<Map>().toList() ?? const [];
  final notFound =
      (data['not_found'] as List?)?.whereType<Map>().toList() ?? const [];

  // Coleta todos os pares (oracleId, price) de uma vez
  final priceRows = <(String oracleId, double price)>[];
  var missing = 0;

  for (final card in found) {
    final oracleId = (card['oracle_id'] ?? '').toString().trim();
    if (oracleId.isEmpty) continue;

    final prices = (card['prices'] as Map?)?.cast<String, dynamic>();
    final usd = prices?['usd'] as String?;
    final usdFoil = prices?['usd_foil'] as String?;
    final usdEtched = prices?['usd_etched'] as String?;

    final price = double.tryParse(usd ?? '') ??
        double.tryParse(usdFoil ?? '') ??
        double.tryParse(usdEtched ?? '');

    if (price == null) {
      missing++;
      continue;
    }
    priceRows.add((oracleId, price));
  }

  missing += notFound.length;

  if (dryRun || priceRows.isEmpty) {
    return _BatchStats(updated: priceRows.length, missing: missing);
  }

  // Batch UPDATE: 1 query atualiza todo o lote (antes: N queries sequenciais)
  final values = <String>[];
  final params = <String, dynamic>{};
  for (var i = 0; i < priceRows.length; i++) {
    final (oid, price) = priceRows[i];
    values.add('(@oid$i, @price$i::decimal)');
    params['oid$i'] = oid;
    params['price$i'] = price;
  }

  await connection.execute(
    Sql.named('''
      UPDATE cards c
      SET price = v.price, price_updated_at = NOW()
      FROM (VALUES ${values.join(', ')}) AS v(oracle_id, price)
      WHERE c.scryfall_id::text = v.oracle_id
    '''),
    parameters: params,
  );

  return _BatchStats(updated: priceRows.length, missing: missing);
}
