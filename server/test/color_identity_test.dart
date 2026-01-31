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

  group('Edge Cases - Color Identity', () {
    // Nota: No Magic, a identidade de cor é derivada do mana cost + texto da carta.
    // Hybrid mana (ex: {W/U}) conta como ambas as cores na identidade.
    // Phyrexian mana (ex: {W/P}) conta como a cor indicada.
    // Devoid remove a cor da carta, mas NÃO afeta a identidade de cor.
    // MDFC considera ambas as faces para identidade.
    
    test('hybrid mana - card with {W/U} should have both W and U identity', () {
      // Uma carta com {W/U} no custo tem identidade W e U
      // Se o comandante é apenas W, a carta não pode entrar
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W', 'U'], // Hybrid conta como ambos
          commanderIdentity: {'W'},
        ),
        isFalse,
      );
      
      // Se o comandante é W e U, a carta pode entrar
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W', 'U'],
          commanderIdentity: {'W', 'U'},
        ),
        isTrue,
      );
    });

    test('phyrexian mana - card with {W/P} has W identity', () {
      // Phyrexian mana como {W/P} tem identidade W
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W'],
          commanderIdentity: {'W', 'U'},
        ),
        isTrue,
      );
      
      // Mas não funciona em comandante sem W
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W'],
          commanderIdentity: {'U', 'B'},
        ),
        isFalse,
      );
    });

    test('phyrexian colorless - {P} has no color identity', () {
      // Cartas com apenas {P} (Phyrexian genérico) são colorless na identidade
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[], // Colorless
          commanderIdentity: {'W'},
        ),
        isTrue,
      );
    });

    test('devoid - colorless card but with colored mana symbols still has identity', () {
      // Devoid remove a cor da carta, mas a identidade vem dos símbolos de mana no custo/texto
      // Ex: Eldrazi como "Thought-Knot Seer" tem devoid mas custo {3}{C} (sem identidade de cor)
      // Ex: "Kozilek's Return" tem devoid mas {2}{R} (identidade vermelha)
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['R'], // Devoid, mas tem R no custo
          commanderIdentity: {'R', 'G'},
        ),
        isTrue,
      );
      
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['R'],
          commanderIdentity: {'W', 'U'},
        ),
        isFalse,
      );
    });

    test('MDFC - both faces contribute to identity', () {
      // Modal double-faced cards usam AMBAS as faces para calcular identidade
      // Ex: Se frente é W e verso é B, a identidade é W + B
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W', 'B'], // MDFC com W na frente, B no verso
          commanderIdentity: {'W', 'B'},
        ),
        isTrue,
      );
      
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W', 'B'],
          commanderIdentity: {'W'}, // Comandante só W
        ),
        isFalse,
      );
    });

    test('land with color-producing ability has that identity', () {
      // Terrenos que produzem mana colorido tem essa identidade
      // Ex: Mana Confluence é colorless (pode entrar em qualquer deck)
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[], // Qualquer cor
          commanderIdentity: {'W'},
        ),
        isTrue,
      );
      
      // Mas Blood Crypt tem identidade B e R (pelo texto)
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['B', 'R'],
          commanderIdentity: {'B', 'R'},
        ),
        isTrue,
      );
      
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['B', 'R'],
          commanderIdentity: {'W', 'U'},
        ),
        isFalse,
      );
    });

    test('five-color identity', () {
      // Cartas com WUBRG na identidade
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W', 'U', 'B', 'R', 'G'],
          commanderIdentity: {'W', 'U', 'B', 'R', 'G'},
        ),
        isTrue,
      );
      
      // Mas não funciona se falta uma cor
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W', 'U', 'B', 'R', 'G'],
          commanderIdentity: {'W', 'U', 'B', 'R'}, // Falta G
        ),
        isFalse,
      );
    });

    test('colorless commander (like Kozilek) only allows colorless cards', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[], // Colorless card
          commanderIdentity: <String>{}, // Colorless commander
        ),
        isTrue,
      );
      
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>['W'], // White card
          commanderIdentity: <String>{}, // Colorless commander
        ),
        isFalse,
      );
    });
  });
}
