import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.post) {
    return _validateList(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

/// Valida uma lista de cartas sem criar o deck
/// Retorna quais cartas foram encontradas e quais não
Future<Response> _validateList(RequestContext context) async {
  final pool = context.read<Pool>();

  final body = await context.request.json();
  final format = body['format'] as String?;
  final rawList = body['list'];

  if (format == null || rawList == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Fields format and list are required.'},
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
  final lineRegex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');

  final foundCards = <Map<String, dynamic>>[];
  final notFoundLines = <String>[];
  final warnings = <String>[];

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
      notFoundLines.add(line);
    }
  }

  // 2. Busca em lote
  final foundCardsMap = <String, Map<String, dynamic>>{};
  
  if (namesToQuery.isNotEmpty) {
    final result = await pool.execute(
      Sql.named('SELECT id, name, type_line, image_url FROM cards WHERE lower(name) = ANY(@names)'),
      parameters: {'names': TypedValue(Type.textArray, namesToQuery.toList())},
    );
    for (final row in result) {
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

  // 3. Fallback para nomes com números
  final cleanNamesToQuery = <String>{};

  for (final item in parsedItems) {
    final nameLower = (item['name'] as String).toLowerCase();
    if (!foundCardsMap.containsKey(nameLower)) {
      final cleanName = (item['name'] as String).replaceAll(RegExp(r'\s+\d+$'), '');
      if (cleanName != item['name']) {
        item['cleanName'] = cleanName;
        cleanNamesToQuery.add(cleanName.toLowerCase());
      }
    }
  }

  if (cleanNamesToQuery.isNotEmpty) {
    final result = await pool.execute(
      Sql.named('SELECT id, name, type_line, image_url FROM cards WHERE lower(name) = ANY(@names)'),
      parameters: {'names': TypedValue(Type.textArray, cleanNamesToQuery.toList())},
    );
    for (final row in result) {
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

  // 4. Fallback para Split Cards
  final splitPatternsToQuery = <String>[];
  
  for (final item in parsedItems) {
     final nameKey = item['cleanName'] != null 
        ? (item['cleanName'] as String).toLowerCase() 
        : (item['name'] as String).toLowerCase();
     
     if (!foundCardsMap.containsKey(nameKey)) {
        splitPatternsToQuery.add('$nameKey // %');
     }
  }

  if (splitPatternsToQuery.isNotEmpty) {
      final result = await pool.execute(
        Sql.named('SELECT id, name, type_line, image_url FROM cards WHERE lower(name) LIKE ANY(@patterns)'),
        parameters: {'patterns': TypedValue(Type.textArray, splitPatternsToQuery)},
      );
      
      for (final row in result) {
        final id = row[0] as String;
        final dbName = row[1] as String;
        final typeLine = row[2] as String;
        final imageUrl = row[3] as String?;
        final dbNameLower = dbName.toLowerCase();
        
        final parts = dbNameLower.split(RegExp(r'\s*//\s*'));
        if (parts.isNotEmpty) {
            final prefix = parts[0].trim();
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
  }

  // 5. Montagem da lista de resultados
  for (final item in parsedItems) {
    if (notFoundLines.contains(item['line'])) continue;

    final nameKey = item['cleanName'] != null 
        ? (item['cleanName'] as String).toLowerCase() 
        : (item['name'] as String).toLowerCase();

    if (foundCardsMap.containsKey(nameKey)) {
      final cardData = foundCardsMap[nameKey]!;
      
      foundCards.add({
        'card_id': cardData['id'],
        'name': cardData['name'],
        'type_line': cardData['type_line'],
        'image_url': cardData['image_url'],
        'quantity': item['quantity'],
        'is_commander': item['isCommanderTag'],
        'original_line': item['line'],
      });
    } else {
      if (!notFoundLines.contains(item['line'])) {
        notFoundLines.add(item['line']);
      }
    }
  }

  // 6. Validações de regras
  final limit = (format == 'commander' || format == 'brawl') ? 1 : 4;
  
  for (final card in foundCards) {
    final name = card['name'] as String;
    final typeLine = card['type_line'] as String;
    final quantity = card['quantity'] as int;
    final isBasicLand = typeLine.toLowerCase().contains('basic land');

    if (!isBasicLand && quantity > limit) {
      warnings.add('$name tem $quantity cópias (limite: $limit)');
    }
  }

  // 7. Verifica banlist
  final cardIdsToCheck = foundCards.map((c) => c['card_id'] as String).toList();
  
  if (cardIdsToCheck.isNotEmpty) {
    final legalityResult = await pool.execute(
      Sql.named(
        'SELECT c.name, cl.status FROM card_legalities cl JOIN cards c ON c.id = cl.card_id WHERE cl.card_id = ANY(@ids) AND cl.format = @format'
      ),
      parameters: {
        'ids': TypedValue(Type.uuidArray, cardIdsToCheck),
        'format': format,
      }
    );

    for (final row in legalityResult) {
      if (row[1] == 'banned') {
        warnings.add('${row[0]} é BANIDA em $format');
      }
    }
  }

  // Total de cartas
  final totalCards = foundCards.fold<int>(0, (sum, c) => sum + (c['quantity'] as int));
  
  // Warnings de tamanho do deck
  if (format == 'commander' && totalCards != 100) {
    warnings.add('Deck de Commander deve ter exatamente 100 cartas (encontradas: $totalCards)');
  }

  return Response.json(body: {
    'found_cards': foundCards,
    'not_found_lines': notFoundLines,
    'warnings': warnings,
    'total_cards': totalCards,
    'total_unique': foundCards.length,
  });
}
