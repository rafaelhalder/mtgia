import 'package:dart_frog/dart_frog.dart';
import 'auth_service.dart';

/// Middleware de autenticação para proteger rotas
/// 
/// Uso:
/// ```dart
/// // Em routes/_middleware.dart
/// Handler middleware(Handler handler) {
///   return handler.use(authMiddleware());
/// }
/// ```
/// 
/// Verifica:
/// - Presença do header Authorization
/// - Formato "Bearer <token>"
/// - Validade do JWT token
/// 
/// Se válido, injeta o userId no RequestContext para uso nos handlers
Middleware authMiddleware() {
  return (handler) {
    return (context) async {
      // Obter header de autorização
      final authHeader = context.request.headers['Authorization'];

      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.json(
          statusCode: 401,
          body: {
            'error': 'Token de autenticação não fornecido',
            'message': 'Inclua o header: Authorization: Bearer <token>',
          },
        );
      }

      // Extrair token
      final token = authHeader.substring(7); // Remove "Bearer "

      // Validar token
      final authService = AuthService();
      final payload = authService.verifyToken(token);

      if (payload == null) {
        return Response.json(
          statusCode: 401,
          body: {
            'error': 'Token inválido ou expirado',
            'message': 'Faça login novamente para obter um novo token',
          },
        );
      }

      // Injetar userId no contexto para uso nos handlers
      final userId = payload['userId'] as String;
      final requestWithUser = context.provide<String>(() => userId);

      return handler(requestWithUser);
    };
  };
}

/// Extrai o userId do contexto injetado pelo middleware
/// 
/// Uso dentro de um handler protegido:
/// ```dart
/// Future<Response> onRequest(RequestContext context) async {
///   final userId = getUserId(context);
///   // ... usar userId para filtrar dados
/// }
/// ```
String getUserId(RequestContext context) {
  try {
    return context.read<String>();
  } catch (e) {
    throw Exception('UserId não encontrado no contexto. Certifique-se de que authMiddleware() está aplicado.');
  }
}
