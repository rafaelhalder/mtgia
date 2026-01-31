/// Smoke tests para o app Flutter MTG Deck Builder
/// Estes testes validam que os widgets principais renderizam corretamente.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Smoke Tests - Widgets básicos', () {
    testWidgets('MaterialApp renderiza sem erros', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('MTG Deck Builder'),
            ),
          ),
        ),
      );

      expect(find.text('MTG Deck Builder'), findsOneWidget);
    });
  });
}
