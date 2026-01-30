import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.post) {
    return _importDeck(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
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
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Fields name, format, and list are required.'},
    );
  }

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
  // Ex: "1x Sol Ring (cmm) *F*" -> Group 1: "1", Group 2: "Sol Ring", Group 3: "cmm"
  // Usamos [^(]+ para capturar o nome até o primeiro parêntese (set code)
  final lineRegex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');

  final cardsToInsert = <Map<String, dynamic>>[];
  final notFoundCards = <String>[];

  // Estrutura temporária para armazenar o parse inicial
  final parsedItems = <Map<String, dynamic>>[];
  final namesToQuery = <String>{};

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
      namesToQuery.add(cardName.toLowerCase());
    } else {
      notFoundCards.add(line);
    }
  }

  // 2. Busca em lote (Batch Query)
  final foundCardsMap = <String, Map<String, dynamic>>{};
  
  if (namesToQuery.isNotEmpty) {
    final result = await pool.execute(
      Sql.named('SELECT id, name, type_line FROM cards WHERE lower(name) = ANY(@names)'),
      parameters: {'names': TypedValue(Type.textArray, namesToQuery.toList())},
    );
    for (final row in result) {
      final id = row[0] as String;
      final name = row[1] as String;
      final typeLine = row[2] as String;
      foundCardsMap[name.toLowerCase()] = {'id': id, 'name': name, 'type_line': typeLine};
    }
  }

  // 3. Processamento e Fallback (para nomes com números ex: "Forest 96")
  final cleanNamesToQuery = <String>{};
  final itemsNeedingFallback = <Map<String, dynamic>>[];

  for (final item in parsedItems) {
    final nameLower = (item['name'] as String).toLowerCase();
    if (!foundCardsMap.containsKey(nameLower)) {
      // Tenta limpar números no final do nome
      final cleanName = (item['name'] as String).replaceAll(RegExp(r'\s+\d+$'), '');
      if (cleanName != item['name']) {
        item['cleanName'] = cleanName;
        cleanNamesToQuery.add(cleanName.toLowerCase());
        itemsNeedingFallback.add(item);
      }
      // Não marcamos como notFound ainda, pois temos o fallback de Split Cards
    }
  }

  // 4. Busca em lote para os Fallbacks
  if (cleanNamesToQuery.isNotEmpty) {
    final result = await pool.execute(
      Sql.named('SELECT id, name, type_line FROM cards WHERE lower(name) = ANY(@names)'),
      parameters: {'names': TypedValue(Type.textArray, cleanNamesToQuery.toList())},
    );
    for (final row in result) {
      final id = row[0] as String;
      final name = row[1] as String;
      final typeLine = row[2] as String;
      foundCardsMap[name.toLowerCase()] = {'id': id, 'name': name, 'type_line': typeLine};
    }
  }

  // 5. Fallback para Split Cards / Double Faced (Ex: "Command Tower" -> "Command Tower // Command Tower")
  final splitPatternsToQuery = <String>[];
  
  for (final item in parsedItems) {
     final nameKey = item['cleanName'] != null 
        ? (item['cleanName'] as String).toLowerCase() 
        : (item['name'] as String).toLowerCase();
     
     // Se ainda não achou
     if (!foundCardsMap.containsKey(nameKey)) {
        splitPatternsToQuery.add('$nameKey // %');
     }
  }

  if (splitPatternsToQuery.isNotEmpty) {
      final result = await pool.execute(
        Sql.named('SELECT id, name, type_line FROM cards WHERE lower(name) LIKE ANY(@patterns)'),
        parameters: {'patterns': TypedValue(Type.textArray, splitPatternsToQuery)},
      );
      
      for (final row in result) {
        final id = row[0] as String;
        final dbName = row[1] as String;
        final typeLine = row[2] as String;
        final dbNameLower = dbName.toLowerCase();
        
        // Split robusto
        final parts = dbNameLower.split(RegExp(r'\s*//\s*'));
        if (parts.isNotEmpty) {
            final prefix = parts[0].trim();
            if (!foundCardsMap.containsKey(prefix)) {
                 foundCardsMap[prefix] = {'id': id, 'name': dbName, 'type_line': typeLine};
            }
        }
      }
  }

  // 6. Montagem final da lista de inserção
  for (final item in parsedItems) {
    // Verifica se já foi marcado como não encontrado (ex: erro de regex)
    if (notFoundCards.contains(item['line'])) continue;

    final nameKey = item['cleanName'] != null 
        ? (item['cleanName'] as String).toLowerCase() 
        : (item['name'] as String).toLowerCase();

    if (foundCardsMap.containsKey(nameKey)) {
      final cardData = foundCardsMap[nameKey]!;
      final dbName = cardData['name'] as String;
      
      final isCommander = item['isCommanderTag'] || (commanderName != null && 
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
      body: {'error': 'No valid cards found in the list.', 'not_found': notFoundCards},
    );
  }

  // 6.5. Validação de Comandante para formatos que exigem
  if (format == 'commander' || format == 'brawl') {
    final hasCommander = cardsToInsert.any((c) => c['is_commander'] == true);
    
    if (!hasCommander) {
      // Tenta detectar automaticamente um comandante baseado no tipo
      // Procura por Legendary Creature ou Planeswalker com "can be your commander"
      for (final card in cardsToInsert) {
        final typeLine = (card['type_line'] as String).toLowerCase();
        final isLegendaryCreature = typeLine.contains('legendary') && typeLine.contains('creature');
        
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

  for (final card in cardsToInsert) {
    final name = card['name'] as String;
    final typeLine = card['type_line'] as String;
    final quantity = card['quantity'] as int;
    final isBasicLand = typeLine.toLowerCase().contains('basic land');

    if (!isBasicLand && quantity > limit) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Regra violada: $name tem $quantity cópias (Limite: $limit).'},
      );
    }
    cardIdsToCheck.add(card['card_id'] as String);
  }

  if (cardIdsToCheck.isNotEmpty) {
    final legalityResult = await pool.execute(
      Sql.named(
        'SELECT c.name, cl.status FROM card_legalities cl JOIN cards c ON c.id = cl.card_id WHERE cl.card_id = ANY(@ids) AND cl.format = @format'
      ),
      parameters: {
        'ids': TypedValue(Type.textArray, cardIdsToCheck),
        'format': format,
      }
    );

    final bannedCards = <String>[];
    for (final row in legalityResult) {
      if (row[1] == 'banned') {
        bannedCards.add(row[0] as String);
      }
    }

    if (bannedCards.isNotEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'O deck contém cartas BANIDAS no formato $format: ${bannedCards.join(", ")}'},
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
      if (cardsToInsert.isNotEmpty) {
        final valueStrings = <String>[];
        final params = <String, dynamic>{
          'deckId': newDeckId,
        };

        for (var i = 0; i < cardsToInsert.length; i++) {
          final card = cardsToInsert[i];
          final pCardId = 'c$i';
          final pQty = 'q$i';
          final pCmdr = 'cmd$i';
          
          valueStrings.add('(@deckId, @$pCardId, @$pQty, @$pCmdr)');
          params[pCardId] = card['card_id'];
          params[pQty] = card['quantity'];
          params[pCmdr] = card['is_commander'] ?? false;
        }

        final sql = 'INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander) VALUES ${valueStrings.join(',')}';
        
        await session.execute(Sql.named(sql), parameters: params);
      }
      
      final deckMap = deckResult.first.toColumnMap();
      if (deckMap['created_at'] is DateTime) {
        deckMap['created_at'] = (deckMap['created_at'] as DateTime).toIso8601String();
      }
      return deckMap;
    });

    // Prepara warnings para a resposta
    final warnings = <String>[];
    
    // Verifica se é formato Commander/Brawl sem comandante detectado
    if ((format == 'commander' || format == 'brawl') && 
        !cardsToInsert.any((c) => c['is_commander'] == true)) {
      warnings.add('Nenhum comandante foi detectado. Considere marcar uma carta como comandante.');
    }

    final responseBody = {
      'deck': newDeck,
      'cards_imported': cardsToInsert.length,
      'not_found_lines': notFoundCards,
    };
    
    if (warnings.isNotEmpty) {
      responseBody['warnings'] = warnings;
    }

    return Response.json(body: responseBody);

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to import deck: $e'},
    );
  }
}
