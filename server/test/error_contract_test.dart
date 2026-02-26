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
    'email': 'test_error_contract@example.com',
    'password': 'TestPassword123!',
    'username': 'test_error_contract_user',
  };

  const missingDeckId = '00000000-0000-0000-0000-000000000001';

  String? authToken;

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

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['token'] as String;
  }

  Map<String, dynamic> decodeJson(http.Response response) {
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }

  Map<String, String> authHeaders([bool withContentType = false]) {
    return {
      if (withContentType) 'Content-Type': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };
  }

  setUpAll(() async {
    authToken = await getAuthToken();
  });

  group('Error contract | Core + AI', () {
    test(
      'POST /decks without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': 'Unauthorized Deck',
            'format': 'commander',
          }),
        );

        expect(response.statusCode, equals(401));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /decks without required fields returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks'),
          headers: authHeaders(true),
          body: jsonEncode({
            'description': 'missing name/format',
          }),
        );

        expect(response.statusCode, equals(400));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
        expect((body['error'] as String).isNotEmpty, isTrue);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/archetypes without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/archetypes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'deck_id': missingDeckId}),
        );

        expect(response.statusCode, equals(401));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/archetypes without deck_id returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/archetypes'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, equals(400));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/archetypes with missing deck returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/archetypes'),
          headers: authHeaders(true),
          body: jsonEncode({'deck_id': missingDeckId}),
        );

        expect(response.statusCode, equals(404));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/simulate without deck_id returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/simulate'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, equals(400));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/simulate with missing deck returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/simulate'),
          headers: authHeaders(true),
          body: jsonEncode({'deck_id': missingDeckId}),
        );

        expect(response.statusCode, equals(404));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/simulate-matchup without ids returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/simulate-matchup'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, equals(400));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/simulate-matchup with missing my_deck returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/simulate-matchup'),
          headers: authHeaders(true),
          body: jsonEncode({
            'my_deck_id': missingDeckId,
            'opponent_deck_id': missingDeckId,
          }),
        );

        expect(response.statusCode, equals(404));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/weakness-analysis without deck_id returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/weakness-analysis'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, equals(400));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/weakness-analysis with missing deck returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/weakness-analysis'),
          headers: authHeaders(true),
          body: jsonEncode({'deck_id': missingDeckId}),
        );

        expect(response.statusCode, equals(404));
        final body = decodeJson(response);
        expect(body['error'], isA<String>());
      },
      skip: skipIntegration,
    );

  });
}
