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

  const testUser = {
    'email': 'test_optimize_telemetry@example.com',
    'password': 'TestPassword123!',
    'username': 'test_optimize_telemetry_user',
  };

  Map<String, dynamic> decodeJson(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }

  Future<String> getAuthToken() async {
    var response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': testUser['email'],
        'password': testUser['password'],
      }),
    );

    if (response.statusCode != 200) {
      response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testUser),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to register test user: ${response.body}');
      }

      response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': testUser['email'],
          'password': testUser['password'],
        }),
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to login test user: ${response.body}');
    }

    return decodeJson(response)['token'] as String;
  }

  group('AI optimize telemetry contract | /ai/optimize/telemetry', () {
    test(
      'returns 401 without token',
      () async {
        final response =
            await http.get(Uri.parse('$baseUrl/ai/optimize/telemetry'));

        expect(response.statusCode, equals(401), reason: response.body);
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'returns persisted telemetry aggregate with auth',
      () async {
        final token = await getAuthToken();

        final response = await http.get(
          Uri.parse('$baseUrl/ai/optimize/telemetry?days=7'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );

        expect(response.statusCode, equals(200), reason: response.body);

        final body = decodeJson(response);
        expect(body['status'], anyOf(equals('ok'), equals('not_initialized')),
            reason: response.body);

        if (body['status'] == 'ok') {
          expect(body['window_days'], equals(7));
          expect(body['global'], isA<Map<String, dynamic>>());
          expect(body['window'], isA<Map<String, dynamic>>());
          expect(body['current_user_window'], isA<Map<String, dynamic>>());
        }
      },
      skip: skipIntegration,
    );
  });
}
