import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logger.dart';

/// Serviço para integração com EDHREC JSON API
/// 
/// EDHREC é a maior base de dados de Commander, com estatísticas reais
/// de milhões de decklists. Usar esses dados garante que as sugestões
/// sejam baseadas em cartas que REALMENTE funcionam juntas.
/// 
/// Endpoint principal: https://json.edhrec.com/pages/commanders/{slug}.json
class EdhrecService {
  static const _baseUrl = 'https://json.edhrec.com';
  static const _cacheTimeout = Duration(hours: 6); // Cache para evitar requests excessivos
  
  // Cache em memória para evitar requests repetidos no mesmo ciclo de vida do server
  static final Map<String, _CachedResult> _cache = {};
  
  /// Busca os dados de co-ocorrência para um comandante específico.
  /// 
  /// Retorna uma lista de cartas ordenadas por synergy score do EDHREC.
  /// Cada carta inclui:
  /// - name: Nome da carta
  /// - synergy: Score de sinergia (-1.0 a 1.0, onde 1.0 = só aparece neste deck)
  /// - inclusion: % de decks com este commander que usam esta carta
  /// - label: Categoria da carta (ramp, draw, removal, etc)
  Future<EdhrecCommanderData?> fetchCommanderData(String commanderName) async {
    final slug = _toSlug(commanderName);
    
    // Check cache primeiro
    final cached = _cache[slug];
    if (cached != null && !cached.isExpired) {
      Log.d('EDHREC cache hit: $slug');
      return cached.data;
    }
    
    final url = '$_baseUrl/pages/commanders/$slug.json';
    Log.i('EDHREC fetch: $url');
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Referer': 'https://edhrec.com/',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = _parseEdhrecResponse(json, commanderName);
        
        // Cache result
        _cache[slug] = _CachedResult(data, DateTime.now());
        
        Log.i('EDHREC data loaded: ${data.topCards.length} cards for $commanderName');
        return data;
      } else if (response.statusCode == 404) {
        // Commander não encontrado no EDHREC (muito novo ou muito obscuro)
        Log.w('EDHREC: commander not found: $slug');
        return null;
      } else {
        Log.w('EDHREC error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Log.e('EDHREC request failed: $e');
      return null;
    }
  }
  
  /// Converte nome do commander para slug do EDHREC
  /// Ex: "Jin-Gitaxias, Core Augur" → "jin-gitaxias-core-augur"
  /// Ex: "Jin-Gitaxias // The Great Synthesis" → "jin-gitaxias"
  String _toSlug(String name) {
    // Para cartas dupla face (flip/transform), usa apenas a primeira parte
    // Suporta vários formatos: " // ", "//", " / "
    var cleanName = name;
    for (final separator in [' // ', '//', ' / ']) {
      if (cleanName.contains(separator)) {
        cleanName = cleanName.split(separator).first.trim();
        break;
      }
    }
    
    final slug = cleanName
        .toLowerCase()
        .replaceAll(RegExp(r'''[,'"]+'''), '') // Remove pontuação
        .replaceAll(RegExp(r'\s+'), '-')       // Espaços → hífens
        .replaceAll(RegExp(r'-+'), '-')        // Remove hífens duplicados
        .replaceAll(RegExp(r'[^a-z0-9-]'), ''); // Só letras, números, hífens
    
    Log.d('EDHREC slug: "$name" → "$slug"');
    return slug;
  }
  
  /// Parse da resposta JSON do EDHREC
  EdhrecCommanderData _parseEdhrecResponse(Map<String, dynamic> json, String commanderName) {
    final cardLists = <EdhrecCard>[];
    
    // Estrutura EDHREC: container.json_dict.cardlists[]
    // Cada cardlist tem: header (categoria) e cardviews[] (cartas)
    final container = json['container'] as Map<String, dynamic>?;
    final jsonDict = container?['json_dict'] as Map<String, dynamic>?;
    final cardlists = jsonDict?['cardlists'] as List<dynamic>? ?? [];
    
    for (final list in cardlists) {
      final header = (list['header'] as String?) ?? 'uncategorized';
      final cardviews = list['cardviews'] as List<dynamic>? ?? [];
      
      for (final card in cardviews) {
        final name = card['name'] as String?;
        if (name == null) continue;
        
        // Synergy score: -1.0 a 1.0 (1.0 = apenas usado com este commander)
        final synergy = (card['synergy'] as num?)?.toDouble() ?? 0.0;
        
        // Inclusion %: fração de decks que usa esta carta (0.0 a 1.0)
        final inclusion = (card['inclusion'] as num?)?.toDouble() ?? 0.0;
        
        // Número de decks que usam esta carta
        final numDecks = card['num_decks'] as int? ?? 0;
        
        cardLists.add(EdhrecCard(
          name: name,
          synergy: synergy,
          inclusion: inclusion,
          numDecks: numDecks,
          category: _normalizeCategory(header),
        ));
      }
    }
    
    // Ordena por synergy score (maior primeiro)
    cardLists.sort((a, b) => b.synergy.compareTo(a.synergy));
    
    // Extrai temas/strategies do EDHREC
    final themes = <String>[];
    final panels = jsonDict?['panels'] as Map<String, dynamic>? ?? {};
    final themepanel = panels['themepanel'] as Map<String, dynamic>?;
    if (themepanel != null) {
      final themeList = themepanel['themes'] as List<dynamic>? ?? [];
      for (final t in themeList) {
        if (t is Map && t['name'] != null) {
          themes.add(t['name'] as String);
        }
      }
    }
    
    // Extrai número médio de decks
    final deckCount = jsonDict?['header']?['num_decks'] as int? ?? 0;
    
    return EdhrecCommanderData(
      commanderName: commanderName,
      deckCount: deckCount,
      themes: themes,
      topCards: cardLists,
    );
  }
  
  /// Normaliza categoria do EDHREC para padrão interno
  String _normalizeCategory(String header) {
    final lower = header.toLowerCase();
    if (lower.contains('ramp')) return 'ramp';
    if (lower.contains('draw') || lower.contains('card advantage')) return 'card_draw';
    if (lower.contains('removal') || lower.contains('interaction')) return 'removal';
    if (lower.contains('wipe') || lower.contains('board')) return 'board_wipe';
    if (lower.contains('land')) return 'lands';
    if (lower.contains('creature')) return 'creatures';
    if (lower.contains('enchant')) return 'enchantments';
    if (lower.contains('artifact')) return 'artifacts';
    if (lower.contains('instant')) return 'instants';
    if (lower.contains('sorcery')) return 'sorceries';
    if (lower.contains('tutor')) return 'tutors';
    if (lower.contains('protection') || lower.contains('counter')) return 'protection';
    return 'other';
  }
  
  /// Retorna as top N cartas de uma categoria específica
  List<EdhrecCard> getTopByCategory(EdhrecCommanderData data, String category, {int limit = 10}) {
    return data.topCards
        .where((c) => c.category == category)
        .take(limit)
        .toList();
  }
  
  /// Retorna cartas com synergy score acima de um threshold
  List<EdhrecCard> getHighSynergyCards(EdhrecCommanderData data, {double minSynergy = 0.3, int limit = 50}) {
    return data.topCards
        .where((c) => c.synergy >= minSynergy)
        .take(limit)
        .toList();
  }
  
  /// Score de "encaixe" de uma carta no deck.
  /// Retorna um valor 0.0-1.0 baseado em:
  /// - synergy: Quanto maior, mais específico para este commander
  /// - inclusion: Quanto maior, mais "provada" a carta é
  /// 
  /// Fórmula: (synergy + 1) / 2 * 0.6 + inclusion * 0.4
  /// Isso equilibra cartas "sinérgicas mas nichadas" com "staples universais"
  double calculateFitScore(EdhrecCard card) {
    // Synergy vai de -1 a 1, normalizamos para 0-1
    final normalizedSynergy = (card.synergy + 1) / 2;
    // Combinamos 60% synergy, 40% popularidade
    return normalizedSynergy * 0.6 + card.inclusion * 0.4;
  }
  
  /// Limpa cache expirado
  void cleanupCache() {
    _cache.removeWhere((_, v) => v.isExpired);
  }
}

/// Dados de um commander do EDHREC
class EdhrecCommanderData {
  final String commanderName;
  final int deckCount; // Número de decks registrados
  final List<String> themes; // Temas/estratégias sugeridas
  final List<EdhrecCard> topCards; // Cartas ordenadas por synergy
  
  EdhrecCommanderData({
    required this.commanderName,
    required this.deckCount,
    required this.themes,
    required this.topCards,
  });
  
  /// Encontra uma carta por nome (case-insensitive)
  EdhrecCard? findCard(String name) {
    final lower = name.toLowerCase();
    for (final c in topCards) {
      if (c.name.toLowerCase() == lower) return c;
    }
    return null;
  }
  
  /// Verifica se uma carta está nas top N mais sinérgicas
  bool isHighSynergy(String cardName, {double minSynergy = 0.2}) {
    final card = findCard(cardName);
    return card != null && card.synergy >= minSynergy;
  }
}

/// Uma carta do EDHREC com seus scores
class EdhrecCard {
  final String name;
  final double synergy; // -1.0 a 1.0 (maior = mais específico para este commander)
  final double inclusion; // 0.0 a 1.0 (% de decks que usam)
  final int numDecks; // Número absoluto de decks
  final String category; // ramp, card_draw, removal, etc
  
  EdhrecCard({
    required this.name,
    required this.synergy,
    required this.inclusion,
    required this.numDecks,
    required this.category,
  });
  
  @override
  String toString() => '$name (syn:${synergy.toStringAsFixed(2)}, inc:${(inclusion*100).toStringAsFixed(0)}%)';
}

/// Cache interno com timeout
class _CachedResult {
  final EdhrecCommanderData data;
  final DateTime fetchedAt;
  
  _CachedResult(this.data, this.fetchedAt);
  
  bool get isExpired => DateTime.now().difference(fetchedAt) > EdhrecService._cacheTimeout;
}
