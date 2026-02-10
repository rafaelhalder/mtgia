import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/decks/models/deck_details.dart';

void main() {
  group('DeckDetails Model', () {
    test('fromJson deve parsear deck completo com commander e main_board', () {
      final json = {
        'id': 'deck-1',
        'name': 'Krenko Goblins',
        'format': 'commander',
        'description': 'Deck de goblins agressivo',
        'archetype': 'aggro',
        'bracket': 2,
        'synergy_score': 85,
        'strengths': 'Rápido, explosivo',
        'weaknesses': 'Fraco contra board wipes',
        'is_public': true,
        'created_at': '2025-01-30T10:00:00Z',
        'commander': [
          {
            'id': 'card-krenko',
            'name': 'Krenko, Mob Boss',
            'type_line': 'Legendary Creature — Goblin Warrior',
            'mana_cost': '{2}{R}{R}',
            'colors': ['R'],
            'color_identity': ['R'],
            'set_code': 'dds',
            'rarity': 'rare',
            'quantity': 1,
            'is_commander': true,
            'image_url': 'https://img.scryfall.com/krenko.jpg',
          },
        ],
        'main_board': {
          'Creature': [
            {
              'id': 'card-1',
              'name': 'Goblin Guide',
              'type_line': 'Creature — Goblin Scout',
              'set_code': 'zen',
              'rarity': 'rare',
              'quantity': 1,
              'is_commander': false,
            },
          ],
          'Artifact': [
            {
              'id': 'card-2',
              'name': 'Sol Ring',
              'type_line': 'Artifact',
              'set_code': 'cmr',
              'rarity': 'uncommon',
              'quantity': 1,
              'is_commander': false,
            },
          ],
        },
        'stats': {
          'total_cards': 100,
          'avg_cmc': 2.8,
          'color_distribution': {'R': 60},
        },
      };

      final details = DeckDetails.fromJson(json);

      expect(details.id, 'deck-1');
      expect(details.name, 'Krenko Goblins');
      expect(details.format, 'commander');
      expect(details.description, 'Deck de goblins agressivo');
      expect(details.archetype, 'aggro');
      expect(details.bracket, 2);
      expect(details.synergyScore, 85);
      expect(details.isPublic, true);

      // Commander
      expect(details.commander, hasLength(1));
      expect(details.commander.first.name, 'Krenko, Mob Boss');
      expect(details.commander.first.isCommander, true);

      // Commander name/image inferred
      expect(details.commanderName, 'Krenko, Mob Boss');
      expect(details.commanderImageUrl, 'https://img.scryfall.com/krenko.jpg');

      // Main board
      expect(details.mainBoard.keys, containsAll(['Creature', 'Artifact']));
      expect(details.mainBoard['Creature'], hasLength(1));
      expect(details.mainBoard['Creature']!.first.name, 'Goblin Guide');
      expect(details.mainBoard['Artifact'], hasLength(1));
      expect(details.mainBoard['Artifact']!.first.name, 'Sol Ring');

      // Stats
      expect(details.cardCount, 100);
      expect(details.stats['avg_cmc'], 2.8);
    });

    test('fromJson deve lidar com campos mínimos sem commander', () {
      final json = {
        'id': 'deck-2',
        'name': 'Simple Deck',
        'format': 'standard',
        'is_public': false,
        'created_at': '2025-01-30T10:00:00Z',
      };

      final details = DeckDetails.fromJson(json);

      expect(details.id, 'deck-2');
      expect(details.name, 'Simple Deck');
      expect(details.format, 'standard');
      expect(details.commander, isEmpty);
      expect(details.mainBoard, isEmpty);
      expect(details.stats, isEmpty);
      expect(details.cardCount, 0);
      expect(details.commanderName, isNull);
      expect(details.commanderImageUrl, isNull);
    });

    test('fromJson deve usar commander_name explícito sobre inferido', () {
      final json = {
        'id': 'deck-3',
        'name': 'Test',
        'format': 'commander',
        'is_public': false,
        'created_at': '2025-01-30T10:00:00Z',
        'commander_name': 'Explicit Commander',
        'commander_image_url': 'https://explicit.url',
        'commander': [
          {
            'id': 'card-x',
            'name': 'Inferred Commander',
            'type_line': 'Legendary Creature',
            'set_code': 'xxx',
            'rarity': 'mythic',
            'quantity': 1,
            'is_commander': true,
            'image_url': 'https://inferred.url',
          },
        ],
      };

      final details = DeckDetails.fromJson(json);

      expect(details.commanderName, 'Explicit Commander');
      expect(details.commanderImageUrl, 'https://explicit.url');
    });

    test('fromJson deve parsear pricing data', () {
      final json = {
        'id': 'deck-4',
        'name': 'Priced Deck',
        'format': 'modern',
        'is_public': true,
        'created_at': '2025-01-30T10:00:00Z',
        'pricing_currency': 'USD',
        'pricing_total': 350.50,
        'pricing_missing_cards': 3,
        'pricing_updated_at': '2025-01-29T12:00:00Z',
      };

      final details = DeckDetails.fromJson(json);

      expect(details.pricingCurrency, 'USD');
      expect(details.pricingTotal, 350.50);
      expect(details.pricingMissingCards, 3);
      expect(details.pricingUpdatedAt, isNotNull);
    });

    test('copyWith deve substituir campos específicos', () {
      final original = DeckDetails(
        id: 'deck-1',
        name: 'Original',
        format: 'commander',
        isPublic: false,
        createdAt: DateTime(2025, 1, 30),
        stats: {},
        commander: [],
        mainBoard: {},
      );

      final updated = original.copyWith(
        name: 'Updated',
        isPublic: true,
        synergyScore: 90,
      );

      expect(updated.id, 'deck-1');
      expect(updated.name, 'Updated');
      expect(updated.format, 'commander');
      expect(updated.isPublic, true);
      expect(updated.synergyScore, 90);
    });
  });
}
