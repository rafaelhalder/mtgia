import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/http_responses.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return methodNotAllowed();
  }

  try {
    final userId = context.read<String>();
    final pool = context.read<Pool>();
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

    final query = context.request.uri.queryParameters;
    final parsed = _parseTelemetryQuery(query);
    if (parsed.error != null) {
      return badRequest(parsed.error!);
    }

    final isAdmin = await _isAdminUser(
      pool: pool,
      userId: userId,
      env: env,
    );

    final includeGlobal = parsed.includeGlobal;
    if (includeGlobal && !isAdmin) {
      return Response.json(
        statusCode: 403,
        body: {
          'error': 'Access denied for global telemetry scope',
          'message': 'Global telemetry requires admin privileges.',
        },
      );
    }

    final tableReady = await _isTelemetryTableAvailable(pool);
    if (!tableReady) {
      final empty = _emptyAggregate();
      return Response.json(
        statusCode: 200,
        body: {
          'status': 'not_initialized',
          'message':
              'Telemetry table not found. Run: dart run bin/migrate.dart',
          'table': 'ai_optimize_fallback_telemetry',
          'window_days': parsed.days,
          'filters': parsed.toJson(),
          'scope': {
            'include_global': includeGlobal,
            'is_admin': isAdmin,
          },
          if (includeGlobal) 'global': empty,
          if (includeGlobal) 'window': empty,
          'current_user_window': empty,
        },
      );
    }

    final userWindow = await _loadAggregate(
      pool,
      days: parsed.days,
      mode: parsed.mode,
      deckId: parsed.deckId,
      userId: userId,
    );
    final userByDay = await _loadByDay(
      pool,
      days: parsed.days,
      mode: parsed.mode,
      deckId: parsed.deckId,
      userId: userId,
    );

    Map<String, dynamic>? global;
    Map<String, dynamic>? window;
    List<Map<String, dynamic>>? windowByDay;

    if (includeGlobal) {
      global = await _loadAggregate(pool, mode: parsed.mode, deckId: parsed.deckId);
      window = await _loadAggregate(
        pool,
        days: parsed.days,
        mode: parsed.mode,
        deckId: parsed.deckId,
        userId: parsed.userId,
      );
      windowByDay = await _loadByDay(
        pool,
        days: parsed.days,
        mode: parsed.mode,
        deckId: parsed.deckId,
        userId: parsed.userId,
      );
    }

    return Response.json(body: {
      'status': 'ok',
      'source': 'persisted_db',
      'window_days': parsed.days,
      'filters': parsed.toJson(),
      'scope': {
        'include_global': includeGlobal,
        'is_admin': isAdmin,
      },
      if (includeGlobal) 'global': global,
      if (includeGlobal) 'window': window,
      if (includeGlobal) 'window_by_day': windowByDay,
      'current_user_window': userWindow,
      'current_user_by_day': userByDay,
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

Future<Map<String, dynamic>> _loadAggregate(
  Pool pool, {
  int? days,
  String? mode,
  String? deckId,
  String? userId,
}) async {
  final conditions = <String>[];
  final params = <String, dynamic>{};

  if (days != null) {
    conditions.add(
        "created_at >= NOW() - (CAST(@days AS int) * INTERVAL '1 day')");
    params['days'] = days;
  }
  if (mode != null) {
    conditions.add('mode = @mode');
    params['mode'] = mode;
  }
  if (deckId != null) {
    conditions.add('deck_id = CAST(@deck_id AS uuid)');
    params['deck_id'] = deckId;
  }
  if (userId != null) {
    conditions.add('user_id = CAST(@user_id AS uuid)');
    params['user_id'] = userId;
  }

  final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

  final result = await pool.execute(
    Sql.named('''
      SELECT
        COUNT(*)::int AS request_count,
        SUM(CASE WHEN triggered THEN 1 ELSE 0 END)::int AS triggered_count,
        SUM(CASE WHEN applied THEN 1 ELSE 0 END)::int AS applied_count,
        SUM(CASE WHEN no_candidate THEN 1 ELSE 0 END)::int AS no_candidate_count,
        SUM(CASE WHEN no_replacement THEN 1 ELSE 0 END)::int AS no_replacement_count
      FROM ai_optimize_fallback_telemetry
      $whereClause
    '''),
    parameters: params,
  );

  if (result.isEmpty) return _emptyAggregate();
  return _rowToAggregate(result.first.toColumnMap());
}

Future<List<Map<String, dynamic>>> _loadByDay(
  Pool pool, {
  required int days,
  String? mode,
  String? deckId,
  String? userId,
}) async {
  final conditions = <String>[
    "created_at >= NOW() - (CAST(@days AS int) * INTERVAL '1 day')",
  ];
  final params = <String, dynamic>{'days': days};

  if (mode != null) {
    conditions.add('mode = @mode');
    params['mode'] = mode;
  }
  if (deckId != null) {
    conditions.add('deck_id = CAST(@deck_id AS uuid)');
    params['deck_id'] = deckId;
  }
  if (userId != null) {
    conditions.add('user_id = CAST(@user_id AS uuid)');
    params['user_id'] = userId;
  }

  final result = await pool.execute(
    Sql.named('''
      SELECT
        DATE_TRUNC('day', created_at)::date AS day,
        COUNT(*)::int AS request_count,
        SUM(CASE WHEN triggered THEN 1 ELSE 0 END)::int AS triggered_count,
        SUM(CASE WHEN applied THEN 1 ELSE 0 END)::int AS applied_count,
        SUM(CASE WHEN no_candidate THEN 1 ELSE 0 END)::int AS no_candidate_count,
        SUM(CASE WHEN no_replacement THEN 1 ELSE 0 END)::int AS no_replacement_count
      FROM ai_optimize_fallback_telemetry
      WHERE ${conditions.join(' AND ')}
      GROUP BY DATE_TRUNC('day', created_at)::date
      ORDER BY day ASC
    '''),
    parameters: params,
  );

  return result.map((row) {
    final map = row.toColumnMap();
    final aggregate = _rowToAggregate(map);
    return {
      'day': map['day']?.toString(),
      ...aggregate,
    };
  }).toList();
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
    'fallback_not_applied_count': triggeredCount - appliedCount,
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
    'fallback_not_applied_count': 0,
    'trigger_rate': 0.0,
    'apply_rate': 0.0,
  };
}

_TelemetryQuery _parseTelemetryQuery(Map<String, String> query) {
  final daysRaw = query['days'];
  int days = 7;
  if (daysRaw != null && daysRaw.trim().isNotEmpty) {
    final parsed = int.tryParse(daysRaw.trim());
    if (parsed == null) {
      return _TelemetryQuery.error('days must be an integer between 1 and 90');
    }
    if (parsed < 1 || parsed > 90) {
      return _TelemetryQuery.error('days must be between 1 and 90');
    }
    days = parsed;
  }

  final includeGlobalRaw = query['include_global']?.trim().toLowerCase();
  final includeGlobal = includeGlobalRaw == '1' || includeGlobalRaw == 'true';

  final modeRaw = query['mode']?.trim();
  String? mode;
  if (modeRaw != null && modeRaw.isNotEmpty) {
    final normalized = modeRaw.toLowerCase();
    if (normalized != 'optimize' && normalized != 'complete') {
      return _TelemetryQuery.error('mode must be optimize or complete');
    }
    mode = normalized;
  }

  final deckId = query['deck_id']?.trim();
  if (deckId != null && deckId.isNotEmpty && !_isUuid(deckId)) {
    return _TelemetryQuery.error('deck_id must be a valid UUID');
  }

  final userId = query['user_id']?.trim();
  if (userId != null && userId.isNotEmpty && !_isUuid(userId)) {
    return _TelemetryQuery.error('user_id must be a valid UUID');
  }

  return _TelemetryQuery(
    days: days,
    includeGlobal: includeGlobal,
    mode: mode,
    deckId: deckId != null && deckId.isNotEmpty ? deckId : null,
    userId: userId != null && userId.isNotEmpty ? userId : null,
  );
}

Future<bool> _isAdminUser({
  required Pool pool,
  required String userId,
  required DotEnv env,
}) async {
  final rawIds = env['TELEMETRY_ADMIN_USER_IDS'] ?? '';
  final ids = rawIds
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();

  if (ids.contains(userId)) return true;

  final rawEmails = env['TELEMETRY_ADMIN_EMAILS'] ?? '';
  final emails = rawEmails
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();

  emails.add('rafaelhalder@gmail.com');

  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT LOWER(email) AS email
        FROM users
        WHERE id = CAST(@user_id AS uuid)
        LIMIT 1
      '''),
      parameters: {'user_id': userId},
    );

    if (result.isEmpty) return false;
    final email = (result.first.toColumnMap()['email']?.toString() ?? '').trim();
    return email.isNotEmpty && emails.contains(email);
  } catch (_) {
    return false;
  }
}

bool _isUuid(String value) {
  final regex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  return regex.hasMatch(value);
}

class _TelemetryQuery {
  final int days;
  final bool includeGlobal;
  final String? mode;
  final String? deckId;
  final String? userId;
  final String? error;

  _TelemetryQuery({
    required this.days,
    required this.includeGlobal,
    required this.mode,
    required this.deckId,
    required this.userId,
  }) : error = null;

  _TelemetryQuery.error(this.error)
      : days = 7,
        includeGlobal = false,
        mode = null,
        deckId = null,
        userId = null;

  Map<String, dynamic> toJson() => {
        'days': days,
        'include_global': includeGlobal,
        if (mode != null) 'mode': mode,
        if (deckId != null) 'deck_id': deckId,
        if (userId != null) 'user_id': userId,
      };
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
