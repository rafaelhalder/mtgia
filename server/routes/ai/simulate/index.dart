import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/ai/battle_simulator.dart';
import '../../../lib/ai/goldfish_simulator.dart';
import '../../../lib/logger.dart';

/// POST /ai/simulate
/// Simula performance de um deck
///
/// Body:
/// {
///   "deck_id": "uuid",           // Deck para simular
///   "opponent_deck_id": "uuid",  // Opcional: para matchup ou battle
///   "simulations": 1000,         // Opcional: número de simulações (goldfish)
///   "type": "goldfish"           // "goldfish", "matchup" ou "battle"
/// }
///
/// Types:
/// - goldfish: Monte Carlo de mãos iniciais (rápido, 1000 simulações)
/// - matchup: Análise heurística de matchup entre dois decks
/// - battle: Simulação turno-a-turno completa (lento, 1 partida detalhada)
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      body: {'error': 'Method not allowed'},
      statusCode: HttpStatus.methodNotAllowed,
    );
  }

  final pool = context.read<Pool>();

  try {
    final body = await context.request.body();
    final data = jsonDecode(body) as Map<String, dynamic>;

    final deckId = data['deck_id'] as String?;
    if (deckId == null || deckId.isEmpty) {
      return Response.json(
        body: {'error': 'deck_id is required'},
        statusCode: HttpStatus.badRequest,
      );
    }

    final simType = (data['type'] as String?) ?? 'goldfish';
    final simCount = (data['simulations'] as int?) ?? 1000;

    // Busca cartas do deck
    final deckCards = await _fetchDeckCards(pool, deckId);
    if (deckCards.isEmpty) {
      return Response.json(
        body: {'error': 'Deck not found or empty'},
        statusCode: HttpStatus.notFound,
      );
    }

    if (simType == 'battle') {
      // Simulação turno-a-turno completa
      final opponentId = data['opponent_deck_id'] as String?;
      if (opponentId == null || opponentId.isEmpty) {
        return Response.json(
          body: {'error': 'opponent_deck_id is required for battle simulation'},
          statusCode: HttpStatus.badRequest,
        );
      }

      final opponentCards = await _fetchDeckCards(pool, opponentId);
      if (opponentCards.isEmpty) {
        return Response.json(
          body: {'error': 'Opponent deck not found or empty'},
          statusCode: HttpStatus.notFound,
        );
      }

      final simulator = BattleSimulator(
        deckACards: deckCards,
        deckBCards: opponentCards,
        maxTurns: (data['max_turns'] as int?) ?? 30,
      );
      final result = simulator.simulate();

      // Salva resultado para treinamento futuro
      await _saveSimulation(
        pool: pool,
        deckAId: deckId,
        deckBId: opponentId,
        type: 'battle',
        result: result.toJson(),
      );

      return Response.json(
        body: {
          'type': 'battle',
          'deck_a_id': deckId,
          'deck_b_id': opponentId,
          ...result.toJson(),
        },
      );
    } else if (simType == 'matchup') {
      // Análise heurística de matchup
      final opponentId = data['opponent_deck_id'] as String?;
      if (opponentId == null || opponentId.isEmpty) {
        return Response.json(
          body: {'error': 'opponent_deck_id is required for matchup simulation'},
          statusCode: HttpStatus.badRequest,
        );
      }

      final opponentCards = await _fetchDeckCards(pool, opponentId);
      if (opponentCards.isEmpty) {
        return Response.json(
          body: {'error': 'Opponent deck not found or empty'},
          statusCode: HttpStatus.notFound,
        );
      }

      final result = MatchupAnalyzer.analyze(deckCards, opponentCards);

      // Salva resultado para treinamento futuro
      await _saveSimulation(
        pool: pool,
        deckAId: deckId,
        deckBId: opponentId,
        type: 'matchup',
        result: result.toJson(),
      );

      return Response.json(
        body: {
          'type': 'matchup',
          'deck_a_id': deckId,
          'deck_b_id': opponentId,
          ...result.toJson(),
        },
      );
    } else {
      // Simulação goldfish (padrão)
      final simulator = GoldfishSimulator(deckCards, simulations: simCount);
      final result = simulator.simulate();

      // Salva resultado para treinamento futuro
      await _saveSimulation(
        pool: pool,
        deckAId: deckId,
        type: 'goldfish',
        result: result.toJson(),
      );

      return Response.json(
        body: {
          'type': 'goldfish',
          'deck_id': deckId,
          ...result.toJson(),
        },
      );
    }
  } on FormatException catch (e) {
    print('[ERROR] Invalid JSON: ${e.message}: $e');
    return Response.json(
      body: {'error': 'Invalid JSON: ${e.message}'},
      statusCode: HttpStatus.badRequest,
    );
  } catch (e, st) {
    Log.e('Error in /ai/simulate: $e\n$st');
    return Response.json(
      body: {'error': 'Internal server error'},
      statusCode: HttpStatus.internalServerError,
    );
  }
}

/// Busca cartas de um deck com todos os dados necessários
Future<List<Map<String, dynamic>>> _fetchDeckCards(Pool pool, String deckId) async {
  final result = await pool.execute(
    Sql.named('''
      SELECT 
        c.id,
        c.name,
        c.mana_cost,
        c.cmc,
        c.type_line,
        c.oracle_text,
        c.colors,
        c.color_identity,
        dc.quantity,
        dc.is_commander
      FROM deck_cards dc
      JOIN cards c ON c.id = dc.card_id
      WHERE dc.deck_id = @deckId
    '''),
    parameters: {'deckId': deckId},
  );

  return result.map((row) {
    return {
      'id': row[0],
      'name': row[1],
      'mana_cost': row[2],
      'cmc': row[3],
      'type_line': row[4],
      'oracle_text': row[5],
      'colors': row[6],
      'color_identity': row[7],
      'quantity': row[8],
      'is_commander': row[9],
    };
  }).toList();
}

/// Salva resultado da simulação para treinamento de ML
Future<void> _saveSimulation({
  required Pool pool,
  required String deckAId,
  String? deckBId,
  required String type,
  required Map<String, dynamic> result,
}) async {
  try {
    // Verifica se a tabela existe
    final tableExists = await pool.execute('''
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_name = 'battle_simulations'
      )
    ''');

    if (tableExists.isNotEmpty && tableExists.first[0] == true) {
      await pool.execute(
        Sql.named('''
          INSERT INTO battle_simulations (deck_a_id, deck_b_id, game_log)
          VALUES (@deckAId, @deckBId, @gameLog::jsonb)
        '''),
        parameters: {
          'deckAId': deckAId,
          'deckBId': deckBId,
          'gameLog': jsonEncode({'type': type, ...result}),
        },
      );
    }
  } catch (e) {
    print('[ERROR] handler: $e');
    // Não falha a request se não conseguir salvar
    Log.w('Could not save simulation: $e');
  }
}
