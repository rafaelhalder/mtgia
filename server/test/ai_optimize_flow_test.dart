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
    'email': 'test_optimize_flow@example.com',
    'password': 'TestPassword123!',
    'username': 'test_optimize_flow_user',
  };

  final createdDeckIds = <String>[];
  String? authToken;

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

  Map<String, String> authHeaders({bool withContentType = false}) => {
        if (withContentType) 'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Future<String> createDeck({
    required String format,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': 'Optimize Flow ${DateTime.now().millisecondsSinceEpoch}',
        'format': format,
        'description': 'optimize flow test',
        'cards': [],
      }),
    );

    expect(response.statusCode, anyOf(200, 201), reason: response.body);
    return decodeJson(response)['id'] as String;
  }

  Future<void> deleteDeck(String deckId) async {
    await http.delete(
      Uri.parse('$baseUrl/decks/$deckId'),
      headers: authHeaders(),
    );
  }

  setUpAll(() async {
    authToken = await getAuthToken();
  });

  tearDownAll(() async {
    for (final deckId in createdDeckIds) {
      await deleteDeck(deckId);
    }
  });

  group('AI optimize flow | /ai/optimize', () {
    test(
      'returns success contract in mock or real mode',
      () async {
        final deckId = await createDeck(format: 'standard');
        createdDeckIds.add(deckId);

        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': deckId,
            'archetype': 'midrange',
          }),
        );

        expect(response.statusCode, anyOf(200, 500), reason: response.body);
        final body = decodeJson(response);
        if (response.statusCode == 200) {
          expect(body['mode'], isA<String>(), reason: response.body);
          expect(
            ['optimize', 'complete'].contains(body['mode']),
            isTrue,
            reason: 'mode deve ser normalizado para optimize|complete',
          );
          expect(body['reasoning'], isA<String>(), reason: response.body);
          if (body['is_mock'] == true) {
            expect(body['additions'], isA<List>());
            expect(body['deck_analysis'], isA<Map<String, dynamic>>());
          }
        } else {
          expect(body['error'], isA<String>());
          expect(
            (body['error'] as String).contains('Bad state: No element'),
            isFalse,
            reason: 'Regressão: optimize não deve vazar erro interno de coleção vazia.',
          );
        }
      },
      skip: skipIntegration,
    );

    test(
      'returns 400 when archetype is missing',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': '00000000-0000-0000-0000-000000000097',
          }),
        );

        expect(response.statusCode, equals(400), reason: response.body);
        expect(decodeJson(response)['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'returns 404 when deck does not exist',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': '00000000-0000-0000-0000-000000000097',
            'archetype': 'midrange',
          }),
        );

        expect(response.statusCode, equals(404), reason: response.body);
        expect(decodeJson(response)['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'commander incomplete deck without commander returns 400 in real mode or mock success',
      () async {
        final deckId = await createDeck(format: 'commander');
        createdDeckIds.add(deckId);

        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': deckId,
            'archetype': 'control',
          }),
        );

        final body = decodeJson(response);

        if (response.statusCode == 200) {
          expect(body['is_mock'], isTrue,
              reason:
                  '200 nesse cenário só é esperado no caminho mock (sem API key).');
        } else {
          expect(response.statusCode, equals(400), reason: response.body);
          expect(body['error'], isA<String>());
        }
      },
      skip: skipIntegration,
    );
  });
}
