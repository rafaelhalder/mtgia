import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(
    body: {
      'ok': true,
      'service': 'mtgia-server',
      'time': DateTime.now().toIso8601String(),
      'environment': Platform.environment['ENVIRONMENT'] ?? 'development',
      'git_sha': Platform.environment['GIT_SHA'],
    },
  );
}

