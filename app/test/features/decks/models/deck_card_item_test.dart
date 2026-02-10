import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/decks/models/deck_card_item.dart';

void main() {
  group('CardCondition', () {
    test('fromCode deve retornar a condição correta', () {
      expect(CardCondition.fromCode('NM'), CardCondition.nm);
      expect(CardCondition.fromCode('LP'), CardCondition.lp);
      expect(CardCondition.fromCode('MP'), CardCondition.mp);
      expect(CardCondition.fromCode('HP'), CardCondition.hp);
      expect(CardCondition.fromCode('DMG'), CardCondition.dmg);
    });

    test('fromCode deve ser case-insensitive', () {
      expect(CardCondition.fromCode('nm'), CardCondition.nm);
      expect(CardCondition.fromCode('lp'), CardCondition.lp);
      expect(CardCondition.fromCode('Hp'), CardCondition.hp);
    });

    test('fromCode null deve retornar NM como default', () {
      expect(CardCondition.fromCode(null), CardCondition.nm);
    });

    test('fromCode desconhecido deve retornar NM como default', () {
      expect(CardCondition.fromCode('XYZ'), CardCondition.nm);
    });

    test('code e label devem estar corretos', () {
      expect(CardCondition.nm.code, 'NM');
      expect(CardCondition.nm.label, 'Near Mint');
      expect(CardCondition.dmg.code, 'DMG');
      expect(CardCondition.dmg.label, 'Damaged');
    });
  });

  group('DeckCardItem Model', () {
    test('fromJson deve parsear corretamente com todos os campos', () {
      final json = {
        'id': 'card-1',
        'name': 'Sol Ring',
        'mana_cost': '{1}',
        'type_line': 'Artifact',
        'oracle_text': '{T}: Add {C}{C}.',
        'colors': <dynamic>[],
        'color_identity': <dynamic>[],
        'image_url': 'https://img.scryfall.com/sol-ring.jpg',
        'set_code': 'cmr',
        'set_name': 'Commander Legends',
        'set_release_date': '2020-11-20',
        'rarity': 'uncommon',
        'quantity': 1,
        'is_commander': false,
        'collector_number': '331',
        'foil': true,
        'condition': 'LP',
      };

      final card = DeckCardItem.fromJson(json);

      expect(card.id, 'card-1');
      expect(card.name, 'Sol Ring');
      expect(card.manaCost, '{1}');
      expect(card.typeLine, 'Artifact');
      expect(card.oracleText, '{T}: Add {C}{C}.');
      expect(card.colors, isEmpty);
      expect(card.colorIdentity, isEmpty);
      expect(card.imageUrl, 'https://img.scryfall.com/sol-ring.jpg');
      expect(card.setCode, 'cmr');
      expect(card.setName, 'Commander Legends');
      expect(card.setReleaseDate, '2020-11-20');
      expect(card.rarity, 'uncommon');
      expect(card.quantity, 1);
      expect(card.isCommander, false);
      expect(card.collectorNumber, '331');
      expect(card.foil, true);
      expect(card.condition, CardCondition.lp);
    });

    test('fromJson deve usar defaults para campos ausentes', () {
      final json = {
        'id': 'card-2',
        'name': 'Island',
      };

      final card = DeckCardItem.fromJson(json);

      expect(card.id, 'card-2');
      expect(card.name, 'Island');
      expect(card.manaCost, isNull);
      expect(card.typeLine, '');
      expect(card.oracleText, isNull);
      expect(card.colors, isEmpty);
      expect(card.colorIdentity, isEmpty);
      expect(card.imageUrl, isNull);
      expect(card.setCode, '');
      expect(card.rarity, '');
      expect(card.quantity, 1);
      expect(card.isCommander, false);
      expect(card.foil, isNull);
      expect(card.condition, CardCondition.nm);
    });

    test('fromJson deve parsear arrays de cores corretamente', () {
      final json = {
        'id': 'card-3',
        'name': 'Teferi',
        'colors': ['W', 'U'],
        'color_identity': ['W', 'U'],
      };

      final card = DeckCardItem.fromJson(json);

      expect(card.colors, ['W', 'U']);
      expect(card.colorIdentity, ['W', 'U']);
    });

    test('copyWith deve substituir apenas os campos especificados', () {
      final card = DeckCardItem(
        id: 'card-1',
        name: 'Sol Ring',
        typeLine: 'Artifact',
        setCode: 'cmr',
        rarity: 'uncommon',
        quantity: 1,
        isCommander: false,
      );

      final updated = card.copyWith(
        quantity: 4,
        isCommander: true,
        condition: CardCondition.hp,
      );

      expect(updated.id, 'card-1');
      expect(updated.name, 'Sol Ring');
      expect(updated.quantity, 4);
      expect(updated.isCommander, true);
      expect(updated.condition, CardCondition.hp);
    });
  });
}
