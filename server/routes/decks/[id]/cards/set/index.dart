import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

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

      if (replaceSameName) {
        await session.execute(
          Sql.named('''
            DELETE FROM deck_cards dc
            USING cards c
            WHERE dc.card_id = c.id
              AND dc.deck_id = @deckId
              AND LOWER(c.name) = LOWER(@name)
              AND dc.is_commander = FALSE
          '''),
          parameters: {'deckId': deckId, 'name': cardName},
        );
      } else {
        await session.execute(
          Sql.named(
            'DELETE FROM deck_cards WHERE deck_id = @deckId AND card_id = @cardId AND is_commander = FALSE',
          ),
          parameters: {'deckId': deckId, 'cardId': cardId},
        );
      }

      await session.execute(
        Sql.named('''
          INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander)
          VALUES (@deckId, @cardId, @qty, FALSE)
          ON CONFLICT (deck_id, card_id) DO UPDATE SET
            quantity = EXCLUDED.quantity,
            is_commander = (deck_cards.is_commander OR EXCLUDED.is_commander)
        '''),
        parameters: {'deckId': deckId, 'cardId': cardId, 'qty': quantity},
      );

      return {
        'ok': true,
        'deck_id': deckId,
        'card_id': cardId,
        'name': cardName,
        'quantity': quantity,
        'replace_same_name': replaceSameName,
      };
    });

    if (result is Map && result['status'] is int && result['error'] != null) {
      return Response.json(
        statusCode: result['status'] as int,
        body: {'error': result['error']},
      );
    }

    return Response.json(body: (result as Map).cast<String, dynamic>());
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}
