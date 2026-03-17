#!/usr/bin/env dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../lib/ai/optimization_validator.dart';
import '../lib/database.dart';
import '../routes/ai/optimize/index.dart' as optimize_route;

const _defaultApiBaseUrl = 'http://127.0.0.1:8080';
const _artifactDirPath = 'test/artifacts/optimization_validation_three_decks';
const _summaryJsonPath =
    'test/artifacts/optimization_validation_three_decks/latest_summary.json';
const _summaryMdPath = '../RELATORIO_OTIMIZACAO_3_DECKS_2026-03-16.md';

class SourceDeckCandidate {
  SourceDeckCandidate({
    required this.deckId,
    required this.deckName,
    required this.commanderName,
    required this.commanderCardId,
    required this.commanderColors,
    required this.sourceArchetype,
    required this.bracket,
    required this.cards,
  });

  final String deckId;
  final String deckName;
  final String commanderName;
  final String commanderCardId;
  final List<String> commanderColors;
  final String? sourceArchetype;
  final int? bracket;
  final List<Map<String, dynamic>> cards;

  String get resolvedArchetype {
    final detected = _normalizeArchetype(sourceArchetype);
    if (detected != null) return detected;
    final analysis =
        optimize_route.DeckArchetypeAnalyzer(cards, commanderColors)
            .generateAnalysis();
    final byAnalysis =
        _normalizeArchetype(analysis['detected_archetype']?.toString());
    return byAnalysis ?? 'midrange';
  }

  int get totalCards => cards.fold<int>(
      0, (sum, card) => sum + ((card['quantity'] as int?) ?? 0));
}

class DeckRunResult {
  DeckRunResult({
    required this.resultKind,
    required this.commanderName,
    required this.sourceDeckId,
    required this.sourceDeckName,
    required this.cloneDeckId,
    required this.archetype,
    required this.bracket,
    required this.optimizeStatus,
    required this.optimizeMode,
    required this.savedArtifactPath,
    required this.savedDeckValid,
    required this.localValidationScore,
    required this.localValidationVerdict,
    required this.responseValidationScore,
    required this.responseValidationVerdict,
    required this.beforeAverageCmc,
    required this.afterAverageCmc,
    required this.beforeManaAssessment,
    required this.afterManaAssessment,
    required this.beforeInteraction,
    required this.afterInteraction,
    required this.beforeConsistency,
    required this.afterConsistency,
    required this.expectedChecks,
    required this.failedChecks,
    required this.warnings,
    required this.optimizeResponse,
  });

  final String resultKind;
  final String commanderName;
  final String sourceDeckId;
  final String sourceDeckName;
  final String cloneDeckId;
  final String archetype;
  final int bracket;
  final int optimizeStatus;
  final String optimizeMode;
  final String savedArtifactPath;
  final bool savedDeckValid;
  final int localValidationScore;
  final String localValidationVerdict;
  final int? responseValidationScore;
  final String? responseValidationVerdict;
  final double beforeAverageCmc;
  final double afterAverageCmc;
  final String beforeManaAssessment;
  final String afterManaAssessment;
  final int beforeInteraction;
  final int afterInteraction;
  final double beforeConsistency;
  final double afterConsistency;
  final List<String> expectedChecks;
  final List<String> failedChecks;
  final List<String> warnings;
  final Map<String, dynamic> optimizeResponse;

  bool get passed => failedChecks.isEmpty;

  Map<String, dynamic> toJson() => {
        'result_kind': resultKind,
        'commander_name': commanderName,
        'source_deck_id': sourceDeckId,
        'source_deck_name': sourceDeckName,
        'clone_deck_id': cloneDeckId,
        'archetype': archetype,
        'bracket': bracket,
        'optimize_status': optimizeStatus,
        'optimize_mode': optimizeMode,
        'saved_artifact_path': savedArtifactPath,
        'saved_deck_valid': savedDeckValid,
        'local_validation_score': localValidationScore,
        'local_validation_verdict': localValidationVerdict,
        'response_validation_score': responseValidationScore,
        'response_validation_verdict': responseValidationVerdict,
        'before_average_cmc': beforeAverageCmc,
        'after_average_cmc': afterAverageCmc,
        'before_mana_assessment': beforeManaAssessment,
        'after_mana_assessment': afterManaAssessment,
        'before_interaction': beforeInteraction,
        'after_interaction': afterInteraction,
        'before_consistency': beforeConsistency,
        'after_consistency': afterConsistency,
        'expected_checks': expectedChecks,
        'failed_checks': failedChecks,
        'warnings': warnings,
        'passed': passed,
      };
}

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final apiBaseUrl = env['TEST_API_BASE_URL'] ?? _defaultApiBaseUrl;

  final artifactsDir = Directory(_artifactDirPath);
  if (!artifactsDir.existsSync()) {
    artifactsDir.createSync(recursive: true);
  }

  final serverOk = await _ensureServerIsReachable(apiBaseUrl);
  if (!serverOk) {
    stderr.writeln('Servidor inacessivel em $apiBaseUrl.');
    exitCode = 1;
    return;
  }

  final db = Database();
  await db.connect();
  if (!db.isConnected) {
    stderr.writeln('Falha ao conectar ao banco.');
    exitCode = 1;
    return;
  }

  final pool = db.connection;

  try {
    final token = await _getOrCreateAuthToken(apiBaseUrl);
    final candidates = await _loadSourceCandidates(pool);
    final selected = _selectThreeCandidates(candidates);

    if (selected.length < 3) {
      stderr.writeln(
        'Nao foi possivel selecionar 3 decks Commander validos e distintos. Encontrados: ${selected.length}',
      );
      exitCode = 1;
      return;
    }

    final results = <DeckRunResult>[];
    final runStartedAt = DateTime.now().toIso8601String();

    for (final candidate in selected) {
      print('');
      print(
          '=== ${candidate.commanderName} | ${candidate.resolvedArchetype} ===');
      final result = await _runOptimizationForDeck(
        apiBaseUrl: apiBaseUrl,
        token: token,
        candidate: candidate,
      );
      results.add(result);
      print(
        '${result.passed ? 'PASSOU' : 'FALHOU'} | '
        '${result.resultKind} | '
        'score local ${result.localValidationScore}/100 | '
        'veredito ${result.localValidationVerdict}',
      );
    }

    final summary = {
      'generated_at': DateTime.now().toIso8601String(),
      'run_started_at': runStartedAt,
      'api_base_url': apiBaseUrl,
      'artifact_dir': _artifactDirPath,
      'total': results.length,
      'accepted_optimizations':
          results.where((r) => r.resultKind == 'accepted_optimization').length,
      'protected_rejections':
          results.where((r) => r.resultKind == 'protected_rejection').length,
      'passed': results.where((r) => r.passed).length,
      'failed': results.where((r) => !r.passed).length,
      'results': results.map((r) => r.toJson()).toList(),
    };

    await File(_summaryJsonPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary),
    );
    await File(_summaryMdPath).writeAsString(_buildMarkdownReport(summary));

    print('');
    print('Resumo salvo em $_summaryJsonPath');
    print('Relatorio salvo em $_summaryMdPath');

    if (results.any((r) => !r.passed)) {
      exitCode = 1;
    }
  } finally {
    await db.close();
  }
}

Future<bool> _ensureServerIsReachable(String apiBaseUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$apiBaseUrl/health'))
        .timeout(const Duration(seconds: 5));
    return response.statusCode < 500;
  } catch (_) {
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(const {'email': 'healthcheck@example.com'}),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 400 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}

Future<String> _getOrCreateAuthToken(String apiBaseUrl) async {
  const email = 'optimization.validation.bot@example.com';
  const password = 'OptimizationPass123!';
  const username = 'optimization_validation_bot';

  Future<http.Response> login() {
    return http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
  }

  var response = await login();
  if (response.statusCode != 200) {
    final register = await http.post(
      Uri.parse('$apiBaseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'username': username,
      }),
    );

    if (register.statusCode != 201 && register.statusCode != 400) {
      throw Exception('Falha ao registrar usuario de teste: ${register.body}');
    }

    response = await login();
  }

  if (response.statusCode != 200) {
    throw Exception('Falha ao autenticar usuario de teste: ${response.body}');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final token = decoded['token']?.toString();
  if (token == null || token.isEmpty) {
    throw Exception('Token ausente na autenticacao.');
  }
  return token;
}

Future<List<SourceDeckCandidate>> _loadSourceCandidates(Pool pool) async {
  final decksResult = await pool.execute(
    Sql.named('''
      SELECT
        d.id::text,
        d.name,
        NULLIF(TRIM(d.archetype), '') AS archetype,
        d.bracket::int,
        c.id::text AS commander_card_id,
        c.name AS commander_name,
        COALESCE(c.colors, ARRAY[]::text[]) AS commander_colors
      FROM decks d
      JOIN (
        SELECT deck_id, SUM(quantity)::int AS total_cards
        FROM deck_cards
        GROUP BY deck_id
      ) stats ON stats.deck_id = d.id
      JOIN LATERAL (
        SELECT dc.card_id
        FROM deck_cards dc
        WHERE dc.deck_id = d.id AND dc.is_commander = TRUE
        ORDER BY dc.card_id
        LIMIT 1
      ) cmd ON TRUE
      JOIN cards c ON c.id = cmd.card_id
      WHERE d.deleted_at IS NULL
        AND LOWER(d.format) = 'commander'
        AND stats.total_cards = 100
        AND d.name NOT LIKE 'Optimization Validation - %'
      ORDER BY d.created_at DESC NULLS LAST
      LIMIT 120
    '''),
  );

  final candidates = <SourceDeckCandidate>[];

  for (final row in decksResult) {
    final deckId = row[0] as String;
    final deckName = row[1] as String? ?? 'Commander Deck';
    final archetype = row[2] as String?;
    final bracket = row[3] as int?;
    final commanderCardId = row[4] as String;
    final commanderName = row[5] as String;
    final commanderColors =
        (row[6] as List?)?.cast<String>() ?? const <String>[];

    final cards = await _loadDeckCards(pool, deckId);
    if (cards.isEmpty) continue;

    final total = cards.fold<int>(
      0,
      (sum, card) => sum + ((card['quantity'] as int?) ?? 0),
    );
    final hasCommander = cards.any((card) => card['is_commander'] == true);
    if (total != 100 || !hasCommander) continue;

    candidates.add(
      SourceDeckCandidate(
        deckId: deckId,
        deckName: deckName,
        commanderName: commanderName,
        commanderCardId: commanderCardId,
        commanderColors: commanderColors,
        sourceArchetype: archetype,
        bracket: bracket,
        cards: cards,
      ),
    );
  }

  return candidates;
}

Future<List<Map<String, dynamic>>> _loadDeckCards(
    Pool pool, String deckId) async {
  final result = await pool.execute(
    Sql.named('''
      SELECT
        dc.card_id::text,
        dc.quantity::int,
        dc.is_commander,
        c.name,
        c.type_line,
        COALESCE(c.mana_cost, '') AS mana_cost,
        COALESCE(c.colors, ARRAY[]::text[]) AS colors,
        COALESCE(
          (SELECT COUNT(*) FROM regexp_matches(COALESCE(c.mana_cost, ''), '\\{([^}]+)\\}', 'g') AS m(m)),
          0
        )::double precision AS cmc,
        COALESCE(c.oracle_text, '') AS oracle_text
      FROM deck_cards dc
      JOIN cards c ON c.id = dc.card_id
      WHERE dc.deck_id = @deckId
      ORDER BY dc.is_commander DESC, c.name ASC
    '''),
    parameters: {'deckId': deckId},
  );

  return result
      .map(
        (row) => <String, dynamic>{
          'card_id': row[0] as String,
          'quantity': row[1] as int,
          'is_commander': row[2] as bool? ?? false,
          'name': row[3] as String? ?? '',
          'type_line': row[4] as String? ?? '',
          'mana_cost': row[5] as String? ?? '',
          'colors': (row[6] as List?)?.cast<String>() ?? const <String>[],
          'cmc': (row[7] as num?)?.toDouble() ?? 0.0,
          'oracle_text': row[8] as String? ?? '',
        },
      )
      .toList();
}

List<SourceDeckCandidate> _selectThreeCandidates(
  List<SourceDeckCandidate> candidates,
) {
  final selected = <SourceDeckCandidate>[];
  final usedCommanders = <String>{};

  void tryPickByArchetype(String archetype) {
    for (final candidate in candidates) {
      final commanderKey = candidate.commanderName.toLowerCase();
      if (usedCommanders.contains(commanderKey)) continue;
      if (candidate.resolvedArchetype != archetype) continue;
      selected.add(candidate);
      usedCommanders.add(commanderKey);
      return;
    }
  }

  for (final archetype in const ['aggro', 'control', 'midrange']) {
    tryPickByArchetype(archetype);
  }

  for (final candidate in candidates) {
    if (selected.length >= 3) break;
    final commanderKey = candidate.commanderName.toLowerCase();
    if (usedCommanders.contains(commanderKey)) continue;
    selected.add(candidate);
    usedCommanders.add(commanderKey);
  }

  return selected.take(3).toList();
}

Future<DeckRunResult> _runOptimizationForDeck({
  required String apiBaseUrl,
  required String token,
  required SourceDeckCandidate candidate,
}) async {
  final cloneDeckId = await _createDeckClone(
    apiBaseUrl: apiBaseUrl,
    token: token,
    candidate: candidate,
  );

  final optimizePayload = {
    'deck_id': cloneDeckId,
    'archetype': candidate.resolvedArchetype,
    'bracket': candidate.bracket ?? 2,
    'keep_theme': true,
  };

  final optimizeResponse = await _optimizeWithPolling(
    apiBaseUrl: apiBaseUrl,
    token: token,
    payload: optimizePayload,
  );

  final optimizeBody = _decodeJson(optimizeResponse);
  final artifactPath = await _writeDeckArtifact(
    commanderName: candidate.commanderName,
    payload: {
      'source_deck_id': candidate.deckId,
      'source_deck_name': candidate.deckName,
      'clone_deck_id': cloneDeckId,
      'optimize_request': optimizePayload,
      'optimize_status': optimizeResponse.statusCode,
      'optimize_response': optimizeBody,
    },
  );

  if (optimizeResponse.statusCode != 200) {
    final qualityError = optimizeBody['quality_error'] as Map<String, dynamic>?;
    final qualityCode = qualityError?['code']?.toString() ?? '';
    final protectedRejection = optimizeResponse.statusCode == 422 &&
        {
          'OPTIMIZE_NO_SAFE_SWAPS',
          'OPTIMIZE_QUALITY_REJECTED',
          'OPTIMIZE_NO_ACTIONABLE_SWAPS',
        }.contains(qualityCode);

    return DeckRunResult(
      resultKind: protectedRejection ? 'protected_rejection' : 'failure',
      commanderName: candidate.commanderName,
      sourceDeckId: candidate.deckId,
      sourceDeckName: candidate.deckName,
      cloneDeckId: cloneDeckId,
      archetype: candidate.resolvedArchetype,
      bracket: candidate.bracket ?? 2,
      optimizeStatus: optimizeResponse.statusCode,
      optimizeMode: optimizeBody['mode']?.toString() ?? 'unknown',
      savedArtifactPath: artifactPath,
      savedDeckValid: protectedRejection,
      localValidationScore: 0,
      localValidationVerdict:
          protectedRejection ? 'quality_rejected' : 'reprovado',
      responseValidationScore: null,
      responseValidationVerdict: null,
      beforeAverageCmc: 0,
      afterAverageCmc: 0,
      beforeManaAssessment: '',
      afterManaAssessment: '',
      beforeInteraction: 0,
      afterInteraction: 0,
      beforeConsistency: 0,
      afterConsistency: 0,
      expectedChecks: protectedRejection
          ? const [
              'o backend recusou a otimizacao insegura em vez de retornar sucesso ruim'
            ]
          : const [],
      failedChecks: protectedRejection
          ? const []
          : ['POST /ai/optimize retornou ${optimizeResponse.statusCode}'],
      warnings: [
        if (protectedRejection)
          'Rejeicao protegida pelo gate de qualidade: ${qualityError?['message'] ?? qualityCode}',
        ...((qualityError?['reasons'] as List?)?.map((item) => '$item') ??
            const Iterable<String>.empty()),
        _extractMessage(optimizeBody),
      ],
      optimizeResponse: optimizeBody,
    );
  }

  final optimizedCards = _applyRecommendations(
    originalCards: candidate.cards,
    responseBody: optimizeBody,
  );

  final putResponse = await http.put(
    Uri.parse('$apiBaseUrl/decks/$cloneDeckId'),
    headers: _jsonHeaders(token),
    body: jsonEncode({
      'cards': optimizedCards
          .map(
            (card) => {
              'card_id': card['card_id'],
              'quantity': card['quantity'],
              if (card['is_commander'] == true) 'is_commander': true,
            },
          )
          .toList(),
    }),
  );

  final validateResponse = await http.post(
    Uri.parse('$apiBaseUrl/decks/$cloneDeckId/validate'),
    headers: _authHeaders(token),
  );

  final preAnalysis = optimize_route.DeckArchetypeAnalyzer(
          candidate.cards, candidate.commanderColors)
      .generateAnalysis();
  final postAnalysis = optimize_route.DeckArchetypeAnalyzer(
          optimizedCards, candidate.commanderColors)
      .generateAnalysis();

  final validator = OptimizationValidator();
  final localValidation = await validator.validate(
    originalDeck: candidate.cards,
    optimizedDeck: optimizedCards,
    removals: _extractNames(optimizeBody['removals']),
    additions: _extractNames(optimizeBody['additions']),
    commanders: [candidate.commanderName],
    archetype: candidate.resolvedArchetype,
  );

  final responseValidation = (optimizeBody['post_analysis']
      as Map<String, dynamic>?)?['validation'] as Map<String, dynamic>?;

  final expectedChecks = <String>[];
  final failedChecks = <String>[];

  final finalCardCount = optimizedCards.fold<int>(
    0,
    (sum, card) => sum + ((card['quantity'] as int?) ?? 0),
  );
  final commanderCount = optimizedCards
      .where((card) => card['is_commander'] == true)
      .fold<int>(0, (sum, card) => sum + ((card['quantity'] as int?) ?? 0));
  final beforeAverageCmc = _parseDouble(preAnalysis['average_cmc']);
  final afterAverageCmc = _parseDouble(postAnalysis['average_cmc']);
  final beforeManaAssessment =
      preAnalysis['mana_base_assessment']?.toString() ?? '';
  final afterManaAssessment =
      postAnalysis['mana_base_assessment']?.toString() ?? '';
  final beforeInteraction = _countInteraction(preAnalysis);
  final afterInteraction = _countInteraction(postAnalysis);
  final beforeConsistency = localValidation.monteCarlo.before.consistencyScore;
  final afterConsistency = localValidation.monteCarlo.after.consistencyScore;

  void expectCheck(String description, bool passed) {
    expectedChecks.add(description);
    if (!passed) failedChecks.add(description);
  }

  expectCheck('deck final mantem 100 cartas', finalCardCount == 100);
  expectCheck('deck final mantem exatamente 1 comandante', commanderCount == 1);
  expectCheck('PUT /decks/:id para salvar resultado retornou sucesso',
      putResponse.statusCode == 200);
  expectCheck('POST /decks/:id/validate aprovou o deck salvo',
      validateResponse.statusCode == 200);
  expectCheck('Validation local fechou como aprovado',
      localValidation.verdict == 'aprovado');
  expectCheck('Validation local score >= 70', localValidation.score >= 70);
  expectCheck(
    'Validation retornada pela rota fechou como aprovado',
    (responseValidation?['verdict']?.toString() ?? '') == 'aprovado',
  );
  expectCheck(
    'Validation retornada pela rota score >= 70',
    ((responseValidation?['validation_score'] as num?)?.toInt() ?? 0) >= 70,
  );
  expectCheck(
    'Consistencia nao piorou',
    afterConsistency >= beforeConsistency,
  );

  switch (candidate.resolvedArchetype) {
    case 'aggro':
      expectCheck('Aggro reduz ou mantem a curva media',
          afterAverageCmc <= beforeAverageCmc);
      expectCheck(
        'Aggro melhora turn2 play rate',
        localValidation.monteCarlo.after.turn2PlayRate >=
            localValidation.monteCarlo.before.turn2PlayRate,
      );
      break;
    case 'control':
      expectCheck(
        'Control mantem ou melhora interacao',
        afterInteraction >= beforeInteraction,
      );
      expectCheck(
        'Control nao piora a base de mana',
        !_isManaAssessmentWorse(beforeManaAssessment, afterManaAssessment),
      );
      break;
    case 'midrange':
      expectCheck('Midrange reduz ou mantem a curva media',
          afterAverageCmc <= beforeAverageCmc);
      expectCheck(
        'Midrange preserva ramp/removal',
        (localValidation.functional.roleDelta['ramp'] ?? 0) >= 0 &&
            (localValidation.functional.roleDelta['removal'] ?? 0) >= 0,
      );
      break;
    default:
      expectCheck(
        'Arquitetura generica mantem score local >= 45',
        localValidation.score >= 45,
      );
      break;
  }

  return DeckRunResult(
    resultKind: 'accepted_optimization',
    commanderName: candidate.commanderName,
    sourceDeckId: candidate.deckId,
    sourceDeckName: candidate.deckName,
    cloneDeckId: cloneDeckId,
    archetype: candidate.resolvedArchetype,
    bracket: candidate.bracket ?? 2,
    optimizeStatus: optimizeResponse.statusCode,
    optimizeMode: optimizeBody['mode']?.toString() ?? 'optimize',
    savedArtifactPath: artifactPath,
    savedDeckValid: validateResponse.statusCode == 200,
    localValidationScore: localValidation.score,
    localValidationVerdict: localValidation.verdict,
    responseValidationScore: responseValidation?['validation_score'] as int?,
    responseValidationVerdict: responseValidation?['verdict']?.toString(),
    beforeAverageCmc: beforeAverageCmc,
    afterAverageCmc: afterAverageCmc,
    beforeManaAssessment: beforeManaAssessment,
    afterManaAssessment: afterManaAssessment,
    beforeInteraction: beforeInteraction,
    afterInteraction: afterInteraction,
    beforeConsistency: beforeConsistency.toDouble(),
    afterConsistency: afterConsistency.toDouble(),
    expectedChecks: expectedChecks,
    failedChecks: failedChecks,
    warnings: [
      ...localValidation.warnings,
      ...((optimizeBody['validation_warnings'] as List?)?.map((e) => '$e') ??
          const Iterable<String>.empty()),
      if (putResponse.statusCode != 200)
        'Falha ao salvar deck: ${putResponse.body}',
      if (validateResponse.statusCode != 200)
        'Falha no validate: ${validateResponse.body}',
    ],
    optimizeResponse: optimizeBody,
  );
}

Future<String> _createDeckClone({
  required String apiBaseUrl,
  required String token,
  required SourceDeckCandidate candidate,
}) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/decks'),
    headers: _jsonHeaders(token),
    body: jsonEncode({
      'name':
          'Optimization Validation - ${candidate.commanderName} - ${DateTime.now().millisecondsSinceEpoch}',
      'format': 'commander',
      'description': 'Deck clone para validacao real de optimize',
      'is_public': false,
      'cards': candidate.cards
          .map(
            (card) => {
              'card_id': card['card_id'],
              'quantity': card['quantity'],
              if (card['is_commander'] == true) 'is_commander': true,
            },
          )
          .toList(),
    }),
  );

  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('Falha ao criar clone do deck: ${response.body}');
  }

  final body = _decodeJson(response);
  final deckId =
      body['id']?.toString() ?? (body['deck']?['id']?.toString() ?? '');
  if (deckId.isEmpty) {
    throw Exception('Resposta sem id do deck clonado: ${response.body}');
  }
  return deckId;
}

Future<http.Response> _optimizeWithPolling({
  required String apiBaseUrl,
  required String token,
  required Map<String, dynamic> payload,
}) async {
  final response = await http.post(
    Uri.parse('$apiBaseUrl/ai/optimize'),
    headers: _jsonHeaders(token),
    body: jsonEncode(payload),
  );

  if (response.statusCode != 202) {
    return response;
  }

  final body = _decodeJson(response);
  final jobId = body['job_id']?.toString();
  if (jobId == null || jobId.isEmpty) {
    throw Exception('Resposta 202 sem job_id: ${response.body}');
  }

  for (var poll = 0; poll < 150; poll++) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final pollResponse = await http.get(
      Uri.parse('$apiBaseUrl/ai/optimize/jobs/$jobId'),
      headers: _authHeaders(token),
    );
    final pollBody = _decodeJson(pollResponse);
    final status = pollBody['status']?.toString();

    if (status == 'completed') {
      return http.Response(
        jsonEncode(pollBody['result'] ?? <String, dynamic>{}),
        200,
      );
    }
    if (status == 'failed') {
      return http.Response(jsonEncode(pollBody), 422);
    }
  }

  return http.Response(
    jsonEncode({'error': 'Polling timeout para optimize job'}),
    500,
  );
}

Map<String, dynamic> _decodeJson(http.Response response) {
  final body = response.body.trim();
  if (body.isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  return {'value': decoded};
}

Future<String> _writeDeckArtifact({
  required String commanderName,
  required Map<String, dynamic> payload,
}) async {
  final slug = _slugify(commanderName);
  final path = '$_artifactDirPath/$slug.json';
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  return path;
}

List<Map<String, dynamic>> _applyRecommendations({
  required List<Map<String, dynamic>> originalCards,
  required Map<String, dynamic> responseBody,
}) {
  final next =
      originalCards.map((card) => Map<String, dynamic>.from(card)).toList();

  final removalsDetailed =
      (responseBody['removals_detailed'] as List?)?.whereType<Map>().toList() ??
          const <Map>[];

  final additionsDetailed = (responseBody['additions_detailed'] as List?)
          ?.whereType<Map>()
          .toList() ??
      const <Map>[];

  final removalCounts = <String, int>{};
  for (final raw in removalsDetailed) {
    final card = raw.cast<String, dynamic>();
    final name = card['name']?.toString().trim().toLowerCase();
    if (name == null || name.isEmpty) continue;
    final qty = (card['quantity'] as int?) ?? 1;
    removalCounts[name] = (removalCounts[name] ?? 0) + qty;
  }

  for (final entry in removalCounts.entries) {
    var remaining = entry.value;
    for (var i = next.length - 1; i >= 0 && remaining > 0; i--) {
      final cardName = (next[i]['name']?.toString().trim().toLowerCase() ?? '');
      if (cardName != entry.key) continue;
      if (next[i]['is_commander'] == true) continue;

      final qty = (next[i]['quantity'] as int?) ?? 0;
      if (qty <= remaining) {
        next.removeAt(i);
        remaining -= qty;
      } else {
        next[i]['quantity'] = qty - remaining;
        remaining = 0;
      }
    }
  }

  for (final raw in additionsDetailed) {
    final addition = raw.cast<String, dynamic>();
    final cardId = addition['card_id']?.toString();
    if (cardId == null || cardId.isEmpty) continue;

    final qty = (addition['quantity'] as int?) ?? 1;
    final existingIndex = next.indexWhere((card) => card['card_id'] == cardId);

    if (existingIndex >= 0) {
      next[existingIndex]['quantity'] =
          ((next[existingIndex]['quantity'] as int?) ?? 0) + qty;
      continue;
    }

    next.add({
      'card_id': cardId,
      'quantity': qty,
      'is_commander': false,
      'name': addition['name']?.toString() ?? '',
      'type_line': '',
      'mana_cost': '',
      'colors': const <String>[],
      'cmc': 0.0,
      'oracle_text': '',
    });
  }

  return next;
}

List<String> _extractNames(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList();
}

double _parseDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0.0;
}

int _countInteraction(Map<String, dynamic> analysis) {
  final types = (analysis['type_distribution'] as Map<String, dynamic>?) ?? {};
  return ((types['instants'] as int?) ?? 0) +
      ((types['sorceries'] as int?) ?? 0);
}

String? _normalizeArchetype(String? archetype) {
  final value = archetype?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  if (const {'aggro', 'control', 'midrange'}.contains(value)) return value;
  return switch (value) {
    'tempo' || 'spellslinger' => 'control',
    'stax' || 'combo' || 'aristocrats' || 'tribal' || 'voltron' => 'midrange',
    _ => null,
  };
}

bool _isManaAssessmentWorse(String before, String after) {
  final beforeHasIssue = before.toLowerCase().contains('falta mana');
  final afterHasIssue = after.toLowerCase().contains('falta mana');
  return !beforeHasIssue && afterHasIssue;
}

String _slugify(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'deck' : normalized;
}

Map<String, String> _authHeaders(String token) => {
      'Authorization': 'Bearer $token',
    };

Map<String, String> _jsonHeaders(String token) => {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

String _extractMessage(Map<String, dynamic> body) {
  return body['error']?.toString() ??
      body['message']?.toString() ??
      body.toString();
}

String _buildMarkdownReport(Map<String, dynamic> summary) {
  final results =
      (summary['results'] as List).whereType<Map<String, dynamic>>().toList();
  String formatValidation(Map<String, dynamic> result, bool isLocal) {
    final resultKind = result['result_kind']?.toString() ?? '';
    if (resultKind == 'protected_rejection') {
      return isLocal ? 'n/d - quality_rejected' : 'n/d';
    }

    final scoreKey =
        isLocal ? 'local_validation_score' : 'response_validation_score';
    final verdictKey =
        isLocal ? 'local_validation_verdict' : 'response_validation_verdict';
    final score = result[scoreKey];
    final verdict = result[verdictKey];
    if (score == null || verdict == null) return 'n/d';
    return '$score/100 - $verdict';
  }

  String formatPair(
      Map<String, dynamic> result, String beforeKey, String afterKey) {
    final resultKind = result['result_kind']?.toString() ?? '';
    if (resultKind == 'protected_rejection') return 'n/d';
    return '${result[beforeKey]} -> ${result[afterKey]}';
  }

  final buffer = StringBuffer()
    ..writeln('# Relatorio de Otimizacao Real - 3 Decks Commander')
    ..writeln()
    ..writeln('- Gerado em: `${summary['generated_at']}`')
    ..writeln('- API: `${summary['api_base_url']}`')
    ..writeln('- Artefatos: `${summary['artifact_dir']}`')
    ..writeln('- Total: `${summary['total']}`')
    ..writeln('- Otimizacoes aceitas: `${summary['accepted_optimizations']}`')
    ..writeln('- Rejeicoes protegidas: `${summary['protected_rejections']}`')
    ..writeln('- Passaram: `${summary['passed']}`')
    ..writeln('- Falharam: `${summary['failed']}`')
    ..writeln()
    ..writeln('## Resultado por deck')
    ..writeln();

  for (final result in results) {
    buffer
      ..writeln('### ${result['commander_name']}')
      ..writeln()
      ..writeln('- Source deck: `${result['source_deck_id']}`')
      ..writeln('- Clone deck: `${result['clone_deck_id']}`')
      ..writeln('- Tipo de resultado: `${result['result_kind']}`')
      ..writeln('- Archetype usado: `${result['archetype']}`')
      ..writeln('- Optimize status: `${result['optimize_status']}`')
      ..writeln('- Deck salvo valido: `${result['saved_deck_valid']}`')
      ..writeln('- Validation local: `${formatValidation(result, true)}`')
      ..writeln('- Validation da rota: `${formatValidation(result, false)}`')
      ..writeln(
          '- CMC medio: `${formatPair(result, 'before_average_cmc', 'after_average_cmc')}`')
      ..writeln(
          '- Interacao: `${formatPair(result, 'before_interaction', 'after_interaction')}`')
      ..writeln(
          '- Consistencia: `${formatPair(result, 'before_consistency', 'after_consistency')}`')
      ..writeln('- Artifact: `${result['saved_artifact_path']}`')
      ..writeln(
          '- Status final: `${result['passed'] == true ? 'PASSOU' : 'FALHOU'}`')
      ..writeln();

    final failedChecks =
        (result['failed_checks'] as List?)?.map((item) => '$item').toList() ??
            const <String>[];
    if (failedChecks.isNotEmpty) {
      buffer.writeln('Falhas:');
      for (final item in failedChecks) {
        buffer.writeln('- $item');
      }
      buffer.writeln();
    }

    final warnings =
        (result['warnings'] as List?)?.map((item) => '$item').toList() ??
            const <String>[];
    if (warnings.isNotEmpty) {
      buffer.writeln('Avisos:');
      for (final item in warnings.take(12)) {
        buffer.writeln('- $item');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}
