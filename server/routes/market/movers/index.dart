import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /market/movers
///
/// Retorna as cartas com maior variação de preço (gainers e losers)
/// comparando o preço de hoje com o de ontem.
///
/// Query params:
///   - limit: número de cartas por categoria (default: 20, max: 50)
///   - min_price: preço mínimo para filtrar penny stocks (default: 1.00)
///
/// Response:
/// {
///   "date": "2026-02-09",
///   "previous_date": "2026-02-08",
///   "gainers": [ { card_id, name, set_code, image_url, price_today, price_yesterday, change_usd, change_pct } ],
///   "losers":  [ ... ],
///   "total_tracked": 12345
/// }
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: '{"error":"Method not allowed"}');
  }

  final pool = context.read<Pool>();
  final params = context.request.uri.queryParameters;
  final limit = (int.tryParse(params['limit'] ?? '20') ?? 20).clamp(1, 50);
  final minPrice = double.tryParse(params['min_price'] ?? '1.0') ?? 1.0;

  try {
    // Descobre as datas disponíveis (até 7 mais recentes)
    final datesResult = await pool.execute(
      Sql.named('''
        SELECT DISTINCT price_date 
        FROM price_history 
        ORDER BY price_date DESC 
        LIMIT 7
      '''),
    );

    if (datesResult.length < 2) {
      return Response.json(
        body: {
          'date': datesResult.isNotEmpty
              ? datesResult.first[0].toString().substring(0, 10)
              : null,
          'previous_date': null,
          'gainers': <dynamic>[],
          'losers': <dynamic>[],
          'total_tracked': 0,
          'message':
              'Dados insuficientes. São necessários pelo menos 2 dias de histórico de preços.',
        },
      );
    }

    final today = datesResult[0][0].toString().substring(0, 10);

    // Encontra a melhor data de comparação: a mais recente que tenha
    // variações significativas (preços diferentes do dia mais recente).
    // Usa amostragem eficiente: pega 5 cards do dia mais recente e verifica
    // se seus preços mudaram na data candidata.
    var yesterday = datesResult[1][0].toString().substring(0, 10);

    // Pegar 5 card_ids de amostra do dia mais recente (os com maior preço)
    final sampleCards = await pool.execute(
      Sql.named('''
        SELECT card_id, price_usd 
        FROM price_history 
        WHERE price_date = @today::date AND price_usd > 1.0
        ORDER BY price_usd DESC 
        LIMIT 5
      '''),
      parameters: {'today': today},
    );

    if (sampleCards.isNotEmpty) {
      final sampleId = sampleCards.first[0].toString();
      final samplePrice = _toDouble(sampleCards.first[1]) ?? 0;

      for (var i = 1; i < datesResult.length; i++) {
        final candidateDate = datesResult[i][0].toString().substring(0, 10);
        // Verifica se o preço deste card mudou nesta data
        final priceCheck = await pool.execute(
          Sql.named('''
            SELECT price_usd FROM price_history
            WHERE card_id = @card_id::uuid
              AND price_date = @candidate::date
          '''),
          parameters: {'card_id': sampleId, 'candidate': candidateDate},
        );
        if (priceCheck.isNotEmpty) {
          final oldPrice = _toDouble(priceCheck.first[0]) ?? 0;
          // Se o preço mudou (diferença > 0.5%), é um snapshot diferente
          if (samplePrice > 0 && oldPrice > 0) {
            final diff = ((samplePrice - oldPrice) / oldPrice).abs();
            if (diff > 0.005) {
              yesterday = candidateDate;
              break;
            }
          }
        }
        yesterday = candidateDate;
      }
    }

    // Query para pegar gainers (maior aumento %)
    final gainersResult = await pool.execute(
      Sql.named('''
        SELECT 
          c.id,
          c.name,
          c.set_code,
          c.image_url,
          c.rarity,
          c.type_line,
          ph_today.price_usd AS price_today,
          ph_yest.price_usd AS price_yesterday,
          (ph_today.price_usd - ph_yest.price_usd) AS change_usd,
          ROUND(
            ((ph_today.price_usd - ph_yest.price_usd) / ph_yest.price_usd * 100)::numeric, 
            2
          ) AS change_pct
        FROM price_history ph_today
        JOIN price_history ph_yest 
          ON ph_today.card_id = ph_yest.card_id
        JOIN cards c 
          ON c.id = ph_today.card_id
        WHERE ph_today.price_date = @today::date
          AND ph_yest.price_date = @yesterday::date
          AND ph_yest.price_usd > @min_price
          AND ph_today.price_usd > 0
          AND ph_yest.price_usd > 0
          AND ph_today.price_usd > ph_yest.price_usd
        ORDER BY change_pct DESC
        LIMIT @limit
      '''),
      parameters: {
        'today': today,
        'yesterday': yesterday,
        'min_price': minPrice,
        'limit': limit,
      },
    );

    // Query para pegar losers (maior queda %)
    final losersResult = await pool.execute(
      Sql.named('''
        SELECT 
          c.id,
          c.name,
          c.set_code,
          c.image_url,
          c.rarity,
          c.type_line,
          ph_today.price_usd AS price_today,
          ph_yest.price_usd AS price_yesterday,
          (ph_today.price_usd - ph_yest.price_usd) AS change_usd,
          ROUND(
            ((ph_today.price_usd - ph_yest.price_usd) / ph_yest.price_usd * 100)::numeric, 
            2
          ) AS change_pct
        FROM price_history ph_today
        JOIN price_history ph_yest 
          ON ph_today.card_id = ph_yest.card_id
        JOIN cards c 
          ON c.id = ph_today.card_id
        WHERE ph_today.price_date = @today::date
          AND ph_yest.price_date = @yesterday::date
          AND ph_yest.price_usd > @min_price
          AND ph_today.price_usd >= 0
          AND ph_yest.price_usd > 0
          AND ph_today.price_usd < ph_yest.price_usd
        ORDER BY change_pct ASC
        LIMIT @limit
      '''),
      parameters: {
        'today': today,
        'yesterday': yesterday,
        'min_price': minPrice,
        'limit': limit,
      },
    );

    // Total de cartas rastreadas
    final totalResult = await pool.execute(
      Sql.named('''
        SELECT COUNT(DISTINCT card_id) 
        FROM price_history 
        WHERE price_date = @today::date
      '''),
      parameters: {'today': today},
    );

    final totalTracked = _toInt(totalResult.first[0]);

    List<Map<String, dynamic>> mapRows(Result rows) {
      return rows.map((row) {
        return {
          'card_id': row[0].toString(),
          'name': row[1],
          'set_code': row[2],
          'image_url': row[3],
          'rarity': row[4],
          'type_line': row[5],
          'price_today': _toDouble(row[6]),
          'price_yesterday': _toDouble(row[7]),
          'change_usd': _toDouble(row[8]),
          'change_pct': _toDouble(row[9]),
        };
      }).toList();
    }

    return Response.json(
      body: {
        'date': today,
        'previous_date': yesterday,
        'gainers': mapRows(gainersResult),
        'losers': mapRows(losersResult),
        'total_tracked': totalTracked,
      },
    );
  } catch (e) {
    print('[ERROR] Erro ao buscar market movers: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Erro ao buscar market movers'},
    );
  }
}

/// Converte valor do PostgreSQL (DECIMAL/NUMERIC vem como String) para double
double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Converte valor do PostgreSQL (COUNT vem como int/bigint) para int
int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
