import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../../../lib/http_responses.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return methodNotAllowed();
  }

  try {
    final uri = context.request.uri;
    final commander = (uri.queryParameters['commander'] ?? '').trim();
    final limitRaw = uri.queryParameters['limit'];
    final limit = (int.tryParse(limitRaw ?? '') ?? 40).clamp(5, 200);
    final refresh = (uri.queryParameters['refresh'] ?? '').toLowerCase();
    final shouldRefresh = refresh == '1' || refresh == 'true' || refresh == 'yes';

    if (commander.isEmpty) {
      return badRequest('Query parameter commander is required.');
    }

    final pool = context.read<Pool>();

    Map<String, dynamic>? refreshSummary;
    if (shouldRefresh) {
      refreshSummary = await _refreshCommanderFromMtgTop8(
        pool: pool,
        commander: commander,
      );
    }

    var decks = await pool.execute(
      Sql.named('''
        SELECT id::text, archetype, source_url, placement, card_list
        FROM meta_decks
        WHERE format IN ('EDH', 'cEDH')
          AND card_list ILIKE @commanderPattern
        ORDER BY created_at DESC
        LIMIT 200
      '''),
      parameters: {
        'commanderPattern': '%${commander.replaceAll('%', '')}%',
      },
    );

    if (decks.isEmpty) {
      final commanderToken = commander.split(',').first.trim();
      if (commanderToken.isNotEmpty) {
        decks = await pool.execute(
          Sql.named('''
            SELECT id::text, archetype, source_url, placement, card_list
            FROM meta_decks
            WHERE format IN ('EDH', 'cEDH')
              AND archetype ILIKE @archetypePattern
            ORDER BY created_at DESC
            LIMIT 200
          '''),
          parameters: {
            'archetypePattern': '%${commanderToken.replaceAll('%', '')}%',
          },
        );
      }
    }

    if (decks.isEmpty) {
      List<dynamic> fallback = const [];
      try {
        fallback = await pool.execute(
          Sql.named('''
            SELECT card_name, usage_count, meta_deck_count
            FROM card_meta_insights
            WHERE @commander = ANY(common_commanders)
            ORDER BY meta_deck_count DESC, usage_count DESC, card_name ASC
            LIMIT @limit
          '''),
          parameters: {
            'commander': commander,
            'limit': limit,
          },
        );
      } catch (_) {
        fallback = const [];
      }

      if (fallback.isEmpty) {
        return Response.json(body: {
          'commander': commander,
          'meta_decks_found': 0,
          'reference_cards': <Map<String, dynamic>>[],
          'sample_decks': <Map<String, dynamic>>[],
          'message': 'Nenhum deck competitivo encontrado para esse comandante no acervo atual.',
        });
      }

      final cards = fallback.map((row) {
        final name = (row[0] as String?) ?? '';
        final usage = (row[1] as int?) ?? 0;
        final metaCount = (row[2] as int?) ?? 0;
        return {
          'name': name,
          'total_copies': usage,
          'appears_in_decks': metaCount,
          'usage_rate': 0.0,
        };
      }).toList();

      return Response.json(body: {
        'commander': commander,
        'meta_decks_found': 0,
        'reference_cards': cards,
        'sample_decks': <Map<String, dynamic>>[],
        'model': {
          'type': 'commander_competitive_reference',
          'generated_from_meta_decks': 0,
          'generated_from_card_meta_insights': true,
          'top_non_basic_cards': cards.map((e) => e['name']).toList(),
        },
        if (refreshSummary != null) 'refresh': refreshSummary,
      });
    }

    final commanderLower = commander.toLowerCase();
    final counts = <String, int>{};
    final deckAppearances = <String, int>{};
    final sampleDecks = <Map<String, dynamic>>[];

    for (final row in decks) {
      final deckId = row[0] as String;
      final archetype = (row[1] as String?) ?? 'unknown';
      final sourceUrl = (row[2] as String?) ?? '';
      final placement = (row[3] as String?) ?? '';
      final rawList = (row[4] as String?) ?? '';

      if (sampleDecks.length < 10) {
        sampleDecks.add({
          'id': deckId,
          'archetype': archetype,
          'source_url': sourceUrl,
          'placement': placement,
        });
      }

      final seenInDeck = <String>{};
      var inSideboard = false;

      for (final rawLine in rawList.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (line.toLowerCase().contains('sideboard')) {
          inSideboard = true;
          continue;
        }
        if (inSideboard) continue;

        final match = RegExp(r'^(\d+)x?\s+(.+)$').firstMatch(line);
        if (match == null) continue;

        final qty = int.tryParse(match.group(1) ?? '1') ?? 1;
        var name = (match.group(2) ?? '').trim();
        if (name.isEmpty) continue;

        name = name.replaceAll(RegExp(r'\s*\([^)]+\)\s*$'), '').trim();
        if (name.isEmpty) continue;

        final lower = name.toLowerCase();
        if (lower == commanderLower || _isBasicLandName(lower)) continue;

        counts[name] = (counts[name] ?? 0) + qty;
        if (!seenInDeck.contains(lower)) {
          deckAppearances[name] = (deckAppearances[name] ?? 0) + 1;
          seenInDeck.add(lower);
        }
      }
    }

    final totalDecks = decks.length;
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });

    final references = sorted.take(limit).map((e) {
      final appearances = deckAppearances[e.key] ?? 0;
      final usageRate = totalDecks > 0 ? appearances / totalDecks : 0.0;
      return {
        'name': e.key,
        'total_copies': e.value,
        'appears_in_decks': appearances,
        'usage_rate': double.parse(usageRate.toStringAsFixed(3)),
      };
    }).toList();

    return Response.json(body: {
      'commander': commander,
      'meta_decks_found': totalDecks,
      'reference_cards': references,
      'sample_decks': sampleDecks,
      'model': {
        'type': 'commander_competitive_reference',
        'generated_from_meta_decks': totalDecks,
        'top_non_basic_cards': references.map((e) => e['name']).toList(),
      },
      if (refreshSummary != null) 'refresh': refreshSummary,
    });
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {
        'error': 'Failed to build commander reference model.',
        'details': e.toString(),
      },
    );
  }
}

Future<Map<String, dynamic>> _refreshCommanderFromMtgTop8({
  required Pool pool,
  required String commander,
}) async {
  const baseUrl = 'https://www.mtgtop8.com';
  const formats = ['EDH', 'cEDH'];

  final commanderToken = commander.split(',').first.trim().toLowerCase();
  if (commanderToken.isEmpty) {
    return {
      'enabled': true,
      'imported': 0,
      'scanned_events': 0,
      'scanned_decks': 0,
      'matched_commander': false,
    };
  }

  var imported = 0;
  var scannedEvents = 0;
  var scannedDecks = 0;
  var matchedCommander = false;

  for (final formatCode in formats) {
    final formatUrl = '$baseUrl/format?f=$formatCode';
    final formatRes = await http.get(Uri.parse(formatUrl));
    if (formatRes.statusCode != 200) continue;

    final formatDoc = html_parser.parse(formatRes.body);
    final eventLinks = formatDoc
        .querySelectorAll('a[href*="event?e="]')
        .map((e) => e.attributes['href'])
        .whereType<String>()
        .toSet()
        .take(3)
        .toList();

    for (final eventPath in eventLinks) {
      scannedEvents += 1;
      final eventUrl = '$baseUrl/$eventPath';
      final eventRes = await http.get(Uri.parse(eventUrl));
      if (eventRes.statusCode != 200) continue;

      final eventDoc = html_parser.parse(eventRes.body);
      final rows = eventDoc.querySelectorAll('div.hover_tr').take(10).toList();

      for (final row in rows) {
        final link = row.querySelector('a');
        if (link == null) continue;
        final href = link.attributes['href'];
        if (href == null || !href.contains('&d=')) continue;

        scannedDecks += 1;
        final deckUrl = '$baseUrl/$href';

        final exists = await pool.execute(
          Sql.named('SELECT 1 FROM meta_decks WHERE source_url = @url LIMIT 1'),
          parameters: {'url': deckUrl},
        );
        if (exists.isNotEmpty) continue;

        final deckUri = Uri.parse(deckUrl);
        final deckId = deckUri.queryParameters['d'];
        if (deckId == null || deckId.isEmpty) continue;

        final exportUrl = '$baseUrl/mtgo?d=$deckId';
        final exportRes = await http.get(Uri.parse(exportUrl));
        if (exportRes.statusCode != 200) continue;

        final cardList = exportRes.body;
        if (!_deckListContainsCommander(cardList, commanderToken)) {
          continue;
        }

        matchedCommander = true;
        final placement = _extractPlacement(row);
        final archetype = link.text.trim();

        await pool.execute(
          Sql.named('''
            INSERT INTO meta_decks (format, archetype, source_url, card_list, placement)
            VALUES (@format, @archetype, @url, @list, @placement)
            ON CONFLICT (source_url) DO NOTHING
          '''),
          parameters: {
            'format': deckUri.queryParameters['f'] ?? formatCode,
            'archetype': archetype,
            'url': deckUrl,
            'list': cardList,
            'placement': placement,
          },
        );

        imported += 1;
      }
    }
  }

  return {
    'enabled': true,
    'imported': imported,
    'scanned_events': scannedEvents,
    'scanned_decks': scannedDecks,
    'matched_commander': matchedCommander,
  };
}

String _extractPlacement(dynamic row) {
  try {
    final divs = row.querySelectorAll('div');
    if (divs.isNotEmpty) {
      final p = divs.first.text.trim();
      if (p.isNotEmpty) return p;
    }
  } catch (_) {}
  return '?';
}

bool _deckListContainsCommander(String cardList, String commanderToken) {
  if (cardList.trim().isEmpty || commanderToken.trim().isEmpty) return false;
  final normalized = cardList.toLowerCase();
  return normalized.contains(commanderToken);
}

bool _isBasicLandName(String name) {
  final n = name.trim().toLowerCase();
  return n == 'plains' ||
      n == 'island' ||
      n == 'swamp' ||
      n == 'mountain' ||
      n == 'forest' ||
      n == 'wastes';
}
