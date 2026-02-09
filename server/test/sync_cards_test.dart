import 'package:test/test.dart';

import '../lib/sync_cards_utils.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════
  // extractCardRow (AtomicCards)
  // ════════════════════════════════════════════════════════════════════════

  group('extractCardRow', () {
    test('extrai dados corretamente de uma carta válida', () {
      final printings = [
        {
          'name': 'Lightning Bolt',
          'manaCost': '{R}',
          'type': 'Instant',
          'text': 'Lightning Bolt deals 3 damage to any target.',
          'colors': ['R'],
          'colorIdentity': ['R'],
          'printings': ['LEA', 'M10', 'A25'],
          'rarity': 'common',
          'identifiers': {
            'scryfallOracleId': 'abc-123-def',
          },
        },
      ];

      final row = extractCardRow('Lightning Bolt', printings);

      expect(row, isNotNull);
      expect(row![0], 'abc-123-def'); // oracleId
      expect(row[1], 'Lightning Bolt'); // name
      expect(row[2], '{R}'); // manaCost
      expect(row[3], 'Instant'); // typeLine
      expect(row[4], 'Lightning Bolt deals 3 damage to any target.'); // text
      expect(row[5], ['R']); // colors
      expect(row[6], ['R']); // colorIdentity
      expect(row[7], contains('Lightning+Bolt')); // imageUrl encoded
      expect(row[7], contains('set=LEA')); // primeiro set
      expect(row[8], 'LEA'); // setCode
      expect(row[9], 'common'); // rarity
    });

    test('retorna null quando não tem scryfallOracleId', () {
      final printings = [
        {
          'name': 'Sem Id',
          'identifiers': {'mtgjsonId': 'xxx'},
        },
      ];

      final row = extractCardRow('Sem Id', printings);
      expect(row, isNull);
    });

    test('retorna null quando oracleId está vazio', () {
      final printings = [
        {
          'name': 'Vazio',
          'identifiers': {'scryfallOracleId': ''},
        },
      ];

      final row = extractCardRow('Vazio', printings);
      expect(row, isNull);
    });

    test('retorna null quando printings está vazia', () {
      final row = extractCardRow('Nada', []);
      expect(row, isNull);
    });

    test('retorna null quando printings contém tipos inválidos', () {
      final row = extractCardRow('Invalido', ['string', 42, true]);
      expect(row, isNull);
    });

    test('pula printings sem oracleId e usa a primeira válida', () {
      final printings = [
        {
          'name': 'Sem Id',
          'identifiers': {'mtgjsonId': 'aaa'},
        },
        {
          'name': 'Sol Ring',
          'manaCost': '{1}',
          'type': 'Artifact',
          'text': 'Tap: Add two colorless mana.',
          'colors': <String>[],
          'colorIdentity': <String>[],
          'printings': ['CMR'],
          'rarity': 'uncommon',
          'identifiers': {
            'scryfallOracleId': 'sol-ring-id',
          },
        },
      ];

      final row = extractCardRow('Sol Ring', printings);
      expect(row, isNotNull);
      expect(row![0], 'sol-ring-id');
      expect(row[1], 'Sol Ring');
    });

    test('usa cardName como fallback quando chosen não tem name', () {
      final printings = [
        {
          'identifiers': {'scryfallOracleId': 'abc'},
          'printings': ['SET1'],
        },
      ];

      final row = extractCardRow('Fallback Name', printings);
      expect(row, isNotNull);
      expect(row![1], 'Fallback Name');
    });

    test('gera imageUrl sem set param quando printings vazio', () {
      final printings = [
        {
          'name': 'No Set',
          'identifiers': {'scryfallOracleId': 'test-id'},
          'printings': <String>[],
        },
      ];

      final row = extractCardRow('No Set', printings);
      expect(row, isNotNull);
      final imageUrl = row![7] as String;
      expect(imageUrl, isNot(contains('set=')));
      expect(row[8], isNull); // setCode
    });

    test('campos opcionais são null quando ausentes', () {
      final printings = [
        {
          'identifiers': {'scryfallOracleId': 'minimal-id'},
        },
      ];

      final row = extractCardRow('Minimal Card', printings);
      expect(row, isNotNull);
      expect(row![2], isNull); // manaCost
      expect(row[3], isNull); // typeLine
      expect(row[4], isNull); // oracleText
      expect(row[5], <String>[]); // colors
      expect(row[6], <String>[]); // colorIdentity
      expect(row[9], isNull); // rarity
    });

    test('url encoda nomes com caracteres especiais', () {
      final printings = [
        {
          'name': "Urza's Tower",
          'identifiers': {'scryfallOracleId': 'urza-id'},
          'printings': ['ATQ'],
        },
      ];

      final row = extractCardRow("Urza's Tower", printings);
      expect(row, isNotNull);
      final imageUrl = row![7] as String;
      expect(imageUrl, contains('Urza%27s'));
    });

    test('cartas multicoloridas extraem arrays corretamente', () {
      final printings = [
        {
          'name': 'Nicol Bolas, the Ravager',
          'colors': ['B', 'R', 'U'],
          'colorIdentity': ['B', 'R', 'U'],
          'identifiers': {'scryfallOracleId': 'bolas-id'},
          'printings': ['M19'],
          'rarity': 'mythic',
        },
      ];

      final row = extractCardRow('Nicol Bolas, the Ravager', printings);
      expect(row, isNotNull);
      expect(row![5], ['B', 'R', 'U']);
      expect(row[6], ['B', 'R', 'U']);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // extractSetCardRow (Incremental)
  // ════════════════════════════════════════════════════════════════════════

  group('extractSetCardRow', () {
    test('extrai carta de set corretamente', () {
      final card = {
        'name': 'Mountain',
        'manaCost': null,
        'type': 'Basic Land — Mountain',
        'text': null,
        'colors': <String>[],
        'colorIdentity': ['R'],
        'rarity': 'common',
        'identifiers': {'scryfallOracleId': 'mountain-id'},
      };

      final row = extractSetCardRow(card, 'DSK');
      expect(row, isNotNull);
      expect(row![0], 'mountain-id');
      expect(row[1], 'Mountain');
      expect(row[8], 'DSK');
      expect(row[7], contains('set=DSK'));
    });

    test('retorna null sem oracleId', () {
      final card = {
        'name': 'No Id',
        'identifiers': {'mtgjsonId': 'xxx'},
      };
      expect(extractSetCardRow(card, 'SET'), isNull);
    });

    test('retorna null sem name', () {
      final card = {
        'identifiers': {'scryfallOracleId': 'valid-id'},
      };
      expect(extractSetCardRow(card, 'SET'), isNull);
    });

    test('retorna null com name vazio', () {
      final card = {
        'name': '',
        'identifiers': {'scryfallOracleId': 'valid-id'},
      };
      expect(extractSetCardRow(card, 'SET'), isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // getNewSetCodesSinceFromData
  // ════════════════════════════════════════════════════════════════════════

  group('getNewSetCodesSinceFromData', () {
    final setListData = [
      {'code': 'OLD', 'releaseDate': '2020-01-01'},
      {'code': 'MID', 'releaseDate': '2024-01-15'},
      {'code': 'NEW', 'releaseDate': '2025-06-01'},
      {'code': 'NEWEST', 'releaseDate': '2025-12-01'},
    ];

    test('retorna sets após a data de corte', () {
      final since = DateTime(2025, 1, 1);
      final codes = getNewSetCodesSinceFromData(setListData, since);

      expect(codes, containsAll(['NEW', 'NEWEST']));
      expect(codes, isNot(contains('OLD')));
    });

    test('retorna vazio quando todos os sets são antigos', () {
      final since = DateTime(2026, 1, 1);
      final codes = getNewSetCodesSinceFromData(setListData, since);
      expect(codes, isEmpty);
    });

    test('retorna todos quando a data é antiga', () {
      final since = DateTime(2019, 1, 1);
      final codes = getNewSetCodesSinceFromData(setListData, since);
      expect(codes, hasLength(4));
    });

    test('inclui buffer de 2 dias (sets lançados 2 dias antes do corte)', () {
      // since = 2025-06-02 → cutoff = 2025-05-31 → NEW (2025-06-01) está DEPOIS
      final since = DateTime(2025, 6, 2);
      final codes = getNewSetCodesSinceFromData(setListData, since);
      expect(codes, contains('NEW'));
    });

    test('filtra items sem code ou releaseDate', () {
      final data = [
        {'releaseDate': '2025-01-01'}, // sem code
        {'code': 'X'}, // sem releaseDate
        {'code': 'OK', 'releaseDate': '2025-01-01'},
      ];
      final codes = getNewSetCodesSinceFromData(data, DateTime(2024));
      expect(codes, equals(['OK']));
    });

    test('filtra items de tipo inválido', () {
      final data = [
        'string', 42, null,
        {'code': 'OK', 'releaseDate': '2025-01-01'},
      ];
      final codes = getNewSetCodesSinceFromData(data, DateTime(2024));
      expect(codes, equals(['OK']));
    });

    test('retorna lista ordenada', () {
      final data = [
        {'code': 'ZZZ', 'releaseDate': '2025-01-01'},
        {'code': 'AAA', 'releaseDate': '2025-01-01'},
        {'code': 'MMM', 'releaseDate': '2025-01-01'},
      ];
      final codes = getNewSetCodesSinceFromData(data, DateTime(2024));
      expect(codes, equals(['AAA', 'MMM', 'ZZZ']));
    });

    test('data com formato inválido é ignorada', () {
      final data = [
        {'code': 'BAD', 'releaseDate': 'not-a-date'},
        {'code': 'OK', 'releaseDate': '2025-06-01'},
      ];
      final codes = getNewSetCodesSinceFromData(data, DateTime(2024));
      expect(codes, equals(['OK']));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // parseSinceDays
  // ════════════════════════════════════════════════════════════════════════

  group('parseSinceDays', () {
    test('parseia --since-days=60 corretamente', () {
      expect(parseSinceDays(['--since-days=60']), 60);
    });

    test('parseia --since-days=1 corretamente', () {
      expect(parseSinceDays(['--since-days=1']), 1);
    });

    test('retorna null quando não fornecido', () {
      expect(parseSinceDays(['--full', '--force']), isNull);
    });

    test('retorna null para args vazios', () {
      expect(parseSinceDays([]), isNull);
    });

    test('retorna null para valor inválido', () {
      expect(parseSinceDays(['--since-days=abc']), isNull);
    });

    test('retorna null para valor zero', () {
      expect(parseSinceDays(['--since-days=0']), isNull);
    });

    test('retorna null para valor negativo', () {
      expect(parseSinceDays(['--since-days=-5']), isNull);
    });

    test('funciona com outros args antes e depois', () {
      expect(
        parseSinceDays(['--full', '--since-days=30', '--force']),
        30,
      );
    });

    test('usa primeiro match quando há múltiplos', () {
      expect(
        parseSinceDays(['--since-days=10', '--since-days=20']),
        10,
      );
    });

    test('ignora espaços ao redor do valor', () {
      expect(parseSinceDays(['--since-days= 45 ']), 45);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // extractOracleIds
  // ════════════════════════════════════════════════════════════════════════

  group('extractOracleIds', () {
    test('extrai oracle IDs únicos', () {
      final cards = [
        {'identifiers': {'scryfallOracleId': 'id-1'}},
        {'identifiers': {'scryfallOracleId': 'id-2'}},
        {'identifiers': {'scryfallOracleId': 'id-1'}}, // duplicata
      ];
      final ids = extractOracleIds(cards);
      expect(ids, hasLength(2));
      expect(ids, containsAll(['id-1', 'id-2']));
    });

    test('ignora cartas sem identifiers', () {
      final cards = <Map<String, dynamic>>[
        {'name': 'No Ids'},
        {'identifiers': {'scryfallOracleId': 'ok-id'}},
      ];
      final ids = extractOracleIds(cards);
      expect(ids, equals({'ok-id'}));
    });

    test('ignora oracleId vazio', () {
      final cards = [
        {'identifiers': {'scryfallOracleId': ''}},
        {'identifiers': {'scryfallOracleId': 'valid'}},
      ];
      final ids = extractOracleIds(cards);
      expect(ids, equals({'valid'}));
    });

    test('retorna vazio para lista vazia', () {
      expect(extractOracleIds([]), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // extractLegalities
  // ════════════════════════════════════════════════════════════════════════

  group('extractLegalities', () {
    test('extrai legalidades e converte para lowercase', () {
      final card = {
        'legalities': {
          'commander': 'Legal',
          'modern': 'Banned',
          'standard': 'Not Legal',
        },
      };
      final legalities = extractLegalities(card);
      expect(legalities, hasLength(3));
      expect(legalities[0].key, 'commander');
      expect(legalities[0].value, 'legal');
      expect(legalities[1].key, 'modern');
      expect(legalities[1].value, 'banned');
      expect(legalities[2].key, 'standard');
      expect(legalities[2].value, 'not legal');
    });

    test('retorna vazio quando sem legalities', () {
      final card = <String, dynamic>{'name': 'No Legalities'};
      expect(extractLegalities(card), isEmpty);
    });

    test('retorna vazio quando legalities é null', () {
      final card = <String, dynamic>{'legalities': null};
      expect(extractLegalities(card), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Testes de contrato de dados (invariantes)
  // ════════════════════════════════════════════════════════════════════════

  group('invariantes de dados', () {
    test('imageUrl sempre contém scryfall base URL', () {
      final printings = [
        {
          'name': 'Test Card',
          'identifiers': {'scryfallOracleId': 'test-id'},
          'printings': ['TST'],
        },
      ];
      final row = extractCardRow('Test Card', printings);
      expect(row, isNotNull);
      final url = row![7] as String;
      expect(url, startsWith('https://api.scryfall.com/cards/named?'));
      expect(url, contains('format=image'));
    });

    test('oracleId (row[0]) é sempre string não-vazia quando row não é null', () {
      final printings = [
        {
          'identifiers': {'scryfallOracleId': 'valid'},
        },
      ];
      final row = extractCardRow('X', printings);
      expect(row, isNotNull);
      expect(row![0], isA<String>());
      expect((row[0] as String).isNotEmpty, isTrue);
    });

    test('colors e colorIdentity são sempre List<String> não-null', () {
      final printings = [
        {
          'identifiers': {'scryfallOracleId': 'id'},
          // Sem colors e colorIdentity
        },
      ];
      final row = extractCardRow('X', printings);
      expect(row, isNotNull);
      expect(row![5], isA<List<String>>());
      expect(row[6], isA<List<String>>());
    });

    test('extractSetCardRow e extractCardRow geram imageUrls consistentes', () {
      final atomicPrintings = [
        {
          'name': 'Consistency',
          'identifiers': {'scryfallOracleId': 'cons-id'},
          'printings': ['ABC'],
          'manaCost': '{1}',
          'type': 'Instant',
          'colors': ['U'],
          'colorIdentity': ['U'],
          'rarity': 'common',
        },
      ];

      final setCard = {
        'name': 'Consistency',
        'identifiers': {'scryfallOracleId': 'cons-id'},
        'manaCost': '{1}',
        'type': 'Instant',
        'colors': ['U'],
        'colorIdentity': ['U'],
        'rarity': 'common',
      };

      final rowAtomic = extractCardRow('Consistency', atomicPrintings);
      final rowSet = extractSetCardRow(setCard, 'ABC');

      expect(rowAtomic, isNotNull);
      expect(rowSet, isNotNull);
      // Ambos devem conter o nome encodado
      final urlAtomic = rowAtomic![7] as String;
      final urlSet = rowSet![7] as String;
      expect(urlAtomic, contains('Consistency'));
      expect(urlSet, contains('Consistency'));
      expect(urlAtomic, contains('set=ABC'));
      expect(urlSet, contains('set=ABC'));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Stress / edge cases
  // ════════════════════════════════════════════════════════════════════════

  group('edge cases', () {
    test('carta com nome unicode', () {
      final printings = [
        {
          'name': 'Ælhão do Ébano',
          'identifiers': {'scryfallOracleId': 'unicode-id'},
          'printings': ['UNI'],
        },
      ];
      final row = extractCardRow('Ælhão do Ébano', printings);
      expect(row, isNotNull);
      expect(row![1], 'Ælhão do Ébano');
    });

    test('carta com nome muito longo', () {
      final longName = 'A' * 200;
      final printings = [
        {
          'name': longName,
          'identifiers': {'scryfallOracleId': 'long-id'},
          'printings': ['TST'],
        },
      ];
      final row = extractCardRow(longName, printings);
      expect(row, isNotNull);
      expect((row![1] as String).length, 200);
    });

    test('carta split com // no nome', () {
      final printings = [
        {
          'name': 'Fire // Ice',
          'identifiers': {'scryfallOracleId': 'split-id'},
          'printings': ['DMR'],
        },
      ];
      final row = extractCardRow('Fire // Ice', printings);
      expect(row, isNotNull);
      expect(row![1], 'Fire // Ice');
    });

    test('getNewSetCodesSinceFromData com centenas de sets não causa problema', () {
      final bigList = List.generate(1000, (i) => {
        'code': 'S${i.toString().padLeft(4, '0')}',
        'releaseDate': '2025-06-01',
      });
      final codes = getNewSetCodesSinceFromData(bigList, DateTime(2024));
      expect(codes, hasLength(1000));
      // Deve estar ordenado
      for (var i = 1; i < codes.length; i++) {
        expect(codes[i].compareTo(codes[i - 1]) >= 0, isTrue,
            reason: 'Lista deve estar ordenada');
      }
    });
  });
}
