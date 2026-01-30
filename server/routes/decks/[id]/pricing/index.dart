import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// POST /decks/:id/pricing
///
/// Calcula um custo estimado do deck baseado em preço USD (Scryfall),
/// com cache em `cards.price` e `cards.price_updated_at`.
///
/// Body opcional:
/// { "force": true }
Future<Response> onRequest(RequestContext context, String deckId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final userId = context.read<String>();
  final pool = context.read<Pool>();

  final body =
      await context.request.json().catchError((_) => const <String, dynamic>{});
  final force = body is Map ? (body['force'] == true) : false;

  try {
    final deckResult = await pool.execute(
      Sql.named('''
        SELECT id
        FROM decks
        WHERE id = @deckId AND user_id = @userId
      '''),
      parameters: {'deckId': deckId, 'userId': userId},
    );
    if (deckResult.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Deck not found.'},
      );
    }

    final rows = await pool.execute(
      Sql.named('''
        SELECT
          dc.card_id::text,
          dc.quantity::int,
          dc.is_commander,
          c.name,
          c.scryfall_id::text,
          c.set_code,
          c.price,
          c.price_updated_at
        FROM deck_cards dc
        JOIN cards c ON c.id = dc.card_id
        WHERE dc.deck_id = @deckId
      '''),
      parameters: {'deckId': deckId},
    );

    final items = <Map<String, dynamic>>[];
    var total = 0.0;
    var missing = 0;

    for (final r in rows) {
      final m = r.toColumnMap();
      final qty = (m['quantity'] as int?) ?? 0;
      final price = (m['price'] as num?)?.toDouble();
      final updatedAt = m['price_updated_at'] as DateTime?;

      // Sempre manter preço atualizado: por padrão, atualiza diariamente.
      final isStale = updatedAt == null ||
          DateTime.now().toUtc().difference(updatedAt.toUtc()).inHours >= 24;

      double? finalPrice = price;
      if (force || finalPrice == null || isStale) {
        // No nosso schema, `cards.scryfall_id` é o Oracle ID (UUID).
        // Para obter preço, tentamos:
        // 1) /cards/{id} (caso futuramente seja Card ID)
        // 2) /cards/search?q=oracleid:<uuid> set:<set_code>
        // 3) /cards/search?q=oracleid:<uuid> (fallback)
        final oracleId = (m['scryfall_id'] as String?)?.trim();
        final setCode = (m['set_code'] as String?)?.trim();
        if (oracleId != null && oracleId.isNotEmpty) {
          final fetched = await _fetchUsdPriceFromScryfall(
            idOrOracleId: oracleId,
            setCode: setCode,
          );
          if (fetched != null) {
            finalPrice = fetched;
            await pool.execute(
              Sql.named('''
                UPDATE cards
                SET price = @price,
                    price_updated_at = NOW()
                WHERE id = @id
              '''),
              parameters: {'price': fetched, 'id': m['card_id']},
            );
          }
        }
      }

      if (finalPrice == null) {
        missing += qty;
      } else {
        total += finalPrice * qty;
      }

      items.add({
        'card_id': m['card_id'],
        'name': m['name'],
        'set_code': m['set_code'],
        'quantity': qty,
        'is_commander': m['is_commander'] == true,
        'unit_price_usd': finalPrice,
        'line_total_usd': finalPrice == null ? null : (finalPrice * qty),
      });
    }

    // Salva snapshot no deck (para exibir sem recalcular).
    await pool.execute(
      Sql.named('''
        UPDATE decks
        SET pricing_currency = @currency,
            pricing_total = @total,
            pricing_missing_cards = @missing,
            pricing_updated_at = NOW()
        WHERE id = @deckId AND user_id = @userId
      '''),
      parameters: {
        'currency': 'USD',
        'total': double.parse(total.toStringAsFixed(2)),
        'missing': missing,
        'deckId': deckId,
        'userId': userId,
      },
    );

    return Response.json(
      body: {
        'deck_id': deckId,
        'currency': 'USD',
        'estimated_total_usd': double.parse(total.toStringAsFixed(2)),
        'missing_price_cards': missing,
        'items': items,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to price deck: $e'},
    );
  }
}

Future<double?> _fetchUsdPriceFromScryfall({
  required String idOrOracleId,
  String? setCode,
}) async {
  // 1) Tenta como Card ID (se for).
  {
    final uri = Uri.parse('https://api.scryfall.com/cards/$idOrOracleId');
    final response =
        await http.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode == 200) {
      return _parseUsdPriceFromCardJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    }
  }

  // 2/3) Busca por oracleid (o nosso caso atual).
  final queries = <String>[
    if ((setCode ?? '').trim().isNotEmpty)
      'oracleid:$idOrOracleId set:${setCode!.trim()}',
    'oracleid:$idOrOracleId',
  ];

  for (final q in queries) {
    final uri = Uri.https('api.scryfall.com', '/cards/search', {
      'q': q,
      'unique': 'prints',
      'order': 'released',
      'dir': 'desc',
    });
    final response =
        await http.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode != 200) continue;
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final data = (json['data'] as List?)?.whereType<Map>().toList() ?? const [];
    if (data.isEmpty) continue;
    final first = data.first.cast<String, dynamic>();
    final price = _parseUsdPriceFromCardJson(first);
    if (price != null) return price;
  }

  return null;
}

double? _parseUsdPriceFromCardJson(Map<String, dynamic> json) {
  final prices = (json['prices'] as Map?)?.cast<String, dynamic>();
  if (prices == null) return null;

  final usd = prices['usd'];
  if (usd is String && usd.trim().isNotEmpty) {
    return double.tryParse(usd);
  }
  return null;
}
