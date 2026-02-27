class ImportListParseResult {
  final List<Map<String, dynamic>> parsedItems;
  final List<String> invalidLines;

  const ImportListParseResult({
    required this.parsedItems,
    required this.invalidLines,
  });
}

List<String> normalizeImportLines(dynamic rawList) {
  final lines = <String>[];

  if (rawList is String) {
    lines.addAll(rawList.split('\n'));
    return lines;
  }

  if (rawList is List) {
    for (final item in rawList) {
      if (item is String) {
        lines.add(item);
        continue;
      }

      if (item is Map) {
        final q = item['quantity'] ?? item['amount'] ?? item['qtd'] ?? 1;
        final n = item['name'] ?? item['card_name'] ?? item['card'] ?? '';
        if (n.toString().trim().isNotEmpty) {
          lines.add('$q $n');
        }
      }
    }
    return lines;
  }

  throw const FormatException('Field list must be a String or a List.');
}

ImportListParseResult parseImportLines(List<String> lines) {
  final parsedItems = <Map<String, dynamic>>[];
  final invalidLines = <String>[];
  final lineRegex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');

  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;

    final match = lineRegex.firstMatch(line);
    if (match == null) {
      invalidLines.add(line);
      continue;
    }

    final quantity = int.parse(match.group(1)!);
    final cardName = match.group(2)!.trim();
    final lineLower = line.toLowerCase();
    final isCommanderTag = lineLower.contains('[commander') ||
        lineLower.contains('*cmdr*') ||
        lineLower.contains('!commander');

    parsedItems.add({
      'line': line,
      'name': cardName,
      'quantity': quantity,
      'isCommanderTag': isCommanderTag,
    });
  }

  return ImportListParseResult(
    parsedItems: parsedItems,
    invalidLines: invalidLines,
  );
}
