import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth_middleware.dart';
import '../../lib/rate_limit_middleware.dart';

/// Middleware de autenticação e rate limiting para rotas de IA
/// 
/// Aplica:
/// 1. Autenticação (JWT token obrigatório)
/// 2. Rate limiting (10 requisições por minuto por usuário)
/// 
/// Rate limiting é mais restritivo nas rotas de IA porque:
/// - Chamadas à OpenAI são custosas ($$$)
/// - Tempo de resposta é longo (5-10s)
/// - Previne uso abusivo do sistema
Handler middleware(Handler handler) {
  return handler
      .use(authMiddleware())
      .use(aiRateLimit());
}
