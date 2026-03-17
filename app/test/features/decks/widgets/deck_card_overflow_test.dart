import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manaloom/features/decks/models/deck.dart';
import 'package:manaloom/features/decks/widgets/deck_card.dart';

/// Widget tests para detectar overflow no DeckCard em diferentes tamanhos de tela.
///
/// Flutter reporta overflow como FlutterError — estes testes verificam que
/// nenhum overflow ocorre em cenários comuns (telas estreitas, nomes longos,
/// 5 cores WUBRG + chip + ícone público etc.).
void main() {
  // Helper: cria Deck com parâmetros configuráveis para testar overflow
  Deck makeDeck({
    String name = 'Test Deck',
    String format = 'commander',
    String? description,
    bool isPublic = false,
    int cardCount = 50,
    int? synergyScore,
    String? commanderName,
    String? commanderImageUrl,
    List<String> colorIdentity = const [],
  }) {
    return Deck(
      id: 'deck-test-${name.hashCode}',
      name: name,
      format: format,
      description: description,
      isPublic: isPublic,
      createdAt: DateTime(2025, 6, 15),
      cardCount: cardCount,
      synergyScore: synergyScore,
      commanderName: commanderName,
      commanderImageUrl: commanderImageUrl,
      colorIdentity: colorIdentity,
    );
  }

  // Helper: renderiza DeckCard dentro de constraints específicos
  Widget buildTestWidget(Deck deck, {double width = 400, double height = 800}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: SingleChildScrollView(
            child: DeckCard(
              deck: deck,
              onTap: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
  }

  group('DeckCard Overflow Tests', () {
    // ── Tamanhos de tela para testar ──
    // Representam: iPhone SE (320), Galaxy small (360), iPhone standard (375),
    // Pixel (411), iPhone Plus (414), iPad mini vert (768)
    final screenWidths = [280.0, 320.0, 360.0, 375.0, 411.0];

    for (final width in screenWidths) {
      testWidgets(
        'sem overflow em largura $width — deck básico Commander',
        (tester) async {
          final deck = makeDeck(
            name: 'Krenko Goblins',
            format: 'commander',
            cardCount: 87,
            colorIdentity: ['R'],
          );
          await tester.pumpWidget(buildTestWidget(deck, width: width));
          await tester.pumpAndSettle();

          // Se houver overflow, Flutter levanta FlutterError
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('sem overflow — 5 cores WUBRG + público + commander thumbnail', (tester) async {
      final deck = makeDeck(
        name: 'Kenrith, the Returned King',
        format: 'commander',
        cardCount: 100,
        synergyScore: 85,
        isPublic: true,
        commanderName: 'Kenrith, the Returned King',
        colorIdentity: ['W', 'U', 'B', 'R', 'G'],
      );
      // Menor largura (iPhone SE)
      await tester.pumpWidget(buildTestWidget(deck, width: 320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem overflow — nome muito longo + 5 cores + público', (tester) async {
      final deck = makeDeck(
        name: 'Breya, Etherium Shaper — Ultimate Artifacts & Thopters Commander Combo Deck',
        format: 'commander',
        description: 'Este é um deck extremamente focado em combos com artefatos e thopters para gerar valor infinito.',
        cardCount: 100,
        synergyScore: 92,
        isPublic: true,
        commanderName: 'Breya, Etherium Shaper',
        colorIdentity: ['W', 'U', 'B', 'R'],
      );
      await tester.pumpWidget(buildTestWidget(deck, width: 280));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem overflow — formato longo (commander) + cores + tela 280px', (tester) async {
      final deck = makeDeck(
        name: 'Goblin Deck',
        format: 'commander',
        cardCount: 42,
        isPublic: true,
        colorIdentity: ['R', 'G'],
      );
      await tester.pumpWidget(buildTestWidget(deck, width: 280));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem overflow — deck sem cartas e sem cores', (tester) async {
      final deck = makeDeck(
        name: 'Novo Deck Vazio',
        format: 'standard',
        cardCount: 0,
        colorIdentity: [],
      );
      await tester.pumpWidget(buildTestWidget(deck, width: 320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem overflow — deck Modern sem commander + synergy + público', (tester) async {
      final deck = makeDeck(
        name: 'Tron Control with Urzas',
        format: 'modern',
        cardCount: 60,
        synergyScore: 78,
        isPublic: true,
        colorIdentity: ['G', 'R'],
      );
      await tester.pumpWidget(buildTestWidget(deck, width: 320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem overflow — todos os formatos em 320px', (tester) async {
      final formats = ['commander', 'standard', 'modern', 'pioneer', 'legacy', 'vintage', 'pauper'];
      for (final format in formats) {
        final deck = makeDeck(
          name: 'Deck de $format',
          format: format,
          cardCount: 60,
          colorIdentity: ['W', 'U', 'B', 'R', 'G'],
          isPublic: true,
        );
        await tester.pumpWidget(buildTestWidget(deck, width: 320));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'Overflow no formato $format em 320px');
      }
    });

    testWidgets('sem overflow — descrição longa em tela estreita', (tester) async {
      final deck = makeDeck(
        name: 'Goblins',
        format: 'legacy',
        description: 'Um deck extremamente agressivo focado em goblins tribais com líderes que geram tokens e buffs massivos para toda a board.',
        cardCount: 60,
        synergyScore: 65,
        colorIdentity: ['R'],
      );
      await tester.pumpWidget(buildTestWidget(deck, width: 280));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
