import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../../lib/deck_rules_service.dart';

/// POST /decks/:id/cards/replace
/// Body: { "old_card_id": "...", "new_card_id": "..." }
///
/// Troca a edição (card_id) de uma carta já existente no deck.
/// Importante: valida por NOME (para suportar múltiplas printings sem quebrar
/// limites de cópias).
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

  final oldCardId = body['old_card_id']?.toString();
  final newCardId = body['new_card_id']?.toString();
  if (oldCardId == null || oldCardId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'old_card_id é obrigatório'},
    );
  }
  if (newCardId == null || newCardId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'new_card_id é obrigatório'},
    );
  }
  if (oldCardId == newCardId) {
    return Response.json(body: {'ok': true, 'changed': false});
  }

  try {
    final res = await pool.runTx((session) async {
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

      final oldRow = await session.execute(
        Sql.named(
          'SELECT quantity::int, is_commander FROM deck_cards WHERE deck_id = @deckId AND card_id = @cardId LIMIT 1',
        ),
        parameters: {'deckId': deckId, 'cardId': oldCardId},
      );
      if (oldRow.isEmpty) {
        throw DeckRulesException('Carta original não encontrada no deck.');
      }
      final oldQty = oldRow.first[0] as int;
      final oldIsCommander = oldRow.first[1] as bool? ?? false;

      final cardsInfo = await session.execute(
        Sql.named('''
          SELECT id::text, name, type_line, oracle_text, colors, color_identity
          FROM cards
          WHERE id = ANY(@ids)
        '''),
        parameters: {
          'ids': [oldCardId, newCardId],
        },
      );

      Map<String, dynamic>? oldInfo;
      Map<String, dynamic>? newInfo;
      for (final r in cardsInfo) {
        final id = r[0] as String;
        final m = {
          'id': id,
          'name': r[1] as String,
          'type_line': r[2] as String? ?? '',
          'oracle_text': r[3] as String?,
          'colors': (r[4] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[],
          'color_identity':
              (r[5] as List?)?.map((e) => e.toString()).toList() ??
                  const <String>[],
        };
        if (id == oldCardId) oldInfo = m;
        if (id == newCardId) newInfo = m;
      }

      if (oldInfo == null || newInfo == null) {
        throw DeckRulesException('Carta não encontrada (old/new).');
      }

      final oldName = (oldInfo['name'] as String).trim();
      final newName = (newInfo['name'] as String).trim();
      if (oldName.toLowerCase() != newName.toLowerCase()) {
        throw DeckRulesException(
            'Só é permitido trocar edição da mesma carta.');
      }

      final newExisting = await session.execute(
        Sql.named(
          'SELECT quantity::int, is_commander FROM deck_cards WHERE deck_id = @deckId AND card_id = @cardId LIMIT 1',
        ),
        parameters: {'deckId': deckId, 'cardId': newCardId},
      );

      // Monta uma visão normalizada do deck para validar (por nome, identidade, etc).
      final deckCards = await session.execute(
        Sql.named('''
          SELECT card_id::text, quantity::int, is_commander
          FROM deck_cards
          WHERE deck_id = @deckId
        '''),
        parameters: {'deckId': deckId},
      );

      final next = <Map<String, dynamic>>[];
      for (final r in deckCards) {
        final id = r[0] as String;
        final qty = r[1] as int;
        final isCmd = r[2] as bool? ?? false;

        if (id == oldCardId) continue;

        if (id == newCardId) {
          // Se já existe, soma (vamos validar depois; se estourar, falha).
          next.add({
            'card_id': newCardId,
            'quantity': qty + oldQty,
            'is_commander': isCmd || oldIsCommander,
          });
          continue;
        }

        next.add({'card_id': id, 'quantity': qty, 'is_commander': isCmd});
      }

      if (next.every((c) => c['card_id'] != newCardId)) {
        next.add({
          'card_id': newCardId,
          'quantity': oldQty,
          'is_commander': oldIsCommander,
        });
      }

      await DeckRulesService(session).validateAndThrow(
        format: format,
        cards: next,
        strict: false,
      );

      // Aplica a troca
      if (newExisting.isNotEmpty) {
        // Merge: delete old, update new.
        final newQty = (newExisting.first[0] as int) + oldQty;
        final newIsCommander =
            (newExisting.first[1] as bool? ?? false) || oldIsCommander;

        await session.execute(
          Sql.named(
            'UPDATE deck_cards SET quantity = @qty, is_commander = @isCommander WHERE deck_id = @deckId AND card_id = @newId',
          ),
          parameters: {
            'deckId': deckId,
            'newId': newCardId,
            'qty': newQty,
            'isCommander': newIsCommander,
          },
        );
        await session.execute(
          Sql.named(
            'DELETE FROM deck_cards WHERE deck_id = @deckId AND card_id = @oldId',
          ),
          parameters: {'deckId': deckId, 'oldId': oldCardId},
        );
      } else {
        // Update in-place
        await session.execute(
          Sql.named(
            'UPDATE deck_cards SET card_id = @newId WHERE deck_id = @deckId AND card_id = @oldId',
          ),
          parameters: {
            'deckId': deckId,
            'oldId': oldCardId,
            'newId': newCardId
          },
        );
      }

      return {
        'changed': true,
        'name': oldName,
        'old_card_id': oldCardId,
        'new_card_id': newCardId,
      };
    });

    return Response.json(body: {'ok': true, ...res});
  } on DeckRulesException catch (e) {
    print('[ERROR] handler: $e');
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
