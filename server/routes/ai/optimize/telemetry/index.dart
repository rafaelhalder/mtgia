import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/http_responses.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return methodNotAllowed();
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();

    final daysRaw = context.request.uri.queryParameters['days'];
    final parsedDays = int.tryParse(daysRaw ?? '');
    final days = (parsedDays ?? 7).clamp(1, 90);

    final tableReady = await _isTelemetryTableAvailable(pool);
    if (!tableReady) {
      return Response.json(
        statusCode: 200,
        body: {
          'status': 'not_initialized',
          'message':
              'Telemetry table not found. Run: dart run bin/migrate.dart',
          'table': 'ai_optimize_fallback_telemetry',
          'window_days': days,
          'global': _emptyAggregate(),
          'window': _emptyAggregate(),
          'current_user_window': _emptyAggregate(),
        },
      );
    }

    final global = await _loadGlobalAggregate(pool);
    final window = await _loadWindowAggregate(pool, days: days);
    final userWindow =
        await _loadWindowAggregate(pool, days: days, userId: userId);

    return Response.json(body: {
      'status': 'ok',
      'source': 'persisted_db',
      'window_days': days,
      'global': global,
      'window': window,
      'current_user_window': userWindow,
    });
  } catch (e) {
    return internalServerError('Failed to load optimize telemetry', details: e);
  }
}

Future<bool> _isTelemetryTableAvailable(Pool pool) async {
  final result = await pool.execute(Sql.named('''
    SELECT COUNT(*)::int AS c
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'ai_optimize_fallback_telemetry'
  '''));

  if (result.isEmpty) return false;
  final value = result.first.toColumnMap()['c'];
  return _toInt(value) > 0;
}

Future<Map<String, dynamic>> _loadGlobalAggregate(Pool pool) async {
  final result = await pool.execute('''
    SELECT
      COUNT(*)::int AS request_count,
      SUM(CASE WHEN triggered THEN 1 ELSE 0 END)::int AS triggered_count,
      SUM(CASE WHEN applied THEN 1 ELSE 0 END)::int AS applied_count,
      SUM(CASE WHEN no_candidate THEN 1 ELSE 0 END)::int AS no_candidate_count,
      SUM(CASE WHEN no_replacement THEN 1 ELSE 0 END)::int AS no_replacement_count
    FROM ai_optimize_fallback_telemetry
  ''');

  if (result.isEmpty) return _emptyAggregate();
  return _rowToAggregate(result.first.toColumnMap());
}

Future<Map<String, dynamic>> _loadWindowAggregate(
  Pool pool, {
  required int days,
  String? userId,
}) async {
  final userFilter = userId == null ? '' : ' AND user_id = CAST(@user_id AS uuid)';

  final result = await pool.execute(
    Sql.named('''
      SELECT
        COUNT(*)::int AS request_count,
        SUM(CASE WHEN triggered THEN 1 ELSE 0 END)::int AS triggered_count,
        SUM(CASE WHEN applied THEN 1 ELSE 0 END)::int AS applied_count,
        SUM(CASE WHEN no_candidate THEN 1 ELSE 0 END)::int AS no_candidate_count,
        SUM(CASE WHEN no_replacement THEN 1 ELSE 0 END)::int AS no_replacement_count
      FROM ai_optimize_fallback_telemetry
      WHERE created_at >= NOW() - (CAST(@days AS int) * INTERVAL '1 day')
      $userFilter
    '''),
    parameters: {
      'days': days,
      if (userId != null) 'user_id': userId,
    },
  );

  if (result.isEmpty) return _emptyAggregate();
  return _rowToAggregate(result.first.toColumnMap());
}

Map<String, dynamic> _rowToAggregate(Map<String, dynamic> row) {
  final requestCount = _toInt(row['request_count']);
  final triggeredCount = _toInt(row['triggered_count']);
  final appliedCount = _toInt(row['applied_count']);
  final noCandidateCount = _toInt(row['no_candidate_count']);
  final noReplacementCount = _toInt(row['no_replacement_count']);

  return {
    'request_count': requestCount,
    'triggered_count': triggeredCount,
    'applied_count': appliedCount,
    'no_candidate_count': noCandidateCount,
    'no_replacement_count': noReplacementCount,
    'trigger_rate': requestCount > 0 ? triggeredCount / requestCount : 0.0,
    'apply_rate': triggeredCount > 0 ? appliedCount / triggeredCount : 0.0,
  };
}

Map<String, dynamic> _emptyAggregate() {
  return {
    'request_count': 0,
    'triggered_count': 0,
    'applied_count': 0,
    'no_candidate_count': 0,
    'no_replacement_count': 0,
    'trigger_rate': 0.0,
    'apply_rate': 0.0,
  };
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
