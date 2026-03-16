import 'package:test/test.dart';

import '../lib/deck_rules_service.dart';
import '../lib/generated_deck_validation_service.dart';

void main() {
  group('GeneratedDeckValidationService', () {
    test('keeps a valid 60-card deck even when one unknown card is removed',
        () async {
      final service = GeneratedDeckValidationService(
        _FakeGeneratedDeckRepository(
          cardsByName: {
            'mountain': {'id': 'mountain-id', 'name': 'Mountain'},
          },
          suggestionsByName: {
            'Mountan': ['Mountain'],
          },
        ),
      );

      final result = await service.validate(
        format: 'standard',
        cards: [
          {'name': 'Mountain', 'quantity': 60},
          {'name': 'Mountan', 'quantity': 1},
        ],
      );

      expect(result.isValid, isTrue);
      expect(result.generatedDeck['commander'], isNull);
      expect(result.invalidCards, equals(['Mountan']));
      expect(result.suggestions['Mountan'], equals(['Mountain']));
      expect((result.generatedDeck['cards'] as List).single, {
        'name': 'Mountain',
        'quantity': 60,
      });
    });

    test('fails commander generation when commander field is missing',
        () async {
      final service = GeneratedDeckValidationService(
        _FakeGeneratedDeckRepository(
          cardsByName: {
            'plains': {'id': 'plains-id', 'name': 'Plains'},
          },
        ),
      );

      final result = await service.validate(
        format: 'commander',
        cards: [
          {'name': 'Plains', 'quantity': 99},
        ],
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors,
        contains(
            'Deck commander precisa de um comandante valido no campo "commander".'),
      );
    });

    test(
        'fails commander generation when unresolved cards break exact deck size',
        () async {
      final service = GeneratedDeckValidationService(
        _FakeGeneratedDeckRepository(
          cardsByName: {
            'isamaru, hound of konda': {
              'id': 'cmdr-id',
              'name': 'Isamaru, Hound of Konda',
            },
            'plains': {'id': 'plains-id', 'name': 'Plains'},
          },
          suggestionsByName: {
            'Plins': ['Plains'],
          },
        ),
      );

      final result = await service.validate(
        format: 'commander',
        commanderName: 'Isamaru, Hound of Konda',
        cards: [
          {'name': 'Plains', 'quantity': 98},
          {'name': 'Plins', 'quantity': 1},
        ],
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors,
        contains(
          'Regra violada: deck commander deve ter exatamente 100 cartas (atual: 99).',
        ),
      );
      expect(result.suggestions['Plins'], equals(['Plains']));
    });
  });
}

class _FakeGeneratedDeckRepository implements GeneratedDeckRepository {
  _FakeGeneratedDeckRepository({
    required this.cardsByName,
    this.suggestionsByName = const {},
  });

  final Map<String, Map<String, dynamic>> cardsByName;
  final Map<String, List<String>> suggestionsByName;

  @override
  Future<Map<String, List<String>>> findSuggestions(List<String> names) async {
    return {
      for (final name in names)
        if (suggestionsByName.containsKey(name)) name: suggestionsByName[name]!,
    };
  }

  @override
  Future<Map<String, Map<String, dynamic>>> resolveCardNames(
    List<Map<String, dynamic>> parsedItems,
  ) async {
    final resolved = <String, Map<String, dynamic>>{};

    for (final item in parsedItems) {
      final name = (item['name'] as String).trim().toLowerCase();
      final card = cardsByName[name];
      if (card != null) {
        resolved[name] = card;
      }
    }

    return resolved;
  }

  @override
  Future<void> validateDeck({
    required String format,
    required List<Map<String, dynamic>> cards,
  }) async {
    final normalizedFormat = format.trim().toLowerCase();
    final total =
        cards.fold<int>(0, (sum, card) => sum + (card['quantity'] as int));
    final commanders =
        cards.where((card) => card['is_commander'] == true).toList();

    if (normalizedFormat == 'commander') {
      if (commanders.isEmpty) {
        throw DeckRulesException(
          'Regra violada: deck commander precisa de 1 comandante selecionado.',
        );
      }
      if (total != 100) {
        throw DeckRulesException(
          'Regra violada: deck commander deve ter exatamente 100 cartas (atual: $total).',
        );
      }
      return;
    }

    if (normalizedFormat == 'brawl') {
      if (commanders.isEmpty) {
        throw DeckRulesException(
          'Regra violada: deck brawl precisa de 1 comandante selecionado.',
        );
      }
      if (total != 60) {
        throw DeckRulesException(
          'Regra violada: deck brawl deve ter exatamente 60 cartas (atual: $total).',
        );
      }
      return;
    }

    if (total < 60) {
      throw DeckRulesException(
        'Regra violada: deck $normalizedFormat precisa de pelo menos 60 cartas (atual: $total).',
      );
    }
  }
}
