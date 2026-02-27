import 'dart:convert';

import '../lib/database.dart';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  final totalResult = await conn.execute('SELECT COUNT(*)::int FROM meta_decks');
  final total = (totalResult.first[0] as int?) ?? 0;

  final byFormatResult = await conn.execute(
    'SELECT format, COUNT(*)::int FROM meta_decks GROUP BY format ORDER BY COUNT(*) DESC',
  );

  final top8SourceResult = await conn.execute(
    "SELECT COUNT(*)::int FROM meta_decks WHERE source_url ILIKE 'https://www.mtgtop8.com/%'",
  );
  final top8Count = (top8SourceResult.first[0] as int?) ?? 0;

  final latestResult = await conn.execute('''
    SELECT format, archetype, placement, source_url, created_at
    FROM meta_decks
    ORDER BY created_at DESC
    LIMIT 12
  ''');

  final payload = {
    'total_meta_decks': total,
    'by_format': byFormatResult
        .map((r) => {'format': r[0], 'count': r[1]})
        .toList(),
    'mtgtop8_count': top8Count,
    'latest_samples': latestResult
        .map((r) => {
              'format': r[0],
              'archetype': r[1],
              'placement': r[2],
              'source_url': r[3],
              'created_at': r[4].toString(),
            })
        .toList(),
  };

  print(const JsonEncoder.withIndent('  ').convert(payload));
}
