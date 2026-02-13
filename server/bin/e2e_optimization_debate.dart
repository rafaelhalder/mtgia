#!/usr/bin/env dart
// ignore_for_file: avoid_print

/// =============================================================================
/// E2E Test Suite v2: Optimization Analysis & Debate
/// =============================================================================
/// 
/// Este script executa 10 testes E2E completos e depois faz uma análise
/// detalhada (debate) de cada otimização, salvando os resultados em uma
/// tabela para uso futuro como base de aprendizado.
/// 
/// Uso:
///   dart run bin/e2e_optimization_debate.dart [--runs=10] [--api=https://...]
/// 
/// Saída:
///   - Resultados de cada teste no console
///   - Análise/debate de cada otimização
///   - Dados salvos em optimization_analysis_logs
/// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

// Configuração
const defaultApiUrl = 'https://evolution-cartinhas.8ktevp.easypanel.host';
const testUserPrefix = 'e2e_debate_';

/// Dados coletados de uma otimização para análise
class OptimizationData {
  final int testNumber;
  final String commanderName;
  final List<String> commanderColors;
  final String operationMode;
  final int initialCardCount;
  final int finalCardCount;
  final String? targetArchetype;
  final String? detectedTheme;
  final List<String> edhrecThemes;
  final bool themeMatch;
  final bool hybridModeUsed;
  
  // Métricas antes/depois
  final Map<String, dynamic> beforeAnalysis;
  final Map<String, dynamic> afterAnalysis;
  
  // Alterações
  final List<String> removals;
  final List<String> additions;
  
  // Validação
  final int? validationScore;
  final String? validationVerdict;
  final int colorIdentityViolations;
  final int edhrecValidatedCount;
  final int edhrecNotValidatedCount;
  final List<String> validationWarnings;
  
  // Performance
  final int executionTimeMs;
  
  // Resposta completa da API
  final Map<String, dynamic> fullResponse;

  OptimizationData({
    required this.testNumber,
    required this.commanderName,
    required this.commanderColors,
    required this.operationMode,
    required this.initialCardCount,
    required this.finalCardCount,
    this.targetArchetype,
    this.detectedTheme,
    this.edhrecThemes = const [],
    this.themeMatch = false,
    this.hybridModeUsed = false,
    required this.beforeAnalysis,
    required this.afterAnalysis,
    this.removals = const [],
    this.additions = const [],
    this.validationScore,
    this.validationVerdict,
    this.colorIdentityViolations = 0,
    this.edhrecValidatedCount = 0,
    this.edhrecNotValidatedCount = 0,
    this.validationWarnings = const [],
    required this.executionTimeMs,
    required this.fullResponse,
  });
}

/// Análise/Debate de uma otimização
class OptimizationDebate {
  final OptimizationData data;
  
  // Scores calculados
  late double effectivenessScore;
  late List<String> improvementsAchieved;
  late List<String> potentialIssues;
  late List<String> alternativeApproaches;
  late String lessonsLearned;
  late Map<String, dynamic> decisionsReasoning;
  late Map<String, dynamic> swapAnalysis;
  late Map<String, dynamic> roleDelta;

  OptimizationDebate(this.data) {
    _analyze();
  }

  void _analyze() {
    improvementsAchieved = [];
    potentialIssues = [];
    alternativeApproaches = [];
    decisionsReasoning = {};
    swapAnalysis = {};
    roleDelta = {};
    
    // 1. Analisar mudanças de CMC
    final beforeCmc = _parseDouble(data.beforeAnalysis['average_cmc']);
    final afterCmc = _parseDouble(data.afterAnalysis['average_cmc']);
    final cmcDelta = afterCmc - beforeCmc;
    
    decisionsReasoning['cmc_change'] = {
      'before': beforeCmc,
      'after': afterCmc,
      'delta': cmcDelta,
      'direction': cmcDelta < 0 ? 'decreased' : (cmcDelta > 0 ? 'increased' : 'unchanged'),
    };
    
    if (cmcDelta < -0.3) {
      improvementsAchieved.add('CMC médio reduzido de ${beforeCmc.toStringAsFixed(2)} para ${afterCmc.toStringAsFixed(2)} (-${(-cmcDelta).toStringAsFixed(2)})');
    } else if (cmcDelta > 0.3) {
      potentialIssues.add('CMC médio aumentou de ${beforeCmc.toStringAsFixed(2)} para ${afterCmc.toStringAsFixed(2)} (+${cmcDelta.toStringAsFixed(2)})');
    }
    
    // 2. Analisar distribuição de tipos
    final beforeTypes = data.beforeAnalysis['type_distribution'] as Map<String, dynamic>? ?? {};
    final afterTypes = data.afterAnalysis['type_distribution'] as Map<String, dynamic>? ?? {};
    
    final landsBefore = (beforeTypes['lands'] as int?) ?? 0;
    final landsAfter = (afterTypes['lands'] as int?) ?? 0;
    final landsDelta = landsAfter - landsBefore;
    
    roleDelta = {
      'lands': landsDelta,
      'creatures': ((afterTypes['creatures'] as int?) ?? 0) - ((beforeTypes['creatures'] as int?) ?? 0),
      'instants': ((afterTypes['instants'] as int?) ?? 0) - ((beforeTypes['instants'] as int?) ?? 0),
      'sorceries': ((afterTypes['sorceries'] as int?) ?? 0) - ((beforeTypes['sorceries'] as int?) ?? 0),
      'artifacts': ((afterTypes['artifacts'] as int?) ?? 0) - ((beforeTypes['artifacts'] as int?) ?? 0),
      'enchantments': ((afterTypes['enchantments'] as int?) ?? 0) - ((beforeTypes['enchantments'] as int?) ?? 0),
    };
    
    if (landsDelta > 3) {
      improvementsAchieved.add('Base de mana reforçada: +$landsDelta terrenos');
    } else if (landsDelta < -3) {
      potentialIssues.add('Muitos terrenos removidos: $landsDelta');
    }
    
    // 3. Analisar consistência (Monte Carlo)
    final beforeMC = data.beforeAnalysis['validation']?['monte_carlo'] as Map<String, dynamic>?;
    final afterMC = data.afterAnalysis['validation']?['monte_carlo'] as Map<String, dynamic>?;
    
    double consistencyBefore = 0, consistencyAfter = 0;
    double keepAt7Before = 0, keepAt7After = 0;
    
    if (beforeMC != null && afterMC != null) {
      consistencyBefore = _parseDouble(beforeMC['before']?['consistency_score'] ?? beforeMC['consistency_score']);
      consistencyAfter = _parseDouble(afterMC['after']?['consistency_score'] ?? afterMC['consistency_score']);
      
      final mulliganBefore = beforeMC['mulligan_before'] as Map<String, dynamic>? ?? beforeMC['mulligan'] as Map<String, dynamic>? ?? {};
      final mulliganAfter = afterMC['mulligan_after'] as Map<String, dynamic>? ?? afterMC['mulligan'] as Map<String, dynamic>? ?? {};
      
      keepAt7Before = _parseDouble(mulliganBefore['keep_at_7']);
      keepAt7After = _parseDouble(mulliganAfter['keep_at_7']);
    }
    
    final consistencyDelta = consistencyAfter - consistencyBefore;
    final keepAt7Delta = keepAt7After - keepAt7Before;
    
    decisionsReasoning['consistency'] = {
      'before': consistencyBefore,
      'after': consistencyAfter,
      'delta': consistencyDelta,
      'keep_at_7_before': keepAt7Before,
      'keep_at_7_after': keepAt7After,
      'keep_at_7_delta': keepAt7Delta,
    };
    
    if (consistencyDelta > 2) {
      improvementsAchieved.add('Consistência melhorou: ${consistencyBefore.toStringAsFixed(1)} → ${consistencyAfter.toStringAsFixed(1)} (+${consistencyDelta.toStringAsFixed(1)})');
    } else if (consistencyDelta < -2) {
      potentialIssues.add('Consistência piorou: ${consistencyBefore.toStringAsFixed(1)} → ${consistencyAfter.toStringAsFixed(1)} (${consistencyDelta.toStringAsFixed(1)})');
    }
    
    if (keepAt7Delta > 0.05) {
      improvementsAchieved.add('Taxa de mãos jogáveis melhorou: ${(keepAt7Before*100).toStringAsFixed(0)}% → ${(keepAt7After*100).toStringAsFixed(0)}%');
    } else if (keepAt7Delta < -0.05) {
      potentialIssues.add('Taxa de mãos jogáveis piorou: ${(keepAt7Before*100).toStringAsFixed(0)}% → ${(keepAt7After*100).toStringAsFixed(0)}%');
    }
    
    // 4. Analisar EDHREC validation
    if (data.edhrecNotValidatedCount > 0) {
      final percent = (data.edhrecNotValidatedCount / (data.edhrecValidatedCount + data.edhrecNotValidatedCount) * 100).toStringAsFixed(0);
      if (int.parse(percent) > 50) {
        potentialIssues.add('${data.edhrecNotValidatedCount} cartas ($percent%) não aparecem nos dados EDHREC - possível baixa sinergia');
        alternativeApproaches.add('Considerar aumentar peso do EDHREC na seleção (atualmente 70%)');
      } else if (int.parse(percent) > 30) {
        alternativeApproaches.add('${data.edhrecNotValidatedCount} cartas não-EDHREC podem ser inovadoras ou de baixa sinergia');
      }
    }
    
    // 5. Analisar color identity
    if (data.colorIdentityViolations > 0) {
      potentialIssues.add('${data.colorIdentityViolations} sugestão(ões) da IA violaram color identity (filtradas)');
      alternativeApproaches.add('Melhorar prompt da IA para enfatizar restrições de cor');
    }
    
    // 6. Analisar tema híbrido
    if (data.hybridModeUsed) {
      decisionsReasoning['hybrid_mode'] = {
        'used': true,
        'detected_theme': data.detectedTheme,
        'edhrec_themes': data.edhrecThemes,
        'reason': 'Tema detectado não corresponde aos temas EDHREC populares',
        'approach': '70% cartas EDHREC + 30% cartas do tema do usuário',
      };
      
      if (data.validationScore != null && data.validationScore! >= 50) {
        improvementsAchieved.add('Modo híbrido ativado com sucesso: respeitou tema do usuário mantendo base EDHREC');
      }
    }
    
    // 7. Analisar trocas específicas
    swapAnalysis = {
      'total_removals': data.removals.length,
      'total_additions': data.additions.length,
      'net_change': data.additions.length - data.removals.length,
      'removals_sample': data.removals.take(5).toList(),
      'additions_sample': data.additions.take(5).toList(),
    };
    
    // 8. Calcular score de efetividade (0-100)
    effectivenessScore = _calculateEffectivenessScore();
    
    // 9. Gerar lições aprendidas
    lessonsLearned = _generateLessonsLearned();
  }
  
  double _calculateEffectivenessScore() {
    double score = 50.0; // Base
    
    // Validation score contribui com até 30 pontos
    if (data.validationScore != null) {
      score += (data.validationScore! - 50) * 0.3;
    }
    
    // Melhorias de consistência (até 10 pontos)
    final consistencyDelta = decisionsReasoning['consistency']?['delta'] as double? ?? 0;
    score += consistencyDelta.clamp(-10, 10);
    
    // Keep at 7 improvement (até 10 pontos)
    final keep7Delta = (decisionsReasoning['consistency']?['keep_at_7_delta'] as double? ?? 0) * 100;
    score += keep7Delta.clamp(-10, 10);
    
    // CMC optimization (até 5 pontos)
    final cmcDelta = decisionsReasoning['cmc_change']?['delta'] as double? ?? 0;
    if (cmcDelta < 0 && cmcDelta > -1) {
      score += 5; // Redução moderada é bom
    } else if (cmcDelta < -1) {
      score += 3; // Redução agressiva
    } else if (cmcDelta > 0.5) {
      score -= 3; // Aumento significativo
    }
    
    // Penalidades
    score -= data.colorIdentityViolations * 2;
    score -= potentialIssues.length * 1.5;
    
    // Bônus por melhorias
    score += improvementsAchieved.length * 2;
    
    return score.clamp(0, 100);
  }
  
  String _generateLessonsLearned() {
    final lessons = <String>[];
    
    if (data.hybridModeUsed && effectivenessScore >= 60) {
      lessons.add('Modo híbrido funcionou bem para tema não-convencional.');
    }
    
    if (data.colorIdentityViolations > 0) {
      lessons.add('IA ainda sugere cartas fora da identidade de cor - reforçar no prompt.');
    }
    
    if (data.edhrecNotValidatedCount > data.additions.length * 0.5) {
      lessons.add('Muitas cartas fora do EDHREC - considerar aumentar threshold de sinergia.');
    }
    
    final cmcDelta = decisionsReasoning['cmc_change']?['delta'] as double? ?? 0;
    if (cmcDelta.abs() > 0.5) {
      lessons.add('CMC ${cmcDelta < 0 ? "reduziu" : "aumentou"} significativamente - monitorar impacto.');
    }
    
    if (effectivenessScore < 40) {
      lessons.add('Efetividade baixa - revisar parâmetros de otimização.');
    } else if (effectivenessScore >= 70) {
      lessons.add('Otimização bem-sucedida - padrões podem ser replicados.');
    }
    
    return lessons.join(' ');
  }
  
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  
  void printDebate() {
    print('\n${'='*70}');
    print('📊 DEBATE/ANÁLISE - Teste #${data.testNumber}');
    print('='*70);
    print('Commander: ${data.commanderName} (${data.commanderColors.join("")})');
    print('Modo: ${data.operationMode} | Cards: ${data.initialCardCount} → ${data.finalCardCount}');
    print('Arquétipo: ${data.targetArchetype ?? "auto"} | Tema detectado: ${data.detectedTheme ?? "N/A"}');
    print('Tempo: ${data.executionTimeMs}ms');
    print('-'*70);
    
    print('\n📈 DECISÕES TOMADAS:');
    print('  CMC: ${decisionsReasoning['cmc_change']?['before']?.toStringAsFixed(2)} → ${decisionsReasoning['cmc_change']?['after']?.toStringAsFixed(2)} (${decisionsReasoning['cmc_change']?['direction']})');
    print('  Consistência: ${decisionsReasoning['consistency']?['before']?.toStringAsFixed(1)} → ${decisionsReasoning['consistency']?['after']?.toStringAsFixed(1)}');
    print('  Keep@7: ${((decisionsReasoning['consistency']?['keep_at_7_before'] ?? 0)*100).toStringAsFixed(0)}% → ${((decisionsReasoning['consistency']?['keep_at_7_after'] ?? 0)*100).toStringAsFixed(0)}%');
    print('  Alterações: -${data.removals.length} / +${data.additions.length}');
    if (data.hybridModeUsed) {
      print('  🔀 Modo Híbrido: ATIVO (70% EDHREC + 30% tema)');
    }
    
    print('\n🔄 DISTRIBUIÇÃO DE TIPOS (delta):');
    roleDelta.forEach((type, delta) {
      if (delta != 0) {
        print('  $type: ${delta > 0 ? '+' : ''}$delta');
      }
    });
    
    print('\n✅ MELHORIAS ALCANÇADAS:');
    if (improvementsAchieved.isEmpty) {
      print('  (nenhuma melhoria significativa detectada)');
    } else {
      for (final imp in improvementsAchieved) {
        print('  • $imp');
      }
    }
    
    print('\n⚠️ POSSÍVEIS PROBLEMAS:');
    if (potentialIssues.isEmpty) {
      print('  (nenhum problema detectado)');
    } else {
      for (final issue in potentialIssues) {
        print('  • $issue');
      }
    }
    
    print('\n💡 ABORDAGENS ALTERNATIVAS:');
    if (alternativeApproaches.isEmpty) {
      print('  (sem sugestões)');
    } else {
      for (final alt in alternativeApproaches) {
        print('  • $alt');
      }
    }
    
    print('\n🎯 VALIDAÇÃO:');
    print('  Score: ${data.validationScore ?? "N/A"}/100');
    print('  Veredito: ${data.validationVerdict ?? "N/A"}');
    print('  EDHREC validadas: ${data.edhrecValidatedCount}/${data.edhrecValidatedCount + data.edhrecNotValidatedCount}');
    print('  Violações de cor: ${data.colorIdentityViolations}');
    
    print('\n📝 LIÇÕES APRENDIDAS:');
    print('  $lessonsLearned');
    
    print('\n🏆 SCORE DE EFETIVIDADE: ${effectivenessScore.toStringAsFixed(1)}/100');
    final emoji = effectivenessScore >= 70 ? '🟢' : (effectivenessScore >= 50 ? '🟡' : '🔴');
    print('  Status: $emoji');
    print('='*70);
  }
}

/// Suite de testes E2E com debate
class E2EDebateSuite {
  final String apiUrl;
  final Random random = Random();
  final List<OptimizationData> collectedData = [];
  final List<OptimizationDebate> debates = [];
  
  String? token;
  String? userId;
  late String testRunId;
  Pool? pool;

  E2EDebateSuite(this.apiUrl);

  Future<void> connectDatabase() async {
    final env = DotEnv()..load();
    pool = Pool.withEndpoints(
      [
        Endpoint(
          host: env['DB_HOST'] ?? 'localhost',
          database: env['DB_NAME'] ?? 'mtg_db',
          username: env['DB_USER'] ?? 'postgres',
          password: env['DB_PASS'] ?? env['DB_PASSWORD'] ?? 'postgres',
          port: int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432,
        ),
      ],
      settings: PoolSettings(maxConnectionCount: 3, sslMode: SslMode.disable),
    );
    print('📦 Database connected');
  }

  Future<void> registerAndLogin() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final username = '$testUserPrefix$timestamp';
    final email = '$username@test.local';
    final password = 'TestPass123!';

    // Registrar
    final registerRes = await http.post(
      Uri.parse('$apiUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email, 'password': password}),
    );

    if (registerRes.statusCode == 201 || registerRes.statusCode == 200) {
      final data = jsonDecode(registerRes.body);
      token = data['token'];
      userId = data['user']?['id'];
      print('✅ User registered: $username');
    } else if (registerRes.statusCode == 409) {
      // Já existe, fazer login
      final loginRes = await http.post(
        Uri.parse('$apiUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (loginRes.statusCode == 200) {
        final data = jsonDecode(loginRes.body);
        token = data['token'];
        userId = data['user']?['id'];
        print('✅ User logged in: $username');
      } else {
        throw Exception('Login failed: ${loginRes.statusCode}');
      }
    } else {
      throw Exception('Register failed: ${registerRes.statusCode} - ${registerRes.body}');
    }
  }

  // Rastrear commanders já usados para garantir variabilidade
  final _usedCommanders = <String>{};
  
  Future<Map<String, dynamic>> fetchRandomCommander() async {
    // Lista expandida de commanders temáticos para testes variados
    final commanders = [
      // Grindy/Recursion
      'Muldrotha, the Gravetide',
      'Meren of Clan Nel Toth',
      'Karador, Ghost Chieftain',
      // Superfriends/Counters
      'Atraxa, Praetors\' Voice',
      'Sisay, Weatherlight Captain',
      // Tribal
      'Edgar Markov',
      'The Ur-Dragon',
      'Sliver Overlord',
      // Value/Sacrifice
      'Korvold, Fae-Cursed King',
      'Prosper, Tome-Bound',
      'Teysa Karlov',
      // Stealth/Combat
      'Yuriko, the Tiger\'s Shadow',
      'Najeela, the Blade-Blossom',
      // Aggro/Tokens
      'Krenko, Mob Boss',
      'Purphoros, God of the Forge',
      'Jetmir, Nexus of Revels',
      // Landfall/Ramp
      'Omnath, Locus of Creation',
      'Lord Windgrace',
      'Tatyova, Benthic Druid',
      // Big Creatures
      'Kaalia of the Vast',
      'Mayael the Anima',
      // Spellslinger
      'Kess, Dissident Mage',
      'Niv-Mizzet, Parun',
      // Artifacts
      'Breya, Etherium Shaper',
      'Urza, Lord High Artificer',
      // Control
      'Oloro, Ageless Ascetic',
      'Grand Arbiter Augustin IV',
    ];
    
    // Filtrar commanders já usados nesta bateria
    final available = commanders.where((c) => !_usedCommanders.contains(c)).toList();
    
    // Se todos já foram usados, resetar (para baterias > commanders disponíveis)
    final pool = available.isNotEmpty ? available : commanders;
    
    final name = pool[random.nextInt(pool.length)];
    _usedCommanders.add(name);
    
    final res = await http.get(
      Uri.parse('$apiUrl/cards?name=${Uri.encodeComponent(name)}&limit=1'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final cards = data['data'] as List? ?? [];
      if (cards.isNotEmpty) {
        return cards.first as Map<String, dynamic>;
      }
    }
    
    // Fallback para busca genérica
    final fallbackRes = await http.get(
      Uri.parse('$apiUrl/cards?name=legendary creature&limit=10'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    if (fallbackRes.statusCode == 200) {
      final data = jsonDecode(fallbackRes.body);
      final cards = data['data'] as List? ?? [];
      if (cards.isNotEmpty) {
        return cards[random.nextInt(cards.length)] as Map<String, dynamic>;
      }
    }
    
    throw Exception('Could not find any commander');
  }

  Future<List<Map<String, dynamic>>> fetchCardsInColors(List<String> colors, int count) async {
    // Buscar cartas e filtrar manualmente por identidade de cor
    final colorSet = colors.map((c) => c.toUpperCase()).toSet();
    final uniqueCards = <String, Map<String, dynamic>>{}; // Map para garantir unicidade por ID
    
    // Buscar em batches diferentes para ter variedade
    final queries = [
      'creature',
      'instant',
      'sorcery',
      'artifact',
      'enchantment',
      'land',
    ];
    
    for (final query in queries) {
      final res = await http.get(
        Uri.parse('$apiUrl/cards?type=$query&limit=100'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final cards = (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
        
        // Filtrar por identidade de cor
        for (final card in cards) {
          final cardId = card['id']?.toString();
          if (cardId == null || uniqueCards.containsKey(cardId)) continue; // Skip duplicates
          
          final cardColors = (card['colors'] as List?)?.cast<String>() ?? [];
          final cardColorSet = cardColors.map((c) => c.toUpperCase()).toSet();
          
          // Carta é válida se todas suas cores estão dentro da identidade do commander
          // OU se é colorless (sem cores)
          if (cardColorSet.isEmpty || cardColorSet.every((c) => colorSet.contains(c))) {
            uniqueCards[cardId] = card;
          }
        }
      }
    }
    
    // Shuffle e pegar o número necessário
    final allCards = uniqueCards.values.toList();
    allCards.shuffle(random);
    return allCards.take(count).toList();
  }

  Future<String> createDeck(String name, String commanderId, List<Map<String, dynamic>> cards) async {
    final cardPayload = cards.map((c) {
      final id = c['id']?.toString() ?? c['card_id']?.toString();
      return {
        'card_id': id,
        'quantity': 1,
        'is_commander': c['id']?.toString() == commanderId,
      };
    }).toList();

    final res = await http.post(
      Uri.parse('$apiUrl/decks'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'format': 'commander',
        'description': 'E2E Debate Test Deck',
        'cards': cardPayload,
      }),
    );

    if (res.statusCode == 201 || res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['deck']?['id'] ?? data['id']).toString();
    }
    throw Exception('Create deck failed: ${res.statusCode} - ${res.body}');
  }

  Future<Map<String, dynamic>> optimizeDeck(String deckId, {String? archetype}) async {
    final body = <String, dynamic>{'deck_id': deckId};
    if (archetype != null) {
      body['archetype'] = archetype;
    }

    final res = await http.post(
      Uri.parse('$apiUrl/ai/optimize'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Optimize failed: ${res.statusCode} - ${res.body}');
  }

  Future<void> runSingleTest(int testNumber) async {
    print('\n${'─'*70}');
    print('🧪 TESTE #$testNumber');
    print('─'*70);
    
    final stopwatch = Stopwatch()..start();
    
    try {
      // 1. Buscar commander
      final commander = await fetchRandomCommander();
      final commanderName = commander['name'] as String;
      final commanderColors = (commander['colors'] as List?)?.cast<String>() ?? ['U'];
      final commanderId = commander['id']?.toString() ?? '';
      
      print('  Commander: $commanderName (${commanderColors.join("")})');
      
      // 2. Buscar cartas nas cores
      final targetCount = 40 + random.nextInt(50); // 40-89 cartas
      final isComplete = targetCount < 90;
      final mode = isComplete ? 'complete' : 'optimize';
      
      final cards = await fetchCardsInColors(commanderColors, targetCount);
      print('  Cards iniciais: ${cards.length} (modo: $mode)');
      
      // 3. Criar deck
      final deckId = await createDeck(
        'Debate Test #$testNumber - $commanderName',
        commanderId,
        [commander, ...cards],
      );
      print('  Deck criado: $deckId');
      
      // 4. Arquétipos para teste (sem null - archetype é obrigatório na API)
      final archetypes = ['Aggro', 'Control', 'Midrange', 'Combo', 'Tempo', 'Ramp'];
      final archetype = archetypes[random.nextInt(archetypes.length)];
      
      // 5. Otimizar
      print('  Otimizando... (archetype: ${archetype ?? "auto"})');
      final optimizeResult = await optimizeDeck(deckId, archetype: archetype);
      
      stopwatch.stop();
      print('  ✅ Concluído em ${stopwatch.elapsedMilliseconds}ms');
      
      // 6. Coletar dados
      final theme = optimizeResult['theme'] as Map<String, dynamic>? ?? {};
      final edhrecValidation = optimizeResult['edhrec_validation'] as Map<String, dynamic>?;
      final warnings = optimizeResult['validation_warnings'] as List? ?? [];
      final postAnalysis = optimizeResult['post_analysis'] as Map<String, dynamic>? ?? {};
      final validation = postAnalysis['validation'] as Map<String, dynamic>? ?? {};
      
      // Verificar se modo híbrido foi usado
      final hybridUsed = warnings.any((w) => w.toString().contains('HÍBRIDA') || w.toString().contains('híbrido'));
      
      final data = OptimizationData(
        testNumber: testNumber,
        commanderName: commanderName,
        commanderColors: commanderColors,
        operationMode: optimizeResult['mode']?.toString() ?? mode,
        initialCardCount: cards.length + 1,
        finalCardCount: (optimizeResult['additions'] as List?)?.length ?? 0 + cards.length + 1,
        targetArchetype: archetype,
        detectedTheme: theme['theme']?.toString(),
        edhrecThemes: (edhrecValidation?['themes'] as List?)?.cast<String>() ?? [],
        themeMatch: !hybridUsed,
        hybridModeUsed: hybridUsed,
        beforeAnalysis: optimizeResult['deck_analysis'] as Map<String, dynamic>? ?? {},
        afterAnalysis: postAnalysis,
        removals: (optimizeResult['removals'] as List?)?.cast<String>() ?? [],
        additions: (optimizeResult['additions'] as List?)?.cast<String>() ?? [],
        validationScore: validation['validation_score'] as int?,
        validationVerdict: validation['verdict']?.toString(),
        colorIdentityViolations: (warnings.where((w) => w.toString().contains('identidade de cor')).length),
        edhrecValidatedCount: (edhrecValidation?['additions_validated'] as int?) ?? 0,
        edhrecNotValidatedCount: (edhrecValidation?['additions_not_in_edhrec'] as List?)?.length ?? 0,
        validationWarnings: warnings.map((w) => w.toString()).toList(),
        executionTimeMs: stopwatch.elapsedMilliseconds,
        fullResponse: optimizeResult,
      );
      
      collectedData.add(data);
      
    } catch (e) {
      print('  ❌ Erro: $e');
    }
  }

  Future<void> runAllTests(int runs) async {
    testRunId = 'test_${DateTime.now().millisecondsSinceEpoch}';
    print('\n${'═'*70}');
    print('🚀 INICIANDO SUITE E2E COM DEBATE');
    print('═'*70);
    print('API: $apiUrl');
    print('Testes: $runs');
    print('Run ID: $testRunId');
    print('═'*70);
    
    await connectDatabase();
    await registerAndLogin();
    
    for (var i = 1; i <= runs; i++) {
      await runSingleTest(i);
      if (i < runs) {
        await Future.delayed(Duration(seconds: 2)); // Evitar rate limiting
      }
    }
    
    print('\n${'═'*70}');
    print('📊 FASE DE DEBATE/ANÁLISE');
    print('═'*70);
    
    for (final data in collectedData) {
      final debate = OptimizationDebate(data);
      debates.add(debate);
      debate.printDebate();
    }
    
    await saveToDatabase();
    await printSummary();
    
    await pool?.close();
  }

  Future<void> saveToDatabase() async {
    if (pool == null) return;
    
    print('\n💾 Salvando análises no banco de dados...');
    
    for (final debate in debates) {
      final d = debate.data;
      try {
        await pool!.execute(
          Sql.named('''
            INSERT INTO optimization_analysis_logs (
              test_run_id, test_number, commander_name, commander_colors,
              initial_card_count, final_card_count, operation_mode, target_archetype,
              detected_theme, edhrec_themes, theme_match, hybrid_mode_used,
              before_avg_cmc, before_land_count, before_creature_count,
              after_avg_cmc, after_land_count, after_creature_count,
              removals_count, additions_count, removals_list, additions_list,
              validation_score, validation_verdict,
              color_identity_violations, edhrec_validated_count, edhrec_not_validated_count,
              validation_warnings, decisions_reasoning, swap_analysis, role_delta,
              execution_time_ms, effectiveness_score, improvements_achieved,
              potential_issues, alternative_approaches, lessons_learned
            ) VALUES (
              @test_run_id, @test_number, @commander_name, @commander_colors,
              @initial_card_count, @final_card_count, @operation_mode, @target_archetype,
              @detected_theme, @edhrec_themes, @theme_match, @hybrid_mode_used,
              @before_avg_cmc, @before_land_count, @before_creature_count,
              @after_avg_cmc, @after_land_count, @after_creature_count,
              @removals_count, @additions_count, @removals_list::jsonb, @additions_list::jsonb,
              @validation_score, @validation_verdict,
              @color_identity_violations, @edhrec_validated_count, @edhrec_not_validated_count,
              @validation_warnings::jsonb, @decisions_reasoning::jsonb, @swap_analysis::jsonb, @role_delta::jsonb,
              @execution_time_ms, @effectiveness_score, @improvements_achieved::jsonb,
              @potential_issues::jsonb, @alternative_approaches::jsonb, @lessons_learned
            )
          '''),
          parameters: {
            'test_run_id': testRunId,
            'test_number': d.testNumber,
            'commander_name': d.commanderName,
            'commander_colors': d.commanderColors,
            'initial_card_count': d.initialCardCount,
            'final_card_count': d.finalCardCount,
            'operation_mode': d.operationMode,
            'target_archetype': d.targetArchetype,
            'detected_theme': d.detectedTheme,
            'edhrec_themes': d.edhrecThemes,
            'theme_match': d.themeMatch,
            'hybrid_mode_used': d.hybridModeUsed,
            'before_avg_cmc': _parseDouble(d.beforeAnalysis['average_cmc']),
            'before_land_count': (d.beforeAnalysis['type_distribution'] as Map?)?['lands'] ?? 0,
            'before_creature_count': (d.beforeAnalysis['type_distribution'] as Map?)?['creatures'] ?? 0,
            'after_avg_cmc': _parseDouble(d.afterAnalysis['average_cmc']),
            'after_land_count': (d.afterAnalysis['type_distribution'] as Map?)?['lands'] ?? 0,
            'after_creature_count': (d.afterAnalysis['type_distribution'] as Map?)?['creatures'] ?? 0,
            'removals_count': d.removals.length,
            'additions_count': d.additions.length,
            'removals_list': jsonEncode(d.removals),
            'additions_list': jsonEncode(d.additions),
            'validation_score': d.validationScore,
            'validation_verdict': d.validationVerdict,
            'color_identity_violations': d.colorIdentityViolations,
            'edhrec_validated_count': d.edhrecValidatedCount,
            'edhrec_not_validated_count': d.edhrecNotValidatedCount,
            'validation_warnings': jsonEncode(d.validationWarnings),
            'decisions_reasoning': jsonEncode(debate.decisionsReasoning),
            'swap_analysis': jsonEncode(debate.swapAnalysis),
            'role_delta': jsonEncode(debate.roleDelta),
            'execution_time_ms': d.executionTimeMs,
            'effectiveness_score': debate.effectivenessScore,
            'improvements_achieved': jsonEncode(debate.improvementsAchieved),
            'potential_issues': jsonEncode(debate.potentialIssues),
            'alternative_approaches': jsonEncode(debate.alternativeApproaches),
            'lessons_learned': debate.lessonsLearned,
          },
        );
        print('  ✅ Teste #${d.testNumber} salvo');
      } catch (e) {
        print('  ⚠️ Erro ao salvar teste #${d.testNumber}: $e');
      }
    }
  }
  
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Future<void> printSummary() async {
    print('\n${'═'*70}');
    print('📈 RESUMO FINAL DA BATERIA DE TESTES');
    print('═'*70);
    
    if (collectedData.isEmpty) {
      print('\n⚠️ Nenhum teste completou com sucesso.');
      print('   Verifique os logs de erro acima.');
      print('═'*70);
      return;
    }
    
    final avgEffectiveness = debates.isEmpty ? 0.0 :
        debates.map((d) => d.effectivenessScore).reduce((a, b) => a + b) / debates.length;
    
    final avgTime = collectedData.map((d) => d.executionTimeMs).reduce((a, b) => a + b) ~/ collectedData.length;
    
    final hybridCount = collectedData.where((d) => d.hybridModeUsed).length;
    final colorViolations = collectedData.map((d) => d.colorIdentityViolations).reduce((a, b) => a + b);
    
    final allImprovements = <String>[];
    final allIssues = <String>[];
    for (final debate in debates) {
      allImprovements.addAll(debate.improvementsAchieved);
      allIssues.addAll(debate.potentialIssues);
    }
    
    print('\n📊 ESTATÍSTICAS GERAIS:');
    print('  Testes executados: ${collectedData.length}');
    print('  Efetividade média: ${avgEffectiveness.toStringAsFixed(1)}/100');
    print('  Tempo médio: ${avgTime}ms');
    print('  Modo híbrido usado: $hybridCount/${collectedData.length}');
    print('  Violações de cor total: $colorViolations');
    
    print('\n✅ MELHORIAS MAIS COMUNS:');
    final improvementCounts = <String, int>{};
    for (final imp in allImprovements) {
      final key = imp.split(':').first;
      improvementCounts[key] = (improvementCounts[key] ?? 0) + 1;
    }
    improvementCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(5).forEach((e) => print('  ${e.value}x ${e.key}'));
    
    print('\n⚠️ PROBLEMAS MAIS COMUNS:');
    final issueCounts = <String, int>{};
    for (final issue in allIssues) {
      final key = issue.split(':').first;
      issueCounts[key] = (issueCounts[key] ?? 0) + 1;
    }
    issueCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(5).forEach((e) => print('  ${e.value}x ${e.key}'));
    
    print('\n🎯 CONCLUSÕES:');
    if (avgEffectiveness >= 65) {
      print('  🟢 Sistema de otimização tem boa efetividade geral');
    } else if (avgEffectiveness >= 50) {
      print('  🟡 Efetividade moderada - há espaço para melhorias');
    } else {
      print('  🔴 Efetividade baixa - revisar algoritmo urgentemente');
    }
    
    if (hybridCount > collectedData.length * 0.3) {
      print('  🔀 Modo híbrido usado frequentemente - usuários tendem a builds off-meta');
    }
    
    if (colorViolations > collectedData.length) {
      print('  ⚠️ Muitas violações de cor - melhorar filtros de identidade');
    }
    
    print('\n📦 Dados salvos em: optimization_analysis_logs');
    print('   Run ID: $testRunId');
    print('═'*70);
  }
}

Future<void> main(List<String> args) async {
  var runs = 10;
  var apiUrl = defaultApiUrl;
  
  for (final arg in args) {
    if (arg.startsWith('--runs=')) {
      runs = int.tryParse(arg.split('=')[1]) ?? 10;
    } else if (arg.startsWith('--api=')) {
      apiUrl = arg.split('=')[1];
    }
  }
  
  final suite = E2EDebateSuite(apiUrl);
  await suite.runAllTests(runs);
}
