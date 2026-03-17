import 'package:test/test.dart';

import '../lib/card_resolution_support.dart';

void main() {
  group('resolveCardCandidateNames', () {
    test('resolves exact match before broader candidates', () {
      final decision = resolveCardCandidateNames(
        'Sol Ring',
        ['Sol Ring', 'Sol Ring Deluxe'],
      );

      expect(decision.isResolved, isTrue);
      expect(decision.matchedName, equals('Sol Ring'));
      expect(decision.strategy, equals('exact'));
    });

    test('resolves unique prefix match', () {
      final decision = resolveCardCandidateNames(
        'Atraxa',
        ['Atraxa, Praetors\' Voice'],
      );

      expect(decision.isResolved, isTrue);
      expect(decision.matchedName, equals('Atraxa, Praetors\' Voice'));
      expect(decision.strategy, equals('prefix'));
    });

    test('marks multiple prefix matches as ambiguous', () {
      final decision = resolveCardCandidateNames(
        'Lightning',
        ['Lightning Bolt', 'Lightning Helix', 'Lightning Greaves'],
      );

      expect(decision.isResolved, isFalse);
      expect(decision.isAmbiguous, isTrue);
      expect(decision.candidateNames, hasLength(3));
    });

    test('resolves unique contains match when prefix is absent', () {
      final decision = resolveCardCandidateNames(
        'Lotus',
        ['Black Lotus'],
      );

      expect(decision.isResolved, isTrue);
      expect(decision.matchedName, equals('Black Lotus'));
      expect(decision.strategy, equals('contains'));
    });

    test('returns unresolved when there are no candidates', () {
      final decision = resolveCardCandidateNames('Unknown Card', const []);

      expect(decision.isResolved, isFalse);
      expect(decision.isAmbiguous, isFalse);
      expect(decision.candidateNames, isEmpty);
    });
  });
}
