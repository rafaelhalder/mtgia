import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  final skipIntegration = Platform.environment['RUN_INTEGRATION_TESTS'] == '1'
      ? null
      : 'Requer servidor rodando (defina RUN_INTEGRATION_TESTS=1).';

  final baseUrl =
      Platform.environment['TEST_API_BASE_URL'] ?? 'http://localhost:8080';

  Map<String, dynamic> decodeJson(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return <String, dynamic>{};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  group('Auth normalization', () {
    test(
      'register stores normalized username/email and login accepts mixed-case email',
      () async {
        final suffix = DateTime.now().millisecondsSinceEpoch;
        final rawUsername = '  MixedCaseUser$suffix  ';
        final rawEmail = '  Mixed.User.$suffix@Example.COM  ';
        const password = 'TestPassword123!';

        final registerResponse = await http.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': rawUsername,
            'email': rawEmail,
            'password': password,
          }),
        );

        expect(
          registerResponse.statusCode,
          anyOf(200, 201),
          reason: registerResponse.body,
        );

        final registerData = decodeJson(registerResponse);
        final user = registerData['user'] as Map<String, dynamic>;
        expect(user['username'], equals('mixedcaseuser$suffix'));
        expect(user['email'], equals('mixed.user.$suffix@example.com'));

        final loginResponse = await http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': '  MIXED.USER.$suffix@EXAMPLE.COM  ',
            'password': password,
          }),
        );

        expect(loginResponse.statusCode, equals(200),
            reason: loginResponse.body);
        final loginData = decodeJson(loginResponse);
        final loginUser = loginData['user'] as Map<String, dynamic>;
        expect(loginUser['username'], equals('mixedcaseuser$suffix'));
        expect(loginUser['email'], equals('mixed.user.$suffix@example.com'));
      },
      skip: skipIntegration,
    );

    test(
      'register rejects duplicate username/email even with different casing',
      () async {
        final suffix = DateTime.now().millisecondsSinceEpoch;
        final firstResponse = await http.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': 'duplicateuser$suffix',
            'email': 'duplicate.$suffix@example.com',
            'password': 'TestPassword123!',
          }),
        );

        expect(firstResponse.statusCode, anyOf(200, 201),
            reason: firstResponse.body);

        final duplicateResponse = await http.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': 'DuplicateUser$suffix',
            'email': 'DUPLICATE.$suffix@EXAMPLE.COM',
            'password': 'TestPassword123!',
          }),
        );

        expect(duplicateResponse.statusCode, equals(400),
            reason: duplicateResponse.body);
      },
      skip: skipIntegration,
    );
  });
}
