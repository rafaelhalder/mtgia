import 'dart:io';
import 'dart:math';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/archetype_counters_service.dart';

/// Endpoint para simular matchup entre dois decks
/// 
/// POST /ai/simulate-matchup
/// Body: { 
///   "my_deck_id": "uuid", 
///   "opponent_deck_id": "uuid",  // Pode ser de meta_decks ou decks
///   "simulations": 100           // Opcional, default 50
/// }
/// 
/// Retorna análise de matchup com win rate estimado e recomendações
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final myDeckId = body['my_deck_id'] as String?;
    final opponentDeckId = body['opponent_deck_id'] as String?;
    final simulationCount = body['simulations'] as int? ?? 50;

    if (myDeckId == null || opponentDeckId == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'my_deck_id and opponent_deck_id are required'},
      );
    }

    final pool = context.read<Pool>();
    final countersService = ArchetypeCountersService(pool);

    // 1. Buscar dados de ambos os decks
    final myDeckData = await _getDeckData(pool, myDeckId);
    final opponentDeckData = await _getDeckData(pool, opponentDeckId);

    if (myDeckData == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Your deck not found'},
      );
    }

    if (opponentDeckData == null) {
      // Tentar buscar de meta_decks
      final metaDeckData = await _getMetaDeckData(pool, opponentDeckId);
      if (metaDeckData == null) {
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'error': 'Opponent deck not found'},
        );
      }
      // Usar meta deck
      return _analyzeMatchup(
        pool: pool,
        countersService: countersService,
        myDeck: myDeckData,
        opponentDeck: metaDeckData,
        simulationCount: simulationCount,
        isMetaDeck: true,
      );
    }

    return _analyzeMatchup(
      pool: pool,
      countersService: countersService,
      myDeck: myDeckData,
      opponentDeck: opponentDeckData,
      simulationCount: simulationCount,
      isMetaDeck: false,
    );

  } catch (e, stack) {
    print('Erro em simulate-matchup: $e\n$stack');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to simulate matchup'},
    );
  }
}

/// Busca dados completos de um deck
Future<Map<String, dynamic>?> _getDeckData(Pool pool, String deckId) async {
  try {
    final deckResult = await pool.execute(
      Sql.named('SELECT id, name, format FROM decks WHERE id = @id'),
      parameters: {'id': deckId},
    );

    if (deckResult.isEmpty) return null;

    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, c.type_line, c.oracle_text, c.mana_cost, c.colors, dc.quantity, dc.is_commander,
               COALESCE(
                 (SELECT SUM(
                   CASE 
                     WHEN m[1] ~ '^[0-9]+\$' THEN m[1]::int
                     WHEN m[1] IN ('W','U','B','R','G','C') THEN 1
                     WHEN m[1] = 'X' THEN 0
                     ELSE 1
                   END
                 ) FROM regexp_matches(c.mana_cost, '\\{([^}]+)\\}', 'g') AS m(m)),
                 0
               ) as cmc
        FROM deck_cards dc 
        JOIN cards c ON c.id = dc.card_id 
        WHERE dc.deck_id = @id
      '''),
      parameters: {'id': deckId},
    );

    final cards = <Map<String, dynamic>>[];
    String? commander;
    int landCount = 0;
    int creatureCount = 0;
    int rampCount = 0;
    int removalCount = 0;
    int counterspellCount = 0;
    double totalCMC = 0;
    int nonLandCards = 0;
    final colors = <String>{};

    for (final row in cardsResult) {
      final name = row[0] as String;
      final typeLine = (row[1] as String?) ?? '';
      final oracleText = ((row[2] as String?) ?? '').toLowerCase();
      final quantity = row[5] as int;
      final isCommander = row[6] as bool;
      final cmc = (row[7] as num?)?.toDouble() ?? 0;
      final cardColors = (row[4] as List?)?.cast<String>() ?? [];

      colors.addAll(cardColors);

      if (isCommander) commander = name;

      cards.add({
        'name': name,
        'type_line': typeLine,
        'oracle_text': oracleText,
        'quantity': quantity,
        'cmc': cmc,
        'is_commander': isCommander,
      });

      final typeLineLower = typeLine.toLowerCase();

      if (typeLineLower.contains('land')) {
        landCount += quantity;
      } else {
        nonLandCards += quantity;
        totalCMC += cmc * quantity;
      }

      if (typeLineLower.contains('creature')) creatureCount += quantity;
      if (oracleText.contains('add {') || oracleText.contains('search your library for a') && oracleText.contains('land')) rampCount += quantity;
      if (oracleText.contains('destroy target') || oracleText.contains('exile target')) removalCount += quantity;
      if (oracleText.contains('counter target')) counterspellCount += quantity;
    }

    return {
      'id': deckResult.first[0] as String,
      'name': deckResult.first[1] as String,
      'format': deckResult.first[2] as String,
      'commander': commander,
      'cards': cards,
      'colors': colors.toList(),
      'stats': {
        'lands': landCount,
        'creatures': creatureCount,
        'ramp': rampCount,
        'removal': removalCount,
        'counterspells': counterspellCount,
        'average_cmc': nonLandCards > 0 ? totalCMC / nonLandCards : 0.0,
      },
    };
  } catch (e) {
    print('[ERROR] handler: $e');
    print('Erro ao buscar deck $deckId: $e');
    return null;
  }
}

/// Busca dados de um meta deck
Future<Map<String, dynamic>?> _getMetaDeckData(Pool pool, String metaDeckId) async {
  try {
    final result = await pool.execute(
      Sql.named('SELECT id, format, archetype, card_list, placement FROM meta_decks WHERE id = @id'),
      parameters: {'id': metaDeckId},
    );

    if (result.isEmpty) return null;

    final cardList = result.first[3] as String;
    final lines = cardList.split('\n').where((l) => l.trim().isNotEmpty).toList();

    return {
      'id': result.first[0] as String,
      'name': '${result.first[2]} (Meta)',
      'format': result.first[1] as String,
      'archetype': result.first[2] as String,
      'placement': result.first[4] as String?,
      'card_count': lines.length,
      'is_meta_deck': true,
    };
  } catch (e) {
    print('[ERROR] handler: $e');
    print('Erro ao buscar meta deck $metaDeckId: $e');
    return null;
  }
}

/// Analisa o matchup e retorna resultado
Future<Response> _analyzeMatchup({
  required Pool pool,
  required ArchetypeCountersService countersService,
  required Map<String, dynamic> myDeck,
  required Map<String, dynamic> opponentDeck,
  required int simulationCount,
  required bool isMetaDeck,
}) async {
  // Detectar arquétipos
  final myCards = (myDeck['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final myArchetypeData = await countersService.detectDeckArchetype(cards: myCards);
  final myArchetype = myArchetypeData['archetype'] as String;

  String opponentArchetype;
  if (isMetaDeck) {
    opponentArchetype = opponentDeck['archetype'] as String? ?? 'unknown';
  } else {
    final oppCards = (opponentDeck['cards'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final oppArchetypeData = await countersService.detectDeckArchetype(cards: oppCards);
    opponentArchetype = oppArchetypeData['archetype'] as String;
  }

  // Buscar hate cards relevantes
  final hateCardsForOpponent = await countersService.getHateCards(
    archetype: opponentArchetype,
    colors: (myDeck['colors'] as List?)?.cast<String>(),
  );

  // Calcular vantagens/desvantagens baseado em estatísticas
  final myStats = myDeck['stats'] as Map<String, dynamic>? ?? {};
  final oppStats = opponentDeck['stats'] as Map<String, dynamic>? ?? {};

  double myScore = 50.0; // Base 50%
  final advantages = <String>[];
  final disadvantages = <String>[];
  final recommendations = <String>[];

  // Comparar ramp
  final myRamp = (myStats['ramp'] as int?) ?? 0;
  final oppRamp = (oppStats['ramp'] as int?) ?? 5;
  if (myRamp > oppRamp + 3) {
    myScore += 5;
    advantages.add('Mais ramp que o oponente (+${myRamp - oppRamp})');
  } else if (oppRamp > myRamp + 3) {
    myScore -= 5;
    disadvantages.add('Menos ramp que o oponente (-${oppRamp - myRamp})');
    recommendations.add('Adicionar mais fontes de ramp');
  }

  // Comparar removal
  final myRemoval = (myStats['removal'] as int?) ?? 0;
  final oppRemoval = (oppStats['removal'] as int?) ?? 5;
  if (myRemoval > oppRemoval + 2) {
    myScore += 5;
    advantages.add('Mais removal que o oponente');
  } else if (myRemoval < 5) {
    myScore -= 5;
    disadvantages.add('Removal insuficiente');
    recommendations.add('Adicionar mais removal pontual');
  }

  // Comparar curva de mana
  final myCMC = (myStats['average_cmc'] as num?)?.toDouble() ?? 3.0;
  final oppCMC = (oppStats['average_cmc'] as num?)?.toDouble() ?? 3.0;
  if (myCMC < oppCMC - 0.5) {
    myScore += 7;
    advantages.add('Curva de mana mais baixa (${myCMC.toStringAsFixed(1)} vs ${oppCMC.toStringAsFixed(1)})');
  } else if (myCMC > oppCMC + 0.5) {
    myScore -= 5;
    disadvantages.add('Curva de mana mais alta');
    recommendations.add('Reduzir CMC médio do deck');
  }

  // Counterspells (vantagem em matchups)
  final myCounters = (myStats['counterspells'] as int?) ?? 0;
  if (myCounters >= 5) {
    myScore += 5;
    advantages.add('Boa quantidade de counters ($myCounters)');
  }

  // Verificar se tem hate cards
  int hateCardCount = 0;
  for (final card in myCards) {
    if (hateCardsForOpponent.contains(card['name'])) {
      hateCardCount++;
    }
  }
  
  if (hateCardCount > 0) {
    myScore += hateCardCount * 3;
    advantages.add('Tem $hateCardCount hate cards contra $opponentArchetype');
  } else if (hateCardsForOpponent.isNotEmpty) {
    myScore -= 5;
    disadvantages.add('Sem hate cards contra $opponentArchetype');
    recommendations.addAll(hateCardsForOpponent.take(3).map((c) => 'Considerar adicionar: $c'));
  }

  // Matchup arquétipo vs arquétipo
  final matchupModifier = _getArchetypeMatchupModifier(myArchetype, opponentArchetype);
  myScore += matchupModifier;
  if (matchupModifier > 0) {
    advantages.add('$myArchetype geralmente tem vantagem contra $opponentArchetype');
  } else if (matchupModifier < 0) {
    disadvantages.add('$opponentArchetype geralmente tem vantagem contra $myArchetype');
  }

  // Simular partidas (Monte Carlo simplificado)
  final random = Random();
  int wins = 0;
  int totalTurns = 0;

  for (int i = 0; i < simulationCount; i++) {
    // Simular uma partida baseada nas estatísticas
    final roll = random.nextDouble() * 100;
    
    // Adicionar variância
    final variance = (random.nextDouble() - 0.5) * 20;
    final effectiveWinChance = myScore + variance;
    
    if (roll < effectiveWinChance) {
      wins++;
      // Estimar turnos para vitória baseado na curva
      totalTurns += (6 + (myCMC * 1.5) + random.nextInt(4)).round();
    } else {
      totalTurns += (6 + (oppCMC * 1.5) + random.nextInt(4)).round();
    }
  }

  final winRate = wins / simulationCount;
  final avgTurns = totalTurns / simulationCount;

  // Salvar resultado no banco
  try {
    await pool.execute(
      Sql.named('''
        INSERT INTO deck_matchups (deck_id, opponent_deck_id, win_rate, notes)
        VALUES (@my_deck, @opp_deck, @win_rate, @notes)
        ON CONFLICT (deck_id, opponent_deck_id) 
        DO UPDATE SET win_rate = @win_rate, notes = @notes, updated_at = CURRENT_TIMESTAMP
      '''),
      parameters: {
        'my_deck': myDeck['id'],
        'opp_deck': opponentDeck['id'],
        'win_rate': winRate,
        'notes': 'Auto-generated: ${advantages.join(", ")}',
      },
    );
  } catch (e) {
    print('[ERROR] handler: $e');
    print('Aviso: Não foi possível salvar matchup: $e');
  }

  return Response.json(body: {
    'my_deck': {
      'id': myDeck['id'],
      'name': myDeck['name'],
      'archetype': myArchetype,
      'commander': myDeck['commander'],
    },
    'opponent_deck': {
      'id': opponentDeck['id'],
      'name': opponentDeck['name'],
      'archetype': opponentArchetype,
      'is_meta_deck': isMetaDeck,
    },
    'simulation': {
      'runs': simulationCount,
      'wins': wins,
      'losses': simulationCount - wins,
      'win_rate': (winRate * 100).toStringAsFixed(1) + '%',
      'win_rate_numeric': winRate,
      'average_game_length': avgTurns.toStringAsFixed(1),
    },
    'analysis': {
      'base_win_chance': myScore,
      'advantages': advantages,
      'disadvantages': disadvantages,
    },
    'recommendations': {
      'cards_to_add': recommendations,
      'hate_cards_for_opponent': hateCardsForOpponent.take(5).toList(),
    },
    'matchup_verdict': _getMatchupVerdict(winRate),
  });
}

/// Retorna modificador de win rate baseado em matchup de arquétipos
double _getArchetypeMatchupModifier(String myArchetype, String oppArchetype) {
  final matchups = {
    'aggro': {'control': -10, 'combo': 5, 'midrange': 0, 'ramp': 10},
    'control': {'aggro': 10, 'combo': -5, 'midrange': 5, 'ramp': 5},
    'combo': {'aggro': -5, 'control': 5, 'midrange': 0, 'stax': -15},
    'midrange': {'aggro': 0, 'control': -5, 'combo': 0, 'ramp': 0},
    'ramp': {'aggro': -10, 'control': -5, 'combo': 5, 'midrange': 0},
    'graveyard': {'control': -5, 'aggro': 5},
    'tokens': {'control': -10, 'aggro': -5},
    'stax': {'combo': 15, 'control': 5, 'aggro': 0},
  };

  return matchups[myArchetype]?[oppArchetype]?.toDouble() ?? 0.0;
}

/// Retorna veredicto textual do matchup
String _getMatchupVerdict(double winRate) {
  if (winRate >= 0.65) return 'Matchup MUITO favorável ✅';
  if (winRate >= 0.55) return 'Matchup favorável 👍';
  if (winRate >= 0.45) return 'Matchup equilibrado ⚖️';
  if (winRate >= 0.35) return 'Matchup desfavorável 👎';
  return 'Matchup MUITO desfavorável ❌';
}
