import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.get) {
    return _searchRules(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

/// Busca regras no banco de dados.
///
/// Parâmetros de query:
/// - `q`: Termo de busca (opcional). Se omitido, retorna as primeiras regras.
/// - `limit`: Limite de resultados (padrão 20).
/// - `meta`: Quando `true|1`, inclui metadados de sincronização (`sync_state`).
Future<Response> _searchRules(RequestContext context) async {
  final params = context.request.uri.queryParameters;
  final query = params['q']?.trim();
  final limit = int.tryParse(params['limit'] ?? '20') ?? 20;
  final includeMeta = _isTrue(params['meta']);

  // Validação básica do limite para evitar abuso
  final safeLimit = (limit > 100) ? 100 : limit;

  final pool = context.read<Pool>();

  try {
    Result result;

    if (query == null || query.isEmpty) {
      // Sem busca específica: retorna as primeiras regras (geralmente introdução)
      result = await pool.execute(
        Sql.named(
            'SELECT id, title, description, category FROM rules ORDER BY title ASC LIMIT @limit'),
        parameters: {'limit': safeLimit},
      );
    } else {
      // Busca textual no título (número da regra) ou descrição
      result = await pool.execute(
        Sql.named('''
          SELECT id, title, description, category 
          FROM rules 
          WHERE title ILIKE @query OR description ILIKE @query 
          ORDER BY title ASC 
          LIMIT @limit
        '''),
        parameters: {
          'query': '%$query%',
          'limit': safeLimit,
        },
      );
    }

    final rules = result.map((row) => row.toColumnMap()).toList();

    if (!includeMeta) {
      return Response.json(body: rules);
    }

    final meta = await _tryLoadRulesMeta(pool);
    return Response.json(
      body: {
        'meta': meta,
        'data': rules,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to search rules: $e'},
    );
  }
}

bool _isTrue(String? value) {
  if (value == null) return false;
  final v = value.trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes' || v == 'y' || v == 'on';
}

Future<Map<String, dynamic>?> _tryLoadRulesMeta(Pool pool) async {
  try {
    await pool.execute(
      Sql.named('''
        CREATE TABLE IF NOT EXISTS sync_state (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
      '''),
    );

    final result = await pool.execute(
      Sql.named('''
        SELECT key, value, updated_at
        FROM sync_state
        WHERE key IN ('rules_source_url', 'rules_version_date', 'rules_last_sync_at')
        ORDER BY key ASC
      '''),
    );

    if (result.isEmpty) return null;
    final map = <String, dynamic>{};
    for (final row in result) {
      final cols = row.toColumnMap();
      map[cols['key'].toString()] = cols['value']?.toString();
    }
    return map;
  } catch (_) {
    return null;
  }
}
