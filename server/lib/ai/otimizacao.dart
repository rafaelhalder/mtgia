import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'sinergia.dart';
class DeckOptimizerService {
  final String openAiKey;
  final SynergyEngine synergyEngine;

  DeckOptimizerService(this.openAiKey) : synergyEngine = SynergyEngine();

  /// O fluxo principal de otimização
  Future<Map<String, dynamic>> optimizeDeck({
    required Map<String, dynamic> deckData,
    required List<String> commanders,
    required String targetArchetype,
  }) async {
    final List<dynamic> currentCards = deckData['cards'];
    final List<String> colors = List<String>.from(deckData['colors']);

    // 1. ANÁLISE QUANTITATIVA (O que a IA "acha" vs O que os dados dizem)
    // Classificamos as cartas atuais por "Score de Eficiência"
    // Score = (Popularidade EDHREC) / (CMC + 1) -> Cartas populares e baratas têm score alto
    final scoredCards = _calculateEfficiencyScores(currentCards);

    // Identifica as 15 cartas estatisticamente mais fracas (Candidatas a corte)
    // Isso ajuda a IA a não tentar tirar staples
    final weakCandidates = scoredCards.take(15).toList();

    // 2. BUSCA DE SINERGIA CONTEXTUAL (RAG)
    // Em vez de staples genéricos, buscamos o que comba com o Comandante
    final synergyCards = await synergyEngine.fetchCommanderSynergies(
      commanderName: commanders.first, 
      colors: colors,
      archetype: targetArchetype
    );

    // 3. RECUPERAÇÃO DE DADOS DE META (Staples de formato)
    final formatStaples = await _fetchFormatStaples(colors, targetArchetype);

    // 4. CONSTRUÇÃO DO PROMPT RICO
    // Juntamos tudo para enviar à IA
    final optimizationResult = await _callOpenAI(
      deckList: currentCards.map((c) => c['name'].toString()).toList(),
      commanders: commanders,
      weakCandidates: weakCandidates.map((c) => c['name'].toString()).toList(),
      synergyPool: synergyCards,
      staplesPool: formatStaples,
      archetype: targetArchetype,
    );

    return optimizationResult;
  }

  /// Calcula um score heurístico para identificar cartas suspeitas de serem ruins.
  /// Baseado no Rank EDHREC (se tiver no DB) e CMC.
  List<Map<String, dynamic>> _calculateEfficiencyScores(List<dynamic> cards) {
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

      final score = rank * (cmc > 4 ? 1.5 : 1.0); // Penaliza cartas caras impopulares
      return {'name': card['name'], 'weakness_score': score};
    }).toList();

    // Ordena do maior score (pior carta) para o menor
    scored.sort((a, b) => (b['weakness_score'] as double).compareTo(a['weakness_score'] as double));
    
    // Remove terrenos básicos da lista de "ruins"
    scored.removeWhere((c) => (c['weakness_score'] as double) < 0);
    
    return scored;
  }

  Future<List<String>> _fetchFormatStaples(List<String> colors, String archetype) async {
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
  }) async {
    final userPrompt = jsonEncode({
      "commander": commanders.join(" & "),
      "archetype": archetype,
      "context": {
        "statistically_weak_cards": weakCandidates, // A IA vai olhar isso com carinho para cortar
        "high_synergy_options": synergyPool, // A IA vai escolher daqui para adicionar
        "format_staples": staplesPool
      },
      "current_decklist": deckList
    });

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $openAiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o', // Recomendado GPT-4o ou 3.5-turbo-16k para melhor raciocínio
        'messages': [
          {'role': 'system', 'content': _getSystemPrompt()}, // Função que retorna o texto do arquivo Markdown
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.4, // Baixa temperatura para ser mais analítico e menos criativo
        'response_format': { "type": "json_object" }
      }),
    );

    if (response.statusCode == 200) {
       final data = jsonDecode(utf8.decode(response.bodyBytes));
       return jsonDecode(data['choices'][0]['message']['content']);
    } else {
      throw Exception('Failed to optimize deck');
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

      print('⚠️ Aviso: Arquivo prompt.md não encontrado em ${file.path}');
      return "Você é um especialista em otimização de decks de Magic: The Gathering.";
    } catch (e) {
      print('❌ Erro ao ler prompt.md: $e');
      return "Você é um especialista em otimização de decks de Magic: The Gathering.";
    }
  }
}