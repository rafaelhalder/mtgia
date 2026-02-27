import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../../../lib/request_metrics_service.dart';
import '../../../lib/http_responses.dart';

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return methodNotAllowed();
  }

  final snapshot = RequestMetricsService.instance.snapshot();

  return Response.json(
    statusCode: HttpStatus.ok,
    body: {
      'status': 'ok',
      ...snapshot,
    },
  );
}
