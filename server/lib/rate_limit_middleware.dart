import 'dart:io';
import 'package:dart_frog/dart_frog.dart';

/// Rate Limiter Middleware para prevenir abuso de endpoints
/// 
/// **Uso:**
/// ```dart
/// // Em routes/auth/_middleware.dart (aplicar apenas nas rotas de auth)
/// Handler middleware(Handler handler) {
///   return handler
///     .use(rateLimitMiddleware(maxRequests: 5, windowSeconds: 60));
/// }
/// ```
/// 
/// **Estratégia:**
/// - Limita o número de requisições por IP em uma janela de tempo
/// - Retorna 429 (Too Many Requests) se exceder o limite
/// - Usa memória local (em produção, recomenda-se Redis)
/// 
/// **Parâmetros:**
/// - `maxRequests`: Número máximo de requisições permitidas na janela
/// - `windowSeconds`: Duração da janela em segundos
/// - `identifier`: Função para identificar o cliente (default: IP address)
/// 
/// **Exemplo de Limites Sugeridos:**
/// - Login/Register: 5 requisições por minuto
/// - Endpoints gerais autenticados: 100 requisições por minuto
/// - Endpoints de IA: 10 requisições por minuto (custosos)
class RateLimiter {
  final int maxRequests;
  final int windowSeconds;
  final String Function(RequestContext) identifier;

  // Mapa: identifier -> List<timestamp dos requests>
  final Map<String, List<DateTime>> _requestLog = {};

  RateLimiter({
    required this.maxRequests,
    required this.windowSeconds,
    String Function(RequestContext)? identifier,
  }) : identifier = identifier ?? _defaultIdentifier;

  static String _defaultIdentifier(RequestContext context) {
    // Tenta obter o IP real (considerando proxies)
    final forwardedFor = context.request.headers['X-Forwarded-For'];
    if (forwardedFor != null && forwardedFor.isNotEmpty) {
      return forwardedFor.split(',').first.trim();
    }
    
    // Fallback: usar "anonymous" quando IP não está disponível
    // Em produção com proxy reverso (ex: Nginx), X-Forwarded-For sempre estará presente
    // Se não estiver disponível, não podemos identificar o cliente de forma confiável
    return 'anonymous';
  }

  bool isAllowed(String clientId) {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(seconds: windowSeconds));

    // Limpar requisições antigas da janela
    if (_requestLog.containsKey(clientId)) {
      _requestLog[clientId]!.removeWhere((timestamp) => timestamp.isBefore(windowStart));
    } else {
      _requestLog[clientId] = [];
    }

    // Verificar limite
    if (_requestLog[clientId]!.length >= maxRequests) {
      return false; // Limite excedido
    }

    // Registrar nova requisição
    _requestLog[clientId]!.add(now);
    return true;
  }

  void cleanup() {
    // Periodicamente limpar IDs antigos para evitar memory leak
    // (Implementação simplificada - em produção, usar um timer)
    final cutoff = DateTime.now().subtract(Duration(seconds: windowSeconds * 2));
    _requestLog.removeWhere((_, timestamps) {
      timestamps.removeWhere((t) => t.isBefore(cutoff));
      return timestamps.isEmpty;
    });
  }
}

/// Instâncias globais de rate limiters por tipo de endpoint
final _authRateLimiter = RateLimiter(
  maxRequests: 5,
  windowSeconds: 60, // 5 requisições por minuto
);

final _generalRateLimiter = RateLimiter(
  maxRequests: 100,
  windowSeconds: 60, // 100 requisições por minuto
);

final _aiRateLimiter = RateLimiter(
  maxRequests: 10,
  windowSeconds: 60, // 10 requisições por minuto (IA é custosa)
);

/// Middleware factory para diferentes níveis de rate limiting
Middleware rateLimitMiddleware({
  int maxRequests = 100,
  int windowSeconds = 60,
  String Function(RequestContext)? identifier,
}) {
  final limiter = RateLimiter(
    maxRequests: maxRequests,
    windowSeconds: windowSeconds,
    identifier: identifier,
  );

  return (handler) {
    return (context) async {
      final clientId = limiter.identifier(context);

      if (!limiter.isAllowed(clientId)) {
        return Response.json(
          statusCode: HttpStatus.tooManyRequests, // 429
          body: {
            'error': 'Too Many Requests',
            'message': 'Você excedeu o limite de $maxRequests requisições em $windowSeconds segundos.',
            'retry_after': windowSeconds,
          },
          headers: {
            'Retry-After': windowSeconds.toString(),
            'X-RateLimit-Limit': maxRequests.toString(),
            'X-RateLimit-Window': windowSeconds.toString(),
          },
        );
      }

      // Adicionar headers informativos na resposta bem-sucedida
      final response = await handler(context);
      
      // Contar quantas requisições restam (estimativa)
      final remaining = maxRequests - (limiter._requestLog[clientId]?.length ?? 0);
      
      return response.copyWith(
        headers: {
          ...response.headers,
          'X-RateLimit-Limit': maxRequests.toString(),
          'X-RateLimit-Remaining': remaining.toString(),
          'X-RateLimit-Window': windowSeconds.toString(),
        },
      );
    };
  };
}

/// Middleware específico para rotas de autenticação (mais restritivo)
Middleware authRateLimit() {
  return (handler) {
    return (context) async {
      final clientId = RateLimiter._defaultIdentifier(context);

      if (!_authRateLimiter.isAllowed(clientId)) {
        return Response.json(
          statusCode: HttpStatus.tooManyRequests,
          body: {
            'error': 'Too Many Login Attempts',
            'message': 'Você fez muitas tentativas de login. Aguarde 1 minuto.',
            'retry_after': 60,
          },
          headers: {'Retry-After': '60'},
        );
      }

      return handler(context);
    };
  };
}

/// Middleware específico para rotas de IA (controla custos)
Middleware aiRateLimit() {
  return (handler) {
    return (context) async {
      final clientId = RateLimiter._defaultIdentifier(context);

      if (!_aiRateLimiter.isAllowed(clientId)) {
        return Response.json(
          statusCode: HttpStatus.tooManyRequests,
          body: {
            'error': 'Too Many AI Requests',
            'message': 'Você atingiu o limite de requisições de IA. Aguarde 1 minuto.',
            'retry_after': 60,
          },
          headers: {'Retry-After': '60'},
        );
      }

      return handler(context);
    };
  };
}
