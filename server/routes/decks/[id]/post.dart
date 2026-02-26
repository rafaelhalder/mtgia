import 'package:dart_frog/dart_frog.dart';

import '../../../lib/http_responses.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return methodNotAllowed();
}
