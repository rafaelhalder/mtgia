import 'dart:async';

import 'package:test/test.dart';

import '../lib/rate_limit_middleware.dart';

void main() {
  group('RateLimiter', () {
    test('extracts first forwarded IP when proxy header is present', () {
      final clientId = RateLimiter.buildClientIdentifierFromHeaders({
        'X-Forwarded-For': '203.0.113.10, 10.0.0.1',
      });

      expect(clientId, equals('203.0.113.10'));
    });

    test(
        'builds a fingerprint fallback instead of anonymous when headers exist',
        () {
      final clientId = RateLimiter.buildClientIdentifierFromHeaders({
        'User-Agent': 'Mozilla/5.0',
        'Accept-Language': 'pt-BR',
        'Host': 'localhost:8080',
      });

      expect(clientId, startsWith('fingerprint:'));
    });

    test('keeps anonymous only when no identifying headers exist', () {
      final clientId = RateLimiter.buildClientIdentifierFromHeaders(const {});

      expect(clientId, equals('anonymous'));
    });

    test('allows requests up to limit then blocks', () {
      final limiter = RateLimiter(maxRequests: 2, windowSeconds: 60);

      expect(limiter.isAllowed('client-a'), isTrue);
      expect(limiter.isAllowed('client-a'), isTrue);
      expect(limiter.isAllowed('client-a'), isFalse);
    });

    test('isolates limits by client identifier', () {
      final limiter = RateLimiter(maxRequests: 1, windowSeconds: 60);

      expect(limiter.isAllowed('client-a'), isTrue);
      expect(limiter.isAllowed('client-b'), isTrue);
      expect(limiter.isAllowed('client-a'), isFalse);
      expect(limiter.isAllowed('client-b'), isFalse);
    });

    test('window expiration re-allows requests', () async {
      final limiter = RateLimiter(maxRequests: 1, windowSeconds: 1);

      expect(limiter.isAllowed('client-c'), isTrue);
      expect(limiter.isAllowed('client-c'), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(limiter.isAllowed('client-c'), isTrue);
    });

    test('cleanup removes stale entries from memory', () async {
      final limiter = RateLimiter(maxRequests: 1, windowSeconds: 1);

      expect(limiter.isAllowed('client-d'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      limiter.cleanup();

      expect(limiter.isAllowed('client-d'), isTrue);
    });
  });
}
