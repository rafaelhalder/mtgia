import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/archetype_counters_service.dart';
import '../../../lib/http_responses.dart';

/// Endpoint para análise de fraquezas do deck
/// 
/// POST /ai/weakness-analysis
/// Body: { "deck_id": "uuid" }
/// 
/// Retorna lista de fraquezas identificadas com recomendações
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return methodNotAllowed();
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final deckId = body['deck_id'] as String?;

    if (deckId == null) {
      return badRequest('deck_id is required');
    }

    final pool = context.read<Pool>();
    final countersService = ArchetypeCountersService(pool);

    // 1. Buscar informações do deck
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format FROM decks WHERE id = @id'),
      parameters: {'id': deckId},
    );

    if (deckResult.isEmpty) {
      return notFound('Deck not found');
    }

    final deckName = deckResult.first[0] as String;
    final deckFormat = deckResult.first[1] as String;

    // 2. Buscar todas as cartas do deck com detalhes
    final cardsResult = await pool.execute(
      Sql.named('''
        SELECT c.name, c.type_line, c.oracle_text, c.mana_cost, c.colors, dc.quantity,
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
    final deckColors = <String>{};
    
    int totalCards = 0;
    int landCount = 0;
    int creatureCount = 0;
    int rampCount = 0;
    int drawCount = 0;
    int removalCount = 0;
    int boardWipeCount = 0;
    int protectionCount = 0;
    int graveyardInteractionCount = 0;
    double totalCMC = 0;
    int nonLandCards = 0;

    for (final row in cardsResult) {
      final name = row[0] as String;
      final typeLine = (row[1] as String?) ?? '';
      final oracleText = ((row[2] as String?) ?? '').toLowerCase();
      final manaCost = (row[3] as String?) ?? '';
      final colors = (row[4] as List?)?.cast<String>() ?? [];
      final quantity = row[5] as int;
      final cmc = (row[6] as num?)?.toDouble() ?? 0;

      deckColors.addAll(colors);
      totalCards += quantity;

      cards.add({
        'name': name,
        'type_line': typeLine,
        'oracle_text': oracleText,
        'mana_cost': manaCost,
        'colors': colors,
        'quantity': quantity,
        'cmc': cmc,
      });

      final typeLineLower = typeLine.toLowerCase();

      // Contar tipos e categorias
      if (typeLineLower.contains('land')) {
        landCount += quantity;
      } else {
        nonLandCards += quantity;
        totalCMC += cmc * quantity;
      }

      if (typeLineLower.contains('creature')) {
        creatureCount += quantity;
      }

      // Detectar ramp (expanded: mana dorks, treasure, mana rocks, land ramp)
      if (oracleText.contains('add {') || 
          (oracleText.contains('search your library for a') && oracleText.contains('land')) ||
          oracleText.contains('put a land card') ||
          oracleText.contains('create a treasure') ||
          oracleText.contains('create treasure') ||
          (typeLineLower.contains('creature') && oracleText.contains('add') && oracleText.contains('mana')) ||
          (typeLineLower.contains('artifact') && !typeLineLower.contains('creature') && oracleText.contains('add {') && cmc <= 3)) {
        rampCount += quantity;
      }

      // Detectar card draw (expanded: "look at the top", impulse draw, "reveal...put into hand")
      if ((oracleText.contains('draw') && oracleText.contains('card')) ||
          (oracleText.contains('look at the top') && oracleText.contains('put') && oracleText.contains('hand')) ||
          (oracleText.contains('exile') && oracleText.contains('may play') && !oracleText.contains('target')) ||
          (oracleText.contains('exile') && oracleText.contains('may cast') && !oracleText.contains('target')) ||
          (oracleText.contains('reveal') && oracleText.contains('put') && oracleText.contains('into your hand'))) {
        drawCount += quantity;
      }

      // Detectar removal (expanded: -X/-X, sacrifice, bounce, counter)
      if (oracleText.contains('destroy target') || 
          oracleText.contains('exile target') ||
          (oracleText.contains('deal') && oracleText.contains('damage to target')) ||
          (oracleText.contains('target') && oracleText.contains('gets -') && oracleText.contains('/-')) ||
          oracleText.contains('counter target spell') ||
          (oracleText.contains('target') && oracleText.contains('owner\'s hand') && typeLineLower.contains('instant'))) {
        removalCount += quantity;
      }

      // Detectar board wipes (expanded: "all creatures get -X/-X", "each creature", "return all")
      if (oracleText.contains('destroy all') || 
          oracleText.contains('exile all') ||
          (oracleText.contains('all creatures get -') && oracleText.contains('/-')) ||
          (oracleText.contains('each creature') && oracleText.contains('damage')) ||
          (oracleText.contains('return all') && oracleText.contains('to their owner'))) {
        boardWipeCount += quantity;
      }

      // Detectar proteção
      if (oracleText.contains('hexproof') || 
          oracleText.contains('indestructible') ||
          oracleText.contains('protection from') ||
          oracleText.contains('shroud') ||
          oracleText.contains('ward') ||
          oracleText.contains('counter target spell') ||
          name.toLowerCase().contains('teferi\'s protection') ||
          name.toLowerCase().contains('heroic intervention')) {
        protectionCount += quantity;
      }

      // Detectar interação com cemitério
      if (oracleText.contains('graveyard') || 
          (oracleText.contains('return') && oracleText.contains('from'))) {
        graveyardInteractionCount += quantity;
      }
    }

    // 3. Detectar arquétipo do deck
    final archetypeAnalysis = await countersService.detectDeckArchetype(cards: cards);
    final detectedArchetype = archetypeAnalysis['archetype'] as String;

    // 4. Calcular métricas
    final avgCMC = nonLandCards > 0 ? totalCMC / nonLandCards : 0.0;
    final isCommander = deckFormat.toLowerCase() == 'commander';

    // 5. Identificar fraquezas
    final weaknesses = <Map<String, dynamic>>[];

    // Verificar quantidade de terrenos
    if (isCommander) {
      if (landCount < 33) {
        weaknesses.add({
          'type': 'low_land_count',
          'severity': 'high',
          'description': 'Deck tem apenas $landCount terrenos. Commander decks geralmente precisam de 35-38.',
          'recommendations': ['Adicionar ${35 - landCount} terrenos', 'Considerar terrenos que produzem múltiplas cores'],
          'current_value': landCount,
          'recommended_value': 36,
        });
      } else if (landCount > 40) {
        weaknesses.add({
          'type': 'high_land_count',
          'severity': 'low',
          'description': 'Deck tem $landCount terrenos. Pode ser excessivo para alguns arquétipos.',
          'recommendations': ['Considerar reduzir terrenos se tiver muito ramp'],
          'current_value': landCount,
          'recommended_value': 37,
        });
      }
    }

    // Verificar ramp
    if (rampCount < 8) {
      weaknesses.add({
        'type': 'insufficient_ramp',
        'severity': rampCount < 5 ? 'critical' : 'high',
        'description': 'Deck tem apenas $rampCount fontes de ramp. Recomendado: 10-12.',
        'recommendations': ['Sol Ring', 'Arcane Signet', 'Signets/Talismans das suas cores', 'Cultivate', 'Kodama\'s Reach'],
        'current_value': rampCount,
        'recommended_value': 10,
      });
    }

    // Verificar card draw
    if (drawCount < 8) {
      weaknesses.add({
        'type': 'insufficient_card_draw',
        'severity': drawCount < 4 ? 'critical' : 'high',
        'description': 'Deck tem apenas $drawCount fontes de draw. Recomendado: 10+.',
        'recommendations': ['Rhystic Study', 'Mystic Remora', 'Beast Whisperer', 'Phyrexian Arena'],
        'current_value': drawCount,
        'recommended_value': 10,
      });
    }

    // Verificar removal
    if (removalCount < 6) {
      weaknesses.add({
        'type': 'insufficient_removal',
        'severity': removalCount < 3 ? 'critical' : 'medium',
        'description': 'Deck tem apenas $removalCount remoções pontuais. Recomendado: 8-10.',
        'recommendations': ['Swords to Plowshares', 'Path to Exile', 'Beast Within', 'Generous Gift'],
        'current_value': removalCount,
        'recommended_value': 8,
      });
    }

    // Verificar board wipes
    if (boardWipeCount < 2) {
      weaknesses.add({
        'type': 'insufficient_board_wipes',
        'severity': 'medium',
        'description': 'Deck tem apenas $boardWipeCount board wipes. Recomendado: 3-4.',
        'recommendations': ['Wrath of God', 'Damnation', 'Cyclonic Rift', 'Toxic Deluge'],
        'current_value': boardWipeCount,
        'recommended_value': 3,
      });
    }

    // Verificar curva de mana
    if (avgCMC > 3.5 && detectedArchetype != 'control') {
      weaknesses.add({
        'type': 'high_mana_curve',
        'severity': avgCMC > 4.0 ? 'high' : 'medium',
        'description': 'CMC médio de ${avgCMC.toStringAsFixed(2)} é alto para $detectedArchetype.',
        'recommendations': ['Reduzir cartas com CMC > 5', 'Adicionar mais cartas de custo 1-3'],
        'current_value': avgCMC,
        'recommended_value': 2.5,
      });
    }

    // Verificar vulnerabilidade a graveyard hate
    if (graveyardInteractionCount > 10 && protectionCount < 3) {
      weaknesses.add({
        'type': 'graveyard_vulnerability',
        'severity': 'high',
        'description': 'Deck depende muito do cemitério ($graveyardInteractionCount cartas) mas tem pouca proteção.',
        'recommendations': ['Teferi\'s Protection', 'Heroic Intervention', 'Ground Seal', 'Orbs of Warding'],
        'current_value': graveyardInteractionCount,
        'recommended_value': 0,
      });
    }

    // Verificar proteção geral
    if (protectionCount < 3) {
      weaknesses.add({
        'type': 'low_protection',
        'severity': 'medium',
        'description': 'Deck tem apenas $protectionCount fontes de proteção.',
        'recommendations': ['Lightning Greaves', 'Swiftfoot Boots', 'Heroic Intervention', 'Teferi\'s Protection'],
        'current_value': protectionCount,
        'recommended_value': 5,
      });
    }

    // Verificar remoção de artefatos/encantamentos
    int artifactEnchantmentRemovalCount = 0;
    for (final card in cards) {
      final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
      if (oracle.contains('destroy target artifact') ||
          oracle.contains('destroy target enchantment') ||
          oracle.contains('exile target artifact') ||
          oracle.contains('exile target enchantment') ||
          oracle.contains('destroy target nonland permanent') ||
          oracle.contains('exile target nonland permanent') ||
          oracle.contains('destroy target permanent')) {
        artifactEnchantmentRemovalCount += (card['quantity'] as int);
      }
    }
    if (artifactEnchantmentRemovalCount < 3) {
      weaknesses.add({
        'type': 'insufficient_artifact_enchantment_removal',
        'severity': artifactEnchantmentRemovalCount == 0 ? 'critical' : 'medium',
        'description': 'Deck tem apenas $artifactEnchantmentRemovalCount remoções de artefatos/encantamentos. Recomendado: 4-6.',
        'recommendations': ['Nature\'s Claim', 'Beast Within', 'Generous Gift', 'Vandalblast', 'Austere Command'],
        'current_value': artifactEnchantmentRemovalCount,
        'recommended_value': 5,
      });
    }

    // Verificar win conditions (cartas que podem fechar o jogo)
    int winConditionCount = 0;
    for (final card in cards) {
      final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
      final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
      if (oracle.contains('you win the game') ||
          oracle.contains('each opponent loses') ||
          oracle.contains('extra turn') ||
          (oracle.contains('deal') && oracle.contains('damage to each opponent')) ||
          (typeLine.contains('creature') && oracle.contains('whenever') && oracle.contains('combat damage to a player')) ||
          (oracle.contains('x') && oracle.contains('each opponent') && oracle.contains('loses')) ||
          (oracle.contains('damage to any target') && oracle.contains('x')) ||
          oracle.contains('you gain control of target') ||
          (oracle.contains('create') && oracle.contains('token') && oracle.contains('each'))) {
        winConditionCount += (card['quantity'] as int);
      }
    }
    if (winConditionCount < 2) {
      weaknesses.add({
        'type': 'insufficient_win_conditions',
        'severity': winConditionCount == 0 ? 'critical' : 'high',
        'description': 'Deck tem apenas $winConditionCount condições de vitória claras. Recomendado: 2-3 caminhos distintos para vencer.',
        'recommendations': ['Adicionar finalizadores que fechem o jogo', 'Considerar combos de 2-3 cartas', 'Incluir dano direto ou drain effects'],
        'current_value': winConditionCount,
        'recommended_value': 3,
      });
    }

    // Verificar se o deck tem interação no turno dos oponentes (instant-speed)
    int instantSpeedCount = 0;
    for (final card in cards) {
      final typeLine = ((card['type_line'] as String?) ?? '').toLowerCase();
      final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
      if (typeLine.contains('instant') || oracle.contains('flash')) {
        instantSpeedCount += (card['quantity'] as int);
      }
    }
    if (isCommander && instantSpeedCount < 8) {
      weaknesses.add({
        'type': 'low_instant_speed_interaction',
        'severity': instantSpeedCount < 4 ? 'high' : 'medium',
        'description': 'Deck tem apenas $instantSpeedCount cartas instant-speed. Em multiplayer, interação nos turnos dos oponentes é crucial.',
        'recommendations': ['Priorizar instants sobre sorceries', 'Adicionar counterspells', 'Incluir removal instant-speed como Swords to Plowshares'],
        'current_value': instantSpeedCount,
        'recommended_value': 10,
      });
    }

    // 6. Buscar hate cards recomendados para o arquétipo detectado
    final hateCards = await countersService.getHateCards(
      archetype: detectedArchetype,
      colors: deckColors.toList(),
    );

    // 7. Salvar análise no banco (opcional)
    try {
      for (final weakness in weaknesses) {
        await pool.execute(
          Sql.named('''
            INSERT INTO deck_weakness_reports 
              (deck_id, weakness_type, severity, description, recommendations, auto_detected)
            VALUES 
              (@deck_id, @type, @severity, @description, @recommendations, TRUE)
            ON CONFLICT DO NOTHING
          '''),
          parameters: {
            'deck_id': deckId,
            'type': weakness['type'],
            'severity': weakness['severity'],
            'description': weakness['description'],
            'recommendations': TypedValue(Type.textArray, weakness['recommendations'] as List<String>),
          },
        );
      }
    } catch (e) {
      print('[ERROR] handler: $e');
      // Não falha se não conseguir salvar
      print('Aviso: Não foi possível salvar relatório de fraquezas: $e');
    }

    // 8. Retornar análise completa
    return Response.json(body: {
      'deck_id': deckId,
      'deck_name': deckName,
      'format': deckFormat,
      'detected_archetype': detectedArchetype,
      'archetype_confidence': archetypeAnalysis['confidence'],
      'statistics': {
        'total_cards': totalCards,
        'lands': landCount,
        'creatures': creatureCount,
        'ramp_sources': rampCount,
        'card_draw': drawCount,
        'removal': removalCount,
        'board_wipes': boardWipeCount,
        'protection': protectionCount,
        'average_cmc': avgCMC.toStringAsFixed(2),
      },
      'weaknesses': weaknesses,
      'weakness_count': weaknesses.length,
      'critical_count': weaknesses.where((w) => w['severity'] == 'critical').length,
      'hate_cards_for_archetype': hateCards,
      'colors': deckColors.toList(),
    });

  } catch (e, stack) {
    print('Erro em weakness-analysis: $e\n$stack');
    return internalServerError('Failed to analyze deck weaknesses');
  }
}
