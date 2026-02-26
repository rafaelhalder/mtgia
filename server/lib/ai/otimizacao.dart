import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import '../ai_log_service.dart';
import '../logger.dart';
import '../ml_knowledge_service.dart';
import '../openai_runtime_config.dart';
import 'edhrec_service.dart';
import 'sinergia.dart';

class DeckOptimizerService {
  final String openAiKey;
  final SynergyEngine synergyEngine;
  final EdhrecService edhrecService;
  final AiLogService? _logService;
  final MLKnowledgeService? _mlService;

  DeckOptimizerService(this.openAiKey, {dynamic db})
      : synergyEngine = SynergyEngine(),
        edhrecService = EdhrecService(),
        _logService = db != null ? AiLogService(db) : null,
        _mlService = db != null ? MLKnowledgeService(db) : null;

  /// O fluxo principal de otimização
  Future<Map<String, dynamic>> optimizeDeck({
    required Map<String, dynamic> deckData,
    required List<String> commanders,
    required String targetArchetype,
    int? bracket,
    bool keepTheme = true,
    String? detectedTheme,
    List<String>? coreCards,
    String? userId,
    String? deckId,
  }) async {
    final List<dynamic> currentCards = deckData['cards'];
    final List<String> colors = List<String>.from(deckData['colors']);

    // 0. BUSCA DE DADOS EDHREC (co-ocorrência real)
    // Esta é a fonte mais confiável: dados de milhões de decks reais.
    // Cartas frequentemente usadas juntas têm sinergia comprovada.
    // NOTA: Pular se não há comandante (Modern, Standard, etc.)
    EdhrecCommanderData? edhrecData;
    if (commanders.isNotEmpty) {
      edhrecData = await edhrecService.fetchCommanderData(commanders.firstOrNull ?? "");
      if (edhrecData != null) {
        Log.i('EDHREC: ${edhrecData.deckCount} decks analisados, ${edhrecData.topCards.length} cartas, temas: ${edhrecData.themes.join(", ")}');
      }
    }

    // 1. ANÁLISE QUANTITATIVA (O que a IA "acha" vs O que os dados dizem)
    // Classificamos as cartas atuais por "Score de Eficiência"
    // Score = (Popularidade EDHREC) / (CMC + 1) -> Cartas populares e baratas têm score alto
    //
    // CORREÇÃO: Agora considera sinergia com o comandante.
    // Cartas que compartilham keywords mecânicos com o commander recebem bônus.
    // MELHORIA: Também usa dados reais do EDHREC quando disponíveis.
    final commanderKeywords = _extractMechanicKeywords(commanders, currentCards);
    final scoredCards = _calculateEfficiencyScoresWithEdhrec(
      currentCards,
      commanderKeywords,
      edhrecData,
    );

    // Identifica as 15 cartas estatisticamente mais fracas (Candidatas a corte)
    // Isso ajuda a IA a não tentar tirar staples
    final weakCandidates = scoredCards.take(15).toList();

    // 2. BUSCA DE SINERGIA CONTEXTUAL (RAG + EDHREC)
    // Prioriza dados EDHREC (co-ocorrência real), com fallback para Scryfall
    // HÍBRIDO: Se tema detectado não bate com EDHREC, mistura 70% EDHREC + 30% tema
    List<String> synergyCards;
    bool themeMatchesEdhrec = false;
    
    if (edhrecData != null && edhrecData.topCards.isNotEmpty) {
      // Verificar se tema detectado corresponde aos temas EDHREC
      final edhrecThemesLower = edhrecData.themes.map((t) => t.toLowerCase()).toList();
      final targetLower = targetArchetype.toLowerCase();
      
      for (final edhrecTheme in edhrecThemesLower) {
        if (targetLower.contains(edhrecTheme) || edhrecTheme.contains(targetLower)) {
          themeMatchesEdhrec = true;
          break;
        }
      }
      
      if (themeMatchesEdhrec) {
        // Tema bate: usar 100% EDHREC
        synergyCards = edhrecService
            .getHighSynergyCards(edhrecData, minSynergy: 0.15, limit: 40)
            .map((c) => c.name)
            .toList();
        Log.i('EDHREC synergy pool (theme match): ${synergyCards.length} cartas');
      } else {
        // Tema NÃO bate: HÍBRIDO 70% EDHREC + 30% tema do usuário
        final edhrecCards = edhrecService
            .getHighSynergyCards(edhrecData, minSynergy: 0.1, limit: 30)
            .map((c) => c.name)
            .toList();
        
        // Buscar cartas do tema do usuário (Scryfall/archetype)
        final themeCards = await synergyEngine.fetchCommanderSynergies(
          commanderName: commanders.firstOrNull ?? "",
          colors: colors,
          archetype: targetArchetype,
        );
        
        // Misturar: 70% EDHREC + 30% tema (sem duplicatas)
        final edhrecPortion = (edhrecCards.length * 0.7).round();
        final themePortion = (themeCards.length * 0.3).round().clamp(0, 15);
        
        synergyCards = [
          ...edhrecCards.take(edhrecPortion),
          ...themeCards.where((c) => !edhrecCards.contains(c)).take(themePortion),
        ];
        
        Log.i('HYBRID synergy pool: ${edhrecPortion} EDHREC + ${themePortion} theme ($targetArchetype) = ${synergyCards.length} cartas');
      }
    } else {
      // Fallback: busca no Scryfall
      synergyCards = await synergyEngine.fetchCommanderSynergies(
          commanderName: commanders.firstOrNull ?? '',
          colors: colors,
          archetype: targetArchetype);
    }

    // 3. RECUPERAÇÃO DE DADOS DE META (Staples de formato)
    final formatStaples = await _fetchFormatStaples(colors, targetArchetype);

    // 3.5. CONSULTA AO CONHECIMENTO ML (Imitation Learning)
    // Busca padrões aprendidos dos meta decks e sinergias conhecidas
    String? mlContext;
    if (_mlService != null) {
      try {
        final mlData = await _mlService!.getContextForDeck(
          archetype: targetArchetype,
          format: 'commander',
          commanderName: commanders.firstOrNull,
          currentCards: currentCards.map((c) => c['name'].toString()).toList(),
        );
        mlContext = _mlService!.generatePromptContext(mlData);
        Log.i('ML Knowledge: ${mlData.recommendations.length} recomendações, ${mlData.relevantSynergies.length} sinergias (${mlData.queryTimeMs}ms)');
      } catch (e) {
        Log.w('ML Knowledge error (continuando sem): $e');
      }
    }

    // 4. CONSTRUÇÃO DO PROMPT RICO
    // Juntamos tudo para enviar à IA
    final optimizationResult = await _callOpenAI(
      deckList: currentCards.map((c) => c['name'].toString()).toList(),
      commanders: commanders,
      weakCandidates: weakCandidates.map((c) => c['name'].toString()).toList(),
      synergyPool: synergyCards,
      staplesPool: formatStaples,
      archetype: targetArchetype,
      bracket: bracket,
      keepTheme: keepTheme,
      detectedTheme: detectedTheme,
      coreCards: coreCards,
      userId: userId,
      deckId: deckId,
      mlContext: mlContext,
    );

    return optimizationResult;
  }

  /// Completa um deck incompleto (gera apenas adições).
  Future<Map<String, dynamic>> completeDeck({
    required Map<String, dynamic> deckData,
    required List<String> commanders,
    required String targetArchetype,
    required int targetAdditions,
    int? bracket,
    bool keepTheme = true,
    String? detectedTheme,
    List<String>? coreCards,
    String? userId,
    String? deckId,
  }) async {
    final List<dynamic> currentCards = deckData['cards'];
    final List<String> colors = List<String>.from(deckData['colors']);

    // Busca dados EDHREC para sugestões mais precisas
    // HÍBRIDO: Se tema detectado não bate com EDHREC, mistura 70% EDHREC + 30% tema
    final edhrecData = await edhrecService.fetchCommanderData(commanders.firstOrNull ?? "");
    
    List<String> synergyCards;
    bool themeMatchesEdhrec = false;
    
    if (edhrecData != null && edhrecData.topCards.isNotEmpty) {
      // Verificar se tema detectado corresponde aos temas EDHREC
      final edhrecThemesLower = edhrecData.themes.map((t) => t.toLowerCase()).toList();
      final targetLower = targetArchetype.toLowerCase();
      
      for (final edhrecTheme in edhrecThemesLower) {
        if (targetLower.contains(edhrecTheme) || edhrecTheme.contains(targetLower)) {
          themeMatchesEdhrec = true;
          break;
        }
      }
      
      if (themeMatchesEdhrec) {
        // Tema bate: usar 100% EDHREC
        synergyCards = edhrecService
            .getHighSynergyCards(edhrecData, minSynergy: 0.1, limit: 60)
            .map((c) => c.name)
            .toList();
        Log.i('EDHREC complete pool (theme match): ${synergyCards.length} cartas');
      } else {
        // Tema NÃO bate: HÍBRIDO 70% EDHREC + 30% tema do usuário
        final edhrecCards = edhrecService
            .getHighSynergyCards(edhrecData, minSynergy: 0.08, limit: 45)
            .map((c) => c.name)
            .toList();
        
        // Buscar cartas do tema do usuário (Scryfall/archetype)
        final themeCards = await synergyEngine.fetchCommanderSynergies(
          commanderName: commanders.firstOrNull ?? "",
          colors: colors,
          archetype: targetArchetype,
        );
        
        // Misturar: 70% EDHREC + 30% tema (sem duplicatas)
        final edhrecPortion = (edhrecCards.length * 0.7).round();
        final themePortion = (themeCards.length * 0.3).round().clamp(0, 20);
        
        synergyCards = [
          ...edhrecCards.take(edhrecPortion),
          ...themeCards.where((c) => !edhrecCards.contains(c)).take(themePortion),
        ];
        
        Log.i('HYBRID complete pool: ${edhrecPortion} EDHREC + ${themePortion} theme ($targetArchetype) = ${synergyCards.length} cartas');
      }
    } else {
      // Fallback para Scryfall
      synergyCards = await synergyEngine.fetchCommanderSynergies(
        commanderName: commanders.firstOrNull ?? "",
        colors: colors,
        archetype: targetArchetype,
      );
    }

    final formatStaples = await _fetchFormatStaples(colors, targetArchetype);

    // CONSULTA AO CONHECIMENTO ML (Imitation Learning) para complete
    String? mlContext;
    if (_mlService != null) {
      try {
        final mlData = await _mlService!.getContextForDeck(
          archetype: targetArchetype,
          format: 'commander',
          commanderName: commanders.firstOrNull,
          currentCards: currentCards.map((c) => c['name'].toString()).toList(),
        );
        mlContext = _mlService!.generatePromptContext(mlData);
        Log.i('ML Knowledge (complete): ${mlData.recommendations.length} recomendações (${mlData.queryTimeMs}ms)');
      } catch (e) {
        Log.w('ML Knowledge error (continuando sem): $e');
      }
    }

    final completionResult = await _callOpenAIComplete(
      deckList: currentCards.map((c) => c['name'].toString()).toList(),
      commanders: commanders,
      synergyPool: synergyCards,
      staplesPool: formatStaples,
      archetype: targetArchetype,
      bracket: bracket,
      targetAdditions: targetAdditions,
      keepTheme: keepTheme,
      detectedTheme: detectedTheme,
      coreCards: coreCards,
      userId: userId,
      deckId: deckId,
      mlContext: mlContext,
    );

    return completionResult;
  }

  /// Extrai keywords mecânicos do commander para detecção de sinergia.
  /// Analisa o oracle_text do commander e retorna keywords relevantes.
  Set<String> _extractMechanicKeywords(
      List<String> commanders, List<dynamic> currentCards) {
    final keywords = <String>{};
    for (final cmdr in commanders) {
      Map<String, dynamic>? cmdrCard;
      for (final c in currentCards) {
        if ((c['name'] as String?)?.toLowerCase() == cmdr.toLowerCase()) {
          cmdrCard = c as Map<String, dynamic>;
          break;
        }
      }
      if (cmdrCard == null) continue;
      final oracle =
          ((cmdrCard['oracle_text'] as String?) ?? '').toLowerCase();
      final typeLine =
          ((cmdrCard['type_line'] as String?) ?? '').toLowerCase();

      // Mecânicas comuns — keywords de sinergia
      const mechanicPatterns = [
        'artifact', 'enchantment', 'token', 'sacrifice', 'graveyard',
        'counter', 'draw', 'discard', 'exile', 'mill', 'scry',
        'flying', 'trample', 'lifelink', 'deathtouch',
        'enter', 'leaves', 'dies', 'cast', 'noncreature',
        'instant', 'sorcery', 'equipment', 'aura', 'creature',
        '+1/+1', 'proliferate', 'energy', 'treasure', 'food', 'clue',
        'landfall', 'land', 'historic', 'legendary',
      ];

      for (final pattern in mechanicPatterns) {
        if (oracle.contains(pattern) || typeLine.contains(pattern)) {
          keywords.add(pattern);
        }
      }
    }
    return keywords;
  }

  /// Calcula um score heurístico para identificar cartas suspeitas de serem ruins.
  /// Baseado no Rank EDHREC (se tiver no DB), CMC e sinergia com o commander.
  ///
  /// MELHORIA v2: Cartas que compartilham keywords mecânicos com o commander
  /// recebem bônus de sinergia (score ÷2), evitando que peças sinérgicas
  /// sejam erroneamente marcadas como "fracas" só por serem impopulares globalmente.
  List<Map<String, dynamic>> _calculateEfficiencyScores(
      List<dynamic> cards, Set<String> commanderKeywords) {
    // Primeiro, calcula a mediana do EDHREC rank das cartas que têm rank
    final ranksWithValue = cards
        .where((c) => c['edhrec_rank'] != null)
        .map((c) => c['edhrec_rank'] as int)
        .toList();

    // Calcula a mediana do deck (ou usa 5000 como fallback razoável)
    // Nota: Usamos divisão inteira (~/) pois ranks são inteiros e a precisão
    // de 1 unidade não afeta significativamente o score final
    int medianRank = 5000;
    if (ranksWithValue.isNotEmpty) {
      ranksWithValue.sort();
      final mid = ranksWithValue.length ~/ 2;
      medianRank = ranksWithValue.length.isOdd
          ? ranksWithValue[mid]
          : ((ranksWithValue[mid - 1] + ranksWithValue[mid]) ~/ 2);
    }

    var scored = cards.map((card) {
      // Para cartas sem rank (novas ou de nicho), usa a mediana do deck
      // Isso evita penalizar injustamente cartas recém-lançadas
      final rank = (card['edhrec_rank'] as int?) ?? medianRank;
      final cmc = (card['cmc'] as num?)?.toDouble() ?? 0.0;

      // Lógica: Rank baixo é bom (ex: Sol Ring é rank 1). CMC baixo é bom.
      // Score Alto = Carta Ruim (Rank alto + Custo alto)
      // Ajuste para terrenos: Terrenos básicos sempre têm score "neutro" para não serem cortados automaticamente
      if ((card['type_line'] as String).contains('Basic Land')) {
        return {'name': card['name'], 'weakness_score': -1.0};
      }

      final score =
          rank * (cmc > 4 ? 1.5 : 1.0); // Penaliza cartas caras impopulares

      // BÔNUS DE SINERGIA: se a carta compartilha keywords com o commander,
      // ela provavelmente está no deck por uma razão — reduz o score de fraqueza.
      final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
      final typeLine2 = ((card['type_line'] as String?) ?? '').toLowerCase();
      var synergyHits = 0;
      for (final kw in commanderKeywords) {
        if (oracle.contains(kw) || typeLine2.contains(kw)) synergyHits++;
      }
      // 2+ keywords em comum → score ÷2 (forte sinergia)
      // 1 keyword → score ×0.7
      final adjustedScore = synergyHits >= 2
          ? score / 2
          : synergyHits == 1
              ? score * 0.7
              : score;

      return {'name': card['name'], 'weakness_score': adjustedScore};
    }).toList();

    // Ordena do maior score (pior carta) para o menor
    scored.sort((a, b) => (b['weakness_score'] as double)
        .compareTo(a['weakness_score'] as double));

    // Remove terrenos básicos da lista de "ruins"
    scored.removeWhere((c) => (c['weakness_score'] as double) < 0);

    return scored;
  }

  /// Versão aprimorada que usa dados reais do EDHREC para scoring.
  /// 
  /// Se a carta está na lista de co-ocorrência do EDHREC para este commander,
  /// ela é considerada "comprovadamente sinérgica" e recebe um bônus massivo,
  /// removendo-a das candidatas a corte.
  /// 
  /// Isso evita o erro clássico de a IA cortar cartas "impopulares globalmente"
  /// mas que são perfeitas para aquele commander específico.
  List<Map<String, dynamic>> _calculateEfficiencyScoresWithEdhrec(
    List<dynamic> cards,
    Set<String> commanderKeywords,
    EdhrecCommanderData? edhrecData,
  ) {
    // Se não temos dados EDHREC, usa o método original
    if (edhrecData == null) {
      return _calculateEfficiencyScores(cards, commanderKeywords);
    }

    // Primeiro, calcula a mediana do EDHREC rank das cartas que têm rank
    final ranksWithValue = cards
        .where((c) => c['edhrec_rank'] != null)
        .map((c) => c['edhrec_rank'] as int)
        .toList();

    int medianRank = 5000;
    if (ranksWithValue.isNotEmpty) {
      ranksWithValue.sort();
      final mid = ranksWithValue.length ~/ 2;
      medianRank = ranksWithValue.length.isOdd
          ? ranksWithValue[mid]
          : ((ranksWithValue[mid - 1] + ranksWithValue[mid]) ~/ 2);
    }

    var scored = cards.map((card) {
      final cardName = card['name'] as String;
      
      // Terrenos básicos: sempre protegidos
      if ((card['type_line'] as String).contains('Basic Land')) {
        return {'name': cardName, 'weakness_score': -1.0};
      }

      final rank = (card['edhrec_rank'] as int?) ?? medianRank;
      final cmc = (card['cmc'] as num?)?.toDouble() ?? 0.0;
      
      // Score base: rank alto + CMC alto = ruim
      var score = rank * (cmc > 4 ? 1.5 : 1.0);

      // VERIFICAÇÃO EDHREC: se a carta está nas top do commander, protege ela
      final edhrecCard = edhrecData.findCard(cardName);
      if (edhrecCard != null) {
        // Carta está na lista do EDHREC para este commander!
        // Synergy > 0.3 = muito sinérgica → score ÷4
        // Synergy > 0.15 = sinérgica → score ÷2.5
        // Synergy > 0 = alguma sinergia → score ÷1.5
        // Synergy <= 0 = staple genérica (pode ser cortada se necessário)
        if (edhrecCard.synergy > 0.3) {
          score /= 4;
          Log.d('EDHREC: $cardName é muito sinérgica (${edhrecCard.synergy.toStringAsFixed(2)}) - protegida');
        } else if (edhrecCard.synergy > 0.15) {
          score /= 2.5;
        } else if (edhrecCard.synergy > 0) {
          score /= 1.5;
        }
        // Bônus adicional por inclusion alta (muita gente usa)
        if (edhrecCard.inclusion > 0.5) {
          score *= 0.8; // Reduz score (protege)
        }
      } else {
        // Carta NÃO está no EDHREC para este commander
        // Pode ser carta nova, ou carta que não comba bem
        // Usa o método de keywords como fallback
        final oracle = ((card['oracle_text'] as String?) ?? '').toLowerCase();
        final typeLine2 = ((card['type_line'] as String?) ?? '').toLowerCase();
        var synergyHits = 0;
        for (final kw in commanderKeywords) {
          if (oracle.contains(kw) || typeLine2.contains(kw)) synergyHits++;
        }
        if (synergyHits >= 2) {
          score /= 2;
        } else if (synergyHits == 1) {
          score *= 0.7;
        }
      }

      return {'name': cardName, 'weakness_score': score};
    }).toList();

    // Ordena do maior score (pior carta) para o menor
    scored.sort((a, b) => (b['weakness_score'] as double)
        .compareTo(a['weakness_score'] as double));

    // Remove terrenos básicos da lista
    scored.removeWhere((c) => (c['weakness_score'] as double) < 0);

    return scored;
  }

  Future<List<String>> _fetchFormatStaples(
      List<String> colors, String archetype) async {
    // Busca staples genéricas das cores do deck (ordenadas por EDHREC rank via _searchScryfall)
    final colorQuery = colors.isEmpty ? "c:c" : "id<=${colors.join('')}";
    // Ex: "format:commander -is:banned id<=UB"
    final query = "format:commander -is:banned $colorQuery";

    return await synergyEngine.searchScryfall(query);
  }

  Future<Map<String, dynamic>> _callOpenAI({
    required List<String> deckList,
    required List<String> commanders,
    required List<String> weakCandidates,
    required List<String> synergyPool,
    required List<String> staplesPool,
    required String archetype,
    int? bracket,
    required bool keepTheme,
    String? detectedTheme,
    List<String>? coreCards,
    String? userId,
    String? deckId,
    String? mlContext,
  }) async {
    final stopwatch = Stopwatch()..start();
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final aiConfig = OpenAiRuntimeConfig(env);
    final model = aiConfig.modelFor(
      key: 'OPENAI_MODEL_OPTIMIZE',
      fallback: 'gpt-4o',
    );
    final temperature = aiConfig.temperatureFor(
      key: 'OPENAI_TEMP_OPTIMIZE',
      fallback: 0.3,
    );

    // Calcular número dinâmico de trocas baseado na qualidade do deck
    // Mais cartas fracas = mais trocas sugeridas
    final weakCount = weakCandidates.length;
    final suggestedSwaps = weakCount <= 5 ? weakCount.clamp(2, 5)
        : weakCount <= 10 ? (weakCount * 0.7).round().clamp(4, 8)
        : (weakCount * 0.5).round().clamp(6, 12);
    
    Log.d('Trocas dinâmicas: $suggestedSwaps (baseado em $weakCount cartas fracas)');

    final userPrompt = jsonEncode({
      "commander": commanders.join(" & "),
      "archetype": archetype,
      "bracket": bracket,
      "suggested_swaps": suggestedSwaps,  // Número dinâmico de trocas
      "constraints": {
        "keep_theme": keepTheme,
        if (detectedTheme != null) "deck_theme": detectedTheme,
        if (coreCards != null && coreCards.isNotEmpty) "core_cards": coreCards,
        "notes":
            "Se keep_theme=true: NÃO mude o plano/tema do deck; preserve as core_cards (nunca remover).",
      },
      "context": {
        "statistically_weak_cards":
            weakCandidates, // A IA vai olhar isso com carinho para cortar
        "high_synergy_options":
            synergyPool, // A IA vai escolher daqui para adicionar
        "format_staples": staplesPool,
        if (mlContext != null) "ml_knowledge": mlContext,
      },
      "current_decklist": deckList
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openAiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': _getSystemPrompt()
            }, // Função que retorna o texto do arquivo Markdown
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': temperature,
          'response_format': {"type": "json_object"}
        }),
      );

      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final result = jsonDecode(data['choices'][0]['message']['content']);

        // Log de sucesso
        await _logService?.log(
          userId: userId,
          deckId: deckId,
          endpoint: 'optimize',
            model: model,
          promptSummary:
              'Commander: ${commanders.join(" & ")}, Archetype: $archetype, Bracket: $bracket',
          responseSummary: result['summary']?.toString(),
          latencyMs: stopwatch.elapsedMilliseconds,
          inputTokens: data['usage']?['prompt_tokens'] as int?,
          outputTokens: data['usage']?['completion_tokens'] as int?,
          success: true,
        );

        return result;
      } else {
        // Log de erro
        await _logService?.log(
          userId: userId,
          deckId: deckId,
          endpoint: 'optimize',
            model: model,
          promptSummary:
              'Commander: ${commanders.join(" & ")}, Archetype: $archetype',
          latencyMs: stopwatch.elapsedMilliseconds,
          success: false,
          errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
        );
        throw Exception('Failed to optimize deck');
      }
    } catch (e) {
      stopwatch.stop();
      await _logService?.log(
        userId: userId,
        deckId: deckId,
        endpoint: 'optimize',
        model: model,
        promptSummary:
            'Commander: ${commanders.join(" & ")}, Archetype: $archetype',
        latencyMs: stopwatch.elapsedMilliseconds,
        success: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  String _getSystemPrompt() {
    try {
      // Tenta localizar o arquivo prompt.md relativo ao diretório de execução (server/)
      var file = File('lib/ai/prompt.md');

      if (!file.existsSync()) {
        // Tenta caminho alternativo caso esteja rodando da raiz
        file = File('server/lib/ai/prompt.md');
      }

      if (file.existsSync()) {
        return file.readAsStringSync();
      }

      Log.w('Arquivo prompt.md não encontrado em ${file.path}');
      return "Você é um especialista em otimização de decks de Magic: The Gathering.";
    } catch (e) {
      Log.e('Erro ao ler prompt.md: $e');
      return "Você é um especialista em otimização de decks de Magic: The Gathering.";
    }
  }

  Future<Map<String, dynamic>> _callOpenAIComplete({
    required List<String> deckList,
    required List<String> commanders,
    required List<String> synergyPool,
    required List<String> staplesPool,
    required String archetype,
    required int targetAdditions,
    int? bracket,
    required bool keepTheme,
    String? detectedTheme,
    List<String>? coreCards,
    String? userId,
    String? deckId,
    String? mlContext,
  }) async {
    final stopwatch = Stopwatch()..start();
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final aiConfig = OpenAiRuntimeConfig(env);
    final model = aiConfig.modelFor(
      key: 'OPENAI_MODEL_COMPLETE',
      fallback: 'gpt-4o',
    );
    final temperature = aiConfig.temperatureFor(
      key: 'OPENAI_TEMP_COMPLETE',
      fallback: 0.3,
    );

    final userPrompt = jsonEncode({
      "commander": commanders.join(" & "),
      "archetype": archetype,
      "bracket": bracket,
      "target_additions": targetAdditions,
      "constraints": {
        "keep_theme": keepTheme,
        if (detectedTheme != null) "deck_theme": detectedTheme,
        if (coreCards != null && coreCards.isNotEmpty) "core_cards": coreCards,
        "notes":
            "Se keep_theme=true: complete sem desviar do tema; preserve as core_cards (nunca sugerir remover).",
      },
      "context": {
        "high_synergy_options": synergyPool,
        "format_staples": staplesPool,
        if (mlContext != null) "ml_knowledge": mlContext,
      },
      "current_decklist": deckList
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openAiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': _getSystemPromptComplete()},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': temperature,
          'response_format': {"type": "json_object"}
        }),
      );

      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final result = jsonDecode(data['choices'][0]['message']['content']);

        // Log de sucesso
        await _logService?.log(
          userId: userId,
          deckId: deckId,
          endpoint: 'complete',
            model: model,
          promptSummary:
              'Commander: ${commanders.join(" & ")}, Archetype: $archetype, Additions: $targetAdditions',
          responseSummary: result['summary']?.toString(),
          latencyMs: stopwatch.elapsedMilliseconds,
          inputTokens: data['usage']?['prompt_tokens'] as int?,
          outputTokens: data['usage']?['completion_tokens'] as int?,
          success: true,
        );

        return result;
      }

      // Log de erro HTTP
      await _logService?.log(
        userId: userId,
        deckId: deckId,
        endpoint: 'complete',
        model: model,
        promptSummary:
            'Commander: ${commanders.join(" & ")}, Archetype: $archetype',
        latencyMs: stopwatch.elapsedMilliseconds,
        success: false,
        errorMessage: 'HTTP ${response.statusCode}',
      );
      throw Exception('Failed to complete deck');
    } catch (e) {
      stopwatch.stop();
      await _logService?.log(
        userId: userId,
        deckId: deckId,
        endpoint: 'complete',
        model: model,
        promptSummary:
            'Commander: ${commanders.join(" & ")}, Archetype: $archetype',
        latencyMs: stopwatch.elapsedMilliseconds,
        success: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  String _getSystemPromptComplete() {
    try {
      var file = File('lib/ai/prompt_complete.md');
      if (!file.existsSync()) {
        file = File('server/lib/ai/prompt_complete.md');
      }
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
      return 'Você é um especialista em construção de decks de Magic: The Gathering.';
    } catch (_) {
      return 'Você é um especialista em construção de decks de Magic: The Gathering.';
    }
  }
}
