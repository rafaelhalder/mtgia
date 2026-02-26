import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/import_card_lookup_service.dart';

String _cleanLookupKey(String value) => value.replaceAll(RegExp(r'\s+\d+$'), '');

int _sumQuantities(List<Map<String, dynamic>> cards) =>
    cards.fold<int>(0, (sum, c) => sum + (c['quantity'] as int? ?? 0));

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.post) {
    return _importToDeck(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

/// Importa uma lista de cartas para um deck EXISTENTE
Future<Response> _importToDeck(RequestContext context) async {
  final userId = context.read<String>();
  final pool = context.read<Pool>();

  final body = await context.request.json();
  final deckId = body['deck_id'] as String?;
  final rawList = body['list'];
  final replaceAll = body['replace_all'] == true;

  if (deckId == null || rawList == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Fields deck_id and list are required.'},
    );
  }

  // Verifica se o deck pertence ao usuário
  final deckCheck = await pool.execute(
    Sql.named(
        'SELECT id, format FROM decks WHERE id = @id AND user_id = @userId'),
    parameters: {'id': deckId, 'userId': userId},
  );

  if (deckCheck.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'error': 'Deck not found or access denied.'},
    );
  }

  final format = deckCheck.first[1] as String;

  List<String> lines = [];
  if (rawList is String) {
    lines = rawList.split('\n');
  } else if (rawList is List) {
    for (var item in rawList) {
      if (item is String) {
        lines.add(item);
      } else if (item is Map) {
        final q = item['quantity'] ?? item['amount'] ?? item['qtd'] ?? 1;
        final n = item['name'] ?? item['card_name'] ?? item['card'] ?? '';
        if (n.toString().isNotEmpty) {
          lines.add('$q $n');
        }
      }
    }
  } else {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Field list must be a String or a List.'},
    );
  }

  // Regex para fazer o parse da linha
  final lineRegex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');

  final cardsToInsert = <Map<String, dynamic>>[];
  final notFoundCards = <String>[];
  final warnings = <String>[];

  final parsedItems = <Map<String, dynamic>>[];

  // 1. Parse de todas as linhas
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;

    final match = lineRegex.firstMatch(line);
    if (match != null) {
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
    } else {
      notFoundCards.add(line);
    }
  }

  // 2) Resolve nomes em lote (exato + clean + split fallback)
  final foundCardsMap = await resolveImportCardNames(pool, parsedItems);

  // 5. Montagem da lista final
  for (final item in parsedItems) {
    if (notFoundCards.contains(item['line'])) continue;

    final originalKey = (item['name'] as String).toLowerCase();
    final cleanedKey = _cleanLookupKey(originalKey);
    final nameKey = foundCardsMap.containsKey(originalKey) ? originalKey : cleanedKey;

    if (foundCardsMap.containsKey(nameKey)) {
      final cardData = foundCardsMap[nameKey]!;

      cardsToInsert.add({
        'card_id': cardData['id'],
        'quantity': item['quantity'],
        'is_commander': item['isCommanderTag'] ?? false,
        'name': cardData['name'],
        'type_line': cardData['type_line'],
      });
    } else {
      if (!notFoundCards.contains(item['line'])) {
        notFoundCards.add(item['line']);
      }
    }
  }

  if (cardsToInsert.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {
        'error': 'No valid cards found in the list.',
        'not_found_lines': notFoundCards
      },
    );
  }

  // 6. Validação de regras
  final limit = (format == 'commander' || format == 'brawl') ? 1 : 4;

  // Agrupa cartas por card_id para evitar duplicatas
  final cardMap = <String, Map<String, dynamic>>{};
  for (final card in cardsToInsert) {
    final cardId = card['card_id'] as String;
    final existing = cardMap[cardId];
    if (existing == null) {
      cardMap[cardId] = Map<String, dynamic>.from(card);
      continue;
    }

    existing['quantity'] =
        (existing['quantity'] as int) + (card['quantity'] as int);
    if (card['is_commander'] == true) {
      existing['is_commander'] = true;
    }
  }

  final consolidatedCards = cardMap.values.toList();

  // Warnings com quantidades consolidadas
  warnings.clear();
  for (final card in consolidatedCards) {
    final name = card['name'] as String;
    final typeLine = card['type_line'] as String;
    final quantity = card['quantity'] as int;
    final isBasicLand = typeLine.toLowerCase().contains('basic land');

    if (!isBasicLand && quantity > limit) {
      warnings.add('$name: $quantity cópias (limite $limit)');
    }
  }

  try {
    await pool.runTx((session) async {
      // Se replaceAll, remove as cartas existentes
      if (replaceAll) {
        await session.execute(
          Sql.named('DELETE FROM deck_cards WHERE deck_id = @deckId'),
          parameters: {'deckId': deckId},
        );
      }

      // Upsert para evitar violação de UNIQUE em (deck_id, card_id)
      const upsertSql = '''
INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander)
VALUES (@deckId, @cardId, @qty, @isCmd)
ON CONFLICT (deck_id, card_id)
DO UPDATE SET
  quantity = deck_cards.quantity + EXCLUDED.quantity,
  is_commander = (deck_cards.is_commander OR EXCLUDED.is_commander)
''';

      for (final card in consolidatedCards) {
        final cardId = card['card_id'] as String;
        await session.execute(
          Sql.named(upsertSql),
          parameters: {
            'deckId': deckId,
            'cardId': cardId,
            'qty': card['quantity'],
            'isCmd': card['is_commander'] ?? false,
          },
        );
      }
    });

    return Response.json(body: {
      'success': true,
      'cards_imported': _sumQuantities(consolidatedCards),
      'not_found_lines': notFoundCards,
      'warnings': warnings,
    });
  } catch (e) {
    print('[ERROR] Failed to import cards: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to import cards'},
    );
  }
}
