import 'dart:convert';
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
    List<String> synergyCards = [];
    try {
      synergyCards = await synergyEngine.fetchCommanderSynergies(
        commanderName: commanders.isNotEmpty ? commanders.first : '',
        colors: colors,
        archetype: targetArchetype,
      );
    } catch (e) {
      print('Erro ao buscar sinergias do Scryfall: $e');
      // Continua com lista vazia se Scryfall falhar
    }

    // 3. RECUPERAÇÃO DE DADOS DE META (Staples de formato)
    List<String> formatStaples = [];
    try {
      formatStaples = await _fetchFormatStaples(colors, targetArchetype);
    } catch (e) {
      print('Erro ao buscar staples do formato: $e');
      // Fallback para staples universais seguros
      formatStaples = ['Sol Ring', 'Arcane Signet', 'Command Tower'];
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
    );

    return optimizationResult;
  }

  /// Calcula um score heurístico para identificar cartas suspeitas de serem ruins.
  /// Baseado no Rank EDHREC (se tiver no DB) e CMC.
  List<Map<String, dynamic>> _calculateEfficiencyScores(List<dynamic> cards) {
    // Nota: Assumimos que 'edhrec_rank' vem do seu DB. Se null, assumimos rank alto (impopular).
    var scored = cards.map((card) {
      final rank = (card['edhrec_rank'] as int?) ?? 15000;
      final cmc = (card['cmc'] as num?)?.toDouble() ?? 0.0;
      final typeLine = (card['type_line'] as String?) ?? '';

      // Lógica: Rank baixo é bom (ex: Sol Ring é rank 1). CMC baixo é bom.
      // Score Alto = Carta Ruim (Rank alto + Custo alto)
      // Ajuste para terrenos: Terrenos básicos sempre têm score "neutro" para não serem cortados automaticamente
      if (typeLine.contains('Basic Land')) {
        return {'name': card['name'], 'weakness_score': -1.0};
      }

      final score = rank * (cmc > 4 ? 1.5 : 1.0); // Penaliza cartas caras impopulares
      return {'name': card['name'], 'weakness_score': score};
    }).toList();

    // Ordena do maior score (pior carta) para o menor
    scored.sort((a, b) =>
        (b['weakness_score'] as double).compareTo(a['weakness_score'] as double));

    // Remove terrenos básicos da lista de "ruins"
    scored.removeWhere((c) => (c['weakness_score'] as double) < 0);

    return scored;
  }

  /// Busca staples de formato no Scryfall baseado nas cores do deck
  Future<List<String>> _fetchFormatStaples(
      List<String> colors, String archetype) async {
    final List<String> staples = [];

    // Query base: staples universais de Commander ordenados por popularidade (EDHREC)
    // Handle empty colors case to avoid leading space in query
    final colorIdentity = colors.isNotEmpty ? 'id<=${colors.join('')} ' : '';
    final query = '${colorIdentity}format:commander -is:banned';

    try {
      final uri = Uri.https('api.scryfall.com', '/cards/search', {
        'q': query,
        'order': 'edhrec',
      });

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final cards = data['data'] as List?;
        if (cards != null) {
          staples.addAll(cards.take(15).map((c) => c['name'] as String));
        }
      }
    } catch (e) {
      print('Erro ao buscar staples no Scryfall: $e');
    }

    // Fallback: adicionar staples universais se a busca falhar ou retornar vazio
    if (staples.isEmpty) {
      staples.addAll(['Sol Ring', 'Arcane Signet', 'Command Tower']);
    }

    return staples;
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
      'commander': commanders.join(' & '),
      'archetype': archetype,
      'context': {
        'statistically_weak_cards': weakCandidates,
        'high_synergy_options': synergyPool,
        'format_staples': staplesPool,
      },
      'current_decklist': deckList,
    });

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $openAiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o',
        'messages': [
          {'role': 'system', 'content': _getSystemPrompt()},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.4,
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      
      // Safe navigation for OpenAI response structure
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('OpenAI response missing choices array');
      }
      
      final firstChoice = choices[0] as Map<String, dynamic>?;
      final message = firstChoice?['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      
      if (content == null) {
        throw Exception('OpenAI response missing content');
      }
      
      return jsonDecode(content) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Falha na API OpenAI: ${response.statusCode} - ${response.body}');
    }
  }

  /// Sistema de prompt para otimização de decks cEDH/High Power
  String _getSystemPrompt() {
    return '''
Você é um especialista em otimização de decks de Magic: The Gathering para formato Commander (EDH), 
com foco especial em cEDH (Competitive EDH) e High Power.

SUAS RESPONSABILIDADES:
1. Analisar o deck atual e identificar cartas fracas ou fora da estratégia
2. Sugerir remoções baseadas nas cartas estatisticamente fracas fornecidas
3. Sugerir adições das pools de sinergia e staples fornecidas
4. Manter o equilíbrio numérico (mesma quantidade de remoções e adições)

REGRAS CRÍTICAS:
- O número de removals DEVE ser IGUAL ao número de additions
- Priorize cartas da pool de sinergias (high_synergy_options) para adições
- Use statistically_weak_cards como guia para remoções
- NUNCA remova staples de formato (Sol Ring, Mana Crypt, Tutors, Fetchlands)
- Considere a curva de mana ao fazer sugestões
- Foque na consistência e velocidade do deck

FORMATO DE RESPOSTA (JSON estrito):
{
  "removals": ["Card Name 1", "Card Name 2"],
  "additions": ["Card Name 1", "Card Name 2"],
  "reasoning": "Explicação detalhada das mudanças e como melhoram a estratégia do deck"
}
''';
  }
}