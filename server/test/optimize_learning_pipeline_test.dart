import 'package:test/test.dart';

import '../lib/ai/otimizacao.dart';
import '../routes/ai/optimize/index.dart' as optimize_route;

void main() {
  group('mergePriorityPool', () {
    test('prioritizes commander pool and removes duplicates', () {
      final result = mergePriorityPool(
        priorityPool: const [
          'Dockside Extortionist',
          'Mystic Remora',
          'dockside extortionist',
        ],
        candidatePool: const [
          'Mystic Remora',
          'Rhystic Study',
          'Deflecting Swat',
        ],
        limit: 4,
      );

      expect(
        result,
        equals(const [
          'Dockside Extortionist',
          'Mystic Remora',
          'Rhystic Study',
          'Deflecting Swat',
        ]),
      );
    });
  });

  group('buildOptimizationAnalysisLogEntry', () {
    test('captures rejected optimize outcome with reasons and priority source',
        () {
      final entry = optimize_route.buildOptimizationAnalysisLogEntry(
        deckId: 'deck-1',
        userId: 'user-1',
        commanderName: 'Talrand, Sky Summoner',
        commanderColors: const ['U'],
        operationMode: 'optimize',
        requestedMode: 'optimize',
        targetArchetype: 'control',
        detectedTheme: 'spellslinger',
        deckAnalysis: const {
          'average_cmc': '3.1',
          'type_distribution': {
            'lands': 35,
            'creatures': 9,
            'instants': 18,
          },
        },
        postAnalysis: const {
          'average_cmc': '2.8',
          'type_distribution': {
            'lands': 35,
            'creatures': 8,
            'instants': 20,
          },
          'improvements': ['CMC medio reduzido'],
        },
        removals: const ['Cancel', 'Jace\'s Ingenuity'],
        additions: const ['Force of Will', 'Mystic Remora'],
        statusCode: 422,
        qualityError: const {
          'code': 'OPTIMIZE_QUALITY_REJECTED',
          'message': 'Trocas degradam funcoes criticas.',
          'reasons': ['Perde interacao de mesa'],
          'validation': {
            'validation_score': 61,
            'verdict': 'reprovado',
          },
        },
        validationReport: null,
        validationWarnings: const ['warning-1'],
        blockedByColorIdentity: const ['Off-Color Card'],
        blockedByBracket: const [
          {
            'name': 'Mana Crypt',
            'reason': 'above_bracket',
          },
        ],
        commanderPriorityNames: const [
          'Mystic Remora',
          'Force of Will',
          'Rhystic Study',
        ],
        commanderPrioritySource: 'competitive_meta',
        deterministicSwapCandidates: const [
          {
            'remove': 'Cancel',
            'add': 'Force of Will',
          },
        ],
        cacheKey: 'cache-key-1',
        executionTimeMs: 1450,
      );

      expect(entry['validation_score'], equals(61));
      expect(entry['validation_verdict'], equals('reprovado'));
      expect(entry['color_identity_violations'], equals(1));
      expect(entry['effectiveness_score'], equals(61.0));

      final decisions =
          (entry['decisions_reasoning'] as Map).cast<String, dynamic>();
      expect(decisions['status_code'], equals(422));
      expect(
          decisions['quality_error_code'], equals('OPTIMIZE_QUALITY_REJECTED'));
      expect(
          decisions['commander_priority_source'], equals('competitive_meta'));
      expect(decisions['commander_priority_pool_size'], equals(3));
      expect(decisions['deterministic_swap_candidate_count'], equals(1));

      final swapAnalysis =
          (entry['swap_analysis'] as Map).cast<String, dynamic>();
      final acceptedPairs =
          (swapAnalysis['accepted_pairs'] as List).cast<Map<String, dynamic>>();
      expect(acceptedPairs, hasLength(2));
      expect(acceptedPairs.first['remove'], equals('Cancel'));
      expect(acceptedPairs.first['add'], equals('Force of Will'));
    });
  });

  group('scoreOptimizeReplacementCandidate', () {
    test(
        'boosts commander-priority cards and penalizes historically rejected cards',
        () {
      final preferredScore = optimize_route.scoreOptimizeReplacementCandidate(
        functionalNeed: 'draw',
        cardName: 'Mystic Remora',
        typeLine: 'Enchantment',
        oracleText:
            'Cumulative upkeep {1}. Whenever an opponent casts a noncreature spell, you may draw a card unless that player pays {4}.',
        popScore: 420,
        preferredNames: const {'mystic remora'},
        rejectedAdditionCounts: const {},
      );

      final penalizedScore = optimize_route.scoreOptimizeReplacementCandidate(
        functionalNeed: 'draw',
        cardName: 'Chart a Course',
        typeLine: 'Sorcery',
        oracleText: 'Draw two cards. Then discard a card unless you attacked.',
        popScore: 420,
        preferredNames: const {},
        rejectedAdditionCounts: const {'chart a course': 3},
      );

      expect(preferredScore, greaterThan(penalizedScore));
      expect(
        optimize_route.matchesFunctionalNeed(
          'draw',
          oracleText: 'Draw two cards.',
          typeLine: 'Sorcery',
        ),
        isTrue,
      );
      expect(
        optimize_route.matchesFunctionalNeed(
          'protection',
          oracleText: 'Target permanent phases out.',
          typeLine: 'Instant',
        ),
        isTrue,
      );
    });

    test(
        'penalizes temporary rituals and lands in optimize replacement ranking',
        () {
      final stableRampScore = optimize_route.scoreOptimizeReplacementCandidate(
        functionalNeed: 'ramp',
        cardName: 'Arcane Signet',
        typeLine: 'Artifact',
        oracleText:
            '{T}: Add one mana of any color in your commander\'s color identity.',
        popScore: 420,
        preferredNames: const {},
        rejectedAdditionCounts: const {},
      );

      final ritualScore = optimize_route.scoreOptimizeReplacementCandidate(
        functionalNeed: 'ramp',
        cardName: 'Dark Ritual',
        typeLine: 'Instant',
        oracleText: 'Add {B}{B}{B}.',
        popScore: 420,
        preferredNames: const {},
        rejectedAdditionCounts: const {},
      );

      final landScore = optimize_route.scoreOptimizeReplacementCandidate(
        functionalNeed: 'utility',
        cardName: 'Command Tower',
        typeLine: 'Land',
        oracleText:
            '{T}: Add one mana of any color in your commander\'s color identity.',
        popScore: 420,
        preferredNames: const {},
        rejectedAdditionCounts: const {},
      );

      expect(stableRampScore, greaterThan(ritualScore));
      expect(stableRampScore, greaterThan(landScore));
      expect(landScore, lessThan(50));
    });
  });

  group('buildDeterministicOptimizeResponse', () {
    test('creates optimize payload with recognized swap format', () {
      final payload = optimize_route.buildDeterministicOptimizeResponse(
        deterministicSwapCandidates: const [
          {
            'remove': 'Cancel',
            'add': 'Force of Will',
            'reason': 'swap deterministico',
          },
          {
            'remove': 'Divination',
            'add': 'Mystic Remora',
          },
        ],
        targetArchetype: 'control',
      );

      final parsed = optimize_route.parseOptimizeSuggestions(payload);
      expect(payload['strategy_source'], equals('deterministic_first'));
      expect(payload['swaps'], hasLength(2));
      expect(parsed['removals'], equals(['Cancel', 'Divination']));
      expect(parsed['additions'], equals(['Force of Will', 'Mystic Remora']));
    });
  });

  group('resolveOptimizeArchetype', () {
    test('prefers detected control when request is generic midrange', () {
      expect(
        optimize_route.resolveOptimizeArchetype(
          requestedArchetype: 'midrange',
          detectedArchetype: 'control',
        ),
        equals('control'),
      );
    });

    test('keeps explicit requested archetype when detected is generic', () {
      expect(
        optimize_route.resolveOptimizeArchetype(
          requestedArchetype: 'combo',
          detectedArchetype: 'midrange',
        ),
        equals('combo'),
      );
    });
  });

  group('shouldRetryOptimizeWithAiFallback', () {
    test('retries only for deterministic-first quality rejections', () {
      expect(
        optimize_route.shouldRetryOptimizeWithAiFallback(
          deterministicFirstEnabled: true,
          fallbackAlreadyAttempted: false,
          strategySource: 'deterministic_first',
          qualityErrorCode: 'OPTIMIZE_NO_SAFE_SWAPS',
          isComplete: false,
        ),
        isTrue,
      );

      expect(
        optimize_route.shouldRetryOptimizeWithAiFallback(
          deterministicFirstEnabled: true,
          fallbackAlreadyAttempted: false,
          strategySource: 'deterministic_first',
          qualityErrorCode: 'OPTIMIZE_QUALITY_REJECTED',
          isComplete: false,
        ),
        isTrue,
      );

      expect(
        optimize_route.shouldRetryOptimizeWithAiFallback(
          deterministicFirstEnabled: true,
          fallbackAlreadyAttempted: true,
          strategySource: 'deterministic_first',
          qualityErrorCode: 'OPTIMIZE_QUALITY_REJECTED',
          isComplete: false,
        ),
        isFalse,
      );

      expect(
        optimize_route.shouldRetryOptimizeWithAiFallback(
          deterministicFirstEnabled: true,
          fallbackAlreadyAttempted: false,
          strategySource: 'ai_primary',
          qualityErrorCode: 'OPTIMIZE_QUALITY_REJECTED',
          isComplete: false,
        ),
        isFalse,
      );
    });
  });

  group('buildDeterministicOptimizeRemovalCandidates', () {
    test('does not count lands as ramp surplus when ranking nonland removals',
        () {
      final removals =
          optimize_route.buildDeterministicOptimizeRemovalCandidates(
        allCardData: const [
          {
            'name': 'Commander Card',
            'type_line': 'Legendary Creature',
            'oracle_text': 'Flying',
            'quantity': 1,
            'cmc': 3.0,
          },
          {
            'name': 'Island',
            'type_line': 'Basic Land - Island',
            'oracle_text': '({T}: Add {U}.)',
            'quantity': 36,
            'cmc': 0.0,
          },
          {
            'name': 'Counterspell',
            'type_line': 'Instant',
            'oracle_text': 'Counter target spell.',
            'quantity': 1,
            'cmc': 2.0,
          },
          {
            'name': 'Ponder',
            'type_line': 'Sorcery',
            'oracle_text':
                'Look at the top three cards of your library, then draw a card.',
            'quantity': 1,
            'cmc': 1.0,
          },
        ],
        commanders: const ['Commander Card'],
        commanderColorIdentity: const {'U'},
        targetArchetype: 'control',
        keepTheme: true,
        coreCards: const [],
        commanderPriorityNames: const [],
      );

      expect(
        removals.where((candidate) => candidate['name'] == 'Counterspell'),
        isEmpty,
      );
      expect(
        removals.where((candidate) => candidate['name'] == 'Ponder'),
        isEmpty,
      );
    });

    test('allows land removals when the deck has excessive off-plan lands', () {
      final removals =
          optimize_route.buildDeterministicOptimizeRemovalCandidates(
        allCardData: const [
          {
            'name': 'Talrand, Sky Summoner',
            'type_line': 'Legendary Creature',
            'oracle_text':
                'Whenever you cast an instant or sorcery spell, create a 2/2 blue Drake creature token with flying.',
            'quantity': 1,
            'cmc': 4.0,
          },
          {
            'name': 'Wastes',
            'type_line': 'Basic Land - Wastes',
            'oracle_text': '({T}: Add {C}.)',
            'quantity': 38,
            'cmc': 0.0,
          },
          {
            'name': 'Island',
            'type_line': 'Basic Land - Island',
            'oracle_text': '({T}: Add {U}.)',
            'quantity': 28,
            'cmc': 0.0,
          },
          {
            'name': 'Opt',
            'type_line': 'Instant',
            'oracle_text': 'Scry 1. Draw a card.',
            'quantity': 1,
            'cmc': 1.0,
          },
        ],
        commanders: const ['Talrand, Sky Summoner'],
        commanderColorIdentity: const {'U'},
        targetArchetype: 'midrange',
        keepTheme: true,
        coreCards: const [],
        commanderPriorityNames: const [],
      );

      expect(removals, isNotEmpty);
      expect(removals.first['role'], equals('land'));
      expect(removals.first['name'], equals('Wastes'));
    });
  });
}
