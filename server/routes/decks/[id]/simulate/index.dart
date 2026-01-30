import 'dart:io';
import 'dart:math';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method == HttpMethod.get) {
    return _simulateDeck(context, deckId);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _simulateDeck(RequestContext context, String deckId) async {
  final pool = context.read<Pool>();

  try {
    // 1. Buscar cartas do deck
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, c.mana_cost, c.type_line, dc.quantity, dc.is_commander
        FROM deck_cards dc
        JOIN cards c ON dc.card_id = c.id
        WHERE dc.deck_id = @deckId
      '''),
      parameters: {'deckId': deckId},
    );

    if (cardsResult.isEmpty) {
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Deck not found or empty'});
    }

    // 2. Preparar o Baralho (Library)
    final library = <_SimCard>[];
    final commander = <_SimCard>[];

    for (final row in cardsResult) {
      final data = row.toColumnMap();
      final name = data['name'] as String;
      final typeLine = data['type_line'] as String? ?? '';
      final manaCost = data['mana_cost'] as String? ?? '';
      final quantity = data['quantity'] as int;
      final isCommander = data['is_commander'] as bool? ?? false;

      final card = _SimCard(
        name: name,
        isLand: typeLine.toLowerCase().contains('land'),
        cmc: _calculateCmc(manaCost),
      );

      if (isCommander) {
        commander.add(card);
      } else {
        for (var i = 0; i < quantity; i++) {
          library.add(card);
        }
      }
    }

    // 3. Executar Simulação de Monte Carlo
    const iterations = 1000;
    final landCountStats = List<int>.filled(8, 0); // 0 a 7 terrenos na mão inicial
    final onCurveStats = List<int>.filled(6, 0); // Turno 1 a 5 (index 1..5)

    final rng = Random();

    for (var i = 0; i < iterations; i++) {
      // Embaralhar
      final deck = List<_SimCard>.from(library)..shuffle(rng);
      
      // Mão Inicial (7 cartas)
      final hand = deck.take(7).toList();
      final landsInHand = hand.where((c) => c.isLand).length;
      
      // Estatística 1: Terrenos na mão inicial
      if (landsInHand <= 7) {
        landCountStats[landsInHand]++;
      }

      // Simulação de Turnos (1 a 5)
      // Simplificação: Assumimos que jogamos 1 terreno por turno se tivermos
      var landsInPlay = 0;
      // Clone da mão para simular gastos (opcional, aqui faremos checagem de disponibilidade)
      // Para "On Curve", verificamos se temos Mana suficiente E uma mágica de Custo <= Mana
      
      // Estado do jogo simulado
      var currentHand = List<_SimCard>.from(hand);
      var libraryIndex = 7; // Próxima carta a comprar

      for (var turn = 1; turn <= 5; turn++) {
        // Compra carta (se não for o primeiro a jogar... assumimos que compra sempre para simplificar)
        if (libraryIndex < deck.length) {
          currentHand.add(deck[libraryIndex]);
          libraryIndex++;
        }

        // Joga Terreno (se tiver na mão)
        final landIndex = currentHand.indexWhere((c) => c.isLand);
        if (landIndex != -1) {
          landsInPlay++;
          currentHand.removeAt(landIndex); // Remove da mão para não contar o mesmo terreno
        }

        // Verifica se tem jogada na curva (Mágica com CMC == Turno ou CMC <= Turno e > 0)
        // Vamos ser estritos: Jogada "On Curve" idealmente usa toda a mana.
        // Mas "Playable" é qualquer coisa não-terreno que custe <= landsInPlay.
        final hasPlayable = currentHand.any((c) => !c.isLand && c.cmc > 0 && c.cmc <= landsInPlay);
        
        // Ou Commander? (Sempre disponível)
        final hasCommanderPlayable = commander.isNotEmpty && commander.first.cmc <= landsInPlay;

        if (hasPlayable || hasCommanderPlayable) {
          onCurveStats[turn]++;
        }
      }
    }

    // 4. Formatar Resultados
    final landDistribution = <String, String>{};
    for (var i = 0; i < 8; i++) {
      final percent = (landCountStats[i] / iterations * 100).toStringAsFixed(1);
      landDistribution['$i lands'] = '$percent%';
    }

    final curveProbability = <String, String>{};
    for (var i = 1; i <= 5; i++) {
      final percent = (onCurveStats[i] / iterations * 100).toStringAsFixed(1);
      curveProbability['Turn $i'] = '$percent%';
    }

    return Response.json(body: {
      'deck_id': deckId,
      'iterations': iterations,
      'opening_hand': {
        'land_distribution': landDistribution,
        'analysis': _analyzeOpeningHand(landCountStats, iterations),
      },
      'on_curve_probability': curveProbability,
    });

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Simulation failed: $e'},
    );
  }
}

String _analyzeOpeningHand(List<int> stats, int total) {
  // Soma chances de mãos ruins (0, 1, 6, 7 terrenos)
  final badHands = stats[0] + stats[1] + stats[6] + stats[7];
  final badHandPercent = badHands / total;

  if (badHandPercent > 0.30) {
    return 'High risk of mulligan (${(badHandPercent * 100).toStringAsFixed(0)}%). Adjust land count.';
  } else if (badHandPercent > 0.15) {
    return 'Moderate consistency. You might need to mulligan occasionally.';
  } else {
    return 'Excellent consistency! Most hands will be playable.';
  }
}

class _SimCard {
  final String name;
  final bool isLand;
  final int cmc;

  _SimCard({required this.name, required this.isLand, required this.cmc});
}

int _calculateCmc(String manaCost) {
  int cmc = 0;
  final regex = RegExp(r'\{([^}]+)\}');
  final matches = regex.allMatches(manaCost);

  for (final match in matches) {
    final symbol = match.group(1) ?? '';
    final number = int.tryParse(symbol);
    if (number != null) {
      cmc += number;
    } else if (symbol != 'X') {
      cmc += 1;
    }
  }
  return cmc;
}
