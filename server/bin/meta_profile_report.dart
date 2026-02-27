import 'dart:convert';

import '../lib/database.dart';

class CardInfo {
  CardInfo({required this.typeLine, required this.colorIdentity});

  final String typeLine;
  final List<String> colorIdentity;
}

class MutableProfile {
  int deckCount = 0;
  int totalCards = 0;
  int lands = 0;
  int basicLands = 0;
  int creatures = 0;
  int instants = 0;
  int sorceries = 0;
  int enchantments = 0;
  int artifacts = 0;
  int planeswalkers = 0;
}

Future<void> main() async {
  final db = Database();
  await db.connect();
  final conn = db.connection;

  final cardRows = await conn.execute('''
    SELECT LOWER(name) AS name, type_line, color_identity
    FROM cards
  ''');

  final cardMap = <String, CardInfo>{};
  for (final row in cardRows) {
    final name = (row[0] as String?) ?? '';
    if (name.isEmpty) continue;
    final typeLine = (row[1] as String?) ?? '';
    final ci = (row[2] as List?)?.cast<String>() ?? const <String>[];
    cardMap[name] = CardInfo(typeLine: typeLine, colorIdentity: ci);
  }

  final deckRows = await conn.execute('''
    SELECT id::text, format, archetype, card_list
    FROM meta_decks
    WHERE source_url ILIKE 'https://www.mtgtop8.com/%'
  ''');

  final byFormat = <String, MutableProfile>{};
  final byFormatColorTheme = <String, MutableProfile>{};

  for (final row in deckRows) {
    final format = ((row[1] as String?) ?? 'unknown').trim();
    final archetype = ((row[2] as String?) ?? 'unknown').trim();
    final cardList = (row[3] as String?) ?? '';

    final parsed = _parseDeck(
      cardList: cardList,
      cardMap: cardMap,
    );

    if (parsed.totalCards == 0) continue;

    final formatKey = format.isEmpty ? 'unknown' : format;
    final themeKey = _normalizeTheme(archetype);
    final colorsList = parsed.colors.toList()..sort();
    final colorsJoined = colorsList.isEmpty ? 'C' : colorsList.join('');
    final groupKey = '$formatKey|$colorsJoined|$themeKey';

    _accumulate(byFormat.putIfAbsent(formatKey, () => MutableProfile()), parsed);
    _accumulate(byFormatColorTheme.putIfAbsent(groupKey, () => MutableProfile()), parsed);
  }

  final formatReport = byFormat.entries.map((e) {
    final p = e.value;
    return {
      'format': e.key,
      'deck_count': p.deckCount,
      'avg_total_cards': _avg(p.totalCards, p.deckCount),
      'avg_lands': _avg(p.lands, p.deckCount),
      'avg_basic_lands': _avg(p.basicLands, p.deckCount),
      'avg_creatures': _avg(p.creatures, p.deckCount),
      'avg_instants': _avg(p.instants, p.deckCount),
      'avg_sorceries': _avg(p.sorceries, p.deckCount),
      'avg_enchantments': _avg(p.enchantments, p.deckCount),
      'avg_artifacts': _avg(p.artifacts, p.deckCount),
      'avg_planeswalkers': _avg(p.planeswalkers, p.deckCount),
    };
  }).toList()
    ..sort((a, b) => (b['deck_count'] as int).compareTo(a['deck_count'] as int));

  final groupedReport = byFormatColorTheme.entries
      .map((e) {
        final p = e.value;
        final parts = e.key.split('|');
        return {
          'format': parts[0],
          'colors': parts[1],
          'theme': parts[2],
          'deck_count': p.deckCount,
          'avg_lands': _avg(p.lands, p.deckCount),
          'avg_basic_lands': _avg(p.basicLands, p.deckCount),
          'avg_creatures': _avg(p.creatures, p.deckCount),
          'avg_instants': _avg(p.instants, p.deckCount),
          'avg_sorceries': _avg(p.sorceries, p.deckCount),
          'avg_enchantments': _avg(p.enchantments, p.deckCount),
          'avg_artifacts': _avg(p.artifacts, p.deckCount),
          'avg_planeswalkers': _avg(p.planeswalkers, p.deckCount),
        };
      })
      .where((e) => (e['deck_count'] as int) >= 2)
      .toList()
    ..sort((a, b) => (b['deck_count'] as int).compareTo(a['deck_count'] as int));

  final payload = {
    'total_competitive_decks': deckRows.length,
    'formats': formatReport,
    'top_groups_format_color_theme': groupedReport.take(40).toList(),
  };

  print(const JsonEncoder.withIndent('  ').convert(payload));
  await db.close();
}

class ParsedDeck {
  ParsedDeck({
    required this.totalCards,
    required this.lands,
    required this.basicLands,
    required this.creatures,
    required this.instants,
    required this.sorceries,
    required this.enchantments,
    required this.artifacts,
    required this.planeswalkers,
    required this.colors,
  });

  final int totalCards;
  final int lands;
  final int basicLands;
  final int creatures;
  final int instants;
  final int sorceries;
  final int enchantments;
  final int artifacts;
  final int planeswalkers;
  final Set<String> colors;
}

ParsedDeck _parseDeck({
  required String cardList,
  required Map<String, CardInfo> cardMap,
}) {
  final basicNames = {'plains', 'island', 'swamp', 'mountain', 'forest', 'wastes'};
  final colors = <String>{};

  var inSideboard = false;
  var totalCards = 0;
  var lands = 0;
  var basicLands = 0;
  var creatures = 0;
  var instants = 0;
  var sorceries = 0;
  var enchantments = 0;
  var artifacts = 0;
  var planeswalkers = 0;

  for (final rawLine in cardList.split('\n')) {
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
    if (qty <= 0) continue;

    var name = (match.group(2) ?? '').trim();
    if (name.isEmpty) continue;
    name = name.replaceAll(RegExp(r'\s*\([^)]+\)\s*$'), '').trim().toLowerCase();

    totalCards += qty;

    if (basicNames.contains(name)) {
      basicLands += qty;
      lands += qty;
      continue;
    }

    final info = cardMap[name];
    if (info == null) continue;

    for (final c in info.colorIdentity) {
      final upper = c.toUpperCase().trim();
      if (upper.isNotEmpty && 'WUBRGC'.contains(upper)) {
        colors.add(upper);
      }
    }

    final type = info.typeLine.toLowerCase();
    if (type.contains('land')) lands += qty;
    if (type.contains('creature')) creatures += qty;
    if (type.contains('instant')) instants += qty;
    if (type.contains('sorcery')) sorceries += qty;
    if (type.contains('enchantment')) enchantments += qty;
    if (type.contains('artifact')) artifacts += qty;
    if (type.contains('planeswalker')) planeswalkers += qty;
  }

  return ParsedDeck(
    totalCards: totalCards,
    lands: lands,
    basicLands: basicLands,
    creatures: creatures,
    instants: instants,
    sorceries: sorceries,
    enchantments: enchantments,
    artifacts: artifacts,
    planeswalkers: planeswalkers,
    colors: colors,
  );
}

void _accumulate(MutableProfile target, ParsedDeck source) {
  target.deckCount += 1;
  target.totalCards += source.totalCards;
  target.lands += source.lands;
  target.basicLands += source.basicLands;
  target.creatures += source.creatures;
  target.instants += source.instants;
  target.sorceries += source.sorceries;
  target.enchantments += source.enchantments;
  target.artifacts += source.artifacts;
  target.planeswalkers += source.planeswalkers;
}

double _avg(int total, int count) {
  if (count <= 0) return 0;
  return double.parse((total / count).toStringAsFixed(2));
}

String _normalizeTheme(String archetype) {
  final value = archetype.toLowerCase().trim();
  if (value.isEmpty) return 'unknown';

  final cleaned = value.replaceAll(RegExp(r'[^a-z0-9\s\-+]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return 'unknown';

  final tokens = cleaned.split(' ');
  final stop = {
    'the', 'and', 'of', 'deck', 'commander', 'cedh', 'edh', 'duel',
    'mono', 'with', 'for', 'to', 'a', 'an'
  };
  for (final token in tokens) {
    if (token.length < 3) continue;
    if (stop.contains(token)) continue;
    return token;
  }
  return tokens.first;
}
