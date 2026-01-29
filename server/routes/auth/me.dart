import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth_service.dart';

/// Retorna o usuário autenticado a partir do JWT.
///
/// GET /auth/me
/// Header: Authorization: Bearer <token>
///
/// Retorna:
/// - 200: { user: { id, username, email } }
/// - 401: Token ausente/inválido
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final authHeader = context.request.headers['Authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {
        'error': 'Token de autenticação não fornecido',
        'message': 'Inclua o header: Authorization: Bearer <token>',
      },
    );
  }

  final token = authHeader.substring(7);
  final authService = AuthService();
  final user = await authService.getUserFromToken(token);

  if (user == null) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {
        'error': 'Token inválido ou expirado',
        'message': 'Faça login novamente para obter um novo token',
      },
    );
  }

  return Response.json(
    body: {
      'user': user,
    },
  );
}

