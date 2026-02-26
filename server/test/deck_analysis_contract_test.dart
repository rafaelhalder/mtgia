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
    'email': 'test_analysis_contract@example.com',
    'password': 'TestPassword123!',
    'username': 'test_analysis_contract_user',
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

  Future<String> createStandardDeckForAnalysis() async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': 'Analysis Contract ${DateTime.now().millisecondsSinceEpoch}',
        'format': 'standard',
        'description': 'analysis contract test',
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

  group('Deck analysis contract | /decks/:id/analysis', () {
    test(
      'returns 200 with expected payload shape',
      () async {
        final deckId = await createStandardDeckForAnalysis();
        createdDeckIds.add(deckId);

        final response = await http.get(
          Uri.parse('$baseUrl/decks/$deckId/analysis'),
          headers: authHeaders(),
        );

        expect(response.statusCode, equals(200), reason: response.body);
        final body = decodeJson(response);

        expect(body['deck_id'], equals(deckId));
        expect(body['stats'], isA<Map<String, dynamic>>());
        expect(body['mana_curve'], isA<Map<String, dynamic>>());
        expect(body['color_distribution'], isA<Map<String, dynamic>>());
        expect(body['legality'], isA<Map<String, dynamic>>());
      },
      skip: skipIntegration,
    );

    test(
      'returns 404 for missing deck',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/00000000-0000-0000-0000-000000000098/analysis'),
          headers: authHeaders(),
        );

        expect(response.statusCode, equals(404), reason: response.body);
        expect(decodeJson(response)['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'returns 405 for invalid method',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks/00000000-0000-0000-0000-000000000098/analysis'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, equals(405), reason: response.body);
      },
      skip: skipIntegration,
    );
  });
}
