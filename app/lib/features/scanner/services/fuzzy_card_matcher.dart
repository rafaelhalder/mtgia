import 'dart:math' as math;
import '../../cards/providers/card_provider.dart';
import '../../decks/models/deck_card_item.dart';

/// Busca de cartas com tolerância a erros de OCR
class FuzzyCardMatcher {
  final CardProvider _cardProvider;

  FuzzyCardMatcher(this._cardProvider);

  /// Busca cartas mesmo com erros de OCR
  Future<List<DeckCardItem>> searchWithFuzzy(String recognizedName) async {
    final cleanedName = recognizedName.trim();
    if (cleanedName.isEmpty) return [];

    // 1. Busca direta primeiro
    await _cardProvider.searchCards(cleanedName);
    if (_cardProvider.searchResults.isNotEmpty) {
      return _cardProvider.searchResults;
    }

    // 2. Tenta variações comuns de erro OCR
    final variations = _generateOcrVariations(cleanedName);

    for (final variation in variations) {
      if (variation != cleanedName && variation.length >= 3) {
        await _cardProvider.searchCards(variation);
        if (_cardProvider.searchResults.isNotEmpty) {
          return _cardProvider.searchResults;
        }
      }
    }

    // 3. Busca parcial com primeira(s) palavra(s)
    final words = cleanedName.split(RegExp(r'\s+'));
    if (words.length > 1) {
      // Tenta primeiras duas palavras
      final partial = words.take(2).join(' ');
      await _cardProvider.searchCards(partial);
      
      if (_cardProvider.searchResults.isNotEmpty) {
        // Filtra resultados que são similares ao nome completo
        return _cardProvider.searchResults.where((card) {
          return _isSimilar(card.name, cleanedName, threshold: 0.6);
        }).toList();
      }

      // Tenta só primeira palavra
      await _cardProvider.searchCards(words.first);
      if (_cardProvider.searchResults.isNotEmpty) {
        return _cardProvider.searchResults.where((card) {
          return _isSimilar(card.name, cleanedName, threshold: 0.5);
        }).toList();
      }
    }

    // 4. Tenta remover caracteres problemáticos e buscar novamente
    final simplified = cleanedName
        .replaceAll(RegExp(r'[^a-zA-Z\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    if (simplified != cleanedName && simplified.length >= 3) {
      await _cardProvider.searchCards(simplified);
      return _cardProvider.searchResults;
    }

    return [];
  }

  /// Gera variações comuns de erro de OCR
  List<String> _generateOcrVariations(String text) {
    final variations = <String>{text};

    // Substituições comuns de OCR
    final replacements = <String, List<String>>{
      'l': ['I', '1', 'i'],
      'I': ['l', '1'],
      '1': ['l', 'I', 'i'],
      'i': ['l', '1'],
      'O': ['0', 'Q', 'o'],
      '0': ['O', 'o'],
      'o': ['0', 'O'],
      'rn': ['m'],
      'm': ['rn'],
      'vv': ['w'],
      'w': ['vv', 'W'],
      'cl': ['d'],
      'd': ['cl'],
      'B': ['8', 'R'],
      '8': ['B'],
      'S': ['5'],
      '5': ['S'],
      'G': ['6', 'C'],
      '6': ['G'],
      'Z': ['2'],
      '2': ['Z'],
      'A': ['4'],
      '4': ['A'],
      'E': ['3'],
      '3': ['E'],
      'n': ['ri', 'h'],
      'h': ['n', 'b'],
      'u': ['v', 'n'],
      'v': ['u', 'y'],
      'c': ['e', 'o'],
      'e': ['c', 'o'],
      "'": ["'", "", "`"],
      '-': ['—', '–', ' '],
      ' ': ['', '-'],
    };

    // Gera variações para cada substituição
    replacements.forEach((from, toList) {
      if (text.contains(from)) {
        for (final to in toList) {
          // Substitui primeira ocorrência
          variations.add(text.replaceFirst(from, to));
          
          // Substitui todas as ocorrências
          variations.add(text.replaceAll(from, to));
        }
      }
    });

    // Variações de capitalização
    variations.add(text.toLowerCase());
    variations.add(_toTitleCase(text));

    // Remove espaços extras ou duplicados
    variations.add(text.replaceAll(RegExp(r'\s+'), ' ').trim());

    return variations.toList();
  }

  /// Converte para Title Case
  String _toTitleCase(String text) {
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Verifica similaridade usando distância de Levenshtein
  bool _isSimilar(String a, String b, {double threshold = 0.7}) {
    final distance = levenshteinDistance(a.toLowerCase(), b.toLowerCase());
    final maxLen = math.max(a.length, b.length);
    if (maxLen == 0) return true;
    final similarity = 1 - (distance / maxLen);
    return similarity >= threshold;
  }

  /// Calcula distância de Levenshtein entre duas strings
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final m = s1.length;
    final n = s2.length;

    // Usa apenas duas linhas para economizar memória
    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);

    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        curr[j] = math.min(
          math.min(prev[j] + 1, curr[j - 1] + 1),
          prev[j - 1] + cost,
        );
      }
      // Troca as linhas
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[n];
  }

  /// Calcula similaridade (0.0 a 1.0) entre duas strings
  static double similarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    final distance = levenshteinDistance(s1.toLowerCase(), s2.toLowerCase());
    final maxLen = math.max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    return 1 - (distance / maxLen);
  }

  /// Encontra a melhor correspondência em uma lista
  static DeckCardItem? findBestMatch(
    String query,
    List<DeckCardItem> cards, {
    double minSimilarity = 0.6,
  }) {
    if (cards.isEmpty) return null;

    DeckCardItem? bestMatch;
    double bestScore = 0;

    for (final card in cards) {
      final score = similarity(query, card.name);
      if (score > bestScore && score >= minSimilarity) {
        bestScore = score;
        bestMatch = card;
      }
    }

    return bestMatch;
  }
}
