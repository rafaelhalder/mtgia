import 'dart:async';

import 'package:test/test.dart';

import '../lib/rate_limit_middleware.dart';

void main() {
  group('RateLimiter', () {
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
