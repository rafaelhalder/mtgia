import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/deck_rules_service.dart';

Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final pool = context.read<Pool>();

  try {
    final result = await pool.runTx((session) async {
      final deckResult = await session.execute(
        Sql.named(
            'SELECT id::text, format FROM decks WHERE id = @deckId AND user_id = @userId LIMIT 1'),
        parameters: {'deckId': deckId, 'userId': userId},
      );
      if (deckResult.isEmpty) {
        throw Exception('Deck not found or permission denied.');
      }

      final format = (deckResult.first[1] as String).toLowerCase();

      final cardsResult = await session.execute(
        Sql.named('''
          SELECT card_id::text, quantity::int, is_commander
          FROM deck_cards
          WHERE deck_id = @deckId
        '''),
        parameters: {'deckId': deckId},
      );

      final cards = cardsResult
          .map((row) => {
                'card_id': row[0] as String,
                'quantity': row[1] as int,
                'is_commander': row[2] as bool? ?? false,
              })
          .toList();

      await DeckRulesService(session)
          .validateAndThrow(format: format, cards: cards, strict: true);

      return {
        'ok': true,
        'format': format,
        'deck_id': deckId,
      };
    });

    return Response.json(body: result);
  } on DeckRulesException catch (e) {
    print('[ERROR] handler: $e');
    return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'ok': false,
          'error': e.message,
          if (e.cardName != null) 'card_name': e.cardName,
        });
  } catch (e) {
    print('[ERROR] handler: $e');
    return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'ok': false, 'error': e.toString()});
  }
}
