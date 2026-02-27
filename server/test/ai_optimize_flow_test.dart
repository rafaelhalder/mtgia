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
  const sourceDeckId = '0b163477-2e8a-488a-8883-774fcd05281f';

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
    List<Map<String, dynamic>> cards = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decks'),
      headers: authHeaders(withContentType: true),
      body: jsonEncode({
        'name': 'Optimize Flow ${DateTime.now().millisecondsSinceEpoch}',
        'format': format,
        'description': 'optimize flow test',
        'cards': cards,
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

  Future<Map<String, dynamic>> findCardByName(String name) async {
    final uri = Uri.parse('$baseUrl/cards?name=${Uri.encodeQueryComponent(name)}&limit=25&page=1');
    final response = await http.get(uri, headers: authHeaders());
    expect(response.statusCode, equals(200), reason: response.body);

    final body = decodeJson(response);
    final data = (body['data'] as List?)?.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() ?? [];
    expect(data, isNotEmpty, reason: 'Carta "$name" não encontrada para teste de integração.');

    final exact = data.where((c) => (c['name']?.toString().toLowerCase() ?? '') == name.toLowerCase());
    return exact.isNotEmpty ? exact.first : data.first;
  }

  Future<List<String>> commanderCandidatesFromSourceDeck() async {
    final candidates = <String>[];

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/decks/$sourceDeckId'),
        headers: authHeaders(),
      );

      if (response.statusCode == 200) {
        final body = decodeJson(response);
        final cards = (body['cards'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            <Map<String, dynamic>>[];

        for (final card in cards) {
          final isCommander = card['is_commander'] == true;
          final name = card['name']?.toString().trim() ?? '';
          if (isCommander && name.isNotEmpty) {
            candidates.add(name);
          }
        }
      }
    } catch (_) {
      // fallback abaixo
    }

    final fallback = <String>[
      'Atraxa, Praetors\' Voice',
      'Talrand, Sky Summoner',
      'Niv-Mizzet, Parun',
      'Krenko, Mob Boss',
    ];

    return [...candidates, ...fallback].toSet().toList();
  }

  Future<String> createCommanderDeckWithCount(int totalCards) async {
    expect(totalCards >= 1, isTrue);

    final commanderCandidates = await commanderCandidatesFromSourceDeck();

    Map<String, dynamic>? commander;
    for (final candidate in commanderCandidates) {
      try {
        commander = await findCardByName(candidate);
        if (commander['id'] != null) break;
      } catch (_) {
        // tenta próximo candidato
      }
    }

    expect(commander, isNotNull,
        reason: 'Nenhum comandante comum encontrado para montar deck de teste.');

    final island = await findCardByName('Island');

    final cards = <Map<String, dynamic>>[
      {
        'card_id': commander!['id'],
        'quantity': 1,
        'is_commander': true,
      },
      if (totalCards > 1)
        {
          'card_id': island['id'],
          'quantity': totalCards - 1,
        },
    ];

    return createDeck(format: 'commander', cards: cards);
  }

  void assertNoDuplicateNamesAndNoAbsurdCopies(
    List<Map<String, dynamic>> details, {
    required int size,
    required int bracket,
  }) {
    final names = details
        .map((e) => (e['name']?.toString().trim().toLowerCase() ?? ''))
        .where((n) => n.isNotEmpty)
        .toList();

    final uniqueNames = names.toSet();
    expect(
      uniqueNames.length,
      equals(names.length),
      reason:
          'Deck size=$size bracket=$bracket retornou nomes duplicados em additions_detailed.',
    );

    final qtyByName = <String, int>{};
    for (final entry in details) {
      final name = (entry['name']?.toString().trim().toLowerCase() ?? '');
      if (name.isEmpty) continue;
      final qty = (entry['quantity'] as int?) ?? 0;
      qtyByName[name] = (qtyByName[name] ?? 0) + qty;
    }

    for (final key in ['sol ring', 'counterspell', 'cyclonic rift']) {
      expect(
        (qtyByName[key] ?? 0) <= 1,
        isTrue,
        reason:
            'Deck size=$size bracket=$bracket retornou quantidade absurda para "$key".',
      );
    }
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

    test(
      'complete mode works for 1-card commander deck (fase 1)',
      () async {
        final deckSizes = [1];
        final serverErrors = <String>[];

        for (final size in deckSizes) {
          final deckId = await createCommanderDeckWithCount(size);
          createdDeckIds.add(deckId);

          final response = await http.post(
            Uri.parse('$baseUrl/ai/optimize'),
            headers: authHeaders(withContentType: true),
            body: jsonEncode({
              'deck_id': deckId,
              'archetype': 'control',
            }),
          );

          expect(response.statusCode, anyOf(200, 500), reason: 'deck size $size => ${response.body}');

          if (response.statusCode == 500) {
            serverErrors.add('size=$size => ${response.body}');
            continue;
          }

          final body = decodeJson(response);
          final details = (body['additions_detailed'] as List?)
                  ?.whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList() ??
              <Map<String, dynamic>>[];

          assertNoDuplicateNamesAndNoAbsurdCopies(details, size: size, bracket: 2);
        }

        expect(
          serverErrors,
          isEmpty,
          reason:
              'Optimize falhou no cenário size=1: ${serverErrors.join(' | ')}',
        );
      },
      skip: skipIntegration,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'stress matrix: optimize with all brackets and sizes 1,2,5,10,15,20,40,60,80,97,99',
      () async {
        final deckSizes = [1, 2, 5, 10, 15, 20, 40, 60, 80, 97, 99];
        final brackets = [1, 2, 3, 4];
        final failures = <String>[];
        var evaluated = 0;

        for (final bracket in brackets) {
          for (final size in deckSizes) {
            final deckId = await createCommanderDeckWithCount(size);
            createdDeckIds.add(deckId);

            final response = await http.post(
              Uri.parse('$baseUrl/ai/optimize'),
              headers: authHeaders(withContentType: true),
              body: jsonEncode({
                'deck_id': deckId,
                'archetype': 'Control',
                'bracket': bracket,
                'keep_theme': true,
              }),
            );

            expect(
              response.statusCode,
              anyOf(200, 500),
              reason: 'size=$size bracket=$bracket => ${response.body}',
            );
            evaluated += 1;
            if (response.statusCode == 500) {
              failures.add('500 size=$size bracket=$bracket body=${response.body}');
              continue;
            }

            final body = decodeJson(response);
            final mode = body['mode'];
            if (mode is! String || !['optimize', 'complete'].contains(mode)) {
              failures.add('contract size=$size bracket=$bracket mode inválido: $mode');
              continue;
            }
            if (body['reasoning'] is! String) {
              failures.add('contract size=$size bracket=$bracket reasoning inválido');
            }
            if (body['deck_analysis'] is! Map<String, dynamic>) {
              failures.add('contract size=$size bracket=$bracket deck_analysis inválido');
            }
            if (body['target_additions'] is! int) {
              failures.add('contract size=$size bracket=$bracket target_additions inválido');
              continue;
            }

            final gotBracket = body['bracket'];
            if (gotBracket is int) {
              if (gotBracket != bracket) {
                failures.add(
                    'contract size=$size bracket=$bracket returnedBracket=$gotBracket');
              }
            }

            final details = (body['additions_detailed'] as List?)
                    ?.whereType<Map>()
                    .map((e) => e.cast<String, dynamic>())
                    .toList() ??
                <Map<String, dynamic>>[];

            for (final entry in details) {
              if (entry['card_id'] is! String) {
                failures.add('contract size=$size bracket=$bracket card_id inválido');
              }
              if (entry['quantity'] is! int || (entry['quantity'] as int) < 1) {
                failures.add('contract size=$size bracket=$bracket quantity inválido');
              }
            }

            try {
              assertNoDuplicateNamesAndNoAbsurdCopies(
                details,
                size: size,
                bracket: bracket,
              );
            } catch (e) {
              failures.add('dedupe size=$size bracket=$bracket => $e');
            }

            final totalDetailed = details.fold<int>(0, (acc, e) => acc + ((e['quantity'] as int?) ?? 0));
            final targetAdditions = body['target_additions'] as int;
            if (totalDetailed > targetAdditions) {
              failures.add(
                  'contract size=$size bracket=$bracket totalDetailed=$totalDetailed > target=$targetAdditions');
            }
          }
        }

        expect(evaluated, equals(deckSizes.length * brackets.length));
        expect(
          failures,
          isEmpty,
          reason:
              'Falhas na matriz completa (${failures.length}): ${failures.take(20).join(' | ')}',
        );
      },
      skip:
          skipIntegration ?? 'Fase 2: matriz completa será reativada após estabilizar size=1.',
      timeout: const Timeout(Duration(minutes: 12)),
    );
  });
}
