import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../lib/archetype_counters_service.dart';

/// Endpoint para análise de fraquezas do deck
/// 
/// POST /ai/weakness-analysis
/// Body: { "deck_id": "uuid" }
/// 
/// Retorna lista de fraquezas identificadas com recomendações
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final deckId = body['deck_id'] as String?;

    if (deckId == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'deck_id is required'},
      );
    }

    final pool = context.read<Pool>();
    final countersService = ArchetypeCountersService(pool);

    // 1. Buscar informações do deck
    final deckResult = await pool.execute(
      Sql.named('SELECT name, format FROM decks WHERE id = @id'),
      parameters: {'id': deckId},
    );

    if (deckResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Deck not found'},
      );
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

      // Detectar ramp
      if (oracleText.contains('add {') || 
          oracleText.contains('search your library for a') && oracleText.contains('land') ||
          oracleText.contains('put a land card')) {
        rampCount += quantity;
      }

      // Detectar card draw
      if (oracleText.contains('draw') && oracleText.contains('card')) {
        drawCount += quantity;
      }

      // Detectar removal
      if (oracleText.contains('destroy target') || 
          oracleText.contains('exile target') ||
          (oracleText.contains('deal') && oracleText.contains('damage to target'))) {
        removalCount += quantity;
      }

      // Detectar board wipes
      if (oracleText.contains('destroy all') || oracleText.contains('exile all')) {
        boardWipeCount += quantity;
      }

      // Detectar proteção
      if (oracleText.contains('hexproof') || 
          oracleText.contains('indestructible') ||
          oracleText.contains('protection from') ||
          oracleText.contains('shroud') ||
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
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to analyze deck weaknesses'},
    );
  }
}
