import 'package:test/test.dart';

import '../routes/ai/optimize/index.dart' as optimize_route;

void main() {
  group('parseOptimizeSuggestions', () {
    test('recognized empty swaps marks recognized_format true', () {
      final result = optimize_route.parseOptimizeSuggestions({
        'summary': 'ok',
        'swaps': <Map<String, dynamic>>[],
      });

      expect(result['recognized_format'], isTrue);
      expect(result['removals'], isEmpty);
      expect(result['additions'], isEmpty);
    });

    test('parses string swap entries with arrows', () {
      final result = optimize_route.parseOptimizeSuggestions({
        'swaps': ['Card A -> Card B', 'Card C => Card D', 'Card E → Card F'],
      });

      expect(result['recognized_format'], isTrue);
      expect(result['removals'], equals(['Card A', 'Card C', 'Card E']));
      expect(result['additions'], equals(['Card B', 'Card D', 'Card F']));
    });

    test('parses nested swap object', () {
      final result = optimize_route.parseOptimizeSuggestions({
        'recommendations': [
          {
            'swap': {'out': 'Temple Bell', 'in': 'Rhystic Study'}
          }
        ],
      });

      expect(result['recognized_format'], isTrue);
      expect(result['removals'], equals(['Temple Bell']));
      expect(result['additions'], equals(['Rhystic Study']));
    });
  });
}
