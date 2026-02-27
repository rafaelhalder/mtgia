import 'dart:convert';

import '../lib/database.dart';

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  final rows = await conn.execute('''
    SELECT id::text, format, source_url, card_list
    FROM meta_decks
    WHERE source_url ILIKE 'https://www.mtgtop8.com/%'
  ''');

  final basics = {'plains', 'island', 'swamp', 'mountain', 'forest', 'wastes'};

  int basicCount(String raw) {
    if (raw.trim().isEmpty) return 0;
    var inSideboard = false;
    var total = 0;

    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.toLowerCase().contains('sideboard')) {
        inSideboard = true;
        continue;
      }
      if (inSideboard) continue;

      final match = RegExp(r'^(\d+)x?\s+(.+)$').firstMatch(line);
      if (match == null) continue;

      final qty = int.tryParse(match.group(1) ?? '0') ?? 0;
      var name = (match.group(2) ?? '').trim();
      if (name.isEmpty) continue;
      name = name.replaceAll(RegExp(r'\s*\([^)]+\)\s*$'), '').trim().toLowerCase();

      if (basics.contains(name)) {
        total += qty;
      }
    }

    return total;
  }

  final decks = rows.map((r) {
    final id = (r[0] as String?) ?? '';
    final format = (r[1] as String?) ?? 'unknown';
    final url = (r[2] as String?) ?? '';
    final list = (r[3] as String?) ?? '';
    final count = basicCount(list);
    return {
      'id': id,
      'format': format,
      'url': url,
      'basic_count': count,
    };
  }).toList();

  List<Map<String, dynamic>> overThreshold(int threshold) =>
      decks.where((d) => (d['basic_count'] as int) > threshold).toList();

  Map<String, int> byFormat(List<Map<String, dynamic>> list) {
    final result = <String, int>{};
    for (final d in list) {
      final format = d['format'] as String;
      result[format] = (result[format] ?? 0) + 1;
    }
    return result;
  }

  final over40 = overThreshold(40);
  final over50 = overThreshold(50);
  final over60 = decks.where((d) => (d['basic_count'] as int) > 60).toList();

  final payload = {
    'total_competitive_saved': decks.length,
    'with_basic_lands_over_40': over40.length,
    'with_basic_lands_over_50': over50.length,
    'with_basic_lands_over_60': over60.length,
    'by_format_over40': byFormat(over40),
    'by_format_over50': byFormat(over50),
    'by_format_over60': byFormat(over60),
    'sample_over40': over40.take(10).toList(),
    'sample_over50': over50.take(10).toList(),
    'sample_over60': over60.take(10).toList(),
  };

  print(const JsonEncoder.withIndent('  ').convert(payload));

  await db.close();
}
