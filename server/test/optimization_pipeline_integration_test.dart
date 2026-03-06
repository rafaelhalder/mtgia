import 'package:test/test.dart';

import '../routes/ai/optimize/index.dart' as optimize_route;

/// Integration-style tests that simulate the full optimization pipeline logic
/// without needing a database connection.
///
/// These tests validate that:
/// 1. A realistic Commander deck optimization produces valid results
/// 2. The response structure matches the expected contract
/// 3. Edge cases are handled correctly (empty AI response, all filtered, etc.)
/// 4. The pipeline never produces an invalid deck state

// ─── Helpers ────────────────────────────────────────────────────────────────

bool _isBasicLandName(String name) {
  final n = name.trim().toLowerCase();
  return n == 'plains' ||
      n == 'island' ||
      n == 'swamp' ||
      n == 'mountain' ||
      n == 'forest' ||
      n == 'wastes' ||
      n == 'snow-covered plains' ||
      n == 'snow-covered island' ||
      n == 'snow-covered swamp' ||
      n == 'snow-covered mountain' ||
      n == 'snow-covered forest';
}

/// Simulates the entire post-AI validation pipeline:
/// 1. Parse AI response
/// 2. Filter removals (must exist in deck, can't be commander/core)
/// 3. Filter additions (can't already be in deck for Commander)
/// 4. Balance removals/additions
/// 5. Final validation
Map<String, dynamic> simulateOptimizePipeline({
  required Map<String, dynamic> aiResponse,
  required Set<String> deckNamesLower,
  required Set<String> commanderNamesLower,
  required Set<String> coreCardsLower,
  required String format,
  bool keepTheme = true,
}) {
  // Step 1: Parse AI response
  final parsed = optimize_route.parseOptimizeSuggestions(aiResponse);
  var removals = (parsed['removals'] as List).cast<String>();
  var additions = (parsed['additions'] as List).cast<String>();

  // Step 2: Filter removals — must exist in deck
  removals = removals
      .where((n) => deckNamesLower.contains(n.toLowerCase()))
      .toList();

  // Step 2b: Never remove commanders
  removals = removals
      .where((n) => !commanderNamesLower.contains(n.toLowerCase()))
      .toList();

  // Step 2c: If keep_theme, never remove core cards
  if (keepTheme) {
    removals = removals
        .where((n) => !coreCardsLower.contains(n.toLowerCase()))
        .toList();
  }

  // Step 3: In optimize mode, filter additions already in deck
  additions = additions
      .where((n) => !deckNamesLower.contains(n.toLowerCase()))
      .toList();

  // Step 4: Balance — truncate to min length
  final minCount =
      removals.length < additions.length ? removals.length : additions.length;
  removals = removals.take(minCount).toList();
  additions = additions.take(minCount).toList();

  // Step 5: Final validation — no duplicate non-basics in Commander
  if (format == 'commander' || format == 'brawl') {
    final removalSet = removals.map((n) => n.toLowerCase()).toSet();
    additions = additions.where((n) {
      final lower = n.toLowerCase();
      final isBasic = _isBasicLandName(lower);
      final alreadyInDeck = deckNamesLower.contains(lower);
      final beingRemoved = removalSet.contains(lower);
      return isBasic || !alreadyInDeck || beingRemoved;
    }).toList();
    // Re-balance after filtering
    if (removals.length > additions.length) {
      removals = removals.take(additions.length).toList();
    }
  }

  return {
    'removals': removals,
    'additions': additions,
    'balanced': removals.length == additions.length,
  };
}

// ─── Test Data ──────────────────────────────────────────────────────────────

/// A realistic 100-card Commander deck for testing
final _testCommanderDeck = <String>{
  // Commander
  'atraxa, praetors\' voice',
  // Lands (36)
  'island', 'plains', 'swamp', 'forest',
  'command tower', 'exotic orchard', 'breeding pool',
  'hallowed fountain', 'godless shrine', 'overgrown tomb',
  'temple garden', 'watery grave', 'zagoth triome',
  'indatha triome', 'raffine\'s tower', 'spara\'s headquarters',
  'flooded strand', 'polluted delta', 'windswept heath',
  'marsh flats', 'verdant catacombs', 'rejuvenating springs',
  'underground river', 'yavimaya coast', 'llanowar wastes',
  'caves of koilos', 'adarkar wastes', 'brushland',
  'urborg, tomb of yawgmoth', 'boseiju, who endures',
  'otawara, soaring city', 'reliquary tower',
  'arcane sanctum', 'seaside citadel', 'opulent palace', 'sandsteppe citadel',
  // Ramp (10)
  'sol ring', 'arcane signet', 'fellwar stone',
  'chromatic lantern', 'dimir signet', 'simic signet',
  'cultivate', 'kodama\'s reach', 'farseek', 'three visits',
  // Draw (8)
  'rhystic study', 'sylvan library', 'phyrexian arena',
  'mystic remora', 'blue sun\'s zenith', 'brainstorm',
  'ponder', 'preordain',
  // Removal (8)
  'swords to plowshares', 'path to exile', 'anguished unmaking',
  'beast within', 'generous gift', 'cyclonic rift',
  'supreme verdict', 'toxic deluge',
  // Counters (4)
  'counterspell', 'swan song', 'dovin\'s veto', 'negate',
  // Proliferate/Theme (20)
  'deepglow skate', 'evolution sage', 'thrummingbird',
  'flux channeler', 'contagion engine', 'contagion clasp',
  'inexorable tide', 'karn\'s bastion', 'the ozolith',
  'vorinclex, monstrous raider', 'doubling season', 'hardened scales',
  'winding constrictor', 'corpsejack menace', 'rishkar, peema renegade',
  'walking ballista', 'astral cornucopia', 'everflowing chalice',
  'crystalline crawler', 'gilder bairn',
  // Utility (14)
  'lightning greaves', 'swiftfoot boots', 'heroic intervention',
  'teferi\'s protection', 'smothering tithe', 'esper sentinel',
  'eternal witness', 'demonic tutor', 'enlightened tutor',
  'vampiric tutor', 'the great henge', 'aura shards',
  'mirari\'s wake', 'privileged position',
};

void main() {
  group('Optimization Pipeline — Full Simulation', () {
    test('balanced AI response produces balanced output', () {
      final aiResponse = {
        'removals': ['Gilder Bairn', 'Astral Cornucopia', 'Everflowing Chalice'],
        'additions': ['Luminarch Aspirant', 'Ozolith, the Shattered Spire', 'Grateful Apparition'],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {'deepglow skate', 'evolution sage', 'vorinclex, monstrous raider'},
        format: 'commander',
      );

      expect(result['balanced'], isTrue);
      expect(result['removals'], hasLength(3));
      expect(result['additions'], hasLength(3));
    });

    test('AI suggesting commander removal is blocked', () {
      final aiResponse = {
        'removals': ['Atraxa, Praetors\' Voice', 'Gilder Bairn'],
        'additions': ['New Card A', 'New Card B'],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      // Commander removal blocked, so only 1 valid removal
      expect(result['removals'], hasLength(1));
      expect(result['additions'], hasLength(1));
      expect(result['removals'], isNot(contains('Atraxa, Praetors\' Voice')));
    });

    test('AI suggesting core card removal is blocked when keepTheme=true', () {
      final aiResponse = {
        'removals': ['Deepglow Skate', 'Gilder Bairn', 'Astral Cornucopia'],
        'additions': ['New Card A', 'New Card B', 'New Card C'],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {'deepglow skate'},
        format: 'commander',
        keepTheme: true,
      );

      expect(result['removals'], isNot(contains('Deepglow Skate')));
      expect(result['balanced'], isTrue);
    });

    test('AI suggesting non-existent card for removal is filtered', () {
      final aiResponse = {
        'removals': ['Card That Does Not Exist', 'Gilder Bairn'],
        'additions': ['New Card A', 'New Card B'],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      // Only 1 valid removal (Gilder Bairn), so truncated to 1
      expect(result['removals'], hasLength(1));
      expect(result['additions'], hasLength(1));
    });

    test('AI suggesting card already in deck as addition is filtered (Commander)', () {
      final aiResponse = {
        'removals': ['Gilder Bairn', 'Astral Cornucopia'],
        'additions': ['Sol Ring', 'Luminarch Aspirant'],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      // Sol Ring already in deck, filtered out
      expect(result['additions'], isNot(contains('Sol Ring')));
      expect(result['balanced'], isTrue);
      expect(result['removals'], hasLength(1));
      expect(result['additions'], hasLength(1));
    });

    test('empty AI response produces empty output', () {
      final aiResponse = <String, dynamic>{
        'reasoning': 'The deck is already optimal.',
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      expect(result['removals'], isEmpty);
      expect(result['additions'], isEmpty);
      expect(result['balanced'], isTrue);
    });

    test('more removals than additions is truncated (not filled with basics)', () {
      final aiResponse = {
        'removals': [
          'Gilder Bairn',
          'Astral Cornucopia',
          'Everflowing Chalice',
          'Crystalline Crawler',
          'Corpsejack Menace',
        ],
        'additions': [
          'Luminarch Aspirant',
          'Grateful Apparition',
        ],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      // Should truncate removals to match additions, NOT add basic lands
      expect(result['balanced'], isTrue);
      expect(result['removals'], hasLength(2));
      expect(result['additions'], hasLength(2));
      // Verify no basic lands in additions
      for (final name in result['additions'] as List) {
        expect(_isBasicLandName(name as String), isFalse,
            reason: 'Optimize should not add basic lands as swaps: $name');
      }
    });

    test('more additions than removals is truncated', () {
      final aiResponse = {
        'removals': ['Gilder Bairn'],
        'additions': [
          'Luminarch Aspirant',
          'Grateful Apparition',
          'Ozolith, the Shattered Spire',
        ],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      expect(result['balanced'], isTrue);
      expect(result['removals'], hasLength(1));
      expect(result['additions'], hasLength(1));
    });

    test('deck size is preserved after optimization (Commander = 100)', () {
      const originalCount = 100;
      final aiResponse = {
        'removals': ['Gilder Bairn', 'Astral Cornucopia', 'Everflowing Chalice'],
        'additions': ['Luminarch Aspirant', 'Grateful Apparition', 'Ozolith, the Shattered Spire'],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      final removals = result['removals'] as List;
      final additions = result['additions'] as List;
      final resultCount = originalCount - removals.length + additions.length;
      expect(resultCount, equals(originalCount),
          reason: 'Deck must remain at exactly 100 cards after optimization');
    });

    test('all removals must exist in original deck', () {
      final aiResponse = {
        'removals': [
          'Gilder Bairn', // In deck
          'Lightning Bolt', // NOT in deck
          'Force of Will', // NOT in deck
        ],
        'additions': [
          'Card A',
          'Card B',
          'Card C',
        ],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      // Only Gilder Bairn is in the deck
      for (final name in result['removals'] as List) {
        expect(_testCommanderDeck.contains((name as String).toLowerCase()), isTrue,
            reason: 'Removal "$name" must exist in original deck');
      }
    });

    test('swap format parsing produces correct pairs', () {
      final aiResponse = {
        'swaps': [
          {'out': 'Gilder Bairn', 'in': 'Luminarch Aspirant'},
          {'out': 'Astral Cornucopia', 'in': 'Grateful Apparition'},
        ],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      expect(result['removals'], hasLength(2));
      expect(result['additions'], hasLength(2));
      expect(result['balanced'], isTrue);
    });

    test('arrow format parsing produces correct pairs', () {
      final aiResponse = {
        'swaps': [
          'Gilder Bairn -> Luminarch Aspirant',
          'Astral Cornucopia → Grateful Apparition',
        ],
      };

      final result = simulateOptimizePipeline(
        aiResponse: aiResponse,
        deckNamesLower: _testCommanderDeck,
        commanderNamesLower: {'atraxa, praetors\' voice'},
        coreCardsLower: {},
        format: 'commander',
      );

      expect(result['removals'], hasLength(2));
      expect(result['additions'], hasLength(2));
      expect(result['balanced'], isTrue);
    });
  });

  group('DeckArchetypeAnalyzer — Analysis Quality', () {
    test('generates valid analysis for a typical Commander deck', () {
      final cards = <Map<String, dynamic>>[
        // Commander
        {'name': 'Atraxa', 'type_line': 'Legendary Creature', 'mana_cost': '{G}{W}{U}{B}', 'colors': ['G', 'W', 'U', 'B'], 'cmc': 4.0, 'oracle_text': 'Proliferate', 'quantity': 1},
        // Lands
        for (var i = 0; i < 36; i++)
          {'name': 'Island', 'type_line': 'Basic Land — Island', 'mana_cost': '', 'colors': <String>[], 'cmc': 0.0, 'oracle_text': '', 'quantity': 1},
        // Creatures
        for (var i = 0; i < 25; i++)
          {'name': 'Creature $i', 'type_line': 'Creature', 'mana_cost': '{2}{U}', 'colors': ['U'], 'cmc': 3.0, 'oracle_text': 'Some ability.', 'quantity': 1},
        // Instants
        for (var i = 0; i < 15; i++)
          {'name': 'Instant $i', 'type_line': 'Instant', 'mana_cost': '{1}{U}', 'colors': ['U'], 'cmc': 2.0, 'oracle_text': 'Counter target spell.', 'quantity': 1},
        // Sorceries
        for (var i = 0; i < 10; i++)
          {'name': 'Sorcery $i', 'type_line': 'Sorcery', 'mana_cost': '{3}{B}', 'colors': ['B'], 'cmc': 4.0, 'oracle_text': 'Destroy target creature.', 'quantity': 1},
        // Enchantments
        for (var i = 0; i < 8; i++)
          {'name': 'Enchantment $i', 'type_line': 'Enchantment', 'mana_cost': '{2}{W}', 'colors': ['W'], 'cmc': 3.0, 'oracle_text': 'Whenever a creature enters...', 'quantity': 1},
        // Artifacts
        for (var i = 0; i < 5; i++)
          {'name': 'Artifact $i', 'type_line': 'Artifact', 'mana_cost': '{2}', 'colors': <String>[], 'cmc': 2.0, 'oracle_text': '{T}: Add one mana.', 'quantity': 1},
      ];

      final analyzer = optimize_route.DeckArchetypeAnalyzer(cards, ['G', 'W', 'U', 'B']);
      final analysis = analyzer.generateAnalysis();

      expect(analysis, isNotNull);
      expect(analysis['average_cmc'], isNotNull);
      expect(analysis['type_distribution'], isNotNull);
      
      final types = analysis['type_distribution'] as Map<String, dynamic>;
      expect(types['lands'], equals(36));
      expect(types['creatures'], greaterThanOrEqualTo(25)); // Commander is also a creature
      expect(types['instants'], equals(15));
      expect(types['sorceries'], equals(10));
      expect(types['enchantments'], equals(8));
      expect(types['artifacts'], equals(5));

      // Verify CMC is reasonable (non-land average)
      final avgCmc = double.tryParse(analysis['average_cmc'].toString()) ?? 0;
      expect(avgCmc, greaterThan(0));
      expect(avgCmc, lessThan(10));
    });

    test('deck with too few lands shows mana warning', () {
      final cards = <Map<String, dynamic>>[
        for (var i = 0; i < 20; i++)
          {'name': 'Island', 'type_line': 'Basic Land — Island', 'mana_cost': '', 'colors': <String>[], 'cmc': 0.0, 'oracle_text': '', 'quantity': 1},
        for (var i = 0; i < 80; i++)
          {'name': 'Creature $i', 'type_line': 'Creature', 'mana_cost': '{3}{U}', 'colors': ['U'], 'cmc': 4.0, 'oracle_text': 'Power.', 'quantity': 1},
      ];

      final analyzer = optimize_route.DeckArchetypeAnalyzer(cards, ['U']);
      final analysis = analyzer.generateAnalysis();

      final manaAssessment = analysis['mana_base_assessment'] as String? ?? '';
      // With only 20 lands in a 100-card deck, there should be a mana warning
      expect(manaAssessment.isNotEmpty, isTrue);
    });

    test('deck with good land ratio produces healthy analysis', () {
      final cards = <Map<String, dynamic>>[
        for (var i = 0; i < 37; i++)
          {'name': 'Island', 'type_line': 'Basic Land — Island', 'mana_cost': '', 'colors': ['U'], 'color_identity': ['U'], 'cmc': 0.0, 'oracle_text': '{T}: Add {U}.', 'quantity': 1},
        for (var i = 0; i < 63; i++)
          {'name': 'Creature $i', 'type_line': 'Creature', 'mana_cost': '{2}{U}', 'colors': ['U'], 'cmc': 3.0, 'oracle_text': 'Power.', 'quantity': 1},
      ];

      final analyzer = optimize_route.DeckArchetypeAnalyzer(cards, ['U']);
      final analysis = analyzer.generateAnalysis();

      // With 37 lands and mono-U, mana base should be fine
      final types = analysis['type_distribution'] as Map<String, dynamic>;
      expect(types['lands'], equals(37));
      expect(analysis['total_cards'], equals(100));
    });
  });
}
