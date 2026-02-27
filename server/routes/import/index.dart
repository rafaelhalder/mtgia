import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../lib/http_responses.dart';
import '../../lib/import_card_lookup_service.dart';
import '../../lib/import_list_service.dart';

List<Map<String, dynamic>> _consolidateCardsById(
  List<Map<String, dynamic>> cards,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final card in cards) {
    final cardId = card['card_id'] as String;
    final existing = byId[cardId];
    if (existing == null) {
      byId[cardId] = Map<String, dynamic>.from(card);
      continue;
    }

    existing['quantity'] =
        (existing['quantity'] as int) + (card['quantity'] as int);
    if (card['is_commander'] == true) {
      existing['is_commander'] = true;
    }
  }
  return byId.values.toList();
}

int _sumQuantities(List<Map<String, dynamic>> cards) =>
    cards.fold<int>(0, (sum, c) => sum + (c['quantity'] as int? ?? 0));

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.post) {
    return _importDeck(context);
  }
  return methodNotAllowed();
}

Future<Response> _importDeck(RequestContext context) async {
  final userId = context.read<String>();
  final pool = context.read<Pool>();

  final body = await context.request.json();
  final name = body['name'] as String?;
  final format = body['format'] as String?;
  final description = body['description'] as String?;
  final commanderName = body['commander'] as String?;
  final rawList = body['list'];

  if (name == null || format == null || rawList == null) {
    return badRequest('Fields name, format, and list are required.');
  }

  late final List<String> lines;
  try {
    lines = normalizeImportLines(rawList);
  } on FormatException catch (e) {
    return badRequest(e.message);
  }

  final cardsToInsert = <Map<String, dynamic>>[];
  final notFoundCards = <String>[];

  final parseResult = parseImportLines(lines);
  final parsedItems = parseResult.parsedItems;
  notFoundCards.addAll(parseResult.invalidLines);

  final foundCardsMap = await resolveImportCardNames(pool, parsedItems);

  // 6. Montagem final da lista de inserção
  for (final item in parsedItems) {
    // Verifica se já foi marcado como não encontrado (ex: erro de regex)
    if (notFoundCards.contains(item['line'])) continue;

    final originalKey = (item['name'] as String).toLowerCase();
    final cleanedKey = cleanImportLookupKey(originalKey);
    final nameKey = foundCardsMap.containsKey(originalKey)
      ? originalKey
      : cleanedKey;

    if (foundCardsMap.containsKey(nameKey)) {
      final cardData = foundCardsMap[nameKey]!;
      final dbName = cardData['name'] as String;

      final isCommander = item['isCommanderTag'] ||
          (commanderName != null &&
              dbName.toLowerCase() == commanderName.toLowerCase());

      cardsToInsert.add({
        'card_id': cardData['id'],
        'quantity': item['quantity'],
        'is_commander': isCommander,
        'name': dbName,
        'type_line': cardData['type_line'],
      });
    } else {
      // Se chegou até aqui e não achou, agora sim é erro
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
        'not_found': notFoundCards,
        'hint':
            'Confira formato das linhas (ex: "1 Sol Ring") e nomes das cartas.',
      },
    );
  }

  final consolidatedCards = _consolidateCardsById(cardsToInsert);

  // 6.5. Validação de Comandante para formatos que exigem
  if (format == 'commander' || format == 'brawl') {
    final hasCommander =
        consolidatedCards.any((c) => c['is_commander'] == true);

    if (!hasCommander) {
      // Tenta detectar automaticamente um comandante baseado no tipo
      // Procura por Legendary Creature ou Planeswalker com "can be your commander"
      for (final card in consolidatedCards) {
        final typeLine = (card['type_line'] as String).toLowerCase();
        final isLegendaryCreature =
            typeLine.contains('legendary') && typeLine.contains('creature');

        if (isLegendaryCreature) {
          // Marca a primeira Legendary Creature como comandante
          card['is_commander'] = true;
          break;
        }
      }
    }
  }

  // 7. Validação de Regras (Banlist e Limites)
  final limit = (format == 'commander' || format == 'brawl') ? 1 : 4;
  final cardIdsToCheck = <String>[];

  for (final card in consolidatedCards) {
    final name = card['name'] as String;
    final typeLine = card['type_line'] as String;
    final quantity = card['quantity'] as int;
    final isBasicLand = typeLine.toLowerCase().contains('basic land');

    if (!isBasicLand && quantity > limit) {
      return badRequest('Regra violada: $name tem $quantity cópias (Limite: $limit).');
    }
    cardIdsToCheck.add(card['card_id'] as String);
  }

  if (cardIdsToCheck.isNotEmpty) {
    final legalityResult = await pool.execute(
        Sql.named(
            'SELECT c.name, cl.status FROM card_legalities cl JOIN cards c ON c.id = cl.card_id WHERE cl.card_id = ANY(@ids) AND cl.format = @format'),
        parameters: {
          'ids': TypedValue(Type.uuidArray, cardIdsToCheck),
          'format': format,
        });

    final bannedCards = <String>[];
    for (final row in legalityResult) {
      if (row[1] == 'banned') {
        bannedCards.add(row[0] as String);
      }
    }

    if (bannedCards.isNotEmpty) {
      return badRequest(
        'O deck contém cartas BANIDAS no formato $format: ${bannedCards.join(", ")}',
      );
    }
  }

  try {
    final newDeck = await pool.runTx((session) async {
      // 1. Criar o Deck
      final deckResult = await session.execute(
        Sql.named(
          'INSERT INTO decks (user_id, name, format, description) VALUES (@userId, @name, @format, @desc) RETURNING id, name, format, created_at',
        ),
        parameters: {
          'userId': userId,
          'name': name,
          'format': format,
          'desc': description,
        },
      );

      final newDeckId = deckResult.first.toColumnMap()['id'];

      // 2. Inserir as Cartas (Bulk Insert)
      if (consolidatedCards.isNotEmpty) {
        final valueStrings = <String>[];
        final params = <String, dynamic>{
          'deckId': newDeckId,
        };

        for (var i = 0; i < consolidatedCards.length; i++) {
          final card = consolidatedCards[i];
          final pCardId = 'c$i';
          final pQty = 'q$i';
          final pCmdr = 'cmd$i';

          valueStrings.add('(@deckId, @$pCardId, @$pQty, @$pCmdr)');
          params[pCardId] = card['card_id'];
          params[pQty] = card['quantity'];
          params[pCmdr] = card['is_commander'] ?? false;
        }

        final sql =
            'INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander) VALUES ${valueStrings.join(',')}';

        await session.execute(Sql.named(sql), parameters: params);
      }

      final deckMap = deckResult.first.toColumnMap();
      if (deckMap['created_at'] is DateTime) {
        deckMap['created_at'] =
            (deckMap['created_at'] as DateTime).toIso8601String();
      }
      return deckMap;
    });

    // Prepara warnings para a resposta
    final warnings = <String>[];

    // Verifica se é formato Commander/Brawl sem comandante detectado
    if ((format == 'commander' || format == 'brawl') &&
        !consolidatedCards.any((c) => c['is_commander'] == true)) {
      warnings.add(
          'Nenhum comandante foi detectado. Considere marcar uma carta como comandante.');
    }

    final responseBody = {
      'deck': newDeck,
      'cards_imported': _sumQuantities(consolidatedCards),
      'not_found_lines': notFoundCards,
    };

    if (warnings.isNotEmpty) {
      responseBody['warnings'] = warnings;
    }

    return Response.json(body: responseBody);
  } catch (e) {
    print('[ERROR] Failed to import deck: $e');
    return internalServerError('Failed to import deck');
  }
}
