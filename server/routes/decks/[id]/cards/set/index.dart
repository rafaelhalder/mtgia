import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../../../../../lib/deck_rules_service.dart';

/// POST /decks/:id/cards/set
///
/// Body:
/// {
///   "card_id": "...",
///   "quantity": 1,
///   "replace_same_name": true|false
/// }
///
/// - quantity é ABSOLUTO (não soma).
/// - Se replace_same_name=true, remove todas as outras edições da mesma carta
///   (mesmo nome) do deck antes de setar a quantidade.
Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final pool = context.read<Pool>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'JSON inválido'},
    );
  }

  final cardId = body['card_id']?.toString();
  final quantityRaw = body['quantity'];
  final quantity = quantityRaw is int
      ? quantityRaw
      : int.tryParse(quantityRaw?.toString() ?? '');
  final replaceSameName = body['replace_same_name'] == true;
  final condition = _validateCondition(body['condition']?.toString());

  if (cardId == null || cardId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'card_id é obrigatório'},
    );
  }
  if (quantity == null || quantity <= 0) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'quantity deve ser > 0'},
    );
  }

  try {
    final result = await pool.runTx((session) async {
      final deckResult = await session.execute(
        Sql.named(
          'SELECT format FROM decks WHERE id = @deckId AND user_id = @userId LIMIT 1',
        ),
        parameters: {'deckId': deckId, 'userId': userId},
      );
      if (deckResult.isEmpty) {
        throw Exception('Deck not found or permission denied.');
      }
      final format = (deckResult.first[0] as String).toLowerCase();

      final cardInfo = await session.execute(
        Sql.named(
          'SELECT name, type_line FROM cards WHERE id = @id LIMIT 1',
        ),
        parameters: {'id': cardId},
      );
      if (cardInfo.isEmpty) {
        return {
          'error': 'Carta não encontrada.',
          'status': HttpStatus.badRequest,
        };
      }
      final cardName = (cardInfo.first[0] as String).trim();
      final typeLine = (cardInfo.first[1] as String? ?? '').toLowerCase();
      final isBasicLand = typeLine.contains('basic land');

      // Validação mínima por carta (permite corrigir decks que já estão inválidos)
      // - Commander/Brawl: nonbasic deve ser exatamente 1.
      // - Outros formatos: nonbasic não pode exceder 4.
      final maxCopies = (format == 'commander' || format == 'brawl') ? 1 : 4;
      if (!isBasicLand && quantity > maxCopies) {
        return {
          'error':
              'Regra violada: "$cardName" excede o limite de $maxCopies cópia(s) para o formato $format.',
          'status': HttpStatus.badRequest,
        };
      }

      final existingCardsResult = await session.execute(
        Sql.named('''
          SELECT dc.card_id::text, dc.quantity::int, dc.is_commander, dc.condition, c.name
          FROM deck_cards dc
          JOIN cards c ON c.id = dc.card_id
          WHERE dc.deck_id = @deckId
        '''),
        parameters: {'deckId': deckId},
      );

      final nextCards = <String, Map<String, dynamic>>{};
      for (final row in existingCardsResult) {
        final existingCardId = row[0] as String;
        nextCards[existingCardId] = {
          'card_id': existingCardId,
          'quantity': row[1] as int,
          'is_commander': row[2] as bool? ?? false,
          'condition': row[3] as String? ?? 'NM',
          'name': row[4] as String,
        };
      }

      if (replaceSameName) {
        nextCards.removeWhere((_, card) {
          final sameName = (card['name'] as String).toLowerCase() ==
              cardName.toLowerCase();
          final isCommander = card['is_commander'] as bool? ?? false;
          return sameName && !isCommander;
        });
      } else {
        final existing = nextCards[cardId];
        if (existing != null && !(existing['is_commander'] as bool? ?? false)) {
          nextCards.remove(cardId);
        }
      }

      nextCards[cardId] = {
        'card_id': cardId,
        'quantity': quantity,
        'is_commander': false,
        'condition': condition,
        'name': cardName,
      };

      final validatedCards = nextCards.values
          .map((card) => {
                'card_id': card['card_id'],
                'quantity': card['quantity'],
                'is_commander': card['is_commander'],
              })
          .toList();

      await DeckRulesService(session).validateAndThrow(
        format: format,
        cards: validatedCards,
        strict: false,
      );

      await session.execute(
        Sql.named('DELETE FROM deck_cards WHERE deck_id = @deckId'),
        parameters: {'deckId': deckId},
      );

      if (nextCards.isNotEmpty) {
        final values = <String>[];
        final params = <String, dynamic>{'deckId': deckId};

        final cardsList = nextCards.values.toList();
        for (var i = 0; i < cardsList.length; i++) {
          final card = cardsList[i];
          final pId = 'c$i';
          final pQty = 'q$i';
          final pCmd = 'cmd$i';
          final pCond = 'cond$i';

          values.add('(@deckId, @$pId, @$pQty, @$pCmd, @$pCond)');
          params[pId] = card['card_id'];
          params[pQty] = card['quantity'];
          params[pCmd] = card['is_commander'] ?? false;
          params[pCond] = card['condition'] ?? 'NM';
        }

        final sql = '''
          INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander, condition)
          VALUES ${values.join(', ')}
        ''';
        await session.execute(Sql.named(sql), parameters: params);
      }

      return {
        'ok': true,
        'deck_id': deckId,
        'card_id': cardId,
        'name': cardName,
        'quantity': quantity,
        'condition': condition,
        'replace_same_name': replaceSameName,
      };
    });

    if (result['status'] != null && result['error'] != null) {
      return Response.json(
        statusCode: result['status'] as int,
        body: {'error': result['error']},
      );
    }

    return Response.json(body: result.cast<String, dynamic>());
  } on DeckRulesException catch (e) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': e.message},
    );
  } catch (e) {
    print('[ERROR] handler: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}

/// Valida e normaliza o valor de condição da carta.
String _validateCondition(String? raw) {
  if (raw == null) return 'NM';
  final upper = raw.trim().toUpperCase();
  const valid = {'NM', 'LP', 'MP', 'HP', 'DMG'};
  return valid.contains(upper) ? upper : 'NM';
}
