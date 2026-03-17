import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/ai/optimize_job.dart';

/// GET /ai/optimize/jobs/:id
///
/// Polling endpoint — o cliente chama a cada 2s para acompanhar o
/// progresso de um job assíncrono de otimização de deck.
///
/// Responses:
///   200 + status=processing → job ainda rodando (com stage/progress)
///   200 + status=completed  → job pronto (com result)
///   200 + status=failed     → job falhou (com error)
///   404                     → job_id inválido ou expirado
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Method not allowed'},
    );
  }

  final userId = context.read<String>();
  final pool = context.read<Pool>();
  final job = await OptimizeJobStore.get(pool, id);
  if (job == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {
        'error': 'Job não encontrado ou expirado.',
        'job_id': id,
      },
    );
  }

  if (job.userId != null && job.userId != userId) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {
        'error': 'Job não encontrado ou expirado.',
        'job_id': id,
      },
    );
  }

  return Response.json(body: job.toJson());
}
