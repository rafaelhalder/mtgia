import 'package:postgres/postgres.dart';

String cleanImportLookupKey(String value) =>
  value.replaceAll(RegExp(r'\s+\d+$'), '');

/// Resolve nomes de cartas para dados do banco em lote.
///
/// Estratégia:
/// 1) match exato case-insensitive por nome original e versão "limpa" (ex: Forest 96 -> Forest)
/// 2) fallback para split cards via pattern `<nome> // %`
Future<Map<String, Map<String, dynamic>>> resolveImportCardNames(
  Pool pool,
  List<Map<String, dynamic>> parsedItems,
) async {
  final foundCardsMap = <String, Map<String, dynamic>>{};

  final exactKeys = <String>{};
  for (final item in parsedItems) {
    final rawName = item['name']?.toString().trim();
    if (rawName == null || rawName.isEmpty) continue;

    final originalKey = rawName.toLowerCase();
    final cleanKey = cleanImportLookupKey(originalKey);

    exactKeys.add(originalKey);
    exactKeys.add(cleanKey);
  }

  if (exactKeys.isNotEmpty) {
    final exactResult = await pool.execute(
      Sql.named('''
        SELECT id, name, type_line, image_url
        FROM cards
        WHERE lower(name) = ANY(@names)
      '''),
      parameters: {
        'names': TypedValue(Type.textArray, exactKeys.toList()),
      },
    );

    for (final row in exactResult) {
      final id = row[0] as String;
      final name = row[1] as String;
      final typeLine = row[2] as String;
      final imageUrl = row[3] as String?;
      foundCardsMap[name.toLowerCase()] = {
        'id': id,
        'name': name,
        'type_line': typeLine,
        'image_url': imageUrl,
      };
    }
  }

  // Fallback para Split Cards / Double-Faced
  final splitPatternsToQuery = <String>[];
  for (final item in parsedItems) {
    final rawName = item['name']?.toString().trim();
    if (rawName == null || rawName.isEmpty) continue;

    final originalKey = rawName.toLowerCase();
    final cleanKey = cleanImportLookupKey(originalKey);
    final lookupKey = foundCardsMap.containsKey(originalKey)
        ? originalKey
        : cleanKey;

    if (!foundCardsMap.containsKey(lookupKey)) {
      splitPatternsToQuery.add('$lookupKey // %');
    }
  }

  if (splitPatternsToQuery.isNotEmpty) {
    final splitResult = await pool.execute(
      Sql.named('''
        SELECT id, name, type_line, image_url
        FROM cards
        WHERE lower(name) LIKE ANY(@patterns)
      '''),
      parameters: {
        'patterns': TypedValue(Type.textArray, splitPatternsToQuery),
      },
    );

    for (final row in splitResult) {
      final id = row[0] as String;
      final dbName = row[1] as String;
      final typeLine = row[2] as String;
      final imageUrl = row[3] as String?;
      final dbNameLower = dbName.toLowerCase();

      final parts = dbNameLower.split(RegExp(r'\s*//\s*'));
      if (parts.isEmpty) continue;

      final prefix = parts.first.trim();
      if (!foundCardsMap.containsKey(prefix)) {
        foundCardsMap[prefix] = {
          'id': id,
          'name': dbName,
          'type_line': typeLine,
          'image_url': imageUrl,
        };
      }
    }
  }

  return foundCardsMap;
}
