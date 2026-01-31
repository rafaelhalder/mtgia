import 'dart:math';

import 'package:test/test.dart';

import '../lib/ai/goldfish_simulator.dart';

void main() {
  group('GoldfishSimulator', () {
    test('detects mana screw with few lands', () {
      // Deck com apenas 15 terrenos (muito poucos para Commander)
      final cards = [
        ..._generateLands(15),
        ..._generateSpells(85, avgCmc: 3),
      ];

      final simulator = GoldfishSimulator(cards, simulations: 500);
      final result = simulator.simulate();

      // Com poucos terrenos, screw rate deve ser significativo
      // e as recomendações devem mencionar terrenos
      expect(result.screwRate, greaterThan(0.05));
      expect(result.landCount, equals(15));
      expect(result.recommendations.any((r) => r.contains('terrenos')), isTrue);
    });

    test('detects mana flood with too many lands', () {
      // Deck com 50 terrenos (excessivo)
      final cards = [
        ..._generateLands(50),
        ..._generateSpells(50, avgCmc: 3),
      ];

      final simulator = GoldfishSimulator(cards, simulations: 500);
      final result = simulator.simulate();

      // Com muitos terrenos, flood rate deve ser alto e recomendações devem aparecer
      expect(result.landCount, equals(50));
      expect(result.recommendations.any((r) => r.contains('terrenos')), isTrue);
    });

    test('balanced deck has good consistency score', () {
      // Deck balanceado (36 terrenos, curva boa)
      final cards = [
        ..._generateLands(36),
        ..._generateSpells(10, avgCmc: 1), // 10 cartas de 1 CMC
        ..._generateSpells(15, avgCmc: 2), // 15 cartas de 2 CMC
        ..._generateSpells(15, avgCmc: 3), // 15 cartas de 3 CMC
        ..._generateSpells(14, avgCmc: 4), // 14 cartas de 4 CMC
        ..._generateSpells(10, avgCmc: 5), // 10 cartas de 5+ CMC
      ];

      final simulator = GoldfishSimulator(cards, simulations: 1000);
      final result = simulator.simulate();

      // Score deve ser razoável (>60)
      expect(result.consistencyScore, greaterThan(60));
      expect(result.keepableRate, greaterThan(0.70));
    });

    test('calculates CMC distribution correctly', () {
      final cards = [
        ..._generateLands(35),
        {'name': 'Sol Ring', 'cmc': 1, 'type_line': 'Artifact', 'quantity': 1},
        {'name': 'Arcane Signet', 'cmc': 2, 'type_line': 'Artifact', 'quantity': 1},
        {'name': 'Commander', 'cmc': 5, 'type_line': 'Legendary Creature', 'quantity': 1},
      ];

      final simulator = GoldfishSimulator(cards, simulations: 100);
      final result = simulator.simulate();

      expect(result.cmcDistribution[1], equals(1));
      expect(result.cmcDistribution[2], equals(1));
      expect(result.cmcDistribution[5], equals(1));
      expect(result.landCount, equals(35));
    });

    test('handles quantity correctly', () {
      final cards = [
        {'name': 'Island', 'type_line': 'Basic Land', 'quantity': 36},
        {'name': 'Counterspell', 'cmc': 2, 'type_line': 'Instant', 'oracle_text': 'Counter spell', 'quantity': 4},
      ];

      final simulator = GoldfishSimulator(cards, simulations: 100);
      final result = simulator.simulate();

      expect(result.landCount, equals(36));
    });

    test('generates meaningful recommendations', () {
      // Deck muito pesado
      final heavyDeck = [
        ..._generateLands(35),
        ..._generateSpells(65, avgCmc: 5),
      ];

      final simulator = GoldfishSimulator(heavyDeck, simulations: 500);
      final result = simulator.simulate();

      expect(result.avgCmc, greaterThan(4.0));
      expect(result.recommendations.any((r) => r.contains('CMC') || r.contains('lento')), isTrue);
    });

    test('turn play rates increase with turns', () {
      final cards = [
        ..._generateLands(36),
        ..._generateSpells(64, avgCmc: 3),
      ];

      final simulator = GoldfishSimulator(cards, simulations: 1000);
      final result = simulator.simulate();

      // Mais mana = mais chances de jogar
      expect(result.turn2PlayRate, greaterThanOrEqualTo(result.turn1PlayRate));
      expect(result.turn3PlayRate, greaterThanOrEqualTo(result.turn2PlayRate));
      expect(result.turn4PlayRate, greaterThanOrEqualTo(result.turn3PlayRate));
    });

    test('deterministic with fixed seed', () {
      final cards = [
        ..._generateLands(36),
        ..._generateSpells(64, avgCmc: 3),
      ];

      final sim1 = GoldfishSimulator(cards, simulations: 100, random: Random(42));
      final sim2 = GoldfishSimulator(cards, simulations: 100, random: Random(42));

      final result1 = sim1.simulate();
      final result2 = sim2.simulate();

      expect(result1.consistencyScore, equals(result2.consistencyScore));
      expect(result1.screwRate, equals(result2.screwRate));
    });
  });

  group('MatchupAnalyzer', () {
    test('faster deck has advantage', () {
      final fastDeck = [
        ..._generateLands(32),
        ..._generateSpells(68, avgCmc: 2),
      ];

      final slowDeck = [
        ..._generateLands(38),
        ..._generateSpells(62, avgCmc: 4),
      ];

      final result = MatchupAnalyzer.analyze(fastDeck, slowDeck);

      expect(result.winRateA, greaterThan(0.5));
      expect(result.notes.any((n) => n.contains('rápido')), isTrue);
    });

    test('removal helps against creature-heavy', () {
      final removalDeck = [
        ..._generateLands(35),
        ..._generateCardsWithText(30, 'destroy target creature'),
        ..._generateSpells(35, avgCmc: 3),
      ];

      final creatureDeck = [
        ..._generateLands(35),
        ..._generateCreatures(50),
        ..._generateSpells(15, avgCmc: 3),
      ];

      final result = MatchupAnalyzer.analyze(removalDeck, creatureDeck);

      expect(result.winRateA, greaterThan(0.5));
      expect(result.notes.any((n) => n.contains('remoç')), isTrue);
    });

    test('board wipes help against go-wide', () {
      final wipeDeck = [
        ..._generateLands(35),
        ..._generateCardsWithText(5, 'destroy all creatures'),
        ..._generateSpells(60, avgCmc: 3),
      ];

      final tokenDeck = [
        ..._generateLands(35),
        ..._generateCreatures(40),
        ..._generateSpells(25, avgCmc: 2),
      ];

      final result = MatchupAnalyzer.analyze(wipeDeck, tokenDeck);

      expect(result.winRateA, greaterThan(0.5));
    });

    test('returns stats for both decks', () {
      final deckA = [
        ..._generateLands(36),
        ..._generateSpells(64, avgCmc: 3),
      ];

      final deckB = [
        ..._generateLands(36),
        ..._generateSpells(64, avgCmc: 3),
      ];

      final result = MatchupAnalyzer.analyze(deckA, deckB);

      expect(result.statsA['land_count'], equals(36));
      expect(result.statsB['land_count'], equals(36));
      expect(result.statsA.containsKey('avg_cmc'), isTrue);
    });

    test('win rates are complementary', () {
      final deckA = _generateTypicalDeck();
      final deckB = _generateTypicalDeck();

      final result = MatchupAnalyzer.analyze(deckA, deckB);

      // Win rates devem somar aproximadamente 1.0
      expect(result.winRateA + result.winRateB, closeTo(1.0, 0.01));
    });
  });

  group('GoldfishResult', () {
    test('toJson includes all fields', () {
      final result = GoldfishResult(
        simulations: 1000,
        screwRate: 0.12,
        floodRate: 0.08,
        keepableRate: 0.80,
        turn1PlayRate: 0.45,
        turn2PlayRate: 0.82,
        turn3PlayRate: 0.94,
        turn4PlayRate: 0.98,
        avgCmc: 3.2,
        landCount: 36,
        cmcDistribution: {1: 10, 2: 15, 3: 20, 4: 12, 5: 7},
      );

      final json = result.toJson();

      expect(json['consistency_score'], isA<int>());
      expect(json['mana_analysis']['land_count'], equals(36));
      expect(json['curve_analysis']['avg_cmc'], equals(3.2));
      expect(json['recommendations'], isA<List>());
    });
  });
}

// === Helper functions ===

List<Map<String, dynamic>> _generateLands(int count) {
  return List.generate(count, (i) => {
    'name': 'Land $i',
    'type_line': 'Basic Land',
    'cmc': 0,
    'quantity': 1,
  });
}

List<Map<String, dynamic>> _generateSpells(int count, {required int avgCmc}) {
  return List.generate(count, (i) => {
    'name': 'Spell $i',
    'type_line': 'Instant',
    'cmc': avgCmc,
    'oracle_text': 'Do something.',
    'quantity': 1,
  });
}

List<Map<String, dynamic>> _generateCreatures(int count) {
  return List.generate(count, (i) => {
    'name': 'Creature $i',
    'type_line': 'Creature — Human',
    'cmc': 3,
    'oracle_text': '',
    'quantity': 1,
  });
}

List<Map<String, dynamic>> _generateCardsWithText(int count, String text) {
  return List.generate(count, (i) => {
    'name': 'Card $i',
    'type_line': 'Instant',
    'cmc': 3,
    'oracle_text': text,
    'quantity': 1,
  });
}

List<Map<String, dynamic>> _generateTypicalDeck() {
  return [
    ..._generateLands(36),
    ..._generateSpells(20, avgCmc: 2),
    ..._generateSpells(20, avgCmc: 3),
    ..._generateSpells(24, avgCmc: 4),
  ];
}
