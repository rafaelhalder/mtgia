import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dotenv/dotenv.dart';

/// Middleware para proteger rotas que exigem autenticação.
///
/// Ele verifica o token JWT no cabeçalho 'Authorization', valida-o e,
/// se for válido, injeta o ID do usuário no contexto da requisição
/// para que a rota final possa usá-lo.
Handler middleware(Handler handler) {
  return (context) async {
    final authHeader = context.request.headers['Authorization'];

    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.json(
        statusCode: 401,
        body: {'error': 'Authorization header not found or invalid.'},
      );
    }

    final token = authHeader.substring(7); // Remove 'Bearer '
    final env = DotEnv(includePlatformEnvironment: true)..load();
    final jwtSecret = env['JWT_SECRET'];

    if (jwtSecret == null) {
      return Response.json(
        statusCode: 500,
        body: {'error': 'JWT_SECRET not configured on the server.'},
      );
    }

    try {
      // Verifica a validade do token
      final jwt = JWT.verify(token, SecretKey(jwtSecret));
      final userId = jwt.payload['id'] as String;

      // Injeta o ID do usuário no contexto para a rota final usar.
      // O `provider` torna o `userId` acessível via `context.read<String>()`.
      return handler.use(provider<String>((_) => userId))(context);

    } on JWTExpiredException {
      return Response.json(statusCode: 401, body: {'error': 'Token expired.'});
    } on JWTException catch (e) {
      return Response.json(statusCode: 401, body: {'error': 'Invalid token: ${e.message}'});
    } catch (e) {
      return Response.json(
        statusCode: 500,
        body: {'error': 'An unexpected authentication error occurred.'},
      );
    }
  };
}
