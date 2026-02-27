import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../../lib/http_responses.dart';

/// GET /health - Liveness check (básico, sem dependências externas)
/// 
/// Usado para verificar se o servidor está respondendo.
/// Retorna 200 OK se o processo está vivo.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return methodNotAllowed();
  }

  return Response.json(
    body: {
      'status': 'healthy',
      'service': 'mtgia-server',
      'timestamp': DateTime.now().toIso8601String(),
      'environment': Platform.environment['ENVIRONMENT'] ?? 'development',
      'version': Platform.environment['APP_VERSION'] ?? '1.0.0',
      'git_sha': Platform.environment['GIT_SHA'],
      'checks': {
        'process': {'status': 'healthy'}
      },
    },
  );
}

