import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

/// Modelo simplificado de deck público da comunidade
class CommunityDeck {
  final String id;
  final String name;
  final String format;
  final String? description;
  final int? synergyScore;
  final String? ownerId;
  final String? ownerUsername;
  final String? commanderName;
  final String? commanderImageUrl;
  final int cardCount;
  final DateTime createdAt;

  CommunityDeck({
    required this.id,
    required this.name,
    required this.format,
    this.description,
    this.synergyScore,
    this.ownerId,
    this.ownerUsername,
    this.commanderName,
    this.commanderImageUrl,
    this.cardCount = 0,
    required this.createdAt,
  });

  factory CommunityDeck.fromJson(Map<String, dynamic> json) {
    return CommunityDeck(
      id: json['id'] as String,
      name: json['name'] as String,
      format: json['format'] as String,
      description: json['description'] as String?,
      synergyScore: json['synergy_score'] as int?,
      ownerId: json['owner_id'] as String?,
      ownerUsername: json['owner_username'] as String?,
      commanderName: json['commander_name'] as String?,
      commanderImageUrl: json['commander_image_url'] as String?,
      cardCount: json['card_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Provider para o feed da comunidade (decks públicos)
class CommunityProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  List<CommunityDeck> _decks = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  String? _searchQuery;
  String? _formatFilter;

  List<CommunityDeck> get decks => _decks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  int get total => _total;
  String? get searchQuery => _searchQuery;
  String? get formatFilter => _formatFilter;

  CommunityProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Busca decks públicos com paginação e filtros
  Future<void> fetchPublicDecks({
    String? search,
    String? format,
    bool reset = false,
  }) async {
    if (reset) {
      _page = 1;
      _decks = [];
      _hasMore = true;
    }

    if (!_hasMore || _isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _searchQuery = search ?? _searchQuery;
    _formatFilter = format ?? _formatFilter;
    notifyListeners();

    try {
      final queryParams = <String, String>{
        'page': '$_page',
        'limit': '20',
      };
      if (_searchQuery != null && _searchQuery!.isNotEmpty) {
        queryParams['search'] = _searchQuery!;
      }
      if (_formatFilter != null && _formatFilter!.isNotEmpty) {
        queryParams['format'] = _formatFilter!;
      }

      final queryString =
          queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');

      final response =
          await _apiClient.get('/community/decks?$queryString');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final deckList = (data['data'] as List?) ?? [];
        final newDecks =
            deckList.map((d) => CommunityDeck.fromJson(d as Map<String, dynamic>)).toList();

        _decks.addAll(newDecks);
        _total = data['total'] as int? ?? 0;
        _hasMore = _decks.length < _total;
        _page++;
      } else {
        _errorMessage = 'Falha ao carregar decks da comunidade';
      }
    } catch (e) {
      debugPrint('[CommunityProvider] fetchPublicDecks error: $e');
      _errorMessage = 'Erro de conexão: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Limpa filtros e recarrega
  void clearFilters() {
    _searchQuery = null;
    _formatFilter = null;
    fetchPublicDecks(reset: true);
  }

  /// Busca detalhes de um deck público
  Future<Map<String, dynamic>?> fetchPublicDeckDetails(String deckId) async {
    try {
      final response = await _apiClient.get('/community/decks/$deckId');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } catch (e) {
      debugPrint('[CommunityProvider] fetchPublicDeckDetails error: $e');
      return null;
    }
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    _decks = [];
    _isLoading = false;
    _errorMessage = null;
    _page = 1;
    _total = 0;
    _hasMore = true;
    _searchQuery = null;
    _formatFilter = null;
    notifyListeners();
  }
}
