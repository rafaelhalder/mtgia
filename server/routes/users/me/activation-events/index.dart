import 'dart:io';
import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/auth_middleware.dart';
import '../../../../lib/http_responses.dart';

const _allowedEvents = <String>{
  'core_flow_started',
  'format_selected',
  'base_choice_generate',
  'base_choice_import',
  'deck_created',
  'deck_optimized',
  'onboarding_completed',
};

Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method == HttpMethod.post) {
    return _postEvent(context);
  }
  if (method == HttpMethod.get) {
    return _getSummary(context);
  }
  return methodNotAllowed();
}

Future<Response> _postEvent(RequestContext context) async {
  final userId = getUserId(context);
  final pool = context.read<Pool>();

  Map<String, dynamic> body;
  try {
    body = (await context.request.json()) as Map<String, dynamic>;
  } catch (_) {
    return badRequest('JSON inválido');
  }

  final eventName = body['event_name']?.toString().trim();
  if (eventName == null || eventName.isEmpty) {
    return badRequest('event_name é obrigatório');
  }
  if (!_allowedEvents.contains(eventName)) {
    return badRequest('event_name inválido');
  }

  final format = body['format']?.toString().trim();
  final source = body['source']?.toString().trim();
  final deckId = body['deck_id']?.toString().trim();

  final metadataRaw = body['metadata'];
  final metadata = metadataRaw is Map
      ? metadataRaw.map((k, v) => MapEntry(k.toString(), v))
      : <String, dynamic>{};

  try {
    await pool.execute(
      Sql.named('''
        INSERT INTO activation_funnel_events (
          user_id, event_name, format, deck_id, source, metadata
        ) VALUES (
          @userId, @eventName, @format, @deckId, @source, CAST(@metadata AS jsonb)
        )
      '''),
      parameters: {
        'userId': userId,
        'eventName': eventName,
        'format': (format == null || format.isEmpty) ? null : format,
        'deckId': (deckId == null || deckId.isEmpty) ? null : deckId,
        'source': (source == null || source.isEmpty) ? null : source,
        'metadata': jsonEncode(metadata),
      },
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: {'ok': true},
    );
  } catch (e) {
    return internalServerError('Falha ao registrar evento de ativação', details: e);
  }
}

Future<Response> _getSummary(RequestContext context) async {
  final userId = getUserId(context);
  final pool = context.read<Pool>();

  final days = int.tryParse(context.request.uri.queryParameters['days'] ?? '30') ?? 30;
  final safeDays = days.clamp(1, 90);

  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT event_name, COUNT(*)::int AS total
        FROM activation_funnel_events
        WHERE user_id = @userId
          AND created_at >= NOW() - (@days * INTERVAL '1 day')
        GROUP BY event_name
        ORDER BY event_name ASC
      '''),
      parameters: {'userId': userId, 'days': safeDays},
    );

    final events = <Map<String, dynamic>>[];
    for (final row in result) {
      events.add({'event_name': row[0], 'count': row[1]});
    }

    return Response.json(body: {
      'days': safeDays,
      'events': events,
    });
  } catch (e) {
    return internalServerError('Falha ao buscar resumo de ativação', details: e);
  }
}
