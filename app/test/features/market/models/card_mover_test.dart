import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/market/models/card_mover.dart';

void main() {
  group('CardMover Model', () {
    test('fromJson deve parsear corretamente com todos os campos', () {
      final json = {
        'card_id': 'c-1',
        'name': 'Black Lotus',
        'set_code': 'lea',
        'image_url': 'https://img.scryfall.com/bl.jpg',
        'rarity': 'rare',
        'type_line': 'Artifact',
        'price_today': 50000.00,
        'price_yesterday': 45000.00,
        'change_usd': 5000.00,
        'change_pct': 11.11,
      };

      final mover = CardMover.fromJson(json);

      expect(mover.cardId, 'c-1');
      expect(mover.name, 'Black Lotus');
      expect(mover.setCode, 'lea');
      expect(mover.rarity, 'rare');
      expect(mover.priceToday, 50000.00);
      expect(mover.priceYesterday, 45000.00);
      expect(mover.changeUsd, 5000.00);
      expect(mover.changePct, 11.11);
    });

    test('fromJson deve usar defaults para campos ausentes', () {
      final json = <String, dynamic>{};

      final mover = CardMover.fromJson(json);

      expect(mover.cardId, '');
      expect(mover.name, '');
      expect(mover.setCode, isNull);
      expect(mover.imageUrl, isNull);
      expect(mover.priceToday, 0.0);
      expect(mover.priceYesterday, 0.0);
      expect(mover.changeUsd, 0.0);
      expect(mover.changePct, 0.0);
    });

    test('isGainer retorna true para variação positiva', () {
      final mover = CardMover(
        cardId: 'c',
        name: 'Card',
        priceToday: 10,
        priceYesterday: 8,
        changeUsd: 2,
        changePct: 25,
      );

      expect(mover.isGainer, isTrue);
      expect(mover.isLoser, isFalse);
    });

    test('isLoser retorna true para variação negativa', () {
      final mover = CardMover(
        cardId: 'c',
        name: 'Card',
        priceToday: 8,
        priceYesterday: 10,
        changeUsd: -2,
        changePct: -20,
      );

      expect(mover.isGainer, isFalse);
      expect(mover.isLoser, isTrue);
    });

    test('sem variação não é gainer nem loser', () {
      final mover = CardMover(
        cardId: 'c',
        name: 'Card',
        priceToday: 10,
        priceYesterday: 10,
        changeUsd: 0,
        changePct: 0,
      );

      expect(mover.isGainer, isFalse);
      expect(mover.isLoser, isFalse);
    });
  });

  group('MarketMoversData Model', () {
    test('fromJson deve parsear gainers e losers corretamente', () {
      final json = {
        'date': '2025-01-30',
        'previous_date': '2025-01-29',
        'gainers': [
          {
            'card_id': 'g1',
            'name': 'Gainer Card',
            'price_today': 20.0,
            'price_yesterday': 15.0,
            'change_usd': 5.0,
            'change_pct': 33.33,
          },
        ],
        'losers': [
          {
            'card_id': 'l1',
            'name': 'Loser Card',
            'price_today': 10.0,
            'price_yesterday': 15.0,
            'change_usd': -5.0,
            'change_pct': -33.33,
          },
        ],
        'total_tracked': 5000,
      };

      final data = MarketMoversData.fromJson(json);

      expect(data.date, '2025-01-30');
      expect(data.previousDate, '2025-01-29');
      expect(data.gainers, hasLength(1));
      expect(data.gainers.first.name, 'Gainer Card');
      expect(data.losers, hasLength(1));
      expect(data.losers.first.name, 'Loser Card');
      expect(data.totalTracked, 5000);
      expect(data.hasData, isTrue);
      expect(data.needsMoreData, isFalse);
    });

    test('fromJson sem dados deve indicar needsMoreData quando há message', () {
      final json = {
        'gainers': <dynamic>[],
        'losers': <dynamic>[],
        'total_tracked': 0,
        'message': 'Aguardando dados de preço',
      };

      final data = MarketMoversData.fromJson(json);

      expect(data.hasData, isFalse);
      expect(data.needsMoreData, isTrue);
      expect(data.message, 'Aguardando dados de preço');
    });

    test('fromJson com listas null deve usar listas vazias', () {
      final json = <String, dynamic>{};

      final data = MarketMoversData.fromJson(json);

      expect(data.gainers, isEmpty);
      expect(data.losers, isEmpty);
      expect(data.totalTracked, 0);
      expect(data.hasData, isFalse);
    });
  });
}
