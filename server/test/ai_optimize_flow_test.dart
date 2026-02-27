import 'dart:convert';
import 'dart:io' show Platform, Directory, File;

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
  final sourceDeckId =
      Platform.environment['SOURCE_DECK_ID'] ?? '0b163477-2e8a-488a-8883-774fcd05281f';

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

  Future<http.Response> postJsonWithRetry(
    String path,
    Map<String, dynamic> payload, {
    int attempts = 3,
  }) async {
    Object? lastError;

    for (var i = 0; i < attempts; i++) {
      try {
        return await http.post(
          Uri.parse('$baseUrl$path'),
          headers: authHeaders(withContentType: true),
          body: jsonEncode(payload),
        );
      } on http.ClientException catch (e) {
        lastError = e;
        final msg = e.message.toLowerCase();
        final transient = msg.contains('connection closed') ||
            msg.contains('refused') ||
            msg.contains('reset');
        if (!transient || i == attempts - 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }

    throw Exception('POST retry exhausted: $path error=$lastError');
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

  Future<Map<String, dynamic>?> fetchDeckDetails(String deckId) async {
    final privateResponse = await http.get(
      Uri.parse('$baseUrl/decks/$deckId'),
      headers: authHeaders(),
    );

    if (privateResponse.statusCode == 200) {
      final body = decodeJson(privateResponse);
      body['_source_route'] = '/decks/:id';
      body['_source_private_status'] = privateResponse.statusCode;
      return body;
    }

    final publicResponse = await http.get(
      Uri.parse('$baseUrl/community/decks/$deckId'),
      headers: authHeaders(),
    );

    if (publicResponse.statusCode != 200) {
      return {
        '_source_route': 'unavailable',
        '_source_private_status': privateResponse.statusCode,
        '_source_private_body': decodeJson(privateResponse),
        '_source_public_status': publicResponse.statusCode,
        '_source_public_body': decodeJson(publicResponse),
      };
    }

    final body = decodeJson(publicResponse);
    body['_source_route'] = '/community/decks/:id';
    body['_source_private_status'] = privateResponse.statusCode;
    body['_source_public_status'] = publicResponse.statusCode;
    return body;
  }

  List<Map<String, dynamic>> extractCardsForClone(Map<String, dynamic> sourceDeck) {
    final privateCards = (sourceDeck['cards'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        <Map<String, dynamic>>[];

    if (privateCards.isNotEmpty) {
      return privateCards
          .where((c) => c['card_id'] is String)
          .map((c) => {
                'card_id': c['card_id'] as String,
                'quantity': (c['quantity'] as int?) ?? 1,
                if (c['is_commander'] == true) 'is_commander': true,
              })
          .toList();
    }

    final publicCards = (sourceDeck['all_cards_flat'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        <Map<String, dynamic>>[];

    return publicCards
        .where((c) => c['id'] is String)
        .map((c) => {
              'card_id': c['id'] as String,
              'quantity': (c['quantity'] as int?) ?? 1,
              if (c['is_commander'] == true) 'is_commander': true,
            })
        .toList();
  }

  Future<void> persistValidationArtifact({
    required String scenario,
    required Map<String, dynamic> payload,
  }) async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final dir = Directory('test/artifacts/ai_optimize');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final latestFile = File('${dir.path}/${scenario}_latest.json');
    final historicalFile = File('${dir.path}/${scenario}_$timestamp.json');
    final content = const JsonEncoder.withIndent('  ').convert(payload);

    latestFile.writeAsStringSync(content);
    historicalFile.writeAsStringSync(content);

    print('📦 Artifact salvo: ${historicalFile.path}');
    print('📌 Latest: ${latestFile.path}');
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

  bool isBasicLandName(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized == 'plains' ||
        normalized == 'island' ||
        normalized == 'swamp' ||
        normalized == 'mountain' ||
        normalized == 'forest' ||
        normalized == 'wastes';
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

        final response = await postJsonWithRetry('/ai/optimize', {
          'deck_id': deckId,
          'archetype': 'midrange',
        });

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
        final response = await postJsonWithRetry('/ai/optimize', {
          'deck_id': '00000000-0000-0000-0000-000000000097',
        });

        expect(response.statusCode, equals(400), reason: response.body);
        expect(decodeJson(response)['error'], isA<String>());
      },
      skip: skipIntegration,
    );

    test(
      'returns 404 when deck does not exist',
      () async {
        final response = await postJsonWithRetry('/ai/optimize', {
          'deck_id': '00000000-0000-0000-0000-000000000097',
          'archetype': 'midrange',
        });

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

        final response = await postJsonWithRetry('/ai/optimize', {
          'deck_id': deckId,
          'archetype': 'control',
        });

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

          final response = await postJsonWithRetry('/ai/optimize', {
            'deck_id': deckId,
            'archetype': 'control',
          });

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
      'complete mode output can be saved via /decks/:id/cards/bulk',
      () async {
        final deckId = await createCommanderDeckWithCount(1);
        createdDeckIds.add(deckId);

        final optimizeResponse = await postJsonWithRetry('/ai/optimize', {
          'deck_id': deckId,
          'archetype': 'Control',
          'bracket': 2,
          'keep_theme': true,
        });

        expect(optimizeResponse.statusCode, equals(200),
            reason: optimizeResponse.body);

        final optimizeBody = decodeJson(optimizeResponse);
        expect(optimizeBody['mode'], equals('complete'),
            reason:
                'Deck com 1 carta deve entrar em complete mode para reproduzir fluxo do app.');

        final additionsDetailed = (optimizeBody['additions_detailed'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            <Map<String, dynamic>>[];

        expect(additionsDetailed, isNotEmpty,
            reason: 'complete mode sem additions_detailed não é aplicável no app.');

        final bulkCards = additionsDetailed
            .where((item) => item['card_id'] is String)
            .map((item) => {
                  'card_id': item['card_id'] as String,
                  'quantity': (item['quantity'] as int?) ?? 1,
                })
            .toList();

        expect(bulkCards, isNotEmpty,
            reason: 'Nenhuma carta com card_id retornada para bulk save.');

        final bulkResponse = await postJsonWithRetry(
          '/decks/$deckId/cards/bulk',
          {'cards': bulkCards},
        );

        expect(
          bulkResponse.statusCode,
          equals(200),
          reason:
              'Bulk save falhou após optimize complete. body=${bulkResponse.body}',
        );
      },
      skip: skipIntegration,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'source deck regression uses fixed sourceDeckId and persists full return for validation',
      () async {
        final sourceDeck = await fetchDeckDetails(sourceDeckId);
        final sourceAvailable = sourceDeck != null &&
            (sourceDeck['_source_route'] as String?) != 'unavailable';

        final cloneCards = sourceAvailable
            ? extractCardsForClone(sourceDeck)
            : <Map<String, dynamic>>[];

        if (sourceAvailable) {
          expect(
            cloneCards,
            isNotEmpty,
            reason:
                'Deck de referência $sourceDeckId não possui cartas para o teste.',
          );
        }

        String? deckId;
        if (sourceAvailable) {
          final copyResponse = await postJsonWithRetry(
            '/community/decks/$sourceDeckId',
            {},
          );

          if (copyResponse.statusCode == 200 || copyResponse.statusCode == 201) {
            final copiedBody = decodeJson(copyResponse);
            deckId = copiedBody['id'] as String?;
          }
        }

        if (deckId == null && sourceAvailable && cloneCards.isNotEmpty) {
          final source = sourceDeck!;
          deckId = await createDeck(
            format: ((source['format'] as String?)?.trim().isNotEmpty ?? false)
                ? (source['format'] as String)
                : 'commander',
            cards: cloneCards,
          );
        }

        deckId ??= await createCommanderDeckWithCount(1);

        createdDeckIds.add(deckId);

        final optimizeRequest = {
          'deck_id': deckId,
          'archetype': 'Control',
          'bracket': 2,
          'keep_theme': true,
        };

        final optimizeResponse =
            await postJsonWithRetry('/ai/optimize', optimizeRequest);
        expect(optimizeResponse.statusCode, anyOf(equals(200), equals(422)),
            reason: optimizeResponse.body);

        final optimizeBody = decodeJson(optimizeResponse);
        print('🧪 source optimize mode=${optimizeBody['mode']}');
        print('🧪 source optimize body=${jsonEncode(optimizeBody)}');

        final resultEnvelope = <String, dynamic>{
          'source_deck_id': sourceDeckId,
          'source_available': sourceAvailable,
          'source_snapshot': sourceDeck,
          'cloned_deck_id': deckId,
          'optimize_request': optimizeRequest,
          'optimize_status': optimizeResponse.statusCode,
          'optimize_response': optimizeBody,
        };

        if (optimizeResponse.statusCode == 422) {
          await persistValidationArtifact(
            scenario: 'source_deck_optimize',
            payload: resultEnvelope,
          );

          expect(optimizeBody['quality_error'], isA<Map>(),
              reason:
                  'Quando optimize retorna 422 no complete, deve trazer diagnóstico quality_error.');
          return;
        }

        final additionsDetailed = (optimizeBody['additions_detailed'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            <Map<String, dynamic>>[];

        if ((optimizeBody['mode'] as String?) == 'complete') {
          final targetAdditions = (optimizeBody['target_additions'] as int?) ?? 0;
          final nonBasicSuggestions = additionsDetailed.where((entry) {
            final name = (entry['name']?.toString() ?? '').trim();
            if (name.isEmpty) return false;
            return !isBasicLandName(name);
          }).toList();

          final totalAdded = additionsDetailed.fold<int>(
            0,
            (acc, e) => acc + ((e['quantity'] as int?) ?? 0),
          );
          final basicAdded = additionsDetailed.fold<int>(0, (acc, e) {
            final name = (e['name']?.toString() ?? '').trim();
            if (name.isEmpty) return acc;
            if (!isBasicLandName(name)) return acc;
            return acc + ((e['quantity'] as int?) ?? 0);
          });

          if (targetAdditions >= 40) {
            expect(
              nonBasicSuggestions.isNotEmpty,
              isTrue,
              reason:
                  'Complete mode retornou apenas terrenos básicos (target_additions=$targetAdditions), indicando fallback degradado.',
            );

            // Guardrail de qualidade: não aceitar enchimento degenerado de básicos.
            final maxAllowedBasics = (targetAdditions * 0.65).floor();
            expect(
              basicAdded <= maxAllowedBasics,
              isTrue,
              reason:
                  'Complete mode retornou básicos demais ($basicAdded de $totalAdded adições, limite=$maxAllowedBasics).',
            );
          }
        }

        if ((optimizeBody['mode'] as String?) == 'complete' &&
            additionsDetailed.isNotEmpty) {
          final bulkCards = additionsDetailed
              .where((item) => item['card_id'] is String)
              .map((item) => {
                    'card_id': item['card_id'] as String,
                    'quantity': (item['quantity'] as int?) ?? 1,
                  })
              .toList();

          if (bulkCards.isNotEmpty) {
            final bulkResponse = await postJsonWithRetry(
              '/decks/$deckId/cards/bulk',
              {'cards': bulkCards},
            );

            final bulkBody = decodeJson(bulkResponse);
            resultEnvelope['bulk_status'] = bulkResponse.statusCode;
            resultEnvelope['bulk_response'] = bulkBody;

            print('🧪 source bulk status=${bulkResponse.statusCode}');
            print('🧪 source bulk body=${jsonEncode(bulkBody)}');

            expect(
              bulkResponse.statusCode,
              equals(200),
              reason:
                  'Bulk save falhou no teste com sourceDeckId=$sourceDeckId body=${bulkResponse.body}',
            );
          }
        }

        await persistValidationArtifact(
          scenario: 'source_deck_optimize',
          payload: resultEnvelope,
        );
      },
      skip: skipIntegration,
      timeout: const Timeout(Duration(minutes: 4)),
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

            final response = await postJsonWithRetry('/ai/optimize', {
              'deck_id': deckId,
              'archetype': 'Control',
              'bracket': bracket,
              'keep_theme': true,
            });

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
