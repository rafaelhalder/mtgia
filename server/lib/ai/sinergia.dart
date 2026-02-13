import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logger.dart';

class SynergyEngine {
  /// Esta função é o segredo. Ela não busca apenas "cartas boas".
  /// Ela lê o texto do Comandante (via Oracle) e traduz para queries de mecânica do Scryfall.
  Future<List<String>> fetchCommanderSynergies({
    required String commanderName,
    required List<String> colors,
    required String archetype,
  }) async {
    // 1. Obter Oracle Text do Comandante
    final commanderData = await _getCardData(commanderName);
    if (commanderData == null) return [];

    final oracleText = (commanderData['oracle_text'] as String? ?? '').toLowerCase();
    final typeLine = (commanderData['type_line'] as String? ?? '').toLowerCase();
    
    List<String> queries = [];
    final colorQuery = "id<=${colors.join('')}";

    // 2. Análise Semântica Simplificada (Keyword Mapping)
    
    // Exemplo: Comandante de Artefatos (Urza, Breya)
    if (oracleText.contains('artifact') || typeLine.contains('artifact')) {
      queries.add('function:artifact-payoff $colorQuery'); // Cartas que recompensam artefatos
      queries.add('t:artifact order:edhrec $colorQuery'); // Melhores artefatos
    }

    // Exemplo: Comandante de Encantamentos (Sythis, Zur)
    if (oracleText.contains('enchantment') || oracleText.contains('enchanted')) {
      queries.add('function:enchantress $colorQuery'); // Compra carta com encantamento
      queries.add('t:enchantment order:edhrec $colorQuery');
    }

    // Exemplo: Comandante de Tokens (Chatterfang, Jetmir)
    if (oracleText.contains('create') && oracleText.contains('token')) {
      queries.add('function:token-doubler $colorQuery'); // Doubling Season, etc
      queries.add('function:anthem $colorQuery'); // +1/+1 para todos
    }

    // Exemplo: Comandante de Cemitério/Reanimator (Muldrotha, Meren)
    if (oracleText.contains('graveyard') || oracleText.contains('return') || oracleText.contains('sacrifice')) {
      queries.add('function:reanimate $colorQuery');
      queries.add('function:sacrifice-outlet $colorQuery'); // Altares
      queries.add('function:entomb $colorQuery'); // Colocar no cemitério
    }

    // Exemplo: Spellslinger/Storm (Kess, Mizzix)
    if (oracleText.contains('instant') || oracleText.contains('sorcery')) {
      queries.add('function:cantrip $colorQuery');
      queries.add('function:storm-payoff $colorQuery');
    }

    // 3. Executar Queries SEQUENCIALMENTE com rate limiting (Scryfall pede 50-100ms entre requests)
    final results = <List<String>>[];
    for (final q in queries.take(3)) {
      final result = await searchScryfall(q);
      results.add(result);
      // Rate limiting: 120ms entre requests para respeitar Scryfall API
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // Flatten e retornar nomes únicos
    return results.expand((i) => i).toSet().toList();
  }

  Future<Map<String, dynamic>?> _getCardData(String name) async {
    final uri = Uri.parse('https://api.scryfall.com/cards/named?exact=${Uri.encodeComponent(name)}');
    final response = await http.get(uri);
    if (response.statusCode == 200) return jsonDecode(response.body);
    return null;
  }

  Future<List<String>> searchScryfall(String query) async {
    // Query formatada para Commander, ordenada por popularidade (EDHREC)
    // e removendo banidas
    final finalQuery = query.contains('format:') ? query : '$query format:commander -is:banned';
    final uri = Uri.https('api.scryfall.com', '/cards/search', {
      'q': finalQuery,
      'order': 'edhrec', // Crucial: Traz o que os players realmente usam
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = (data['data'] as List).take(20).map((c) => c['name'] as String).toList();
        if (results.isNotEmpty) return results;
      }

      // FALLBACK: Se query com "function:" falha (404/vazio), tenta query textual equivalente
      if (query.contains('function:')) {
        final fallbackQuery = _buildFallbackQuery(query);
        if (fallbackQuery != null) {
          await Future.delayed(const Duration(milliseconds: 120)); // Rate limit
          final fallbackUri = Uri.https('api.scryfall.com', '/cards/search', {
            'q': fallbackQuery,
            'order': 'edhrec',
          });
          final fbResponse = await http.get(fallbackUri);
          if (fbResponse.statusCode == 200) {
            final fbData = jsonDecode(fbResponse.body);
            return (fbData['data'] as List).take(20).map((c) => c['name'] as String).toList();
          }
        }
      }
    } catch (e) {
      Log.w('Erro Scryfall: $e');
    }
    return [];
  }

  /// Converte queries "function:" para queries textuais equivalentes como fallback
  String? _buildFallbackQuery(String query) {
    // Extrair a parte de identidade de cor (id<=...)
    final colorMatch = RegExp(r'id<=\S+').firstMatch(query);
    final colorPart = colorMatch?.group(0) ?? '';

    if (query.contains('function:artifact-payoff')) {
      return 'o:"whenever" o:"artifact" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:enchantress')) {
      return 'o:"whenever" o:"enchantment" o:"draw" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:token-doubler')) {
      return 'o:"if one or more tokens" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:anthem')) {
      return 'o:"creatures you control get" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:reanimate')) {
      return 'o:"return" o:"from your graveyard to the battlefield" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:sacrifice-outlet')) {
      return 'o:"sacrifice a creature" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:entomb')) {
      return 'o:"put" o:"into your graveyard" $colorPart format:commander -is:banned';
    }
    if (query.contains('function:cantrip')) {
      return 'o:"draw a card" cmc<=2 $colorPart format:commander -is:banned';
    }
    if (query.contains('function:storm-payoff')) {
      return 'o:"whenever you cast" o:"instant or sorcery" $colorPart format:commander -is:banned';
    }
    return null;
  }
}