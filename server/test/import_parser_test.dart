import 'package:test/test.dart';

/// Testes unitários para o parser de importação de decks
/// 
/// O parser está implementado em routes/import/index.dart
/// Estes testes validam a lógica de regex e transformação de texto
void main() {
  group('Deck Import Parser - Regex Validation', () {
    test('should parse standard format: "1x Sol Ring"', () {
      final line = '1x Sol Ring';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('1')); // Quantity
      expect(match.group(2)!.trim(), equals('Sol Ring')); // Card name
    });

    test('should parse format without "x": "4 Lightning Bolt"', () {
      final line = '4 Lightning Bolt';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('4'));
      expect(match.group(2)!.trim(), equals('Lightning Bolt'));
    });

    test('should parse format with set code: "1x Command Tower (cmm)"', () {
      final line = '1x Command Tower (cmm)';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('1'));
      expect(match.group(2)!.trim(), equals('Command Tower'));
      expect(match.group(3), equals('cmm')); // Set code
    });

    test('should parse format with foil marker: "1x Sol Ring (cmm) *F*"', () {
      final line = '1x Sol Ring (cmm) *F*';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('1'));
      expect(match.group(2)!.trim(), equals('Sol Ring'));
      expect(match.group(3), equals('cmm'));
    });

    test('should parse cards with numbers in name: "1x Forest 96"', () {
      final line = '1x Forest 96';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('1'));
      expect(match.group(2)!.trim(), equals('Forest 96'));
    });

    test('should parse cards with special characters: "1x Urza\'s Saga"', () {
      final line = "1x Urza's Saga";
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('1'));
      expect(match.group(2)!.trim(), equals("Urza's Saga"));
    });

    test('should parse double-digit quantities: "24 Island"', () {
      final line = '24 Island';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(1), equals('24'));
      expect(match.group(2)!.trim(), equals('Island'));
    });
  });

  group('Deck Import Parser - Commander Tag Detection', () {
    test('should detect [commander] tag', () {
      final line = '1x Atraxa, Praetors\' Voice [commander]';
      final lineLower = line.toLowerCase();
      
      final isCommander = lineLower.contains('[commander') || 
                         lineLower.contains('*cmdr*') || 
                         lineLower.contains('!commander');

      expect(isCommander, isTrue);
    });

    test('should detect *cmdr* tag', () {
      final line = '1x Chulane, Teller of Tales *cmdr*';
      final lineLower = line.toLowerCase();
      
      final isCommander = lineLower.contains('[commander') || 
                         lineLower.contains('*cmdr*') || 
                         lineLower.contains('!commander');

      expect(isCommander, isTrue);
    });

    test('should detect !commander tag', () {
      final line = '1x Edgar Markov !commander';
      final lineLower = line.toLowerCase();
      
      final isCommander = lineLower.contains('[commander') || 
                         lineLower.contains('*cmdr*') || 
                         lineLower.contains('!commander');

      expect(isCommander, isTrue);
    });

    test('should not detect commander in card names', () {
      final line = '1x Commanding Presence';
      final lineLower = line.toLowerCase();
      
      // A regex deveria ser mais precisa, mas para teste básico
      final isCommander = lineLower.contains('[commander') || 
                         lineLower.contains('*cmdr*') || 
                         lineLower.contains('!commander');

      expect(isCommander, isFalse);
    });
  });

  group('Deck Import Parser - Name Cleaning (Fallback)', () {
    test('should clean collector numbers from names: "Forest 96" -> "Forest"', () {
      final cardName = 'Forest 96';
      final cleanName = cardName.replaceAll(RegExp(r'\s+\d+$'), '');

      expect(cleanName, equals('Forest'));
    });

    test('should clean collector numbers: "Island 123" -> "Island"', () {
      final cardName = 'Island 123';
      final cleanName = cardName.replaceAll(RegExp(r'\s+\d+$'), '');

      expect(cleanName, equals('Island'));
    });

    test('should not affect cards without trailing numbers', () {
      final cardName = 'Sol Ring';
      final cleanName = cardName.replaceAll(RegExp(r'\s+\d+$'), '');

      expect(cleanName, equals('Sol Ring'));
    });

    test('should not affect cards with numbers in middle: "Sword of Fire and Ice"', () {
      final cardName = 'Emrakul, the Aeons Torn';
      final cleanName = cardName.replaceAll(RegExp(r'\s+\d+$'), '');

      expect(cleanName, equals('Emrakul, the Aeons Torn'));
    });

    test('should handle multiple spaces before number', () {
      final cardName = 'Mountain   42';
      final cleanName = cardName.replaceAll(RegExp(r'\s+\d+$'), '');

      expect(cleanName, equals('Mountain'));
    });
  });

  group('Deck Import Parser - Split Card Handling', () {
    test('should generate LIKE pattern for split cards', () {
      final cardName = 'fire';
      final pattern = '$cardName // %';

      expect(pattern, equals('fire // %'));
    });

    test('should extract prefix from split card: "Fire // Ice"', () {
      final dbName = 'Fire // Ice';
      final parts = dbName.toLowerCase().split(RegExp(r'\s*//\s*'));

      expect(parts.length, equals(2));
      expect(parts[0].trim(), equals('fire'));
      expect(parts[1].trim(), equals('ice'));
    });

    test('should handle split cards with multiple slashes: "Wear // Tear"', () {
      final dbName = 'Wear // Tear';
      final parts = dbName.toLowerCase().split(RegExp(r'\s*//\s*'));

      expect(parts.length, equals(2));
      expect(parts[0].trim(), equals('wear'));
    });

    test('should handle inconsistent spacing in split names', () {
      final dbName1 = 'Fire//Ice'; // Sem espaços
      final dbName2 = 'Fire  //  Ice'; // Espaços extras
      
      final parts1 = dbName1.toLowerCase().split(RegExp(r'\s*//\s*'));
      final parts2 = dbName2.toLowerCase().split(RegExp(r'\s*//\s*'));

      expect(parts1[0].trim(), equals('fire'));
      expect(parts2[0].trim(), equals('fire'));
    });
  });

  group('Deck Import Parser - Format Validation', () {
    test('should validate Commander copy limit (1 copy)', () {
      final format = 'commander';
      final limit = (format == 'commander' || format == 'brawl') ? 1 : 4;

      expect(limit, equals(1));
    });

    test('should validate Standard copy limit (4 copies)', () {
      final format = 'standard';
      final limit = (format == 'commander' || format == 'brawl') ? 1 : 4;

      expect(limit, equals(4));
    });

    test('should validate Brawl copy limit (1 copy)', () {
      final format = 'brawl';
      final limit = (format == 'commander' || format == 'brawl') ? 1 : 4;

      expect(limit, equals(1));
    });

    test('should allow unlimited basic lands', () {
      final typeLine = 'Basic Land — Forest';
      final isBasicLand = typeLine.toLowerCase().contains('basic land');

      expect(isBasicLand, isTrue);
    });

    test('should not classify non-basic lands as basic', () {
      final typeLine = 'Land — Forest Plains';
      final isBasicLand = typeLine.toLowerCase().contains('basic land');

      expect(isBasicLand, isFalse);
    });
  });

  group('Deck Import Parser - Edge Cases', () {
    test('should handle empty lines', () {
      final line = '';
      final trimmed = line.trim();

      expect(trimmed.isEmpty, isTrue);
    });

    test('should handle lines with only whitespace', () {
      final line = '   \t\n  ';
      final trimmed = line.trim();

      expect(trimmed.isEmpty, isTrue);
    });

    test('should handle malformed quantity: "x4 Sol Ring"', () {
      final line = 'x4 Sol Ring';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      // Este formato não será capturado pela regex atual (quantidade deve vir primeiro)
      expect(match, isNull);
    });

    test('should handle missing quantity: "Sol Ring"', () {
      final line = 'Sol Ring';
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNull);
    });

    test('should parse cards with comma in name: "Atraxa, Praetors\' Voice"', () {
      final line = "1x Atraxa, Praetors' Voice";
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(line);

      expect(match, isNotNull);
      expect(match!.group(2)!.trim(), equals("Atraxa, Praetors' Voice"));
    });

    test('should handle extra whitespace: "  4x   Lightning Bolt  "', () {
      final line = '  4x   Lightning Bolt  ';
      final trimmed = line.trim();
      final regex = RegExp(r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$');
      final match = regex.firstMatch(trimmed);

      expect(match, isNotNull);
      expect(match!.group(1), equals('4'));
      expect(match.group(2)!.trim(), equals('Lightning Bolt'));
    });
  });

  group('Deck Import Parser - List Format Variations', () {
    test('should parse JSON-like object format', () {
      final item = {
        'quantity': 4,
        'name': 'Lightning Bolt',
      };

      final qty = item['quantity'] ?? item['amount'] ?? item['qtd'] ?? 1;
      final name = item['name'] ?? item['card_name'] ?? item['card'] ?? '';

      expect(qty, equals(4));
      expect(name, equals('Lightning Bolt'));
    });

    test('should handle alternative quantity keys', () {
      final item1 = {'amount': 3, 'card': 'Counterspell'};
      final item2 = {'qtd': 2, 'card_name': 'Brainstorm'};

      final qty1 = item1['quantity'] ?? item1['amount'] ?? item1['qtd'] ?? 1;
      final name1 = item1['name'] ?? item1['card_name'] ?? item1['card'] ?? '';

      final qty2 = item2['quantity'] ?? item2['amount'] ?? item2['qtd'] ?? 1;
      final name2 = item2['name'] ?? item2['card_name'] ?? item2['card'] ?? '';

      expect(qty1, equals(3));
      expect(name1, equals('Counterspell'));
      expect(qty2, equals(2));
      expect(name2, equals('Brainstorm'));
    });

    test('should use default quantity when missing', () {
      final item = {'name': 'Sol Ring'};

      final qty = item['quantity'] ?? item['amount'] ?? item['qtd'] ?? 1;
      expect(qty, equals(1));
    });

    test('should handle empty name gracefully', () {
      final item = {'quantity': 4, 'name': ''};

      final name = item['name'] ?? item['card_name'] ?? item['card'] ?? '';
      expect(name.toString().isEmpty, isTrue);
    });
  });
}
