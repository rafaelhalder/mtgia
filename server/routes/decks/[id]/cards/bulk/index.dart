import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../../lib/deck_rules_service.dart';

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

  final items = (body['cards'] as List?)?.whereType<Map>().toList() ?? const [];
  if (items.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'cards é obrigatório e deve ter itens'},
    );
  }

  final parsed =
      items.map((m) => m.cast<String, dynamic>()).map((m) {
        final cardId = m['card_id']?.toString();
        final qtyRaw = m['quantity'];
        final qty = qtyRaw is int ? qtyRaw : int.tryParse('${qtyRaw ?? ''}');
        final isCommander = m['is_commander'] == true;
        return {
          'card_id': cardId,
          'quantity': qty,
          'is_commander': isCommander,
        };
      }).toList();

  if (parsed.any((e) => e['card_id'] == null || (e['card_id'] as String).isEmpty)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Todos os itens precisam de card_id válido'},
    );
  }
  if (parsed.any((e) => e['quantity'] == null || (e['quantity'] as int) <= 0)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Todos os itens precisam de quantity > 0'},
    );
  }
  if (parsed.any((e) => e['is_commander'] == true)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'bulk não aceita is_commander=true (use o endpoint single)'},
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

      // Carrega estado atual
      final existingResult = await session.execute(
        Sql.named(
          'SELECT card_id::text, quantity::int, is_commander FROM deck_cards WHERE deck_id = @deckId',
        ),
        parameters: {'deckId': deckId},
      );

      final current = <String, Map<String, dynamic>>{};
      for (final row in existingResult) {
        final cardId = row[0] as String;
        current[cardId] = {
          'card_id': cardId,
          'quantity': row[1] as int,
          'is_commander': row[2] as bool? ?? false,
        };
      }

      // Aplica incrementos
      for (final item in parsed) {
        final cardId = item['card_id'] as String;
        final qty = item['quantity'] as int;
        if (current.containsKey(cardId)) {
          final existing = current[cardId]!;
          current[cardId] = {
            ...existing,
            'quantity': (existing['quantity'] as int) + qty,
          };
        } else {
          current[cardId] = {
            'card_id': cardId,
            'quantity': qty,
            'is_commander': false,
          };
        }
      }

      final normalized = current.values.toList();

      // Valida regras (inclui identidade/banlist/limites)
      await DeckRulesService(session).validateAndThrow(
        format: format,
        cards: normalized,
        strict: false,
      );

      // Substitui o deck (em lote) – ok para bulk pois é uma operação rara.
      await session.execute(
        Sql.named('DELETE FROM deck_cards WHERE deck_id = @deckId'),
        parameters: {'deckId': deckId},
      );

      if (normalized.isNotEmpty) {
        final values = <String>[];
        final params = <String, dynamic>{'deckId': deckId};

        for (var i = 0; i < normalized.length; i++) {
          final card = normalized[i];
          final pId = 'c$i';
          final pQty = 'q$i';
          final pCmd = 'cmd$i';
          values.add('(@deckId, @$pId, @$pQty, @$pCmd)');
          params[pId] = card['card_id'];
          params[pQty] = card['quantity'];
          params[pCmd] = card['is_commander'] ?? false;
        }

        final sql =
            'INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander) VALUES ${values.join(', ')}';
        await session.execute(Sql.named(sql), parameters: params);
      }

      final total =
          normalized.fold<int>(0, (sum, c) => sum + (c['quantity'] as int));
      return {'total_cards': total};
    });

    return Response.json(body: {'ok': true, ...result});
  } on DeckRulesException catch (e) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': e.message},
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': e.toString()},
    );
  }
}

