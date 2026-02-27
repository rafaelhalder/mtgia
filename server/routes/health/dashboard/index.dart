import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/http_responses.dart';
import '../../../lib/request_metrics_service.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return methodNotAllowed();
  }

  try {
    final pool = context.read<Pool>();
    final requestMetrics = RequestMetricsService.instance.snapshot();

    final aiCost = await _loadAiCostProxy(pool);
    final aiOptimize = await _loadAiOptimizeOverview(pool);

    return Response.json(
      statusCode: HttpStatus.ok,
      body: {
        'status': 'ok',
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'dashboard': {
          'requests': requestMetrics,
          'ai_cost_proxy': aiCost,
          'ai_optimize': aiOptimize,
        },
      },
    );
  } catch (e) {
    return internalServerError('Failed to load operational dashboard',
        details: e);
  }
}

Future<Map<String, dynamic>> _loadAiCostProxy(Pool pool) async {
  final hasTable = await _tableExists(pool, 'ai_logs');
  if (!hasTable) {
    return {
      'status': 'not_initialized',
      'table': 'ai_logs',
      'window_hours': 24,
      'input_tokens': 0,
      'output_tokens': 0,
      'total_calls': 0,
      'errors': 0,
    };
  }

  final result = await pool.execute(Sql.named('''
      SELECT
        COALESCE(SUM(input_tokens),0)::int AS input_tokens,
        COALESCE(SUM(output_tokens),0)::int AS output_tokens,
        COUNT(*)::int AS total_calls,
        SUM(CASE WHEN success THEN 0 ELSE 1 END)::int AS errors
      FROM ai_logs
      WHERE created_at >= NOW() - INTERVAL '24 hours'
  '''));

  final row = result.first.toColumnMap();

  return {
    'status': 'ok',
    'window_hours': 24,
    'input_tokens': row['input_tokens'] ?? 0,
    'output_tokens': row['output_tokens'] ?? 0,
    'total_calls': row['total_calls'] ?? 0,
    'errors': row['errors'] ?? 0,
  };
}

Future<Map<String, dynamic>> _loadAiOptimizeOverview(Pool pool) async {
  final hasTable =
      await _tableExists(pool, 'ai_optimize_fallback_telemetry');
  if (!hasTable) {
    return {
      'status': 'not_initialized',
      'table': 'ai_optimize_fallback_telemetry',
      'window_hours': 24,
      'request_count': 0,
      'triggered_count': 0,
      'applied_count': 0,
      'trigger_rate': 0.0,
      'apply_rate': 0.0,
    };
  }

  final result = await pool.execute(Sql.named('''
      SELECT
        COUNT(*)::int AS request_count,
        SUM(CASE WHEN triggered THEN 1 ELSE 0 END)::int AS triggered_count,
        SUM(CASE WHEN applied THEN 1 ELSE 0 END)::int AS applied_count
      FROM ai_optimize_fallback_telemetry
      WHERE created_at >= NOW() - INTERVAL '24 hours'
  '''));

  final row = result.first.toColumnMap();
  final requestCount = (row['request_count'] as int?) ?? 0;
  final triggeredCount = (row['triggered_count'] as int?) ?? 0;
  final appliedCount = (row['applied_count'] as int?) ?? 0;

  return {
    'status': 'ok',
    'window_hours': 24,
    'request_count': requestCount,
    'triggered_count': triggeredCount,
    'applied_count': appliedCount,
    'trigger_rate': requestCount > 0 ? triggeredCount / requestCount : 0.0,
    'apply_rate': triggeredCount > 0 ? appliedCount / triggeredCount : 0.0,
  };
}

Future<bool> _tableExists(Pool pool, String table) async {
  final result = await pool.execute(
    Sql.named('''
      SELECT COUNT(*)::int AS c
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = @table
    '''),
    parameters: {'table': table},
  );

  if (result.isEmpty) return false;
  return ((result.first.toColumnMap()['c'] as int?) ?? 0) > 0;
}
