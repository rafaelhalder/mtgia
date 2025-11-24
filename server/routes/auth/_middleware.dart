import 'package:dart_frog/dart_frog.dart';
import '../../lib/rate_limit_middleware.dart';

/// Middleware para as rotas de autenticação
/// 
/// Aplica rate limiting restritivo para prevenir ataques de brute force:
/// - 5 tentativas de login/registro por minuto por IP
/// 
/// Este limite é mais agressivo que os endpoints gerais porque
/// ataques de credential stuffing e brute force são comuns em endpoints de auth.
Handler middleware(Handler handler) {
  return handler.use(authRateLimit());
}
