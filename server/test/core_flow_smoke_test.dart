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

  Future<String> resolveCardIdByName(String cardName) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/cards?name=${Uri.encodeQueryComponent(cardName)}&limit=5&page=1',
      ),
      headers: authHeaders(),
    );

    expect(response.statusCode, equals(200), reason: response.body);
    final body = decodeJson(response);

    final dynamicList = (body['data'] as List?) ?? (body['cards'] as List?) ?? [];
    final cards = dynamicList.cast<Map<String, dynamic>>();

    expect(cards, isNotEmpty,
        reason:
            'Carta "$cardName" não encontrada para montar smoke test do fluxo core.');

    final exact = cards.firstWhere(
      (card) =>
          (card['name'] as String?)?.toLowerCase() == cardName.toLowerCase(),
      orElse: () => cards.first,
    );

    final id = exact['id'] as String?;
    expect(id, isNotNull);
    return id!;
  }

  Future<String> createDeck({
    required String name,
    required String format,
    required List<Map<String, dynamic>> cards,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': name,
        'format': format,
        'description': 'Smoke flow core',
        'cards': cards,
      }),
    );

    expect(response.statusCode, anyOf(200, 201), reason: response.body);
    final body = decodeJson(response);

    final deckId = body['id'] as String?;
    expect(deckId, isNotNull, reason: response.body);
    return deckId!;
  }

  Future<String> importDeck({
    required String name,
    required String format,
    required String list,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/import'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': name,
        'format': format,
        'list': list,
      }),
    );

    expect(response.statusCode, equals(200), reason: response.body);

    final body = decodeJson(response);
    final deck = body['deck'] as Map<String, dynamic>?;
    final deckId = deck?['id'] as String?;

    expect(deckId, isNotNull, reason: response.body);
    return deckId!;
  }

  Future<void> validateDeck(String deckId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks/$deckId/validate'),
      headers: authHeaders(),
    );

    expect(response.statusCode, equals(200), reason: response.body);
    final body = decodeJson(response);
    expect(body['ok'], isTrue, reason: response.body);
  }

  Future<void> analyzeDeck(String deckId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/decks/$deckId/analysis'),
      headers: authHeaders(),
    );

    expect(response.statusCode, equals(200), reason: response.body);
    final body = decodeJson(response);

    expect(body['deck_id'], equals(deckId));
    expect(body['stats'], isA<Map<String, dynamic>>());
    expect((body['legality'] as Map<String, dynamic>)['is_valid'], isTrue,
        reason: response.body);
  }

  Future<void> optimizeDeckSuccess(String deckId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ai/optimize'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'deck_id': deckId,
        'archetype': 'midrange',
      }),
    );

    expect(response.statusCode, equals(200), reason: response.body);
    final body = decodeJson(response);
    expect(body['reasoning'], isA<String>());
  }

  Future<void> optimizeDeckErrorMissingArchetype(String deckId) async {
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

  group('Core flow smoke | create/import -> validate -> analyze -> optimize', () {
    test(
      'create deck succeeds through validate/analyze/optimize',
      () async {
        final forestId = await resolveCardIdByName('Forest');

        final deckId = await createDeck(
          name: 'Smoke Create Standard ${DateTime.now().millisecondsSinceEpoch}',
          format: 'standard',
          cards: [
            {
              'card_id': forestId,
              'quantity': 60,
            }
          ],
        );
        createdDeckIds.add(deckId);

        await validateDeck(deckId);
        await analyzeDeck(deckId);
        await optimizeDeckSuccess(deckId);
      },
      skip: skipIntegration,
    );

    test(
      'import success and optimize error critical are both enforced',
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

        expect(invalidImport.statusCode, equals(400),
            reason: invalidImport.body);
        expect(decodeJson(invalidImport)['error'], isA<String>());

        final importedDeckId = await importDeck(
          name: 'Smoke Import Standard ${DateTime.now().millisecondsSinceEpoch}',
          format: 'standard',
          list: '60 Forest',
        );
        createdDeckIds.add(importedDeckId);

        await validateDeck(importedDeckId);
        await analyzeDeck(importedDeckId);
        await optimizeDeckErrorMissingArchetype(importedDeckId);
      },
      skip: skipIntegration,
    );
  });
}
