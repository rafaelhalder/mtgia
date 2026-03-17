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
    'email': 'test_ai_generate_flow@example.com',
    'password': 'TestPassword123!',
    'username': 'test_ai_generate_flow_user',
  };

  const generationCandidates = [
    (
      prompt: 'mono red aggro with low curve burn creatures and haste threats',
      format: 'Standard',
      archetype: 'aggro',
    ),
    (
      prompt: 'mono black midrange with efficient removal and card advantage',
      format: 'Standard',
      archetype: 'midrange',
    ),
    (
      prompt: 'azorius control with board wipes card draw and planeswalkers',
      format: 'Standard',
      archetype: 'control',
    ),
  ];

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

  bool isTransientClientException(Object error) {
    if (error is! http.ClientException) return false;
    final message = error.message.toLowerCase();
    return message.contains('connection closed') ||
        message.contains('reset') ||
        message.contains('refused');
  }

  Future<http.Response> postJson(
    String path,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 90),
    int attempts = 3,
  }) async {
    Object? lastError;

    for (var i = 0; i < attempts; i++) {
      try {
        return await http
            .post(
              Uri.parse('$baseUrl$path'),
              headers: authHeaders(withContentType: true),
              body: jsonEncode(payload),
            )
            .timeout(timeout);
      } catch (error) {
        lastError = error;
        if (!isTransientClientException(error) || i == attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    throw Exception('POST retry exhausted: $path error=$lastError');
  }

  Future<Map<String, dynamic>> generateUsableDeck() async {
    final failures = <String>[];

    for (final candidate in generationCandidates) {
      final response = await postJson('/ai/generate', {
        'prompt': candidate.prompt,
        'format': candidate.format,
      });

      final body = decodeJson(response);
      if (response.statusCode == 200) {
        return {
          'response': body,
          'prompt': candidate.prompt,
          'format': candidate.format,
          'archetype': candidate.archetype,
        };
      }

      failures.add(
        '${candidate.prompt} -> ${response.statusCode}: ${body['error'] ?? response.body}',
      );
    }

    fail(
      'Nenhum prompt de geracao retornou deck valido. Tentativas:\n${failures.join('\n')}',
    );
  }

  int countGeneratedCards(Map<String, dynamic> generatedDeck) {
    final commander = generatedDeck['commander'] as Map<String, dynamic>?;
    final cards =
        (generatedDeck['cards'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];

    final cardCount = cards.fold<int>(
      0,
      (sum, card) => sum + ((card['quantity'] as int?) ?? 1),
    );
    return cardCount + (commander == null ? 0 : 1);
  }

  List<Map<String, dynamic>> cardsForCreatePayload(
    Map<String, dynamic> generatedDeck,
  ) {
    final payload = <Map<String, dynamic>>[];
    final commander = generatedDeck['commander'] as Map<String, dynamic>?;
    final cards =
        (generatedDeck['cards'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];

    if (commander != null && commander['name'] is String) {
      payload.add({
        'name': commander['name'],
        'quantity': 1,
        'is_commander': true,
      });
    }

    for (final card in cards) {
      payload.add({
        'name': card['name'],
        'quantity': (card['quantity'] as int?) ?? 1,
      });
    }

    return payload;
  }

  Future<String> createDeckFromGenerated({
    required Map<String, dynamic> generatedDeck,
    required String format,
    required String prompt,
  }) async {
    final response = await postJson('/decks', {
      'name': 'AI Generated ${DateTime.now().millisecondsSinceEpoch}',
      'format': format.toLowerCase(),
      'description': prompt,
      'cards': cardsForCreatePayload(generatedDeck),
    });

    expect(response.statusCode, anyOf(200, 201), reason: response.body);
    return decodeJson(response)['id'] as String;
  }

  Future<void> validateDeck(String deckId) async {
    Object? lastError;
    http.Response? response;

    for (var i = 0; i < 3; i++) {
      try {
        response = await http.post(
          Uri.parse('$baseUrl/decks/$deckId/validate'),
          headers: authHeaders(),
        );
        break;
      } catch (error) {
        lastError = error;
        if (!isTransientClientException(error) || i == 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    if (response == null) {
      throw Exception('Validate retry exhausted: $deckId error=$lastError');
    }

    expect(response.statusCode, equals(200), reason: response.body);
    final body = decodeJson(response);
    expect(body['ok'], isTrue, reason: response.body);
  }

  Future<http.Response> pollOptimizeJob(
    String jobId, {
    int maxPolls = 120,
  }) async {
    for (var i = 0; i < maxPolls; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final pollResponse = await http.get(
        Uri.parse('$baseUrl/ai/optimize/jobs/$jobId'),
        headers: authHeaders(),
      );

      final data = decodeJson(pollResponse);
      final status = data['status'] as String?;
      if (status == 'completed') {
        return http.Response(jsonEncode(data['result'] ?? {}), 200);
      }
      if (status == 'failed') {
        return http.Response(
          jsonEncode({
            'error': data['error'] ?? 'Job falhou',
            'quality_error': data['quality_error'],
          }),
          422,
        );
      }
    }

    return http.Response('{"error":"Polling timeout"}', 500);
  }

  Future<http.Response> optimizeWithPolling({
    required String deckId,
    required String archetype,
  }) async {
    final response = await postJson('/ai/optimize', {
      'deck_id': deckId,
      'archetype': archetype,
    });

    if (response.statusCode == 202) {
      final body = decodeJson(response);
      final jobId = body['job_id'] as String?;
      expect(jobId, isNotNull, reason: response.body);
      return pollOptimizeJob(jobId!);
    }

    return response;
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

  group('AI generate -> create -> validate/optimize', () {
    test(
      'generated deck can be created and validated',
      () async {
        final generation = await generateUsableDeck();
        final generatedDeck =
            generation['response']['generated_deck'] as Map<String, dynamic>;

        final totalCards = countGeneratedCards(generatedDeck);
        expect(totalCards, greaterThanOrEqualTo(60));

        final deckId = await createDeckFromGenerated(
          generatedDeck: generatedDeck,
          format: generation['format'] as String,
          prompt: generation['prompt'] as String,
        );
        createdDeckIds.add(deckId);

        await validateDeck(deckId);
      },
      skip: skipIntegration,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'generated deck can be created and optimized',
      () async {
        final generation = await generateUsableDeck();
        final generatedDeck =
            generation['response']['generated_deck'] as Map<String, dynamic>;

        final deckId = await createDeckFromGenerated(
          generatedDeck: generatedDeck,
          format: generation['format'] as String,
          prompt: generation['prompt'] as String,
        );
        createdDeckIds.add(deckId);

        final optimizeResponse = await optimizeWithPolling(
          deckId: deckId,
          archetype: generation['archetype'] as String,
        );

        expect(
          optimizeResponse.statusCode,
          anyOf(200, 422),
          reason: optimizeResponse.body,
        );

        final body = decodeJson(optimizeResponse);
        if (optimizeResponse.statusCode == 200) {
          final mode = body['mode'] as String?;
          final postAnalysis = body['post_analysis'] as Map<String, dynamic>?;
          final validation =
              postAnalysis?['validation'] as Map<String, dynamic>?;
          expect(mode, anyOf(equals('optimize'), equals('complete')));
          expect(
            body['reasoning'] != null || body['analysis'] != null,
            isTrue,
            reason: optimizeResponse.body,
          );
          expect(validation, isNotNull, reason: optimizeResponse.body);
          expect(
            validation?['verdict'],
            equals('aprovado'),
            reason: optimizeResponse.body,
          );
          expect(
            (validation?['validation_score'] as num?)?.toInt() ?? 0,
            greaterThanOrEqualTo(70),
            reason: optimizeResponse.body,
          );
        } else {
          expect(body['error'], isA<String>(), reason: optimizeResponse.body);
          expect(
            body['quality_error'] != null || body['error'] != null,
            isTrue,
            reason: optimizeResponse.body,
          );
        }
      },
      skip: skipIntegration,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
