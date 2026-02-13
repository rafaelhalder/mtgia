import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final pool = context.read<Pool>();
  await _ensureSetsTable(pool);
  final params = context.request.uri.queryParameters;

  final query = params['q']?.trim();
  final code = params['code']?.trim().toUpperCase();

  final limit = int.tryParse(params['limit'] ?? '50') ?? 50;
  final page = int.tryParse(params['page'] ?? '1') ?? 1;
  final safeLimit = limit.clamp(1, 200);
  final safePage = page < 1 ? 1 : page;
  final offset = (safePage - 1) * safeLimit;

  final where = <String>[];
  final sqlParams = <String, dynamic>{
    'limit': safeLimit,
    'offset': offset,
  };

  if (code != null && code.isNotEmpty) {
    where.add('code = @code');
    sqlParams['code'] = code;
  }

  if (query != null && query.isNotEmpty) {
    where.add('(name ILIKE @q OR code ILIKE @q)');
    sqlParams['q'] = '%$query%';
  }

  final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT code, name, release_date, type, block, is_online_only, is_foreign_only
        FROM sets
        $whereSql
        ORDER BY release_date DESC NULLS LAST, name ASC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: sqlParams,
    );

    final sets = result.map((row) {
      final map = row.toColumnMap();
      return {
        'code': map['code'],
        'name': map['name'],
        'release_date': (map['release_date'] as DateTime?)?.toIso8601String().split('T').first,
        'type': map['type'],
        'block': map['block'],
        'is_online_only': map['is_online_only'],
        'is_foreign_only': map['is_foreign_only'],
      };
    }).toList();

    return Response.json(
      body: {
        'data': sets,
        'page': safePage,
        'limit': safeLimit,
        'total_returned': sets.length,
      },
    );
  } catch (e) {
    print('[ERROR] Erro interno ao buscar sets: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Erro interno ao buscar sets'},
    );
  }
}

Future<void> _ensureSetsTable(Pool pool) async {
  await pool.execute(
    Sql.named('''
      CREATE TABLE IF NOT EXISTS sets (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        release_date DATE,
        type TEXT,
        block TEXT,
        is_online_only BOOLEAN,
        is_foreign_only BOOLEAN,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    '''),
  );
  await pool.execute(Sql.named('CREATE INDEX IF NOT EXISTS idx_sets_name ON sets (name)'));
}
