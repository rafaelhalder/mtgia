import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /market/card/:cardId
///
/// Retorna o histórico de preço de uma carta específica (últimos 30 dias).
///
/// Response:
/// {
///   "card_id": "...",
///   "name": "...",
///   "current_price": 12.50,
///   "history": [
///     { "date": "2026-02-09", "price_usd": 12.50 },
///     { "date": "2026-02-08", "price_usd": 11.00 },
///     ...
///   ]
/// }
Future<Response> onRequest(RequestContext context, String cardId) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: '{"error":"Method not allowed"}');
  }

  final pool = context.read<Pool>();

  try {
    final historyResult = await pool.execute(
      Sql.named('''
        SELECT 
          ph.price_date,
          ph.price_usd,
          ph.price_usd_foil
        FROM price_history ph
        WHERE ph.card_id = @card_id::uuid
        ORDER BY ph.price_date DESC
        LIMIT 90
      '''),
      parameters: {'card_id': cardId},
    );

    // Busca dados da carta
    final cardResult = await pool.execute(
      Sql.named('''
        SELECT name, set_code, image_url, price, rarity, type_line
        FROM cards 
        WHERE id = @card_id::uuid
      '''),
      parameters: {'card_id': cardId},
    );

    if (cardResult.isEmpty) {
      return Response.json(
        statusCode: 404,
        body: {'error': 'Carta não encontrada'},
      );
    }

    final card = cardResult.first;

    return Response.json(
      body: {
        'card_id': cardId,
        'name': card[0],
        'set_code': card[1],
        'image_url': card[2],
        'current_price': card[3] != null ? (card[3] is num ? (card[3] as num).toDouble() : double.tryParse(card[3].toString())) : null,
        'rarity': card[4],
        'type_line': card[5],
        'history': historyResult.map((row) {
          return {
            'date': row[0].toString().substring(0, 10),
            'price_usd': row[1] != null ? (row[1] is num ? (row[1] as num).toDouble() : double.tryParse(row[1].toString())) : null,
            'price_usd_foil': row[2] != null ? (row[2] is num ? (row[2] as num).toDouble() : double.tryParse(row[2].toString())) : null,
          };
        }).toList(),
      },
    );
  } catch (e) {
    print('[ERROR] Erro ao buscar histórico: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Erro ao buscar histórico'},
    );
  }
}
