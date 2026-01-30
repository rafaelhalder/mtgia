import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Testes de integração do endpoint incremental:
/// - POST /decks/:id/cards
/// - POST /decks/:id/validate (modo estrito)
///
/// Requer servidor rodando em http://localhost:8080.
void main() {
  const baseUrl = 'http://localhost:8080';

  const testUser = {
    'email': 'test_deck_incremental@example.com',
    'password': 'TestPassword123!',
    'username': 'test_deck_incremental_user'
  };

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

  Future<String> createDeck(String token, {String format = 'commander'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': 'Deck incremental',
        'format': format,
        'description': 'Deck de teste',
        'cards': [],
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create deck: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<Map<String, dynamic>?> findCardByNames(
    String token, {
    required List<String> names,
  }) async {
    for (final name in names) {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/cards?name=${Uri.encodeQueryComponent(name)}&limit=10'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) continue;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = (data['data'] as List).cast<Map<String, dynamic>>();
      if (cards.isNotEmpty) return cards.first;
    }
    return null;
  }

  bool isCommanderEligible(Map<String, dynamic> card) {
    final typeLine = (card['type_line'] as String? ?? '').toLowerCase();
    final oracle = (card['oracle_text'] as String? ?? '').toLowerCase();
    return (typeLine.contains('legendary') && typeLine.contains('creature')) ||
        oracle.contains('can be your commander');
  }

  List<String> identityOf(Map<String, dynamic> card) {
    final id =
        (card['color_identity'] as List?)?.map((e) => e.toString()).toList();
    if (id != null && id.isNotEmpty) return id;
    final colors = (card['colors'] as List?)?.map((e) => e.toString()).toList();
    return colors ?? const <String>[];
  }

  Future<http.Response> addCard(
    String token, {
    required String deckId,
    required String cardId,
    required int quantity,
    bool isCommander = false,
  }) {
    return http.post(
      Uri.parse('$baseUrl/decks/$deckId/cards'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'card_id': cardId,
        'quantity': quantity,
        'is_commander': isCommander,
      }),
    );
  }

  Future<http.Response> validateDeck(String token, String deckId) {
    return http.post(
      Uri.parse('$baseUrl/decks/$deckId/validate'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  setUpAll(() async {
    await Future.delayed(const Duration(milliseconds: 200));
  });

  test('POST /decks/:id/cards should add commander and block outside identity',
      () async {
    final token = await getAuthToken();
    final deckId = await createDeck(token, format: 'commander');

    final commander = await findCardByNames(token, names: [
      'Talrand, Sky Summoner',
      'Krenko, Mob Boss',
      'Lathril, Blade of the Elves',
      'Niv-Mizzet, Parun',
    ]);
    if (commander == null || !isCommanderEligible(commander)) {
      return;
    }

    final commanderId = commander['id'] as String;
    final commanderIdentity =
        identityOf(commander).map((e) => e.toUpperCase()).toSet();
    if (commanderIdentity.isEmpty) {
      return;
    }

    final addCommanderRes = await addCard(
      token,
      deckId: deckId,
      cardId: commanderId,
      quantity: 1,
      isCommander: true,
    );
    expect(addCommanderRes.statusCode, equals(200),
        reason: addCommanderRes.body);

    final outside =
        await findCardByNames(token, names: ['Lightning Bolt', 'Shock']);
    if (outside == null) return;

    final outsideId = outside['id'] as String;
    final outsideIdentity =
        identityOf(outside).map((e) => e.toUpperCase()).toSet();
    final outsideIsOutside =
        outsideIdentity.any((c) => !commanderIdentity.contains(c));
    if (!outsideIsOutside) return;

    final addOutsideRes =
        await addCard(token, deckId: deckId, cardId: outsideId, quantity: 1);
    expect(addOutsideRes.statusCode, equals(400), reason: addOutsideRes.body);
  });

  test(
      'POST /decks/:id/validate should fail when deck is not complete (Commander=100)',
      () async {
    final token = await getAuthToken();
    final deckId = await createDeck(token, format: 'commander');

    final commander = await findCardByNames(token, names: [
      'Talrand, Sky Summoner',
      'Krenko, Mob Boss',
      'Lathril, Blade of the Elves',
      'Niv-Mizzet, Parun',
    ]);
    if (commander == null || !isCommanderEligible(commander)) {
      return;
    }

    final commanderId = commander['id'] as String;
    final addCommanderRes = await addCard(
      token,
      deckId: deckId,
      cardId: commanderId,
      quantity: 1,
      isCommander: true,
    );
    expect(addCommanderRes.statusCode, equals(200),
        reason: addCommanderRes.body);

    final validateRes = await validateDeck(token, deckId);
    expect(validateRes.statusCode, equals(400), reason: validateRes.body);
  });
}
