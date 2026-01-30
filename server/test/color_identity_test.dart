import 'package:test/test.dart';

import '../lib/color_identity.dart';

void main() {
  group('isWithinCommanderIdentity', () {
    test('allows colorless cards in any commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[],
          commanderIdentity: {'W', 'U'},
        ),
        isTrue,
      );
    });

    test('allows subset identity', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W'],
          commanderIdentity: {'W', 'U'},
        ),
        isTrue,
      );
    });

    test('rejects identity outside commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['B'],
          commanderIdentity: {'W', 'U'},
        ),
        isFalse,
      );
    });

    test('rejects colored card for colorless commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W'],
          commanderIdentity: <String>{},
        ),
        isFalse,
      );
    });

    test('normalizes identity values', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[' w ', 'u'],
          commanderIdentity: normalizeColorIdentity(const <String>['W', 'U']),
        ),
        isTrue,
      );
    });
  });
}

