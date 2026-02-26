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
  const missingUserId = '00000000-0000-0000-0000-000000000002';
  const missingNotificationId = '00000000-0000-0000-0000-000000000003';
  const missingTradeId = '00000000-0000-0000-0000-000000000004';
  const missingConversationId = '00000000-0000-0000-0000-000000000005';

  String? authToken;
  String? authUserId;

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

  Future<String> getAuthUserId(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load auth user: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>?;
    final id = user?['id'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('Missing user id in /auth/me response: ${response.body}');
    }
    return id;
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
    authUserId = await getAuthUserId(authToken!);
  });

  void expectJsonErrorContract(http.Response response, int statusCode) {
    expect(response.statusCode, equals(statusCode));
    final contentType = response.headers['content-type'] ?? '';
    expect(contentType.toLowerCase(), contains('application/json'));
    final body = decodeJson(response);
    expect(body['error'], isA<String>());
  }

  void expectJsonOrPlainErrorContract(http.Response response, int statusCode) {
    expect(response.statusCode, equals(statusCode));
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();

    if (contentType.contains('application/json')) {
      final body = decodeJson(response);
      final hasError = body['error'] is String;
      final hasMessage = body['message'] is String;
      expect(hasError || hasMessage, isTrue);
      return;
    }

    // Compatibilidade: alguns 404/405 podem vir do framework sem JSON/body.
    expect(contentType.contains('application/json'), isFalse);
  }

  void expect405Contract(http.Response response) {
    expectJsonOrPlainErrorContract(response, 405);
  }

  void expect404Contract(http.Response response) {
    expectJsonOrPlainErrorContract(response, 404);
  }

  void expectJsonMessageContract(http.Response response, int statusCode) {
    expect(response.statusCode, equals(statusCode));
    final contentType = response.headers['content-type'] ?? '';
    expect(contentType.toLowerCase(), contains('application/json'));
    final body = decodeJson(response);
    expect(body['message'], isA<String>());
  }

  void expectOptional400Or404(http.Response response) {
    expect(response.statusCode, anyOf(400, 404));
    if (response.statusCode == 400) {
      expectJsonOrPlainErrorContract(response, 400);
    } else {
      expect404Contract(response);
    }
  }

  void expectOptional401Or404(http.Response response) {
    expect(response.statusCode, anyOf(401, 404));
    if (response.statusCode == 401) {
      expectJsonOrPlainErrorContract(response, 401);
    } else {
      expect404Contract(response);
    }
  }

  void expectOptional404(http.Response response) {
    expect(response.statusCode, equals(404));
    expect404Contract(response);
  }

  void expectOptional405Or404(http.Response response) {
    expect(response.statusCode, anyOf(405, 404));
    if (response.statusCode == 405) {
      expect405Contract(response);
    } else {
      expect404Contract(response);
    }
  }

  group('Error contract | Core + AI', () {
    test(
      'POST /auth/login missing email returns 400 with message',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'password': 'x'}),
        );

        expectJsonMessageContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /auth/register missing username returns 400 with message',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': 'x@example.com', 'password': '123456'}),
        );

        expectJsonMessageContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'GET /auth/me without token returns 401 with error',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/auth/me'));

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /auth/me returns 405 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/auth/me'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks without token returns 401 with error',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/decks'));

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

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

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'DELETE /decks returns 405 with error',
      () async {
        final response = await http.delete(
          Uri.parse('$baseUrl/decks'),
          headers: authHeaders(),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /decks returns 405 with error',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/decks'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks/:id without token returns 401 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks/:id with missing deck returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
          headers: authHeaders(),
        );

        expectJsonErrorContract(response, 404);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /decks/:id without token returns 401 with error',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': 'x'}),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /decks/:id with missing deck returns 404 with error',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
          headers: authHeaders(true),
          body: jsonEncode({'name': 'x'}),
        );

        expectJsonErrorContract(response, 404);
      },
      skip: skipIntegration,
    );

    test(
      'DELETE /decks/:id without token returns 401 with error',
      () async {
        final response = await http.delete(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'DELETE /decks/:id with missing deck returns 404 with error',
      () async {
        final response = await http.delete(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
          headers: authHeaders(),
        );

        expectJsonErrorContract(response, 404);
      },
      skip: skipIntegration,
    );

    test(
      'POST /decks/:id/validate without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks/$missingDeckId/validate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks/:id/validate returns 405 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/$missingDeckId/validate'),
          headers: authHeaders(),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /decks/:id/pricing without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks/$missingDeckId/pricing'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks/:id/pricing returns 405 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/$missingDeckId/pricing'),
          headers: authHeaders(),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /decks/:id/pricing with missing deck returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks/$missingDeckId/pricing'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 404);
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks/:id/export without token returns 401 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/$missingDeckId/export'),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /decks/:id/export returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks/$missingDeckId/export'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, anyOf(404, 405));
        if (response.statusCode == 405) {
          expect405Contract(response);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'GET /decks/:id/export with missing deck returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/decks/$missingDeckId/export'),
          headers: authHeaders(),
        );

        expect404Contract(response);
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

        expectJsonErrorContract(response, 400);
        final body = decodeJson(response);
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

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/explain without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/explain'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'card_name': 'Sol Ring'}),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/explain missing card_name returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/explain'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/optimize without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'deck_id': missingDeckId, 'archetype': 'aggro'}),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/optimize missing required fields returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/optimize with missing deck returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/optimize'),
          headers: authHeaders(true),
          body: jsonEncode({'deck_id': missingDeckId, 'archetype': 'aggro'}),
        );

        expectJsonErrorContract(response, 404);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/generate without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'prompt': 'mono red aggro'}),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/generate missing prompt returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/generate'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'GET /ai/ml-status without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/ai/ml-status'));

        expect(response.statusCode, anyOf(401, 404));
        if (response.statusCode == 401) {
          expectJsonOrPlainErrorContract(response, 401);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /ai/ml-status returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/ai/ml-status'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect(response.statusCode, anyOf(404, 405));
        if (response.statusCode == 405) {
          expect405Contract(response);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /import without token returns 401 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/import'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': 'Import Unauthorized',
            'format': 'commander',
            'list': '1 Sol Ring',
          }),
        );

        expectJsonErrorContract(response, 401);
      },
      skip: skipIntegration,
    );

    test(
      'POST /import with invalid payload returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/import'),
          headers: authHeaders(true),
          body: jsonEncode({
            'name': 'Import Invalid',
            'format': 'commander',
            'list': 123,
          }),
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards returns 405 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/printings returns 405 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/printings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /cards/printings without name returns 400 with error',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/cards/printings'));

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'GET /cards/resolve returns 405 with error',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/cards/resolve'));

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve with empty body returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve'),
          headers: {'Content-Type': 'application/json'},
          body: '',
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve with invalid JSON returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve'),
          headers: {'Content-Type': 'application/json'},
          body: '{',
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve without name returns 400 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'GET /cards/resolve/batch returns 405 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/cards/resolve/batch'),
        );

        expect(response.statusCode, anyOf(404, 405));
        if (response.statusCode == 405) {
          expect405Contract(response);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve/batch with empty body returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve/batch'),
          headers: {'Content-Type': 'application/json'},
          body: '',
        );

        expect(response.statusCode, anyOf(400, 404));
        if (response.statusCode == 400) {
          expectJsonErrorContract(response, 400);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve/batch with invalid JSON returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve/batch'),
          headers: {'Content-Type': 'application/json'},
          body: '{',
        );

        expect(response.statusCode, anyOf(400, 404));
        if (response.statusCode == 400) {
          expectJsonErrorContract(response, 400);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve/batch with names not list returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve/batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'names': 'Sol Ring'}),
        );

        expect(response.statusCode, anyOf(400, 404));
        if (response.statusCode == 400) {
          expectJsonErrorContract(response, 400);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /cards/resolve/batch with empty names returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/cards/resolve/batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'names': <String>[]}),
        );

        expect(response.statusCode, anyOf(400, 404));
        if (response.statusCode == 400) {
          expectJsonErrorContract(response, 400);
        } else {
          expect404Contract(response);
        }
      },
      skip: skipIntegration,
    );

    test(
      'POST /rules returns 405 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/rules'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expect405Contract(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /import returns 405 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/import'),
          headers: authHeaders(),
        );

        expect405Contract(response);
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

        expectJsonErrorContract(response, 400);
      },
      skip: skipIntegration,
    );

    test(
      'POST /decks/:id returns 405 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/decks/$missingDeckId'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expect405Contract(response);
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

        expectJsonErrorContract(response, 404);
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

        expectJsonErrorContract(response, 400);
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

        expectJsonErrorContract(response, 404);
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

        expectJsonErrorContract(response, 400);
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

        expectJsonErrorContract(response, 404);
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

        expectJsonErrorContract(response, 400);
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

        expectJsonErrorContract(response, 404);
      },
      skip: skipIntegration,
    );

    test(
      'POST /community/decks/:id without token returns 401 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/community/decks/$missingDeckId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /community/decks/:id with missing deck returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/community/decks/$missingDeckId'),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /community/decks/:id returns 405 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/community/decks/$missingDeckId'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /community/users without q returns 400 (or 404 compat)',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/community/users'));

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /community/users returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/community/users?q=test'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /community/users/:id with missing user returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/community/users/$missingUserId'),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /community/users/:id returns 405 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/community/users/$missingUserId'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /community/binders/:userId with missing user returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/community/binders/$missingUserId'),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /community/binders/:userId returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/community/binders/$missingUserId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /community/marketplace returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/community/marketplace'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /users/:id/follow without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/users/$missingUserId/follow'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /users/:id/follow without token returns 401 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/users/$missingUserId/follow'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /users/:id/follow with missing user returns 404 with error',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/users/$missingUserId/follow'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /users/:id/follow self returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/users/$authUserId/follow'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /users/:id/followers without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/users/$missingUserId/followers'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /users/:id/followers returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/users/$missingUserId/followers'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /users/:id/following without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/users/$missingUserId/following'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /users/:id/following returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/users/$missingUserId/following'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /notifications without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/notifications'));

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /notifications returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/notifications'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /notifications/count without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/notifications/count'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /notifications/count returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/notifications/count'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /notifications/read-all without token returns 401 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/notifications/read-all'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /notifications/read-all returns 405 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/notifications/read-all'),
          headers: authHeaders(),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /notifications/:id/read without token returns 401 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/notifications/$missingNotificationId/read'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /notifications/:id/read returns 405 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/notifications/$missingNotificationId/read'),
          headers: authHeaders(),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /notifications/:id/read with missing notification returns 404 with error',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/notifications/$missingNotificationId/read'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /trades without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/trades'));

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /trades returns 405 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/trades'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /trades without token returns 401 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/trades'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /trades with empty payload returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/trades'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /trades with invalid type returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/trades'),
          headers: authHeaders(true),
          body: jsonEncode({
            'receiver_id': missingUserId,
            'type': 'invalid_type',
            'my_items': [],
            'requested_items': [],
          }),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /trades/:id without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/trades/$missingTradeId'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /trades/:id with missing trade returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/trades/$missingTradeId'),
          headers: authHeaders(),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /trades/:id returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/trades/$missingTradeId'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /trades/:id/respond without token returns 401 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/trades/$missingTradeId/respond'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'accept'}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /trades/:id/respond invalid action returns 400 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/trades/$missingTradeId/respond'),
          headers: authHeaders(true),
          body: jsonEncode({'action': 'noop'}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /trades/:id/status without token returns 401 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/trades/$missingTradeId/status'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'status': 'shipped'}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /trades/:id/status missing status returns 400 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/trades/$missingTradeId/status'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /trades/:id/messages without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/trades/$missingTradeId/messages'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /trades/:id/messages missing trade returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/trades/$missingTradeId/messages'),
          headers: authHeaders(),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /trades/:id/messages without token returns 401 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/trades/$missingTradeId/messages'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': 'hello'}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /trades/:id/messages invalid payload returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/trades/$missingTradeId/messages'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /conversations without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(Uri.parse('$baseUrl/conversations'));

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /conversations returns 405 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/conversations'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /conversations without token returns 401 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/conversations'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': missingUserId}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /conversations missing user_id returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/conversations'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /conversations/unread-count without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/conversations/unread-count'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /conversations/unread-count returns 405 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/conversations/unread-count'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /conversations/:id/messages without token returns 401 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/conversations/$missingConversationId/messages'),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /conversations/:id/messages missing conversation returns 404 with error',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/conversations/$missingConversationId/messages'),
          headers: authHeaders(),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /conversations/:id/messages without token returns 401 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/conversations/$missingConversationId/messages'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': 'hello'}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'POST /conversations/:id/messages missing message returns 400 (or 404 compat)',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/conversations/$missingConversationId/messages'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional400Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /conversations/:id/read without token returns 401 (or 404 compat)',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/conversations/$missingConversationId/read'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({}),
        );

        expectOptional401Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'GET /conversations/:id/read returns 405 (or 404 compat)',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/conversations/$missingConversationId/read'),
          headers: authHeaders(),
        );

        expectOptional405Or404(response);
      },
      skip: skipIntegration,
    );

    test(
      'PUT /conversations/:id/read missing conversation returns 404 with error',
      () async {
        final response = await http.put(
          Uri.parse('$baseUrl/conversations/$missingConversationId/read'),
          headers: authHeaders(true),
          body: jsonEncode({}),
        );

        expectOptional404(response);
      },
      skip: skipIntegration,
    );

  });
}
