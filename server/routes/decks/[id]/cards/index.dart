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

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
        statusCode: HttpStatus.badRequest, body: {'error': 'JSON inválido'});
  }

  final cardId = body['card_id']?.toString();
  final quantityRaw = body['quantity'];
  final quantity = quantityRaw is int
      ? quantityRaw
      : int.tryParse(quantityRaw?.toString() ?? '');
  final isCommander = body['is_commander'] == true;
  final condition = _validateCondition(body['condition']?.toString());

  if (cardId == null || cardId.isEmpty) {
    return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'card_id é obrigatório'});
  }
  if (quantity == null || quantity <= 0) {
    return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'quantity deve ser > 0'});
  }

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
      final maxTotal = (format == 'commander')
          ? 100
          : (format == 'brawl')
              ? 60
              : null;

      final cardInfoResult = await session.execute(
        Sql.named(
            'SELECT id::text, name, type_line, oracle_text, colors, color_identity FROM cards WHERE id = @id LIMIT 1'),
        parameters: {'id': cardId},
      );
      if (cardInfoResult.isEmpty) {
        throw DeckRulesException('Carta não encontrada.');
      }

      final row = cardInfoResult.first;
      final cardName = row[1] as String;
      final typeLine = (row[2] as String? ?? '').toLowerCase();
      final oracleText = row[3] as String?;
      final colors = (row[4] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      final colorIdentity =
          (row[5] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];

      // Legalidade (banned/not_legal/restricted)
      final legalityResult = await session.execute(
        Sql.named(
            'SELECT status FROM card_legalities WHERE card_id = @id AND format = @format LIMIT 1'),
        parameters: {'id': cardId, 'format': format},
      );
      if (legalityResult.isNotEmpty) {
        final status = (legalityResult.first[0] as String).toLowerCase();
        if (status == 'banned') {
          throw DeckRulesException(
              'Regra violada: "$cardName" é BANIDA no formato $format.');
        }
        if (status == 'not_legal') {
          throw DeckRulesException(
              'Regra violada: "$cardName" não é válida no formato $format.');
        }
        if (status == 'restricted' && quantity > 1) {
          throw DeckRulesException(
              'Regra violada: "$cardName" é RESTRITA no formato $format (máx. 1).');
        }
      }

      final isBasicLand = typeLine.contains('basic land');
      final maxCopies = (format == 'commander' || format == 'brawl') ? 1 : 4;
      if (!isBasicLand && quantity > maxCopies && !isCommander) {
        throw DeckRulesException(
            'Regra violada: "$cardName" excede o limite de $maxCopies cópia(s) para o formato $format.');
      }

      if (isCommander && quantity != 1) {
        throw DeckRulesException(
            'Regra violada: comandante deve ter quantidade 1.');
      }

      // Total atual de cartas
      final totalResult = await session.execute(
        Sql.named(
            'SELECT COALESCE(SUM(quantity), 0)::int FROM deck_cards WHERE deck_id = @deckId'),
        parameters: {'deckId': deckId},
      );
      final currentTotal = (totalResult.first[0] as int?) ?? 0;

      // Quantidade atual da carta no deck (se existir)
      final existingResult = await session.execute(
        Sql.named(
            'SELECT quantity::int, is_commander FROM deck_cards WHERE deck_id = @deckId AND card_id = @cardId LIMIT 1'),
        parameters: {'deckId': deckId, 'cardId': cardId},
      );
      final existingQty =
          existingResult.isNotEmpty ? (existingResult.first[0] as int) : 0;
      final existingIsCommander = existingResult.isNotEmpty
          ? (existingResult.first[1] as bool? ?? false)
          : false;

      final nextQty = isCommander ? 1 : existingQty + quantity;

      // Limite de cópias por NOME (para suportar múltiplas edições/printings)
      if (!isCommander && !isBasicLand) {
        final byNameResult = await session.execute(
          Sql.named('''
            SELECT COALESCE(SUM(dc.quantity), 0)::int
            FROM deck_cards dc
            JOIN cards c ON c.id = dc.card_id
            WHERE dc.deck_id = @deckId
              AND dc.is_commander = FALSE
              AND LOWER(c.name) = LOWER(@name)
          '''),
          parameters: {'deckId': deckId, 'name': cardName},
        );
        final currentNameQty = (byNameResult.first[0] as int?) ?? 0;
        final nextNameQty = currentNameQty + quantity;
        if (nextNameQty > maxCopies) {
          throw DeckRulesException(
            'Regra violada: "$cardName" excede o limite de $maxCopies cópia(s) para o formato $format.',
          );
        }
      }

      // Limite de total de cartas (quando aplicável)
      if (maxTotal != null) {
        final delta = nextQty - existingQty;
        final nextTotal = currentTotal + delta;
        if (nextTotal > maxTotal) {
          throw DeckRulesException(
              'Regra violada: deck $format não pode exceder $maxTotal cartas (atual: $nextTotal).');
        }
      }

      // Regras de Commander: identidade de cor e elegibilidade do comandante
      if (format == 'commander' || format == 'brawl') {
        if (isCommander) {
          final typeLower = typeLine;
          final oracleLower = (oracleText ?? '').toLowerCase();
          final eligible = (typeLower.contains('legendary') &&
                  typeLower.contains('creature')) ||
              oracleLower.contains('can be your commander');
          if (!eligible) {
            throw DeckRulesException(
                'Regra violada: "$cardName" não pode ser comandante.');
          }

          // Substituir comandante existente (MVP: 1 comandante)
          await session.execute(
            Sql.named(
                'UPDATE deck_cards SET is_commander = FALSE WHERE deck_id = @deckId AND is_commander = TRUE'),
            parameters: {'deckId': deckId},
          );

          // Validar identidade do comandante contra TODAS as cartas já no deck (inclusive esta).
          final commanderIdentity =
              (colorIdentity.isNotEmpty ? colorIdentity : colors)
                  .map((e) => e.toUpperCase())
                  .toSet();
          final deckCardsResult = await session.execute(
            Sql.named('''
              SELECT c.name, c.color_identity, c.colors
              FROM deck_cards dc
              JOIN cards c ON c.id = dc.card_id
              WHERE dc.deck_id = @deckId
            '''),
            parameters: {'deckId': deckId},
          );
          for (final r in deckCardsResult) {
            final n = r[0] as String;
            final id = (r[1] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
            final cs = (r[2] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
            final identity = (id.isNotEmpty ? id : cs);
            final ok = identity
                .every((c) => commanderIdentity.contains(c.toUpperCase()));
            if (!ok) {
              throw DeckRulesException(
                  'Regra violada: "$n" está fora da identidade de cor do comandante.');
            }
          }
        } else {
          // Se já existe comandante, validar identidade antes de inserir.
          final commanderResult = await session.execute(
            Sql.named('''
              SELECT c.color_identity, c.colors
              FROM deck_cards dc
              JOIN cards c ON c.id = dc.card_id
              WHERE dc.deck_id = @deckId AND dc.is_commander = TRUE
              LIMIT 1
            '''),
            parameters: {'deckId': deckId},
          );
          if (commanderResult.isNotEmpty) {
            final commanderIdentityList = (commanderResult.first[0] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const <String>[];
            final commanderColors = (commanderResult.first[1] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const <String>[];
            final commanderSet = (commanderIdentityList.isNotEmpty
                    ? commanderIdentityList
                    : commanderColors)
                .map((e) => e.toUpperCase())
                .toSet();

            final identity =
                (colorIdentity.isNotEmpty ? colorIdentity : colors);
            final ok =
                identity.every((c) => commanderSet.contains(c.toUpperCase()));
            if (!ok) {
              throw DeckRulesException(
                  'Regra violada: "$cardName" está fora da identidade de cor do comandante.');
            }
          }
        }
      }

      // Upsert (deck_id, card_id) com a quantidade final, flag de comandante e condição
      await session.execute(
        Sql.named('''
          INSERT INTO deck_cards (deck_id, card_id, quantity, is_commander, condition)
          VALUES (@deckId, @cardId, @qty, @isCommander, @condition)
          ON CONFLICT (deck_id, card_id) DO UPDATE SET
            quantity = EXCLUDED.quantity,
            is_commander = EXCLUDED.is_commander,
            condition = EXCLUDED.condition
        '''),
        parameters: {
          'deckId': deckId,
          'cardId': cardId,
          'qty': nextQty,
          'isCommander': isCommander || existingIsCommander,
          'condition': condition,
        },
      );

      final updatedTotalResult = await session.execute(
        Sql.named(
            'SELECT COALESCE(SUM(quantity), 0)::int FROM deck_cards WHERE deck_id = @deckId'),
        parameters: {'deckId': deckId},
      );
      final updatedTotal = (updatedTotalResult.first[0] as int?) ?? 0;

      return {
        'ok': true,
        'deck_id': deckId,
        'card_id': cardId,
        'card_name': cardName,
        'quantity': nextQty,
        'is_commander': isCommander || existingIsCommander,
        'condition': condition,
        'total_cards': updatedTotal,
      };
    });

    return Response.json(body: result);
  } on DeckRulesException catch (e) {
    print('[ERROR] handler: $e');
    return Response.json(
        statusCode: HttpStatus.badRequest, body: {'error': e.message});
  } catch (e) {
    print('[ERROR] handler: $e');
    return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': e.toString()});
  }
}

/// Valida e normaliza o valor de condição da carta.
/// Valores válidos: NM, LP, MP, HP, DMG (padrão TCGPlayer).
String _validateCondition(String? raw) {
  if (raw == null) return 'NM';
  final upper = raw.trim().toUpperCase();
  const valid = {'NM', 'LP', 'MP', 'HP', 'DMG'};
  return valid.contains(upper) ? upper : 'NM';
}
