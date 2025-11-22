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
Future<Response> _searchRules(RequestContext context) async {
  final params = context.request.uri.queryParameters;
  final query = params['q']?.trim();
  final limit = int.tryParse(params['limit'] ?? '20') ?? 20;

  // Validação básica do limite para evitar abuso
  final safeLimit = (limit > 100) ? 100 : limit;

  final conn = context.read<Connection>();

  try {
    Result result;

    if (query == null || query.isEmpty) {
      // Sem busca específica: retorna as primeiras regras (geralmente introdução)
      result = await conn.execute(
        Sql.named('SELECT id, title, description, category FROM rules ORDER BY title ASC LIMIT @limit'),
        parameters: {'limit': safeLimit},
      );
    } else {
      // Busca textual no título (número da regra) ou descrição
      result = await conn.execute(
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

    return Response.json(body: rules);
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Failed to search rules: $e'},
    );
  }
}
