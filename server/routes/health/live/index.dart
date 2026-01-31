import 'package:dart_frog/dart_frog.dart';

/// GET /health/live - Liveness probe
/// 
/// Endpoint ultra-leve para Kubernetes/Docker liveness probes.
/// Retorna 200 OK se o processo está vivo (sem verificar dependências).
Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'status': 'alive',
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}
