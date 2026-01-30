import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../decks/models/deck_card_item.dart';

class CardProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  List<DeckCardItem> _searchResults = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String _currentQuery = '';
  String? _errorMessage;

  List<DeckCardItem> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;

  CardProvider({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<void> searchCards(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      clearSearch();
      return;
    }

    _currentQuery = q;
    _page = 1;
    _hasMore = true;
    _searchResults = [];
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    try {
      await _fetchPage(query: q, page: 1, append: false);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (_currentQuery.trim().isEmpty) return;

    _isLoadingMore = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _fetchPage(query: _currentQuery, page: _page + 1, append: true);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _fetchPage({
    required String query,
    required int page,
    required bool append,
  }) async {
    const limit = 50;
    final requestQuery = query.trim();
    final encoded = Uri.encodeQueryComponent(requestQuery);
    final response = await _apiClient.get(
      '/cards?name=$encoded&limit=$limit&page=$page',
    );

    // Se o usuário trocou o query no meio, ignora a resposta antiga.
    if (requestQuery != _currentQuery) return;

    if (response.statusCode != 200) {
      _errorMessage = 'Erro ao buscar cartas: ${response.statusCode}';
      _hasMore = false;
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final List<dynamic> cardsJson = (data['data'] as List?) ?? const [];
    final results =
        cardsJson.map((json) {
          return DeckCardItem(
            id: json['id'],
            name: json['name'],
            manaCost: json['mana_cost'],
            typeLine: json['type_line'] ?? '',
            oracleText: json['oracle_text'],
            colors:
                (json['colors'] as List?)?.map((e) => e.toString()).toList() ??
                [],
            colorIdentity:
                (json['color_identity'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            imageUrl: json['image_url'],
            setCode: json['set_code'] ?? '',
            setName: json['set_name'],
            setReleaseDate: json['set_release_date'],
            rarity: json['rarity'] ?? '',
            quantity: 1,
            isCommander: false,
          );
        }).toList();

    if (append) {
      _searchResults = [..._searchResults, ...results];
    } else {
      _searchResults = results;
    }

    _page = page;
    _hasMore = results.length == limit;
  }

  void clearSearch() {
    _searchResults = [];
    _errorMessage = null;
    _currentQuery = '';
    _page = 1;
    _hasMore = false;
    _isLoading = false;
    _isLoadingMore = false;
    notifyListeners();
  }

  /// Solicita uma explicação da carta via IA
  Future<String?> explainCard(DeckCardItem card) async {
    try {
      final response = await _apiClient.post('/ai/explain', {
        'card_id': card.id,
        'card_name': card.name,
        'oracle_text': card.oracleText,
        'type_line': card.typeLine,
      });

      if (response.statusCode == 200) {
        return response.data['explanation'] as String;
      }
      return null;
    } catch (e) {
      return 'Erro ao obter explicação: $e';
    }
  }

  Future<List<Map<String, dynamic>>> fetchPrintingsByName(String name) async {
    final encoded = Uri.encodeQueryComponent(name.trim());
    final response = await _apiClient.get(
      '/cards/printings?name=$encoded&limit=50',
    );
    if (response.statusCode != 200) {
      throw Exception('Falha ao buscar edições: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
    final list = (data['data'] as List?)?.whereType<Map>().toList() ?? const [];
    return list.map((m) => m.cast<String, dynamic>()).toList();
  }
}
