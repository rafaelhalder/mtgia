import 'package:test/test.dart';

import '../lib/ai/goldfish_simulator.dart';
import '../lib/ai/optimization_quality_gate.dart';
import '../lib/ai/optimization_validator.dart';

void main() {
  group('Optimization quality gate', () {
    test('drops unsafe off-role swaps for aggro and keeps safe ramp upgrade',
        () {
      final originalDeck = [
        _card(
          name: 'Chaos Warp',
          typeLine: 'Instant',
          manaCost: '{2}{R}',
          cmc: 3,
          oracleText:
              'The owner of target permanent shuffles it into their library.',
        ),
        _card(
          name: 'Brightstone Ritual',
          typeLine: 'Instant',
          manaCost: '{R}',
          cmc: 1,
          oracleText: 'Add {R} for each Goblin on the battlefield.',
        ),
        _card(
          name: 'Rakdos Signet',
          typeLine: 'Artifact',
          manaCost: '{2}',
          cmc: 2,
          oracleText: '{1}, {T}: Add {B}{R}.',
        ),
      ];

      final additions = [
        _card(
          name: 'Skinrender',
          typeLine: 'Creature',
          manaCost: '{2}{B}{B}',
          cmc: 4,
          oracleText:
              'When this enters, put three -1/-1 counters on target creature.',
        ),
        _card(
          name: 'Glissa Sunslayer',
          typeLine: 'Legendary Creature',
          manaCost: '{1}{B}{G}',
          cmc: 3,
          oracleText: 'First strike, deathtouch.',
        ),
        _card(
          name: 'Devoted Druid',
          typeLine: 'Creature',
          manaCost: '{1}{G}',
          cmc: 2,
          oracleText:
              '{T}: Add {G}. Put a -1/-1 counter on Devoted Druid: Untap Devoted Druid.',
        ),
      ];

      final result = filterUnsafeOptimizeSwapsByCardData(
        removals: const ['Chaos Warp', 'Brightstone Ritual', 'Rakdos Signet'],
        additions: const ['Skinrender', 'Glissa Sunslayer', 'Devoted Druid'],
        originalDeck: originalDeck,
        additionsData: additions,
        archetype: 'aggro',
      );

      expect(result.removals, equals(const ['Rakdos Signet']));
      expect(result.additions, equals(const ['Devoted Druid']));
      expect(result.droppedReasons, hasLength(2));
    });

    test('builds rejection reasons for reprovado midrange optimization', () {
      final validation = ValidationReport(
        score: 25,
        verdict: 'reprovado',
        monteCarlo: MonteCarloComparison(
          before: _goldfish(keepableRate: 0.84, turn2PlayRate: 0.9),
          after: _goldfish(keepableRate: 0.82, turn2PlayRate: 0.88),
          beforeMulligan: _mulligan(),
          afterMulligan: _mulligan(),
        ),
        functional: FunctionalReport(
          swaps: const [],
          upgrades: 0,
          sidegrades: 0,
          tradeoffs: 1,
          questionable: 3,
          roleDelta: const {
            'removal': -1,
            'ramp': -1,
          },
        ),
        warnings: const [],
      );

      final reasons = buildOptimizationRejectionReasons(
        validationReport: validation,
        archetype: 'midrange',
        preCurve: 3.0,
        postCurve: 3.2,
        preManaAssessment: 'Base de mana equilibrada',
        postManaAssessment: 'Base de mana equilibrada',
      );

      expect(reasons, isNotEmpty);
      expect(
        reasons.any((reason) => reason.contains('reprovou')),
        isTrue,
      );
      expect(
        reasons.any((reason) => reason.contains('"removal"')),
        isTrue,
      );
      expect(
        reasons.any((reason) => reason.contains('"ramp"')),
        isTrue,
      );
    });

    test(
        'rejects optimize success when validation still has warnings and no material gain',
        () {
      final validation = ValidationReport(
        score: 63,
        verdict: 'aprovado_com_ressalvas',
        monteCarlo: MonteCarloComparison(
          before: _goldfish(
            keepableRate: 0.84,
            turn2PlayRate: 0.20,
            screwRate: 0.30,
          ),
          after: _goldfish(
            keepableRate: 0.84,
            turn2PlayRate: 0.20,
            screwRate: 0.30,
          ),
          beforeMulligan: _mulligan(keepAt7Rate: 0.10),
          afterMulligan: _mulligan(keepAt7Rate: 0.10),
        ),
        functional: FunctionalReport(
          swaps: const [],
          upgrades: 1,
          sidegrades: 0,
          tradeoffs: 0,
          questionable: 0,
          roleDelta: const {'removal': 0, 'ramp': 0, 'draw': 0},
        ),
        critic: const {
          'approval_score': 55,
          'verdict': 'aprovado_com_ressalvas',
        },
        warnings: const [],
      );

      final reasons = buildOptimizationRejectionReasons(
        validationReport: validation,
        archetype: 'midrange',
        preCurve: 3.0,
        postCurve: 3.0,
        preManaAssessment: 'Falta mana U (Tem 0 fontes, ideal > 15)',
        postManaAssessment: 'Falta mana U (Tem 1 fontes, ideal > 15)',
      );
      final normalizedReasons =
          reasons.map((reason) => reason.toLowerCase()).toList();

      expect(
        normalizedReasons.any((reason) => reason.contains('fechou como')),
        isTrue,
      );
      expect(
        normalizedReasons
            .any((reason) => reason.contains('base de mana continua')),
        isTrue,
      );
      expect(
        normalizedReasons.any((reason) => reason.contains('approval_score')),
        isTrue,
      );
    });

    test('does not reject when validation is approved with clear improvement',
        () {
      final validation = ValidationReport(
        score: 78,
        verdict: 'aprovado',
        monteCarlo: MonteCarloComparison(
          before: _goldfish(
            keepableRate: 0.72,
            turn2PlayRate: 0.58,
            screwRate: 0.18,
          ),
          after: _goldfish(
            keepableRate: 0.78,
            turn2PlayRate: 0.66,
            screwRate: 0.12,
          ),
          beforeMulligan: _mulligan(keepAt7Rate: 0.68),
          afterMulligan: _mulligan(keepAt7Rate: 0.74),
        ),
        functional: FunctionalReport(
          swaps: const [],
          upgrades: 2,
          sidegrades: 0,
          tradeoffs: 0,
          questionable: 0,
          roleDelta: const {'removal': 0, 'ramp': 0, 'draw': 1},
        ),
        critic: const {
          'approval_score': 82,
          'verdict': 'aprovado',
        },
        warnings: const [],
      );

      final reasons = buildOptimizationRejectionReasons(
        validationReport: validation,
        archetype: 'midrange',
        preCurve: 3.4,
        postCurve: 3.1,
        preManaAssessment: 'Base de mana equilibrada',
        postManaAssessment: 'Base de mana equilibrada',
      );

      expect(reasons, isEmpty);
    });

    test('keeps structural recovery swaps for degenerate mana bases', () {
      final originalDeck = [
        _card(
          name: 'Wastes',
          typeLine: 'Basic Land',
          manaCost: '',
          cmc: 0,
          oracleText: '{T}: Add {C}.',
          quantity: 99,
        ),
        _card(
          name: 'Talrand, Sky Summoner',
          typeLine: 'Legendary Creature',
          manaCost: '{2}{U}{U}',
          cmc: 4,
          oracleText:
              'Whenever you cast an instant or sorcery spell, create a 2/2 blue Drake creature token with flying.',
        ),
      ];

      final additions = [
        _card(
          name: 'Arcane Signet',
          typeLine: 'Artifact',
          manaCost: '{2}',
          cmc: 2,
          oracleText:
              '{T}: Add one mana of any color in your commander\'s color identity.',
        ),
      ];

      final result = filterUnsafeOptimizeSwapsByCardData(
        removals: const ['Wastes'],
        additions: const ['Arcane Signet'],
        originalDeck: originalDeck,
        additionsData: additions,
        archetype: 'midrange',
      );

      expect(result.removals, equals(const ['Wastes']));
      expect(result.additions, equals(const ['Arcane Signet']));
      expect(result.droppedReasons, isEmpty);
    });

    test('treats all is dust as wipe and blocks wipe to creature downgrade',
        () {
      final originalDeck = [
        _card(
          name: 'All Is Dust',
          typeLine: 'Tribal Sorcery — Eldrazi',
          manaCost: '{7}',
          cmc: 7,
          oracleText:
              'Each player sacrifices all colored permanents they control.',
        ),
      ];

      final additions = [
        _card(
          name: 'Laboratory Maniac',
          typeLine: 'Creature — Human Wizard',
          manaCost: '{2}{U}',
          cmc: 3,
          oracleText:
              'If you would draw a card while your library has no cards in it, you win the game instead.',
        ),
      ];

      final result = filterUnsafeOptimizeSwapsByCardData(
        removals: const ['All Is Dust'],
        additions: const ['Laboratory Maniac'],
        originalDeck: originalDeck,
        additionsData: additions,
        archetype: 'control',
      );

      expect(result.removals, isEmpty);
      expect(result.additions, isEmpty);
      expect(result.droppedReasons.single, contains('papel wipe ->'));
    });

    test('drops temporary ritual swaps and non-structural land swaps in aggro',
        () {
      final originalDeck = [
        _card(
          name: 'Goblin Ringleader',
          typeLine: 'Creature — Goblin',
          manaCost: '{3}{R}',
          cmc: 4,
          oracleText:
              'When Goblin Ringleader enters, reveal the top four cards of your library.',
        ),
        _card(
          name: 'Abrade',
          typeLine: 'Instant',
          manaCost: '{1}{R}',
          cmc: 2,
          oracleText:
              'Choose one — Abrade deals 3 damage to target creature; or destroy target artifact.',
        ),
      ];

      final additions = [
        _card(
          name: 'Dark Ritual',
          typeLine: 'Instant',
          manaCost: '{B}',
          cmc: 1,
          oracleText: 'Add {B}{B}{B}.',
        ),
        _card(
          name: 'Command Tower',
          typeLine: 'Land',
          manaCost: '',
          cmc: 0,
          oracleText:
              '{T}: Add one mana of any color in your commander\'s color identity.',
        ),
      ];

      final result = filterUnsafeOptimizeSwapsByCardData(
        removals: const ['Goblin Ringleader', 'Abrade'],
        additions: const ['Dark Ritual', 'Command Tower'],
        originalDeck: originalDeck,
        additionsData: additions,
        archetype: 'aggro',
      );

      expect(result.removals, isEmpty);
      expect(result.additions, isEmpty);
      expect(result.droppedReasons, hasLength(2));
    });
  });
}

Map<String, dynamic> _card({
  required String name,
  required String typeLine,
  required String manaCost,
  required double cmc,
  required String oracleText,
  int quantity = 1,
}) {
  return {
    'name': name,
    'type_line': typeLine,
    'mana_cost': manaCost,
    'cmc': cmc,
    'oracle_text': oracleText,
    'quantity': quantity,
  };
}

GoldfishResult _goldfish({
  required double keepableRate,
  required double turn2PlayRate,
  double screwRate = 0.1,
}) {
  return GoldfishResult(
    simulations: 1000,
    screwRate: screwRate,
    floodRate: 0.02,
    keepableRate: keepableRate,
    turn1PlayRate: 0.5,
    turn2PlayRate: turn2PlayRate,
    turn3PlayRate: 0.9,
    turn4PlayRate: 0.95,
    avgCmc: 3.0,
    landCount: 36,
    cmcDistribution: const {1: 10, 2: 12, 3: 8},
  );
}

MulliganReport _mulligan({double keepAt7Rate = 0.8}) {
  return MulliganReport(
    runs: 500,
    avgMulligans: 0.2,
    keepAt7Rate: keepAt7Rate,
    keepAt6Rate: 0.15,
    keepAt5Rate: 0.05,
    keepAt4OrLessRate: 0,
    keepableAfterMullRate: 0.85,
  );
}
