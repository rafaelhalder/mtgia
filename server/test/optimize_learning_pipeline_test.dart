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

      final swapAnalysis =
          (entry['swap_analysis'] as Map).cast<String, dynamic>();
      final acceptedPairs =
          (swapAnalysis['accepted_pairs'] as List).cast<Map<String, dynamic>>();
      expect(acceptedPairs, hasLength(2));
      expect(acceptedPairs.first['remove'], equals('Cancel'));
      expect(acceptedPairs.first['add'], equals('Force of Will'));
    });
  });
}
