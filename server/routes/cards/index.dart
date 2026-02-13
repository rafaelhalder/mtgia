import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

String? _normalizeScryfallImageUrl(String? url) {
  if (url == null) return null;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  if (!trimmed.startsWith('https://api.scryfall.com/')) return trimmed;

  try {
    final uri = Uri.parse(trimmed);
    final qp = Map<String, String>.from(uri.queryParameters);

    // Normalize set= to lowercase to avoid 404 (Scryfall expects lowercase set codes).
    if (qp['set'] != null) qp['set'] = qp['set']!.toLowerCase();

    // Some MTGJSON rows use "Name // Name". Scryfall named endpoint expects the
    // canonical card name, so fallback to the left side.
    final exact = qp['exact'];
    if (uri.path == '/cards/named' && exact != null && exact.contains('//')) {
      final left = exact.split('//').first.trim();
      if (left.isNotEmpty) qp['exact'] = left;
    }

    return uri.replace(queryParameters: qp).toString();
  } catch (_) {
    return trimmed.replaceAllMapped(
      RegExp(r'([?&]set=)([^&]+)'),
      (m) => '${m.group(1)}${m.group(2)!.toLowerCase()}',
    );
  }
}

Future<Response> onRequest(RequestContext context) async {
  // Apenas método GET é permitido
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  // Acessa a conexão do banco de dados fornecida pelo middleware
  final conn = context.read<Pool>();
  final hasSets = await _hasTable(conn, 'sets');

  final params = context.request.uri.queryParameters;
  final nameFilter = params['name'];
  final setFilter = params['set']?.trim();
  // Deduplicar por padrão para evitar variantes duplicadas
  // Use ?dedupe=false para obter todas as variantes
  final deduplicate = params['dedupe']?.toLowerCase() != 'false';

  // Paginação
  final limit = int.tryParse(params['limit'] ?? '50') ?? 50;
  final page = int.tryParse(params['page'] ?? '1') ?? 1;
  final safeLimit = limit.clamp(1, 200);
  final safePage = page < 1 ? 1 : page;
  final offset = (safePage - 1) * safeLimit;

  try {
    final query = _buildQuery(
      nameFilter, setFilter, safeLimit, offset,
      includeSetInfo: hasSets, 
      deduplicate: deduplicate,
    );

    final queryResult = await conn.execute(
      Sql.named(query.sql),
      parameters: query.parameters,
    );

    // Mapeamento do resultado para JSON
    final cards = queryResult.map((row) {
      final map = row.toColumnMap();
      final imageUrl = _normalizeScryfallImageUrl(map['image_url']?.toString());
      return {
        'id': map['id'],
        'scryfall_id': map['scryfall_id'],
        'name': map['name'],
        'mana_cost': map['mana_cost'],
        'type_line': map['type_line'],
        'oracle_text': map['oracle_text'],
        'colors': map['colors'],
        'color_identity': map['color_identity'],
        'image_url': imageUrl,
        'set_code': map['set_code'],
        if (hasSets) 'set_name': map['set_name'],
        if (hasSets)
          'set_release_date': (map['set_release_date'] as DateTime?)
              ?.toIso8601String()
              .split('T')
              .first,
        'rarity': map['rarity'],
      };
    }).toList();

    return Response.json(body: {
      'data': cards,
      'page': safePage,
      'limit': safeLimit,
      'total_returned': cards.length,
    });
  } catch (e) {
    print('[ERROR] Erro interno ao buscar cartas: $e');
    return Response.json(
      statusCode: 500,
      body: {'error': 'Erro interno ao buscar cartas'},
    );
  }
}

class _QueryBuilder {
  final String sql;
  final Map<String, dynamic> parameters;
  _QueryBuilder(this.sql, this.parameters);
}

_QueryBuilder _buildQuery(
    String? nameFilter, String? setFilter, int limit, int offset,
    {required bool includeSetInfo, bool deduplicate = false}) {
  
  final params = <String, dynamic>{};
  final conditions = <String>[];
  
  // Para ordenação: prioriza match exato, depois basic lands, depois alfabético
  String orderExpression = 'c.name ASC';
  
  if (nameFilter != null && nameFilter.isNotEmpty) {
    conditions.add('c.name ILIKE @name');
    params['name'] = '%$nameFilter%';
    params['exact_name'] = nameFilter;
    // Ordem: 1) match exato (case insensitive), 2) basic lands, 3) startsWith, 4) resto
    orderExpression = '''
      CASE 
        WHEN LOWER(c.name) = LOWER(@exact_name) THEN 0
        WHEN c.type_line ILIKE 'Basic Land%' AND LOWER(c.name) = LOWER(@exact_name) THEN 1
        WHEN c.type_line ILIKE 'Basic Land%' THEN 2
        WHEN LOWER(c.name) LIKE LOWER(@exact_name) || '%' THEN 3
        ELSE 4
      END, c.name ASC
    ''';
  }

  if (setFilter != null && setFilter.isNotEmpty) {
    // Usar LOWER para comparação case-insensitive
    conditions.add('LOWER(c.set_code) = LOWER(@set)');
    params['set'] = setFilter;
  }

  final whereClause = conditions.isNotEmpty 
      ? 'WHERE ${conditions.join(' AND ')}' 
      : '';

  String sql;
  
  if (deduplicate) {
    // Deduplicar por (name, LOWER(set_code)) para evitar variantes e inconsistências de case
    // Nota: para dedup com priorização, fazemos ORDER BY com CASE no select externo
    sql = includeSetInfo
        ? '''
          SELECT * FROM (
            SELECT DISTINCT ON (c.name, LOWER(c.set_code))
              c.id, c.scryfall_id, c.name, c.mana_cost, c.type_line,
              c.oracle_text, c.colors, c.color_identity, c.image_url,
              LOWER(c.set_code) AS set_code, c.rarity, c.cmc,
              s.name AS set_name,
              s.release_date AS set_release_date
            FROM cards c
            LEFT JOIN sets s ON LOWER(s.code) = LOWER(c.set_code)
            $whereClause
            ORDER BY c.name, LOWER(c.set_code), s.release_date DESC NULLS LAST
          ) AS deduped
          ORDER BY ${nameFilter != null ? '''
            CASE 
              WHEN LOWER(name) = LOWER(@exact_name) THEN 0
              WHEN type_line ILIKE 'Basic Land%' AND LOWER(name) = LOWER(@exact_name) THEN 1
              WHEN type_line ILIKE 'Basic Land%' THEN 2
              WHEN LOWER(name) LIKE LOWER(@exact_name) || '%' THEN 3
              ELSE 4
            END, name ASC
          ''' : 'name ASC, set_code ASC'}
          LIMIT @limit OFFSET @offset
        '''
        : '''
          SELECT * FROM (
            SELECT DISTINCT ON (c.name, LOWER(c.set_code))
              c.id, c.scryfall_id, c.name, c.mana_cost, c.type_line,
              c.oracle_text, c.colors, c.color_identity, c.image_url,
              LOWER(c.set_code) AS set_code, c.rarity, c.cmc
            FROM cards c
            $whereClause
            ORDER BY c.name, LOWER(c.set_code)
          ) AS deduped
          ORDER BY ${nameFilter != null ? '''
            CASE 
              WHEN LOWER(name) = LOWER(@exact_name) THEN 0
              WHEN type_line ILIKE 'Basic Land%' AND LOWER(name) = LOWER(@exact_name) THEN 1
              WHEN type_line ILIKE 'Basic Land%' THEN 2
              WHEN LOWER(name) LIKE LOWER(@exact_name) || '%' THEN 3
              ELSE 4
            END, name ASC
          ''' : 'name ASC, set_code ASC'}
          LIMIT @limit OFFSET @offset
        ''';
  } else {
    // Query normal sem deduplicação
    sql = includeSetInfo
        ? '''
          SELECT
            c.*,
            s.name AS set_name,
            s.release_date AS set_release_date
          FROM cards c
          LEFT JOIN sets s ON LOWER(s.code) = LOWER(c.set_code)
          $whereClause
          ORDER BY $orderExpression
          LIMIT @limit OFFSET @offset
        '''
        : '''
          SELECT c.* FROM cards c
          $whereClause
          ORDER BY $orderExpression
          LIMIT @limit OFFSET @offset
        ''';
  }

  params['limit'] = limit;
  params['offset'] = offset;

  return _QueryBuilder(sql, params);
}

Future<bool> _hasTable(Pool pool, String tableName) async {
  try {
    final result = await pool.execute(
      Sql.named('SELECT to_regclass(@name)::text'),
      parameters: {'name': 'public.$tableName'},
    );
    final value = result.isNotEmpty ? result.first[0] : null;
    return value != null;
  } catch (_) {
    return false;
  }
}
