import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

Response apiError(
  int statusCode,
  String message, {
  Object? details,
}) {
  final body = <String, dynamic>{'error': message};
  if (details != null) {
    body['details'] = details.toString();
  }
  return Response.json(statusCode: statusCode, body: body);
}

Response badRequest(
  String message, {
  Object? details,
}) =>
    apiError(HttpStatus.badRequest, message, details: details);

Response notFound(
  String message, {
  Object? details,
}) =>
    apiError(HttpStatus.notFound, message, details: details);

Response internalServerError(
  String message, {
  Object? details,
}) =>
    apiError(HttpStatus.internalServerError, message, details: details);

Response methodNotAllowed([
  String message = 'Method not allowed',
]) =>
    apiError(HttpStatus.methodNotAllowed, message);
