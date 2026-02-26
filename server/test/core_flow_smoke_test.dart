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
    'email': 'test_core_flow_smoke@example.com',
    'password': 'TestPassword123!',
    'username': 'test_core_flow_smoke_user',
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

    final data = decodeJson(response);
    return data['token'] as String;
  }

  Map<String, String> authHeaders({bool withContentType = false}) => {
        if (withContentType) 'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Future<String> createDeck({
    required String name,
    required String format,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': name,
        'format': format,
        'description': 'Smoke flow core',
        'cards': [],
      }),
    );

    expect(response.statusCode, anyOf(200, 201), reason: response.body);
    final body = decodeJson(response);
    final deckId = body['id'] as String?;
    expect(deckId, isNotNull, reason: response.body);
    return deckId!;
  }

  Future<void> validateDeckContract(String deckId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks/$deckId/validate'),
      headers: authHeaders(),
    );

    expect(response.statusCode, anyOf(200, 400), reason: response.body);
    final body = decodeJson(response);

    if (response.statusCode == 200) {
      expect(body['ok'], isTrue, reason: response.body);
    } else {
      expect(body['error'], isA<String>(), reason: response.body);
    }
  }

  Future<void> analyzeDeckContract(String deckId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/decks/$deckId/analysis'),
      headers: authHeaders(),
    );

    expect(response.statusCode, equals(200), reason: response.body);
    final body = decodeJson(response);

    expect(body['deck_id'], equals(deckId));
    expect(body['stats'], isA<Map<String, dynamic>>());
    expect(body['legality'], isA<Map<String, dynamic>>());
  }

  Future<void> optimizeDeckContract(String deckId) async {
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
      expect(body['reasoning'], isA<String>(), reason: response.body);
    } else {
      expect(body['error'], isA<String>(), reason: response.body);
    }
  }

  Future<void> optimizeMissingArchetypeError(String deckId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ai/optimize'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({'deck_id': deckId}),
    );

    expect(response.statusCode, equals(400), reason: response.body);
    final body = decodeJson(response);
    expect(body['error'], isA<String>());
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

  group('Core flow smoke | create -> validate -> analyze -> optimize', () {
    test(
      'create flow enforces core contracts',
      () async {
        final deckId = await createDeck(
          name: 'Smoke Create Standard ${DateTime.now().millisecondsSinceEpoch}',
          format: 'standard',
        );
        createdDeckIds.add(deckId);

        await validateDeckContract(deckId);
        await analyzeDeckContract(deckId);
        await optimizeDeckContract(deckId);
      },
      skip: skipIntegration,
    );

    test(
      'import invalid payload and optimize critical error are enforced',
      () async {
        final invalidImport = await http.post(
          Uri.parse('$baseUrl/import'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode({
            'name': 'Smoke Invalid Import',
            'format': 'standard',
            'list': 123,
          }),
        );

        expect(invalidImport.statusCode, equals(400), reason: invalidImport.body);
        expect(decodeJson(invalidImport)['error'], isA<String>());

        final deckId = await createDeck(
          name: 'Smoke Create For Error ${DateTime.now().millisecondsSinceEpoch}',
          format: 'standard',
        );
        createdDeckIds.add(deckId);

        await optimizeMissingArchetypeError(deckId);
      },
      skip: skipIntegration,
    );
  });
}
