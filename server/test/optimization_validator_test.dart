import 'package:test/test.dart';
import '../lib/ai/optimization_validator.dart';

void main() {
  group('OptimizationValidator', () {
    late OptimizationValidator validator;

    setUp(() {
      validator = OptimizationValidator(); // Sem API key = sem Critic AI
    });

    test('validate approves when optimization improves consistency', () async {
      // Deck original: mal balanceado (poucos terrenos, CMC alto)
      final originalDeck = [
        ..._makeLands(28), // Poucos terrenos
        ..._makeSpells(72, avgCmc: 4), // CMC alto
      ];

      // Deck otimizado: melhor balanceado
      final optimizedDeck = [
        ..._makeLands(35), // Mais terrenos
        ..._makeSpells(65, avgCmc: 3), // CMC menor
      ];

      final report = await validator.validate(
        originalDeck: originalDeck,
        optimizedDeck: optimizedDeck,
        removals: ['Expensive Spell 1', 'Expensive Spell 2'],
        additions: ['Sol Ring', 'Arcane Signet'],
        commanders: ['Test Commander'],
        archetype: 'midrange',
      );

      expect(report.score, greaterThan(0));
      expect(report.verdict, isNotEmpty);
      expect(report.monteCarlo.before.consistencyScore, isNotNull);
      expect(report.monteCarlo.after.consistencyScore, isNotNull);
      print('Score: ${report.score}, Verdict: ${report.verdict}');
    });

    test('functional analysis detects role preservation', () async {
      final originalDeck = [
        {
          'name': 'Counterspell',
          'type_line': 'Instant',
          'mana_cost': '{U}{U}',
          'oracle_text': 'Counter target spell.',
          'cmc': 2,
          'quantity': 1,
        },
        ..._makeLands(36),
        ..._makeSpells(63, avgCmc: 3),
      ];

      final optimizedDeck = [
        {
          'name': 'Swan Song',
          'type_line': 'Instant',
          'mana_cost': '{U}',
          'oracle_text': 'Counter target enchantment, instant, or sorcery spell.',
          'cmc': 1,
          'quantity': 1,
        },
        ..._makeLands(36),
        ..._makeSpells(63, avgCmc: 3),
      ];

      final report = await validator.validate(
        originalDeck: originalDeck,
        optimizedDeck: optimizedDeck,
        removals: ['Counterspell'],
        additions: ['Swan Song'],
        commanders: ['Test Commander'],
        archetype: 'control',
      );

      // Removal → Removal = role preserved = upgrade (CMC menor)
      final swap = report.functional.swaps.first;
      expect(swap.removedRole, equals('removal'));
      expect(swap.addedRole, equals('removal'));
      expect(swap.rolePreserved, isTrue);
      expect(swap.verdict, equals('upgrade'));
      print('Swap: ${swap.removed} → ${swap.added} = ${swap.verdict}');
    });

    test('mulligan report produces reasonable rates', () async {
      final deck = [
        ..._makeLands(36),
        ..._makeSpells(64, avgCmc: 3),
      ];

      final report = await validator.validate(
        originalDeck: deck,
        optimizedDeck: deck, // Same deck = no change
        removals: [],
        additions: [],
        commanders: ['Test Commander'],
        archetype: 'midrange',
      );

      final mulligan = report.monteCarlo.beforeMulligan;
      expect(mulligan.keepAt7Rate, greaterThan(0.3)); // >30% keep at 7
      expect(mulligan.avgMulligans, lessThan(2.0)); // Average < 2 mulls
      print('Keep@7: ${(mulligan.keepAt7Rate * 100).toStringAsFixed(1)}%');
      print('Avg mulligans: ${mulligan.avgMulligans.toStringAsFixed(2)}');
    });

    test('toJson produces valid JSON structure', () async {
      final deck = [
        ..._makeLands(36),
        ..._makeSpells(64, avgCmc: 3),
      ];

      final report = await validator.validate(
        originalDeck: deck,
        optimizedDeck: deck,
        removals: [],
        additions: [],
        commanders: ['Test Commander'],
        archetype: 'control',
      );

      final json = report.toJson();
      expect(json['validation_score'], isA<int>());
      expect(json['verdict'], isA<String>());
      expect(json['monte_carlo'], isA<Map>());
      expect(json['functional_analysis'], isA<Map>());
      expect(json['warnings'], isA<List>());
      expect(json.containsKey('critic_ai'), isFalse); // No API key = no critic
    });
  });
}

/// Helper: cria N terrenos básicos
List<Map<String, dynamic>> _makeLands(int count) {
  return List.generate(count, (i) => {
    'name': 'Island ${i + 1}',
    'type_line': 'Basic Land — Island',
    'mana_cost': '',
    'oracle_text': '{T}: Add {U}.',
    'cmc': 0,
    'quantity': 1,
    'colors': <String>[],
  });
}

/// Helper: cria N spells com CMC médio controlado
List<Map<String, dynamic>> _makeSpells(int count, {int avgCmc = 3}) {
  return List.generate(count, (i) {
    final cmc = (i % 5) + 1; // CMC varia de 1-5
    final adjustedCmc = (cmc * avgCmc / 3).round().clamp(1, 8);
    return {
      'name': 'Spell ${i + 1}',
      'type_line': i % 3 == 0 ? 'Creature — Wizard' : (i % 3 == 1 ? 'Instant' : 'Sorcery'),
      'mana_cost': '{${adjustedCmc}}',
      'oracle_text': i % 4 == 0 ? 'Draw a card.' : (i % 4 == 1 ? 'Destroy target creature.' : 'Target player gains 2 life.'),
      'cmc': adjustedCmc,
      'quantity': 1,
      'colors': ['U'],
    };
  });
}
