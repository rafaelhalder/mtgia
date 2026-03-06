import 'package:test/test.dart';

/// Testes de regras MTG: snow basics, tamanho mínimo de deck,
/// cálculo de CMC (incluindo híbrido/phyrexian) e identidade de cor.
///
/// Esses testes replicam as funções auxiliares do servidor para
/// poder ser executados sem banco de dados.

// ─── CMC Calculation ───────────────────────────────────────────────────────

/// Replicação corrigida de calculateCmc (regex \{([^}]+)\})
int calculateCmc(String? manaCost) {
  if (manaCost == null || manaCost.isEmpty) return 0;
  int cmc = 0;
  final regex = RegExp(r'\{([^}]+)\}');
  for (final match in regex.allMatches(manaCost)) {
    final symbol = match.group(1)!;
    if (int.tryParse(symbol) != null) {
      cmc += int.parse(symbol);
    } else if (symbol.toUpperCase() == 'X') {
      // X conta como 0 (variável)
    } else {
      // W, U, B, R, G, C, W/U, W/P, 2/W, etc → 1
      cmc += 1;
    }
  }
  return cmc;
}

// ─── Basic Land Detection ──────────────────────────────────────────────────

/// Replicação de _isBasicLandTypeLine (deck_rules_service.dart e optimize/index.dart)
bool isBasicLandTypeLine(String typeLineLower) {
  return typeLineLower.contains('basic land') ||
      typeLineLower.contains('basic snow land');
}

/// Replicação de _isBasicLandName (optimize/index.dart)
bool isBasicLandName(String name) {
  final normalized = name.trim().toLowerCase();
  return normalized == 'plains' ||
      normalized == 'island' ||
      normalized == 'swamp' ||
      normalized == 'mountain' ||
      normalized == 'forest' ||
      normalized == 'wastes' ||
      normalized == 'snow-covered plains' ||
      normalized == 'snow-covered island' ||
      normalized == 'snow-covered swamp' ||
      normalized == 'snow-covered mountain' ||
      normalized == 'snow-covered forest';
}

/// Replicação de _maxCopiesForFormat (optimize/index.dart)
int maxCopiesForFormat({
  required String deckFormat,
  required String typeLine,
  required String name,
}) {
  final normalizedFormat = deckFormat.toLowerCase();
  final normalizedType = typeLine.toLowerCase();
  final normalizedName = name.trim().toLowerCase();

  final isBasicLand =
      isBasicLandTypeLine(normalizedType) || normalizedName == 'wastes';
  if (isBasicLand) return 999;

  if (normalizedFormat == 'commander' || normalizedFormat == 'brawl') return 1;
  return 4;
}

// ─── Minimum Deck Size ─────────────────────────────────────────────────────

const _minDeckSizeNonCommander = 60;

String? validateMinDeckSize({
  required String format,
  required int totalCards,
  bool strict = false,
}) {
  final f = format.toLowerCase();
  if (f == 'commander' || f == 'brawl') return null; // Tratado separadamente
  if (strict && totalCards < _minDeckSizeNonCommander) {
    return 'Regra violada: deck $f precisa de pelo menos $_minDeckSizeNonCommander cartas (atual: $totalCards).';
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('Snow Basic Land Detection (isBasicLandTypeLine)', () {
    test('Regular basic lands are detected', () {
      expect(isBasicLandTypeLine('basic land — plains'), isTrue);
      expect(isBasicLandTypeLine('basic land — island'), isTrue);
      expect(isBasicLandTypeLine('basic land — swamp'), isTrue);
      expect(isBasicLandTypeLine('basic land — mountain'), isTrue);
      expect(isBasicLandTypeLine('basic land — forest'), isTrue);
      expect(isBasicLandTypeLine('basic land'), isTrue); // Wastes
    });

    test('Snow-Covered basics are detected (fix for bug)', () {
      // Tipo real: "Basic Snow Land — Island"
      expect(isBasicLandTypeLine('basic snow land — plains'), isTrue);
      expect(isBasicLandTypeLine('basic snow land — island'), isTrue);
      expect(isBasicLandTypeLine('basic snow land — swamp'), isTrue);
      expect(isBasicLandTypeLine('basic snow land — mountain'), isTrue);
      expect(isBasicLandTypeLine('basic snow land — forest'), isTrue);
    });

    test('"basic snow land" does NOT contain "basic land" as substring', () {
      // Verifica o motivo do bug original
      expect('basic snow land — island'.contains('basic land'), isFalse);
    });

    test('Non-basic lands are NOT detected as basic', () {
      expect(isBasicLandTypeLine('land'), isFalse);
      expect(isBasicLandTypeLine('legendary land'), isFalse);
      expect(isBasicLandTypeLine('snow land — forest'), isFalse);
      expect(isBasicLandTypeLine('land — urza\'s'), isFalse);
      expect(isBasicLandTypeLine('artifact land'), isFalse);
    });

    test('Type line with mixed casing works (caller lowercases first)', () {
      // A função espera já em minúsculas
      expect(isBasicLandTypeLine('Basic Land — Island'.toLowerCase()), isTrue);
      expect(isBasicLandTypeLine('Basic Snow Land — Island'.toLowerCase()),
          isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Snow Basic Land Names (isBasicLandName)', () {
    test('Regular basic land names are recognized', () {
      expect(isBasicLandName('Plains'), isTrue);
      expect(isBasicLandName('Island'), isTrue);
      expect(isBasicLandName('Swamp'), isTrue);
      expect(isBasicLandName('Mountain'), isTrue);
      expect(isBasicLandName('Forest'), isTrue);
      expect(isBasicLandName('Wastes'), isTrue);
    });

    test('Snow-Covered basic land names are recognized (fix)', () {
      expect(isBasicLandName('Snow-Covered Plains'), isTrue);
      expect(isBasicLandName('Snow-Covered Island'), isTrue);
      expect(isBasicLandName('Snow-Covered Swamp'), isTrue);
      expect(isBasicLandName('Snow-Covered Mountain'), isTrue);
      expect(isBasicLandName('Snow-Covered Forest'), isTrue);
    });

    test('Non-basic names are NOT recognized', () {
      expect(isBasicLandName('Command Tower'), isFalse);
      expect(isBasicLandName('Sol Ring'), isFalse);
      expect(isBasicLandName('Tropical Island'), isFalse);
    });

    test('Case-insensitive check', () {
      expect(isBasicLandName('snow-covered island'), isTrue);
      expect(isBasicLandName('ISLAND'), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Max Copies For Format (_maxCopiesForFormat)', () {
    test('Snow-Covered Island allows unlimited copies in Commander', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Basic Snow Land — Island',
        name: 'Snow-Covered Island',
      );
      expect(max, equals(999));
    });

    test('Snow-Covered Island allows unlimited copies in Standard', () {
      final max = maxCopiesForFormat(
        deckFormat: 'standard',
        typeLine: 'Basic Snow Land — Island',
        name: 'Snow-Covered Island',
      );
      expect(max, equals(999));
    });

    test('Regular Island allows unlimited copies', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Basic Land — Island',
        name: 'Island',
      );
      expect(max, equals(999));
    });

    test('Non-basic land has copy limit 1 in Commander', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Land',
        name: 'Command Tower',
      );
      expect(max, equals(1));
    });

    test('Non-basic has copy limit 4 in Standard', () {
      final max = maxCopiesForFormat(
        deckFormat: 'standard',
        typeLine: 'Instant',
        name: 'Lightning Bolt',
      );
      expect(max, equals(4));
    });

    test('Wastes (colorless basic) allows unlimited copies', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Basic Land',
        name: 'Wastes',
      );
      expect(max, equals(999));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('CMC Calculation — Hybrid & Phyrexian Mana (fixed regex)', () {
    test('Regular colored mana costs', () {
      expect(calculateCmc('{W}'), equals(1));
      expect(calculateCmc('{U}'), equals(1));
      expect(calculateCmc('{B}'), equals(1));
      expect(calculateCmc('{R}'), equals(1));
      expect(calculateCmc('{G}'), equals(1));
      expect(calculateCmc('{C}'), equals(1)); // Colorless mana symbol
    });

    test('Numeric mana costs', () {
      expect(calculateCmc('{0}'), equals(0));
      expect(calculateCmc('{1}'), equals(1));
      expect(calculateCmc('{3}'), equals(3));
      expect(calculateCmc('{7}'), equals(7));
    });

    test('Mixed costs', () {
      expect(calculateCmc('{2}{U}{U}'), equals(4));
      expect(calculateCmc('{1}{W}{B}'), equals(3));
      expect(calculateCmc('{4}{G}{G}'), equals(6));
    });

    test('X costs count as 0', () {
      expect(calculateCmc('{X}{U}{U}'), equals(2));
      expect(calculateCmc('{X}{X}'), equals(0));
    });

    test('Hybrid mana {W/U} counts as 1 (not 0)', () {
      expect(calculateCmc('{W/U}'), equals(1));
      expect(calculateCmc('{W/U}{W/U}'), equals(2));
      expect(calculateCmc('{2/W}'), equals(1));
      expect(calculateCmc('{1}{W/U}'), equals(2));
    });

    test('Phyrexian mana {W/P} counts as 1 (not 0)', () {
      expect(calculateCmc('{W/P}'), equals(1));
      expect(calculateCmc('{U/P}'), equals(1));
      expect(calculateCmc('{W/P}{W/P}'), equals(2));
      expect(calculateCmc('{B/P}{B/P}'), equals(2));
    });

    test('Phyrexian hybrid {G/P} counts as 1', () {
      expect(calculateCmc('{G/P}'), equals(1));
    });

    test('Complex costs with hybrid/phyrexian', () {
      // {1}{W/U}: 1 + 1 = 2
      expect(calculateCmc('{1}{W/U}'), equals(2));
      // {3}{W/U}{W/U}: 3 + 1 + 1 = 5
      expect(calculateCmc('{3}{W/U}{W/U}'), equals(5));
    });

    test('Empty or null mana cost returns 0', () {
      expect(calculateCmc(null), equals(0));
      expect(calculateCmc(''), equals(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Minimum Deck Size Validation (non-Commander formats)', () {
    test('Standard deck with 60 cards passes (strict)', () {
      final error = validateMinDeckSize(
          format: 'standard', totalCards: 60, strict: true);
      expect(error, isNull);
    });

    test('Standard deck with 61 cards passes (strict)', () {
      final error = validateMinDeckSize(
          format: 'standard', totalCards: 61, strict: true);
      expect(error, isNull);
    });

    test('Standard deck with 59 cards fails (strict)', () {
      final error = validateMinDeckSize(
          format: 'standard', totalCards: 59, strict: true);
      expect(error, isNotNull);
      expect(error, contains('60'));
      expect(error, contains('59'));
    });

    test('Modern deck with 60 cards passes', () {
      final error = validateMinDeckSize(
          format: 'modern', totalCards: 60, strict: true);
      expect(error, isNull);
    });

    test('Legacy deck with 60 cards passes', () {
      final error = validateMinDeckSize(
          format: 'legacy', totalCards: 60, strict: true);
      expect(error, isNull);
    });

    test('Vintage deck with 59 cards fails (strict)', () {
      final error = validateMinDeckSize(
          format: 'vintage', totalCards: 59, strict: true);
      expect(error, isNotNull);
    });

    test('Pauper deck with 59 cards fails (strict)', () {
      final error = validateMinDeckSize(
          format: 'pauper', totalCards: 59, strict: true);
      expect(error, isNotNull);
    });

    test('Non-strict mode does not fail on 59 cards', () {
      final error = validateMinDeckSize(
          format: 'standard', totalCards: 59, strict: false);
      expect(error, isNull);
    });

    test('Commander format is exempt from 60-card minimum check', () {
      // Commander tem sua própria validação de 100 cartas
      final error = validateMinDeckSize(
          format: 'commander', totalCards: 30, strict: true);
      expect(error, isNull);
    });

    test('Brawl format is exempt from 60-card minimum check', () {
      final error = validateMinDeckSize(
          format: 'brawl', totalCards: 30, strict: true);
      expect(error, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Commander Format Rules - Copy Limits', () {
    test('Commander allows 1 copy of non-basic', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Instant',
        name: 'Counterspell',
      );
      expect(max, equals(1));
    });

    test('Commander allows unlimited basic lands', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Basic Land — Island',
        name: 'Island',
      );
      expect(max, equals(999));
    });

    test('Commander allows unlimited Snow-Covered basics', () {
      final max = maxCopiesForFormat(
        deckFormat: 'commander',
        typeLine: 'Basic Snow Land — Island',
        name: 'Snow-Covered Island',
      );
      expect(max, equals(999));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Standard/Modern Format Rules - Copy Limits', () {
    test('Standard allows 4 copies of non-basic', () {
      final max = maxCopiesForFormat(
        deckFormat: 'standard',
        typeLine: 'Creature — Human Wizard',
        name: 'Delver of Secrets',
      );
      expect(max, equals(4));
    });

    test('Standard allows unlimited basic lands', () {
      final max = maxCopiesForFormat(
        deckFormat: 'standard',
        typeLine: 'Basic Land — Mountain',
        name: 'Mountain',
      );
      expect(max, equals(999));
    });

    test('Standard allows unlimited Snow-Covered basics', () {
      final max = maxCopiesForFormat(
        deckFormat: 'standard',
        typeLine: 'Basic Snow Land — Mountain',
        name: 'Snow-Covered Mountain',
      );
      expect(max, equals(999));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Card Type Detection', () {
    String getMainType(String typeLine) {
      final t = typeLine.toLowerCase();
      if (t.contains('land')) return 'Land';
      if (t.contains('creature')) return 'Creature';
      if (t.contains('planeswalker')) return 'Planeswalker';
      if (t.contains('artifact')) return 'Artifact';
      if (t.contains('enchantment')) return 'Enchantment';
      if (t.contains('instant')) return 'Instant';
      if (t.contains('sorcery')) return 'Sorcery';
      if (t.contains('battle')) return 'Battle';
      return 'Other';
    }

    test('Snow basic land is detected as land', () {
      expect(getMainType('Basic Snow Land — Island'), equals('Land'));
      expect(getMainType('Basic Snow Land — Forest'), equals('Land'));
    });

    test('Artifact Creature is detected as creature (not artifact)', () {
      // Land check antes de creature, mas artifact é verificado depois
      expect(getMainType('Artifact Creature — Golem'), equals('Creature'));
    });

    test('Enchantment Creature (Gods) is detected as creature', () {
      expect(getMainType('Legendary Enchantment Creature — God'), equals('Creature'));
    });

    test('Legendary Planeswalker detected correctly', () {
      expect(getMainType('Legendary Planeswalker — Jace'), equals('Planeswalker'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Color Identity Integration', () {
    // Replicação de isWithinCommanderIdentity
    Set<String> normalizeColorIdentity(Iterable<String> identity) {
      final normalized = <String>{};
      final allowed = {'W', 'U', 'B', 'R', 'G', 'C'};
      for (final raw in identity) {
        final value = raw.toUpperCase().trim();
        if (value.isEmpty) continue;
        final matches = RegExp(r'[WUBRGC]').allMatches(value);
        for (final match in matches) {
          final symbol = match.group(0);
          if (symbol != null && allowed.contains(symbol)) {
            normalized.add(symbol);
          }
        }
      }
      return normalized;
    }

    bool isWithinCommanderIdentity({
      required Iterable<String> cardIdentity,
      required Set<String> commanderIdentity,
    }) {
      final normalizedCard = normalizeColorIdentity(cardIdentity);
      if (normalizedCard.isEmpty) return true;
      return normalizedCard.every(commanderIdentity.contains);
    }

    test('Snow-Covered Island is colorless — fits any commander', () {
      // Snow-Covered Island tem color_identity vazio (é uma terra, não tem custo)
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[],
          commanderIdentity: {'R'},
        ),
        isTrue,
      );
    });

    test('Colorless card fits colorless commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const <String>[],
          commanderIdentity: {},
        ),
        isTrue,
      );
    });

    test('Blue card fits U/B commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const ['U'],
          commanderIdentity: {'U', 'B'},
        ),
        isTrue,
      );
    });

    test('Red card does NOT fit mono-blue commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const ['R'],
          commanderIdentity: {'U'},
        ),
        isFalse,
      );
    });

    test('WUBRG card requires 5-color commander', () {
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const ['W', 'U', 'B', 'R', 'G'],
          commanderIdentity: {'W', 'U', 'B', 'R', 'G'},
        ),
        isTrue,
      );
      expect(
        isWithinCommanderIdentity(
          cardIdentity: const ['W', 'U', 'B', 'R', 'G'],
          commanderIdentity: {'W', 'U', 'B', 'R'}, // Missing G
        ),
        isFalse,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Commander Eligibility - Background Rule (fix)', () {
    bool isBackground(String typeLine) {
      final t = typeLine.toLowerCase();
      return t.contains('legendary') &&
          t.contains('enchantment') &&
          t.contains('background');
    }

    bool isCommanderEligible(String typeLine, String oracleText) {
      final t = typeLine.toLowerCase();
      final o = oracleText.toLowerCase();
      if (t.contains('legendary') && t.contains('creature')) return true;
      if (o.contains('can be your commander')) return true;
      // Background enchantments NAO sao elegiveis como comandante solo.
      return false;
    }

    test('Legendary Creature is eligible', () {
      expect(isCommanderEligible('Legendary Creature — Phyrexian Praetor', ''), isTrue);
    });

    test('Planeswalker with can-be-your-commander text is eligible', () {
      expect(
        isCommanderEligible(
            'Legendary Planeswalker — Urza',
            'Urza, Lord Protector can be your commander.'),
        isTrue,
      );
    });

    test('Background enchantment alone is NOT eligible as solo commander', () {
      // Bug fix: antes retornava true por causa do if (_isBackground) return true
      expect(
        isCommanderEligible(
            'Legendary Enchantment — Background',
            'Choose this Background when you create your character.'),
        isFalse,
      );
    });

    test('Background is recognized as background type', () {
      expect(isBackground('Legendary Enchantment — Background'), isTrue);
    });

    test('Non-legendary enchantment is not background', () {
      expect(isBackground('Enchantment — Aura'), isFalse);
    });

    test('Non-creature artifact is not eligible', () {
      expect(isCommanderEligible('Artifact', ''), isFalse);
    });

    test('Instant is not eligible', () {
      expect(isCommanderEligible('Instant', ''), isFalse);
    });
  });

}
