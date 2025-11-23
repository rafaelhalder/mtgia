import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  // Apenas método GET é permitido
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  // Acessa a conexão do banco de dados fornecida pelo middleware
  final conn = context.read<Pool>();

  final params = context.request.uri.queryParameters;
  final nameFilter = params['name'];
  
  // Paginação
  final limit = int.tryParse(params['limit'] ?? '50') ?? 50;
  final page = int.tryParse(params['page'] ?? '1') ?? 1;
  final offset = (page - 1) * limit;

  try {
    final query = _buildQuery(nameFilter, limit, offset);
    
    final queryResult = await conn.execute(
      Sql.named(query.sql),
      parameters: query.parameters,
    );

    // Mapeamento do resultado para JSON
    final cards = queryResult.map((row) {
      final map = row.toColumnMap();
      return {
        'id': map['id'],
        'scryfall_id': map['scryfall_id'],
        'name': map['name'],
        'mana_cost': map['mana_cost'],
        'type_line': map['type_line'],
        'oracle_text': map['oracle_text'],
        'colors': map['colors'],
        'image_url': map['image_url'],
        'set_code': map['set_code'],
        'rarity': map['rarity'],
      };
    }).toList();

    return Response.json(body: {
      'data': cards,
      'page': page,
      'limit': limit,
      'total_returned': cards.length,
    });

  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Erro interno ao buscar cartas', 'details': e.toString()},
    );
  }
}

class _QueryBuilder {
  final String sql;
  final Map<String, dynamic> parameters;
  _QueryBuilder(this.sql, this.parameters);
}

_QueryBuilder _buildQuery(String? nameFilter, int limit, int offset) {
  var sql = 'SELECT * FROM cards';
  final params = <String, dynamic>{};
  final conditions = <String>[];

  if (nameFilter != null && nameFilter.isNotEmpty) {
    conditions.add('name ILIKE @name');
    params['name'] = '%$nameFilter%';
  }

  if (conditions.isNotEmpty) {
    sql += ' WHERE ${conditions.join(' AND ')}';
  }

  sql += ' ORDER BY name ASC LIMIT @limit OFFSET @offset';
  params['limit'] = limit;
  params['offset'] = offset;

  return _QueryBuilder(sql, params);
}
