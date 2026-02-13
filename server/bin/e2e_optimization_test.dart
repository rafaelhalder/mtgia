#!/usr/bin/env dart
// ignore_for_file: avoid_print

/// =============================================================================
/// E2E Test Suite: Deck Builder + Optimization Flow
/// =============================================================================
/// 
/// Este script testa o fluxo completo:
/// 1. Registro de usuário
/// 2. Busca de commander aleatório (temático)
/// 3. Busca de cartas nas cores do commander
/// 4. Criação de deck (variável: 40-100 cartas para testar complete/optimize)
/// 5. Otimização/Completion do deck
/// 6. Validação de resultados (color identity, integridade, timing)
/// 
/// Uso:
///   dart run bin/e2e_optimization_test.dart [--runs=5] [--api=https://...] [--mode=optimize|complete|random]
/// 
/// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

// Configuração
const defaultApiUrl = 'https://evolution-cartinhas.8ktevp.easypanel.host';
const testUserPrefix = 'e2e_test_';

// Thresholds de performance
const int maxOptimizeTimeMs = 45000; // 45 segundos máximo
const int warningTimeMs = 30000;     // Warning se passar de 30s

/// Resultado de um teste individual
class TestResult {
  final String testName;
  final bool passed;
  final String? error;
  final Duration duration;
  final Map<String, dynamic> details;

  TestResult({
    required this.testName,
    required this.passed,
    this.error,
    required this.duration,
    this.details = const {},
  });

  @override
  String toString() {
    final status = passed ? '✅ PASS' : '❌ FAIL';
    final durationMs = duration.inMilliseconds;
    var result = '$status $testName (${durationMs}ms)';
    if (!passed && error != null) {
      result += '\n   └─ Error: $error';
    }
    return result;
  }
}

/// Suite de testes E2E
class E2ETestSuite {
  final String apiUrl;
  final String testMode; // 'optimize', 'complete', ou 'random'
  final Random random = Random();
  final List<TestResult> results = [];
  
  String? token;
  String? userId;
  String? deckId;
  Map<String, dynamic>? commanderData;
  List<Map<String, dynamic>> deckCards = [];
  String? expectedTheme;
  Set<String>? commanderIdentity;
  int targetCardCount = 100; // Para modo complete, será menor
  
  // Métricas de timing
  int optimizeTimeMs = 0;

  E2ETestSuite(this.apiUrl, {this.testMode = 'random'});

  /// Executa um teste individual e registra o resultado
  Future<bool> runTest(String name, Future<Map<String, dynamic>> Function() testFn) async {
    final stopwatch = Stopwatch()..start();
    try {
      final details = await testFn();
      stopwatch.stop();
      results.add(TestResult(
        testName: name,
        passed: true,
        duration: stopwatch.elapsed,
        details: details,
      ));
      print(results.last);
      return true;
    } catch (e) {
      stopwatch.stop();
      results.add(TestResult(
        testName: name,
        passed: false,
        error: e.toString(),
        duration: stopwatch.elapsed,
      ));
      print(results.last);
      return false;
    }
  }

  /// 1. Registro de usuário
  Future<Map<String, dynamic>> testRegister() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final username = '$testUserPrefix$timestamp';
    final email = '$username@test.local';
    final password = 'Test123!@#';

    final response = await http.post(
      Uri.parse('$apiUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Register failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    token = data['token'];
    userId = data['user']?['id'];

    if (token == null) {
      throw Exception('No token in response');
    }

    return {
      'username': username,
      'userId': userId,
    };
  }

  /// 2. Busca commander aleatório (organizado por tema para melhor detecção)
  Future<Map<String, dynamic>> testFetchRandomCommander() async {
    // Commanders organizados por tema para teste de detecção
    final commanders = [
      // === TOKENS ===
      {'name': 'Rhys the Redeemed', 'theme': 'tokens'},
      {'name': 'Adrix and Nev, Twincasters', 'theme': 'tokens'},
      {'name': 'Teysa Karlov', 'theme': 'tokens'},
      
      // === VAMPIROS ===
      {'name': 'Edgar Markov', 'theme': 'vampires'},
      {'name': 'Olivia Voldaren', 'theme': 'vampires'},
      
      // === ELFOS ===
      {'name': 'Lathril, Blade of the Elves', 'theme': 'elves'},
      {'name': 'Ezuri, Renegade Leader', 'theme': 'elves'},
      
      // === DRAGÕES ===
      {'name': 'The Ur-Dragon', 'theme': 'dragons'},
      {'name': 'Scion of the Ur-Dragon', 'theme': 'dragons'},
      {'name': 'Kaalia of the Vast', 'theme': 'dragons/demons/angels'},
      
      // === ARTEFATOS ===
      {'name': 'Urza, Lord High Artificer', 'theme': 'artifacts'},
      {'name': 'Breya, Etherium Shaper', 'theme': 'artifacts'},
      
      // === ENCHANTRESS ===
      {'name': 'Sythis, Harvest\'s Hand', 'theme': 'enchantress'},
      {'name': 'Zur the Enchanter', 'theme': 'enchantress'},
      
      // === REANIMATOR / GRAVEYARD ===
      {'name': 'Muldrotha, the Gravetide', 'theme': 'graveyard'},
      {'name': 'Meren of Clan Nel Toth', 'theme': 'graveyard'},
      
      // === AGGRO / GOBLINS ===
      {'name': 'Krenko, Mob Boss', 'theme': 'goblins'},
      
      // === CONTROLE ===
      {'name': 'Yuriko, the Tiger\'s Shadow', 'theme': 'control/ninjas'},
      
      // === VALUE / GENÉRICO ===
      {'name': 'Atraxa, Praetors\' Voice', 'theme': 'counters'},
      {'name': 'Kenrith, the Returned King', 'theme': 'politics'},
      {'name': 'Korvold, Fae-Cursed King', 'theme': 'sacrifice'},
      {'name': 'Prosper, Tome-Bound', 'theme': 'treasures'},
    ];

    final selected = commanders[random.nextInt(commanders.length)];
    final commanderName = selected['name'] as String;
    final expectedTheme = selected['theme'] as String;

    // Busca o commander no banco
    final response = await http.get(
      Uri.parse('$apiUrl/cards?name=${Uri.encodeComponent(commanderName)}&limit=1'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Card search failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final cards = data['data'] as List<dynamic>?;

    if (cards == null || cards.isEmpty) {
      throw Exception('Commander not found: $commanderName');
    }

    commanderData = cards.first as Map<String, dynamic>;
    
    // Extrai identidade de cor (não apenas cores!)
    // Color identity inclui símbolos de mana no texto, etc.
    final colorIdentity = (commanderData!['color_identity'] as List<dynamic>?)?.cast<String>() 
        ?? (commanderData!['colors'] as List<dynamic>?)?.cast<String>() 
        ?? [];

    // Salva para validações posteriores
    this.expectedTheme = expectedTheme;
    this.commanderIdentity = colorIdentity.toSet();

    return {
      'commander': commanderData!['name'],
      'commanderId': commanderData!['id'],
      'colorIdentity': colorIdentity,
      'expectedTheme': expectedTheme,
    };
  }

  /// 3. Busca cartas nas cores do commander
  /// 
  /// IMPORTANTE: Usa color_identity para verificação, não colors!
  /// No Commander, uma carta é legal se sua color_identity é um
  /// subconjunto da color_identity do commander.
  Future<Map<String, dynamic>> testFetchCardsForDeck() async {
    if (commanderData == null) {
      throw Exception('No commander selected');
    }

    // Identidade de cor do commander (o que define as cartas permitidas)
    final cmdIdentity = commanderIdentity ?? 
        (commanderData!['color_identity'] as List<dynamic>?)?.cast<String>().toSet() ??
        (commanderData!['colors'] as List<dynamic>?)?.cast<String>().toSet() ??
        <String>{};

    // Define quantidade de cartas baseado no modo de teste
    if (testMode == 'complete') {
      // Modo complete: deck incompleto (30-70 cartas)
      targetCardCount = 30 + random.nextInt(41); // 30 a 70 cartas
    } else if (testMode == 'optimize') {
      // Modo optimize: deck completo (100 cartas)
      targetCardCount = 100;
    } else {
      // Modo random: escolhe aleatoriamente entre complete e optimize
      if (random.nextBool()) {
        targetCardCount = 30 + random.nextInt(41); // complete
      } else {
        targetCardCount = 100; // optimize
      }
    }

    // Busca cartas nas cores do commander
    final allCards = <Map<String, dynamic>>[];
    
    // Adiciona o commander primeiro
    allCards.add(commanderData!);

    // Busca várias páginas de cartas
    for (var page = 1; page <= 15 && allCards.length < targetCardCount; page++) {
      final response = await http.get(
        Uri.parse('$apiUrl/cards?limit=100&page=$page'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        print('   Warning: Card fetch page $page failed');
        continue;
      }

      final data = jsonDecode(response.body);
      final cards = (data['data'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      
      if (cards.isEmpty) break; // Não há mais cartas
      
      // Filtra cartas que respeitam a identidade de cor do commander
      for (final card in cards) {
        if (allCards.length >= targetCardCount) break;
        
        // Pula o commander se já adicionamos
        if (card['id'] == commanderData!['id']) continue;
        
        // Obtém a identidade de cor da carta
        final cardIdentity = (card['color_identity'] as List<dynamic>?)?.cast<String>().toSet()
            ?? (card['colors'] as List<dynamic>?)?.cast<String>().toSet()
            ?? <String>{};
        
        // REGRA DO COMMANDER: A identidade de cor da carta deve ser
        // um SUBCONJUNTO da identidade de cor do commander
        // (ou seja, todas as cores da carta devem estar no commander)
        final isLegalIdentity = cmdIdentity.isEmpty 
            ? cardIdentity.isEmpty  // Para incolores, só aceita incolores
            : cardIdentity.every((c) => cmdIdentity.contains(c));
        
        if (isLegalIdentity) {
          allCards.add(card);
        }
      }
    }

    // Se não temos cartas suficientes após filtro, logamos warning
    if (allCards.length < targetCardCount) {
      print('   Warning: Only found ${allCards.length} cards matching commander identity (target: $targetCardCount)');
    }

    deckCards = allCards;

    return {
      'cardsFound': deckCards.length,
      'targetCardCount': targetCardCount,
      'testMode': targetCardCount < 100 ? 'complete' : 'optimize',
      'commanderIdentity': cmdIdentity.toList(),
    };
  }

  /// 4. Cria o deck (com quantidade variável de cartas)
  Future<Map<String, dynamic>> testCreateDeck() async {
    if (commanderData == null || deckCards.isEmpty) {
      throw Exception('No cards to create deck');
    }

    // Prepara a lista de cartas para o deck
    final cardsList = <Map<String, dynamic>>[];
    
    // Adiciona o commander
    cardsList.add({
      'card_id': commanderData!['id'],
      'quantity': 1,
      'is_commander': true,
    });

    // Adiciona as outras cartas (até targetCardCount - 1 para incluir commander)
    final maxCards = targetCardCount - 1;
    var added = 0;
    for (final card in deckCards) {
      if (card['id'] == commanderData!['id']) continue;
      if (added >= maxCards) break;
      
      cardsList.add({
        'card_id': card['id'],
        'quantity': 1,
        'is_commander': false,
      });
      added++;
    }

    final modeLabel = cardsList.length < 100 ? 'COMPLETE' : 'OPTIMIZE';
    final deckName = 'E2E [$modeLabel] ${commanderData!['name']} - ${DateTime.now().toIso8601String()}';

    final response = await http.post(
      Uri.parse('$apiUrl/decks'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': deckName,
        'format': 'commander',
        'description': 'Deck criado automaticamente para teste E2E. Modo: $modeLabel',
        'cards': cardsList,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Create deck failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    deckId = data['id'] ?? data['deck']?['id'];

    if (deckId == null) {
      throw Exception('No deck ID in response: ${response.body}');
    }

    return {
      'deckId': deckId,
      'deckName': deckName,
      'cardCount': cardsList.length,
      'mode': cardsList.length < 100 ? 'complete' : 'optimize',
    };
  }

  /// 5. Busca detalhes do deck
  Future<Map<String, dynamic>> testFetchDeckDetails() async {
    if (deckId == null) {
      throw Exception('No deck ID');
    }

    final response = await http.get(
      Uri.parse('$apiUrl/decks/$deckId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Fetch deck failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    // CORREÇÃO: API retorna all_cards_flat, não cards
    final cards = data['all_cards_flat'] as List<dynamic>? ?? [];
    final commander = data['commander'] as List<dynamic>? ?? [];
    final stats = data['stats'] as Map<String, dynamic>?;

    return {
      'deckId': deckId,
      'cardCount': stats?['total_cards'] ?? cards.length,
      'uniqueCards': stats?['unique_cards'] ?? cards.length,
      'hasCommander': commander.isNotEmpty,
    };
  }

  /// 6. Otimiza o deck (com medição de timing e validação de color identity)
  Future<Map<String, dynamic>> testOptimizeDeck() async {
    if (deckId == null) {
      throw Exception('No deck ID');
    }

    final stopwatch = Stopwatch()..start();
    
    final response = await http.post(
      Uri.parse('$apiUrl/ai/optimize'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'deck_id': deckId,
        'archetype': 'auto',
      }),
    );

    stopwatch.stop();
    optimizeTimeMs = stopwatch.elapsedMilliseconds;

    if (response.statusCode != 200) {
      throw Exception('Optimize failed: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    
    final mode = data['mode'];
    final theme = data['theme']?['theme'];
    final removalsRaw = data['removals'];
    final additionsRaw = data['additions'];
    
    // Lidar com diferentes formatos de removals/additions
    // Pode ser List ou Map (as vezes a API retorna Map com índices string)
    List<dynamic> removals = [];
    List<dynamic> additions = [];
    
    if (removalsRaw is List) {
      removals = removalsRaw;
    } else if (removalsRaw is Map) {
      removals = removalsRaw.values.toList();
    }
    
    if (additionsRaw is List) {
      additions = additionsRaw;
    } else if (additionsRaw is Map) {
      additions = additionsRaw.values.toList();
    }
    
    final validationScore = data['post_analysis']?['validation']?['validation_score'];
    final verdict = data['post_analysis']?['validation']?['verdict'];

    // Validação de color identity nas sugestões (additions)
    var colorIdentityViolations = 0;
    final cmdIdentity = commanderIdentity ?? <String>{};
    
    for (final addition in additions) {
      if (addition is! Map) continue;
      
      final cardColors = (addition['color_identity'] as List<dynamic>?)?.cast<String>().toSet()
          ?? (addition['colors'] as List<dynamic>?)?.cast<String>().toSet()
          ?? <String>{};
      
      final isLegal = cmdIdentity.isEmpty
          ? cardColors.isEmpty
          : cardColors.every((c) => cmdIdentity.contains(c));
      
      if (!isLegal) {
        colorIdentityViolations++;
        print('   ⚠️ Color identity violation: ${addition['name']} (${cardColors.toList()}) not in $cmdIdentity');
      }
    }

    // Validação de timing
    String timingStatus = 'ok';
    if (optimizeTimeMs > maxOptimizeTimeMs) {
      timingStatus = 'SLOW';
      print('   ⚠️ Optimize took too long: ${optimizeTimeMs}ms (max: ${maxOptimizeTimeMs}ms)');
    } else if (optimizeTimeMs > warningTimeMs) {
      timingStatus = 'warning';
      print('   ⚠️ Optimize timing warning: ${optimizeTimeMs}ms');
    }

    // Validação de tema detectado vs esperado
    final themeMatch = expectedTheme != null && theme != null && 
        (theme.toLowerCase().contains(expectedTheme!.split('/').first.toLowerCase()) ||
         expectedTheme!.toLowerCase().contains(theme.toLowerCase()));

    return {
      'mode': mode,
      'detectedTheme': theme,
      'expectedTheme': expectedTheme,
      'themeMatch': themeMatch,
      'removals': removals.length,
      'additions': additions.length,
      'validationScore': validationScore,
      'verdict': verdict,
      'balanced': removals.length == additions.length,
      'colorIdentityViolations': colorIdentityViolations,
      'optimizeTimeMs': optimizeTimeMs,
      'timingStatus': timingStatus,
    };
  }

  /// 7. Verifica integridade do deck após sugestões
  Future<Map<String, dynamic>> testValidateOptimizationResult() async {
    // Re-busca o deck para verificar estado
    final response = await http.get(
      Uri.parse('$apiUrl/decks/$deckId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Fetch deck after optimize failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    // CORREÇÃO: API retorna all_cards_flat, não cards
    final cards = data['all_cards_flat'] as List<dynamic>? ?? [];
    final commander = data['commander'] as List<dynamic>? ?? [];
    final stats = data['stats'] as Map<String, dynamic>?;
    
    // Verifica se o deck ainda está íntegro
    final hasCommander = commander.isNotEmpty;
    final totalCards = stats?['total_cards'] ?? cards.length;

    return {
      'cardCount': totalCards,
      'hasCommander': hasCommander,
      'deckIntact': cards.isNotEmpty || commander.isNotEmpty,
    };
  }

  /// 8. Cleanup - deleta o deck de teste
  Future<Map<String, dynamic>> testCleanup() async {
    if (deckId == null) {
      return {'skipped': true};
    }

    final response = await http.delete(
      Uri.parse('$apiUrl/decks/$deckId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    // 200, 204 ou 404 são aceitáveis
    final success = response.statusCode == 200 || 
                    response.statusCode == 204 || 
                    response.statusCode == 404;

    return {
      'deleted': success,
      'statusCode': response.statusCode,
    };
  }

  /// Executa a suite completa
  Future<void> runAll() async {
    print('\n${'=' * 60}');
    print('E2E TEST SUITE - Deck Builder + Optimization');
    print('API: $apiUrl');
    print('Started: ${DateTime.now()}');
    print('=' * 60 + '\n');

    // Executa cada teste em sequência
    var allPassed = true;

    allPassed &= await runTest('1. Register User', testRegister);
    if (!allPassed) {
      print('\n⛔ Cannot continue without registration');
      return;
    }

    allPassed &= await runTest('2. Fetch Random Commander', testFetchRandomCommander);
    if (!allPassed) {
      print('\n⛔ Cannot continue without commander');
      return;
    }

    allPassed &= await runTest('3. Fetch Cards for Deck', testFetchCardsForDeck);
    if (!allPassed) {
      print('\n⛔ Cannot continue without cards');
      return;
    }

    allPassed &= await runTest('4. Create Deck', testCreateDeck);
    if (!allPassed) {
      print('\n⛔ Cannot continue without deck');
      return;
    }

    allPassed &= await runTest('5. Fetch Deck Details', testFetchDeckDetails);
    allPassed &= await runTest('6. Optimize Deck', testOptimizeDeck);
    allPassed &= await runTest('7. Validate Optimization Result', testValidateOptimizationResult);
    
    // Cleanup sempre roda
    await runTest('8. Cleanup (Delete Test Deck)', testCleanup);

    // Resumo
    printSummary();
  }

  void printSummary() {
    print('\n${'=' * 60}');
    print('TEST SUMMARY');
    print('=' * 60);

    final passed = results.where((r) => r.passed).length;
    final failed = results.where((r) => !r.passed).length;
    final total = results.length;
    final totalTime = results.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );

    print('Total: $total | Passed: $passed | Failed: $failed');
    print('Total Time: ${totalTime.inMilliseconds}ms');
    print('');

    if (failed > 0) {
      print('FAILED TESTS:');
      for (final r in results.where((r) => !r.passed)) {
        print('  ❌ ${r.testName}: ${r.error}');
      }
    }

    print('\nDETAILS:');
    for (final r in results) {
      if (r.details.isNotEmpty) {
        print('  ${r.testName}:');
        for (final entry in r.details.entries) {
          print('    ${entry.key}: ${entry.value}');
        }
      }
    }

    print('=' * 60);
    if (failed == 0) {
      print('🎉 ALL TESTS PASSED!');
    } else {
      print('💥 SOME TESTS FAILED');
    }
    print('=' * 60 + '\n');
  }
}

/// Executa múltiplas rodadas de testes
Future<void> runMultipleTests(String apiUrl, int runs, String mode) async {
  print('\n' + '█' * 60);
  print('RUNNING $runs TEST ROUNDS (Mode: $mode)');
  print('█' * 60 + '\n');

  var totalPassed = 0;
  var totalFailed = 0;
  final runResults = <int, Map<String, dynamic>>{};
  var totalOptimizeTime = 0;
  var colorViolationsTotal = 0;

  for (var i = 1; i <= runs; i++) {
    print('\n┌${'─' * 58}┐');
    print('│ RUN $i of $runs ${' ' * (50 - '$i'.length - '$runs'.length)}│');
    print('└${'─' * 58}┘');

    final suite = E2ETestSuite(apiUrl, testMode: mode);
    await suite.runAll();

    final passed = suite.results.every((r) => r.passed || r.testName.contains('Cleanup'));
    
    // Extrair métricas
    final optimizeResult = suite.results.firstWhere(
      (r) => r.testName.contains('Optimize'),
      orElse: () => TestResult(testName: '', passed: false, duration: Duration.zero),
    );
    final optTime = optimizeResult.details['optimizeTimeMs'] as int? ?? 0;
    final colorViolations = optimizeResult.details['colorIdentityViolations'] as int? ?? 0;
    
    totalOptimizeTime += optTime;
    colorViolationsTotal += colorViolations;
    
    runResults[i] = {
      'passed': passed,
      'commander': suite.commanderData?['name'] ?? 'unknown',
      'cardCount': suite.targetCardCount,
      'mode': suite.targetCardCount < 100 ? 'complete' : 'optimize',
      'optimizeTimeMs': optTime,
      'colorViolations': colorViolations,
    };

    if (passed) {
      totalPassed++;
    } else {
      totalFailed++;
    }

    // Pequena pausa entre runs para não sobrecarregar
    if (i < runs) {
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // Resumo final
  print('\n' + '█' * 60);
  print('FINAL RESULTS: $runs RUNS');
  print('█' * 60);
  print('');
  print('Passed: $totalPassed / $runs');
  print('Failed: $totalFailed / $runs');
  print('Success Rate: ${(totalPassed / runs * 100).toStringAsFixed(1)}%');
  print('Avg Optimize Time: ${(totalOptimizeTime / runs).round()}ms');
  print('Total Color Identity Violations: $colorViolationsTotal');
  print('');
  
  for (final entry in runResults.entries) {
    final data = entry.value;
    final status = data['passed'] == true ? '✅' : '❌';
    final cmdName = (data['commander'] as String).split(',').first; // Truncate long names
    final modeStr = data['mode'] as String;
    final cards = data['cardCount'] as int;
    final timeMs = data['optimizeTimeMs'] as int;
    final violations = data['colorViolations'] as int;
    final violationStr = violations > 0 ? ' ⚠️$violations' : '';
    print('  Run ${entry.key}: $status $cmdName ($cards cards, $modeStr, ${timeMs}ms)$violationStr');
  }
  
  print('');
  if (totalFailed == 0 && colorViolationsTotal == 0) {
    print('🎉🎉🎉 ALL $runs RUNS PASSED PERFECTLY! 🎉🎉🎉');
  } else if (totalFailed == 0) {
    print('✅ ALL $runs RUNS PASSED (but $colorViolationsTotal color violations detected)');
  } else {
    print('⚠️  $totalFailed out of $runs runs failed');
  }
  print('█' * 60 + '\n');
}

void main(List<String> args) async {
  // Parse argumentos
  var apiUrl = defaultApiUrl;
  var runs = 3;
  var mode = 'random'; // 'optimize', 'complete', ou 'random'

  for (final arg in args) {
    if (arg.startsWith('--api=')) {
      apiUrl = arg.substring(6);
    } else if (arg.startsWith('--runs=')) {
      runs = int.tryParse(arg.substring(7)) ?? 3;
    } else if (arg.startsWith('--mode=')) {
      mode = arg.substring(7);
      if (!['optimize', 'complete', 'random'].contains(mode)) {
        print('Invalid mode: $mode. Using "random".');
        mode = 'random';
      }
    }
  }

  print('');
  print('╔════════════════════════════════════════════════════════════╗');
  print('║        E2E Test Suite - ManaLoom Deck Optimization         ║');
  print('╠════════════════════════════════════════════════════════════╣');
  print('║ API: ${apiUrl.padRight(53)}║');
  print('║ Runs: ${runs.toString().padRight(52)}║');
  print('║ Mode: ${mode.padRight(52)}║');
  print('╚════════════════════════════════════════════════════════════╝');

  await runMultipleTests(apiUrl, runs, mode);
}
