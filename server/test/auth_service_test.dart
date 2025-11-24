import 'package:test/test.dart';
import 'package:server/auth_service.dart';

/// Testes unitários para o AuthService
/// 
/// Cobertura:
/// - Hash e verificação de senhas
/// - Geração e validação de tokens JWT
/// - Ciclo completo de autenticação
void main() {
  late AuthService authService;

  setUp(() {
    authService = AuthService();
  });

  group('Password Hashing', () {
    test('hashPassword should generate different hashes for same password', () {
      final password = 'testPassword123';
      final hash1 = authService.hashPassword(password);
      final hash2 = authService.hashPassword(password);

      // Bcrypt inclui salt, então hashes devem ser diferentes
      expect(hash1, isNot(equals(hash2)));
      expect(hash1.length, greaterThan(50)); // Bcrypt hashes são longos
    });

    test('verifyPassword should return true for correct password', () {
      final password = 'mySecurePassword!123';
      final hash = authService.hashPassword(password);

      final result = authService.verifyPassword(password, hash);
      expect(result, isTrue);
    });

    test('verifyPassword should return false for incorrect password', () {
      final password = 'correctPassword';
      final wrongPassword = 'wrongPassword';
      final hash = authService.hashPassword(password);

      final result = authService.verifyPassword(wrongPassword, hash);
      expect(result, isFalse);
    });

    test('verifyPassword should handle empty strings', () {
      final password = '';
      final hash = authService.hashPassword(password);

      expect(authService.verifyPassword(password, hash), isTrue);
      expect(authService.verifyPassword('notEmpty', hash), isFalse);
    });

    test('verifyPassword should handle special characters', () {
      final password = '!@#\$%^&*()_+-=[]{}|;:,.<>?/~`';
      final hash = authService.hashPassword(password);

      expect(authService.verifyPassword(password, hash), isTrue);
    });
  });

  group('JWT Token Management', () {
    test('generateToken should create a valid token', () {
      final userId = 'test-user-id-123';
      final username = 'testUser';

      final token = authService.generateToken(userId, username);

      expect(token, isNotEmpty);
      expect(token.split('.').length, equals(3)); // JWT tem 3 partes separadas por ponto
    });

    test('verifyToken should return payload for valid token', () {
      final userId = 'user-id-456';
      final username = 'anotherUser';

      final token = authService.generateToken(userId, username);
      final payload = authService.verifyToken(token);

      expect(payload, isNotNull);
      expect(payload!['userId'], equals(userId));
      expect(payload['username'], equals(username));
      expect(payload['iat'], isA<int>());
    });

    test('verifyToken should return null for invalid token', () {
      final invalidToken = 'invalid.token.here';

      final payload = authService.verifyToken(invalidToken);
      expect(payload, isNull);
    });

    test('verifyToken should return null for malformed token', () {
      final malformedToken = 'malformed-token-without-dots';

      final payload = authService.verifyToken(malformedToken);
      expect(payload, isNull);
    });

    test('verifyToken should return null for empty token', () {
      final payload = authService.verifyToken('');
      expect(payload, isNull);
    });

    test('generateToken should create unique tokens for different users', () {
      final token1 = authService.generateToken('user1', 'username1');
      final token2 = authService.generateToken('user2', 'username2');

      expect(token1, isNot(equals(token2)));
    });

    test('token lifecycle: generate -> verify -> decode', () {
      final userId = 'lifecycle-test-id';
      final username = 'lifecycleUser';

      // 1. Gerar
      final token = authService.generateToken(userId, username);
      expect(token, isNotEmpty);

      // 2. Verificar
      final payload = authService.verifyToken(token);
      expect(payload, isNotNull);

      // 3. Decodificar e validar dados
      expect(payload!['userId'], equals(userId));
      expect(payload['username'], equals(username));
      
      // 4. Verificar timestamp de emissão
      final iat = payload['iat'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(iat, lessThanOrEqualTo(now));
      expect(iat, greaterThan(now - 10000)); // Token criado nos últimos 10 segundos
    });
  });

  group('Edge Cases', () {
    test('hashPassword should handle very long passwords', () {
      final longPassword = 'a' * 1000;
      final hash = authService.hashPassword(longPassword);

      expect(authService.verifyPassword(longPassword, hash), isTrue);
    });

    test('generateToken should handle special characters in username', () {
      final userId = 'user-123';
      final username = 'user@test.com';

      final token = authService.generateToken(userId, username);
      final payload = authService.verifyToken(token);

      expect(payload, isNotNull);
      expect(payload!['username'], equals(username));
    });

    test('generateToken should handle unicode characters', () {
      final userId = 'user-unicode';
      final username = '用户名🎮';

      final token = authService.generateToken(userId, username);
      final payload = authService.verifyToken(token);

      expect(payload, isNotNull);
      expect(payload!['username'], equals(username));
    });

    test('verifyPassword should fail gracefully with invalid hash format', () {
      final password = 'testPassword';
      final invalidHash = 'not-a-valid-bcrypt-hash';

      expect(() => authService.verifyPassword(password, invalidHash), throwsException);
    });
  });
}
