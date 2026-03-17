import 'package:test/test.dart';

import '../lib/ai/optimization_validator.dart';
import '../routes/ai/optimize/index.dart' as optimize_route;

void main() {
  group('Optimization goal validation', () {
    late OptimizationValidator validator;

    setUp(() {
      validator = OptimizationValidator();
    });

    test(
        'aggro optimization closes with lower curve and stronger early pressure',
        () async {
      final originalDeck = _buildAggroOriginalDeck();
      final optimizedDeck = _buildAggroOptimizedDeck();
      final report = await validator.validate(
        originalDeck: originalDeck,
        optimizedDeck: optimizedDeck,
        removals: const [
          'Slow Titan Alpha',
          'Slow Titan Beta',
          'Slow Titan Gamma',
          'Slow Titan Delta',
        ],
        additions: const [
          'One-Drop Scout Alpha',
          'One-Drop Scout Beta',
          'One-Drop Scout Gamma',
          'One-Drop Scout Delta',
        ],
        commanders: const ['Aggro Test Commander'],
        archetype: 'aggro',
      );

      final pre = _analyzeDeck(originalDeck, const ['R']);
      final post = _analyzeDeck(optimizedDeck, const ['R']);
      final preAvg = _avgCmc(pre);
      final postAvg = _avgCmc(post);

      expect(post['detected_archetype'], equals('aggro'));
      expect(postAvg, lessThan(preAvg));
      expect(
        report.monteCarlo.after.turn2PlayRate,
        greaterThan(report.monteCarlo.before.turn2PlayRate),
      );
      expect(
        report.monteCarlo.after.consistencyScore,
        greaterThan(report.monteCarlo.before.consistencyScore),
      );
      expect(report.functional.questionable, equals(0));
      expect(report.verdict, isNot(equals('reprovado')));
    });

    test('control optimization fixes mana and preserves interaction density',
        () async {
      final originalDeck = _buildControlOriginalDeck();
      final optimizedDeck = _buildControlOptimizedDeck();
      final report = await validator.validate(
        originalDeck: originalDeck,
        optimizedDeck: optimizedDeck,
        removals: const [
          'Expensive Counter Alpha',
          'Expensive Counter Beta',
          'Expensive Removal Alpha',
          'Expensive Removal Beta',
          'Clunky Insight Alpha',
          'Clunky Insight Beta',
        ],
        additions: const [
          'Efficient Counter Alpha',
          'Efficient Counter Beta',
          'Efficient Removal Alpha',
          'Efficient Removal Beta',
          'Strategic Insight Alpha',
          'Strategic Insight Beta',
        ],
        commanders: const ['Control Test Commander'],
        archetype: 'control',
      );

      final pre = _analyzeDeck(originalDeck, const ['U', 'B']);
      final post = _analyzeDeck(optimizedDeck, const ['U', 'B']);
      final preTypes = _typeDistribution(pre);
      final postTypes = _typeDistribution(post);
      final preInteraction =
          (preTypes['instants'] ?? 0) + (preTypes['sorceries'] ?? 0);
      final postInteraction =
          (postTypes['instants'] ?? 0) + (postTypes['sorceries'] ?? 0);

      expect(pre['mana_base_assessment'], contains('Falta mana'));
      expect(post['mana_base_assessment'], equals('Base de mana equilibrada'));
      expect(post['detected_archetype'], equals('control'));
      expect(postInteraction, greaterThan(preInteraction));
      expect(
        report.functional.roleDelta['removal']! >= 0,
        isTrue,
      );
      expect(
        report.functional.roleDelta['draw']! >= 0,
        isTrue,
      );
      expect(report.verdict, isNot(equals('reprovado')));
    });

    test('midrange optimization reaches balanced curve and better consistency',
        () async {
      final originalDeck = _buildMidrangeOriginalDeck();
      final optimizedDeck = _buildMidrangeOptimizedDeck();
      final report = await validator.validate(
        originalDeck: originalDeck,
        optimizedDeck: optimizedDeck,
        removals: const [
          'Overcosted Removal Alpha',
          'Overcosted Removal Beta',
          'Slow Relic Alpha',
          'Slow Relic Beta',
          'Clunky Beast Alpha',
          'Clunky Beast Beta',
        ],
        additions: const [
          'Efficient Removal Alpha',
          'Efficient Removal Beta',
          'Ramp Growth Alpha',
          'Ramp Growth Beta',
          'Value Draw Alpha',
          'Value Draw Beta',
        ],
        commanders: const ['Midrange Test Commander'],
        archetype: 'midrange',
      );

      final pre = _analyzeDeck(originalDeck, const ['B', 'G']);
      final post = _analyzeDeck(optimizedDeck, const ['B', 'G']);
      final preAvg = _avgCmc(pre);
      final postAvg = _avgCmc(post);

      expect(post['detected_archetype'], equals('midrange'));
      expect(postAvg, inInclusiveRange(2.5, 3.5));
      expect(postAvg, lessThan(preAvg));
      expect(
        report.monteCarlo.after.consistencyScore,
        greaterThan(report.monteCarlo.before.consistencyScore),
      );
      expect(
        report.functional.roleDelta['removal']! >= 0,
        isTrue,
      );
      expect(
        report.functional.roleDelta['ramp']! >= 0,
        isTrue,
      );
      expect(report.verdict, isNot(equals('reprovado')));
    });
  });
}

Map<String, dynamic> _analyzeDeck(
  List<Map<String, dynamic>> deck,
  List<String> colors,
) {
  return optimize_route.DeckArchetypeAnalyzer(deck, colors).generateAnalysis();
}

double _avgCmc(Map<String, dynamic> analysis) {
  return double.tryParse(analysis['average_cmc']?.toString() ?? '0') ?? 0.0;
}

Map<String, int> _typeDistribution(Map<String, dynamic> analysis) {
  final raw = analysis['type_distribution'] as Map<String, dynamic>? ?? {};
  return raw.map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
}

Map<String, dynamic> _card({
  required String name,
  required String typeLine,
  required String manaCost,
  required double cmc,
  required String oracleText,
  required List<String> colors,
  int quantity = 1,
}) {
  return {
    'name': name,
    'type_line': typeLine,
    'mana_cost': manaCost,
    'cmc': cmc,
    'oracle_text': oracleText,
    'colors': colors,
    'quantity': quantity,
  };
}

Map<String, dynamic> _basicLand({
  required String name,
  required String symbol,
  required int quantity,
}) {
  return _card(
    name: name,
    typeLine: 'Basic Land — $name',
    manaCost: '',
    cmc: 0,
    oracleText: '{T}: Add {$symbol}.',
    colors: const [],
    quantity: quantity,
  );
}

Map<String, dynamic> _dualLand({
  required String name,
  required List<String> symbols,
  required int quantity,
}) {
  final manaText = symbols.map((symbol) => '{$symbol}').join(' or ');
  return _card(
    name: name,
    typeLine: 'Land',
    manaCost: '',
    cmc: 0,
    oracleText: '{T}: Add $manaText.',
    colors: const [],
    quantity: quantity,
  );
}

List<Map<String, dynamic>> _buildAggroOriginalDeck() {
  return [
    _basicLand(name: 'Mountain', symbol: 'R', quantity: 20),
    _card(
      name: 'Three-Drop Raider',
      typeLine: 'Creature — Warrior',
      manaCost: '{2}{R}',
      cmc: 3,
      oracleText: 'Haste.',
      colors: const ['R'],
      quantity: 12,
    ),
    _card(
      name: 'Two-Drop Berserker',
      typeLine: 'Creature — Berserker',
      manaCost: '{1}{R}',
      cmc: 2,
      oracleText: 'Whenever this attacks, it gets +1/+0 until end of turn.',
      colors: const ['R'],
      quantity: 8,
    ),
    _card(
      name: 'Incendiary Strike',
      typeLine: 'Instant',
      manaCost: '{1}{R}',
      cmc: 2,
      oracleText: 'Incendiary Strike deals 3 damage to any target.',
      colors: const ['R'],
      quantity: 8,
    ),
    _card(
      name: 'Battle Cry',
      typeLine: 'Sorcery',
      manaCost: '{1}{R}',
      cmc: 2,
      oracleText: 'Creatures you control get +1/+0 until end of turn.',
      colors: const ['R'],
      quantity: 8,
    ),
    _card(
      name: 'Slow Titan Alpha',
      typeLine: 'Creature — Giant',
      manaCost: '{4}{R}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['R'],
    ),
    _card(
      name: 'Slow Titan Beta',
      typeLine: 'Creature — Giant',
      manaCost: '{4}{R}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['R'],
    ),
    _card(
      name: 'Slow Titan Gamma',
      typeLine: 'Creature — Giant',
      manaCost: '{4}{R}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['R'],
    ),
    _card(
      name: 'Slow Titan Delta',
      typeLine: 'Creature — Giant',
      manaCost: '{4}{R}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['R'],
    ),
  ];
}

List<Map<String, dynamic>> _buildAggroOptimizedDeck() {
  return [
    _basicLand(name: 'Mountain', symbol: 'R', quantity: 22),
    _card(
      name: 'Three-Drop Raider',
      typeLine: 'Creature — Warrior',
      manaCost: '{2}{R}',
      cmc: 3,
      oracleText: 'Haste.',
      colors: const ['R'],
      quantity: 12,
    ),
    _card(
      name: 'Two-Drop Berserker',
      typeLine: 'Creature — Berserker',
      manaCost: '{1}{R}',
      cmc: 2,
      oracleText: 'Whenever this attacks, it gets +1/+0 until end of turn.',
      colors: const ['R'],
      quantity: 8,
    ),
    _card(
      name: 'Incendiary Strike',
      typeLine: 'Instant',
      manaCost: '{1}{R}',
      cmc: 2,
      oracleText: 'Incendiary Strike deals 3 damage to any target.',
      colors: const ['R'],
      quantity: 8,
    ),
    _card(
      name: 'Battle Cry',
      typeLine: 'Sorcery',
      manaCost: '{1}{R}',
      cmc: 2,
      oracleText: 'Creatures you control get +1/+0 until end of turn.',
      colors: const ['R'],
      quantity: 6,
    ),
    _card(
      name: 'One-Drop Scout Alpha',
      typeLine: 'Creature — Scout',
      manaCost: '{R}',
      cmc: 1,
      oracleText: 'Haste.',
      colors: const ['R'],
    ),
    _card(
      name: 'One-Drop Scout Beta',
      typeLine: 'Creature — Scout',
      manaCost: '{R}',
      cmc: 1,
      oracleText: 'Haste.',
      colors: const ['R'],
    ),
    _card(
      name: 'One-Drop Scout Gamma',
      typeLine: 'Creature — Scout',
      manaCost: '{R}',
      cmc: 1,
      oracleText: 'Haste.',
      colors: const ['R'],
    ),
    _card(
      name: 'One-Drop Scout Delta',
      typeLine: 'Creature — Scout',
      manaCost: '{R}',
      cmc: 1,
      oracleText: 'Haste.',
      colors: const ['R'],
    ),
  ];
}

List<Map<String, dynamic>> _buildControlOriginalDeck() {
  return [
    _basicLand(name: 'Island', symbol: 'U', quantity: 24),
    _card(
      name: 'Expensive Counter',
      typeLine: 'Instant',
      manaCost: '{2}{U}{U}',
      cmc: 4,
      oracleText: 'Counter target spell.',
      colors: const ['U'],
      quantity: 4,
    ),
    _card(
      name: 'Expensive Removal',
      typeLine: 'Instant',
      manaCost: '{2}{B}{B}',
      cmc: 4,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
      quantity: 4,
    ),
    _card(
      name: 'Clunky Insight',
      typeLine: 'Sorcery',
      manaCost: '{3}{U}{B}',
      cmc: 5,
      oracleText: 'Draw two cards.',
      colors: const ['U', 'B'],
      quantity: 6,
    ),
    _card(
      name: 'Control Finisher',
      typeLine: 'Creature — Sphinx',
      manaCost: '{3}{U}{U}',
      cmc: 5,
      oracleText: 'Flying.',
      colors: const ['U'],
      quantity: 16,
    ),
    _card(
      name: 'Expensive Counter Alpha',
      typeLine: 'Instant',
      manaCost: '{2}{U}{U}',
      cmc: 4,
      oracleText: 'Counter target spell.',
      colors: const ['U'],
    ),
    _card(
      name: 'Expensive Counter Beta',
      typeLine: 'Instant',
      manaCost: '{2}{U}{U}',
      cmc: 4,
      oracleText: 'Counter target spell.',
      colors: const ['U'],
    ),
    _card(
      name: 'Expensive Removal Alpha',
      typeLine: 'Instant',
      manaCost: '{2}{B}{B}',
      cmc: 4,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Expensive Removal Beta',
      typeLine: 'Instant',
      manaCost: '{2}{B}{B}',
      cmc: 4,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Clunky Insight Alpha',
      typeLine: 'Sorcery',
      manaCost: '{3}{U}{B}',
      cmc: 5,
      oracleText: 'Draw two cards.',
      colors: const ['U', 'B'],
    ),
    _card(
      name: 'Clunky Insight Beta',
      typeLine: 'Sorcery',
      manaCost: '{3}{U}{B}',
      cmc: 5,
      oracleText: 'Draw two cards.',
      colors: const ['U', 'B'],
    ),
  ];
}

List<Map<String, dynamic>> _buildControlOptimizedDeck() {
  return [
    _basicLand(name: 'Island', symbol: 'U', quantity: 14),
    _dualLand(
      name: 'Sunken Archive',
      symbols: const ['U', 'B'],
      quantity: 14,
    ),
    _card(
      name: 'Efficient Counter',
      typeLine: 'Instant',
      manaCost: '{U}{U}',
      cmc: 2,
      oracleText: 'Counter target spell.',
      colors: const ['U'],
      quantity: 6,
    ),
    _card(
      name: 'Efficient Removal',
      typeLine: 'Instant',
      manaCost: '{1}{B}',
      cmc: 2,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
      quantity: 6,
    ),
    _card(
      name: 'Strategic Insight',
      typeLine: 'Instant',
      manaCost: '{3}{U}',
      cmc: 4,
      oracleText: 'Draw two cards.',
      colors: const ['U'],
      quantity: 8,
    ),
    _card(
      name: 'Control Finisher',
      typeLine: 'Creature — Sphinx',
      manaCost: '{3}{U}{U}',
      cmc: 5,
      oracleText: 'Flying.',
      colors: const ['U'],
      quantity: 6,
    ),
    _card(
      name: 'Efficient Counter Alpha',
      typeLine: 'Instant',
      manaCost: '{U}{U}',
      cmc: 2,
      oracleText: 'Counter target spell.',
      colors: const ['U'],
    ),
    _card(
      name: 'Efficient Counter Beta',
      typeLine: 'Instant',
      manaCost: '{U}{U}',
      cmc: 2,
      oracleText: 'Counter target spell.',
      colors: const ['U'],
    ),
    _card(
      name: 'Efficient Removal Alpha',
      typeLine: 'Instant',
      manaCost: '{1}{B}',
      cmc: 2,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Efficient Removal Beta',
      typeLine: 'Instant',
      manaCost: '{1}{B}',
      cmc: 2,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Strategic Insight Alpha',
      typeLine: 'Instant',
      manaCost: '{3}{U}',
      cmc: 4,
      oracleText: 'Draw two cards.',
      colors: const ['U'],
    ),
    _card(
      name: 'Strategic Insight Beta',
      typeLine: 'Instant',
      manaCost: '{3}{U}',
      cmc: 4,
      oracleText: 'Draw two cards.',
      colors: const ['U'],
    ),
  ];
}

List<Map<String, dynamic>> _buildMidrangeOriginalDeck() {
  return [
    _basicLand(name: 'Forest', symbol: 'G', quantity: 15),
    _basicLand(name: 'Swamp', symbol: 'B', quantity: 15),
    _card(
      name: 'Clunky Beast',
      typeLine: 'Creature — Beast',
      manaCost: '{3}{B}{G}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['B', 'G'],
      quantity: 8,
    ),
    _card(
      name: 'Overcosted Removal',
      typeLine: 'Sorcery',
      manaCost: '{2}{B}{B}',
      cmc: 4,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
      quantity: 4,
    ),
    _card(
      name: 'Slow Relic',
      typeLine: 'Artifact',
      manaCost: '{4}',
      cmc: 4,
      oracleText: '{T}: Add {G}.',
      colors: const [],
      quantity: 4,
    ),
    _card(
      name: 'Midrange Utility',
      typeLine: 'Creature — Elf',
      manaCost: '{2}{G}{G}',
      cmc: 4,
      oracleText: 'When this enters, draw a card.',
      colors: const ['G'],
      quantity: 8,
    ),
    _card(
      name: 'Clunky Beast Alpha',
      typeLine: 'Creature — Beast',
      manaCost: '{3}{B}{G}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['B', 'G'],
    ),
    _card(
      name: 'Clunky Beast Beta',
      typeLine: 'Creature — Beast',
      manaCost: '{3}{B}{G}',
      cmc: 5,
      oracleText: 'Trample.',
      colors: const ['B', 'G'],
    ),
    _card(
      name: 'Overcosted Removal Alpha',
      typeLine: 'Sorcery',
      manaCost: '{2}{B}{B}',
      cmc: 4,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Overcosted Removal Beta',
      typeLine: 'Sorcery',
      manaCost: '{2}{B}{B}',
      cmc: 4,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Slow Relic Alpha',
      typeLine: 'Artifact',
      manaCost: '{4}',
      cmc: 4,
      oracleText: '{T}: Add {G}.',
      colors: const [],
    ),
    _card(
      name: 'Slow Relic Beta',
      typeLine: 'Artifact',
      manaCost: '{4}',
      cmc: 4,
      oracleText: '{T}: Add {G}.',
      colors: const [],
    ),
  ];
}

List<Map<String, dynamic>> _buildMidrangeOptimizedDeck() {
  return [
    _basicLand(name: 'Forest', symbol: 'G', quantity: 18),
    _basicLand(name: 'Swamp', symbol: 'B', quantity: 18),
    _card(
      name: 'Efficient Beater',
      typeLine: 'Creature — Beast',
      manaCost: '{1}{B}{G}',
      cmc: 3,
      oracleText: 'Trample.',
      colors: const ['B', 'G'],
      quantity: 10,
    ),
    _card(
      name: 'Efficient Removal',
      typeLine: 'Instant',
      manaCost: '{1}{B}',
      cmc: 2,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
      quantity: 4,
    ),
    _card(
      name: 'Ramp Growth',
      typeLine: 'Sorcery',
      manaCost: '{1}{G}',
      cmc: 2,
      oracleText:
          'Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.',
      colors: const ['G'],
      quantity: 2,
    ),
    _card(
      name: 'Value Draw',
      typeLine: 'Sorcery',
      manaCost: '{3}{G}',
      cmc: 4,
      oracleText: 'Draw two cards.',
      colors: const ['G'],
      quantity: 2,
    ),
    _card(
      name: 'Efficient Removal Alpha',
      typeLine: 'Instant',
      manaCost: '{1}{B}',
      cmc: 2,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Efficient Removal Beta',
      typeLine: 'Instant',
      manaCost: '{1}{B}',
      cmc: 2,
      oracleText: 'Destroy target creature.',
      colors: const ['B'],
    ),
    _card(
      name: 'Ramp Growth Alpha',
      typeLine: 'Sorcery',
      manaCost: '{1}{G}',
      cmc: 2,
      oracleText:
          'Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.',
      colors: const ['G'],
    ),
    _card(
      name: 'Ramp Growth Beta',
      typeLine: 'Sorcery',
      manaCost: '{1}{G}',
      cmc: 2,
      oracleText:
          'Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.',
      colors: const ['G'],
    ),
    _card(
      name: 'Value Draw Alpha',
      typeLine: 'Sorcery',
      manaCost: '{3}{G}',
      cmc: 4,
      oracleText: 'Draw two cards.',
      colors: const ['G'],
    ),
    _card(
      name: 'Value Draw Beta',
      typeLine: 'Sorcery',
      manaCost: '{3}{G}',
      cmc: 4,
      oracleText: 'Draw two cards.',
      colors: const ['G'],
    ),
  ];
}
