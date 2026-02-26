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
    'email': 'test_import_to_deck@example.com',
    'password': 'TestPassword123!',
    'username': 'test_import_to_deck_user',
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

  Future<String> createDeck() async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': 'ImportToDeck ${DateTime.now().millisecondsSinceEpoch}',
        'format': 'standard',
        'description': 'test import to deck',
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

  group('Import to existing deck | /import/to-deck', () {
    test(
      'imports list into existing deck successfully',
      () async {
        final deckId = await createDeck();
        createdDeckIds.add(deckId);

        final response = await http.post(
          Uri.parse('$baseUrl/import/to-deck'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': deckId,
            'list': '10 Forest',
            'replace_all': false,
          }),
        );

        expect(response.statusCode, equals(200), reason: response.body);
        final body = decodeJson(response);
        expect(body['success'], isTrue, reason: response.body);
        expect(body['cards_imported'], equals(10), reason: response.body);
      },
      skip: skipIntegration,
    );

    test(
      'returns 400 when list type is invalid',
      () async {
        final deckId = await createDeck();
        createdDeckIds.add(deckId);

        final response = await http.post(
          Uri.parse('$baseUrl/import/to-deck'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': deckId,
            'list': 123,
          }),
        );

        expect(response.statusCode, equals(400), reason: response.body);
        expect(decodeJson(response)['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'returns 404 for missing deck',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/import/to-deck'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'deck_id': '00000000-0000-0000-0000-000000000099',
            'list': '10 Forest',
          }),
        );

        expect(response.statusCode, equals(404), reason: response.body);
        expect(decodeJson(response)['error'], isA<String>());
      },
      skip: skipIntegration,
    );
  });
}
