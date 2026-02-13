import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

// =====================================================================
// Model: BinderItem
// =====================================================================

class BinderItem {
  final String id;
  final String cardId;
  final String cardName;
  final String? cardImageUrl;
  final String? cardSetCode;
  final String? cardManaCost;
  final String? cardRarity;
  final String? cardTypeLine;
  int quantity;
  String condition; // NM, LP, MP, HP, DMG
  bool isFoil;
  bool forTrade;
  bool forSale;
  double? price;
  String currency;
  String? notes;
  String listType; // 'have' or 'want'

  BinderItem({
    required this.id,
    required this.cardId,
    required this.cardName,
    this.cardImageUrl,
    this.cardSetCode,
    this.cardManaCost,
    this.cardRarity,
    this.cardTypeLine,
    this.quantity = 1,
    this.condition = 'NM',
    this.isFoil = false,
    this.forTrade = false,
    this.forSale = false,
    this.price,
    this.currency = 'BRL',
    this.notes,
    this.listType = 'have',
  });

  factory BinderItem.fromJson(Map<String, dynamic> json) {
    final card = json['card'] as Map<String, dynamic>?;
    return BinderItem(
      id: json['id'] as String,
      cardId: card?['id'] as String? ?? json['card_id'] as String,
      cardName: card?['name'] as String? ?? json['card_name'] as String? ?? '',
      cardImageUrl: card?['image_url'] as String? ?? json['card_image_url'] as String?,
      cardSetCode: card?['set_code'] as String? ?? json['card_set_code'] as String?,
      cardManaCost: card?['mana_cost'] as String? ?? json['card_mana_cost'] as String?,
      cardRarity: card?['rarity'] as String? ?? json['card_rarity'] as String?,
      cardTypeLine: card?['type_line'] as String? ?? json['card_type_line'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      condition: json['condition'] as String? ?? 'NM',
      isFoil: json['is_foil'] as bool? ?? false,
      forTrade: json['for_trade'] as bool? ?? false,
      forSale: json['for_sale'] as bool? ?? false,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency'] as String? ?? 'BRL',
      notes: json['notes'] as String?,
      listType: json['list_type'] as String? ?? 'have',
    );
  }
}

// =====================================================================
// Model: BinderStats
// =====================================================================

class BinderStats {
  final int totalItems;
  final int uniqueCards;
  final int forTradeCount;
  final int forSaleCount;
  final double estimatedValue;

  BinderStats({
    this.totalItems = 0,
    this.uniqueCards = 0,
    this.forTradeCount = 0,
    this.forSaleCount = 0,
    this.estimatedValue = 0.0,
  });

  factory BinderStats.fromJson(Map<String, dynamic> json) {
    return BinderStats(
      totalItems: json['total_items'] as int? ?? 0,
      uniqueCards: json['unique_cards'] as int? ?? 0,
      forTradeCount: json['for_trade_count'] as int? ?? 0,
      forSaleCount: json['for_sale_count'] as int? ?? 0,
      estimatedValue: json['estimated_value'] != null
          ? (json['estimated_value'] as num).toDouble()
          : 0.0,
    );
  }
}

// =====================================================================
// Model: MarketplaceItem (item no marketplace com dados do owner)
// =====================================================================

class MarketplaceItem extends BinderItem {
  final String ownerId;
  final String ownerUsername;
  final String? ownerDisplayName;
  final String? ownerAvatarUrl;
  final String? ownerLocationState;
  final String? ownerLocationCity;
  final String? ownerTradeNotes;

  MarketplaceItem({
    required super.id,
    required super.cardId,
    required super.cardName,
    super.cardImageUrl,
    super.cardSetCode,
    super.cardManaCost,
    super.cardRarity,
    super.cardTypeLine,
    super.quantity,
    super.condition,
    super.isFoil,
    super.forTrade,
    super.forSale,
    super.price,
    super.currency,
    super.notes,
    super.listType,
    required this.ownerId,
    required this.ownerUsername,
    this.ownerDisplayName,
    this.ownerAvatarUrl,
    this.ownerLocationState,
    this.ownerLocationCity,
    this.ownerTradeNotes,
  });

  factory MarketplaceItem.fromJson(Map<String, dynamic> json) {
    final card = json['card'] as Map<String, dynamic>?;
    final owner = json['owner'] as Map<String, dynamic>?;
    return MarketplaceItem(
      id: json['id'] as String,
      cardId: card?['id'] as String? ?? json['card_id'] as String? ?? '',
      cardName: card?['name'] as String? ?? '',
      cardImageUrl: card?['image_url'] as String?,
      cardSetCode: card?['set_code'] as String?,
      cardManaCost: card?['mana_cost'] as String?,
      cardRarity: card?['rarity'] as String?,
      cardTypeLine: card?['type_line'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      condition: json['condition'] as String? ?? 'NM',
      isFoil: json['is_foil'] as bool? ?? false,
      forTrade: json['for_trade'] as bool? ?? false,
      forSale: json['for_sale'] as bool? ?? false,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency'] as String? ?? 'BRL',
      notes: json['notes'] as String?,
      listType: json['list_type'] as String? ?? 'have',
      ownerId: owner?['id'] as String? ?? '',
      ownerUsername: owner?['username'] as String? ?? '',
      ownerDisplayName: owner?['display_name'] as String?,
      ownerAvatarUrl: owner?['avatar_url'] as String?,
      ownerLocationState: owner?['location_state'] as String?,
      ownerLocationCity: owner?['location_city'] as String?,
      ownerTradeNotes: owner?['trade_notes'] as String?,
    );
  }

  String get ownerDisplayLabel => ownerDisplayName ?? ownerUsername;

  /// Retorna label de localização formatada
  String? get ownerLocationLabel {
    if (ownerLocationCity != null && ownerLocationState != null) {
      return '$ownerLocationCity, $ownerLocationState';
    }
    if (ownerLocationState != null) return ownerLocationState;
    return null;
  }
}

// =====================================================================
// Provider: BinderProvider
// =====================================================================

class BinderProvider extends ChangeNotifier {
  final ApiClient _api;

  BinderProvider({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  // My Binder
  List<BinderItem> _items = [];
  BinderStats? _stats;
  bool _isLoading = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  String? _currentFilter; // condition filter
  String? _currentSearch;
  bool? _filterForTrade;
  bool? _filterForSale;
  String? _currentListType; // 'have', 'want', or null (all)

  List<BinderItem> get items => _items;
  BinderStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _hasMore;

  // Marketplace
  List<MarketplaceItem> _marketItems = [];
  bool _isLoadingMarket = false;
  String? _marketError;
  int _marketPage = 1;
  bool _hasMoreMarket = true;

  List<MarketplaceItem> get marketItems => _marketItems;
  bool get isLoadingMarket => _isLoadingMarket;
  String? get marketError => _marketError;
  bool get hasMoreMarket => _hasMoreMarket;

  // Public binder (other user)
  List<BinderItem> _publicItems = [];
  bool _isLoadingPublic = false;
  String? _publicError;
  int _publicPage = 1;
  bool _hasMorePublic = true;
  Map<String, dynamic>? _publicOwner;

  List<BinderItem> get publicItems => _publicItems;
  bool get isLoadingPublic => _isLoadingPublic;
  String? get publicError => _publicError;
  bool get hasMorePublic => _hasMorePublic;
  Map<String, dynamic>? get publicOwner => _publicOwner;

  // ---------------------------------------------------------------
  // My Binder — CRUD
  // ---------------------------------------------------------------

  /// Fetch my binder items (paginado, incremental)
  Future<void> fetchMyBinder({bool reset = false}) async {
    if (_isLoading) return;
    if (!reset && !_hasMore) return;

    if (reset) {
      _page = 1;
      _items = [];
      _hasMore = true;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      var endpoint = '/binder?page=$_page&limit=20';
      if (_currentListType != null) endpoint += '&list_type=$_currentListType';
      if (_currentFilter != null) endpoint += '&condition=$_currentFilter';
      if (_currentSearch != null && _currentSearch!.isNotEmpty) {
        endpoint += '&search=${Uri.encodeComponent(_currentSearch!)}';
      }
      if (_filterForTrade == true) endpoint += '&for_trade=true';
      if (_filterForSale == true) endpoint += '&for_sale=true';

      final res = await _api.get(endpoint);
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        final list = (data['data'] as List<dynamic>? ?? [])
            .map((e) => BinderItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _items.addAll(list);
        _hasMore = list.length >= 20;
        _page++;
        _error = null;
      } else {
        _error = res.data?['error'] ?? 'Erro ao carregar fichário';
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] fetchMyBinder: $e');
      _error = 'Não foi possível conectar ao servidor';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Aplicar filtros e recarregar
  void applyFilters({
    String? condition,
    String? search,
    bool? forTrade,
    bool? forSale,
    String? listType,
  }) {
    _currentFilter = condition;
    _currentSearch = search;
    _filterForTrade = forTrade;
    _filterForSale = forSale;
    _currentListType = listType;
    fetchMyBinder(reset: true);
  }

  /// Fetch stats
  Future<void> fetchStats() async {
    try {
      final res = await _api.get('/binder/stats');
      if (res.statusCode == 200 && res.data is Map) {
        _stats = BinderStats.fromJson(res.data as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] fetchStats: $e');
    }
  }

  /// Adicionar carta ao binder
  Future<bool> addItem({
    required String cardId,
    int quantity = 1,
    String condition = 'NM',
    bool isFoil = false,
    bool forTrade = false,
    bool forSale = false,
    double? price,
    String? notes,
    String listType = 'have',
  }) async {
    try {
      final body = <String, dynamic>{
        'card_id': cardId,
        'quantity': quantity,
        'condition': condition,
        'is_foil': isFoil,
        'for_trade': forTrade,
        'for_sale': forSale,
        'list_type': listType,
        if (price != null) 'price': price,
        if (notes != null) 'notes': notes,
      };

      final res = await _api.post('/binder', body);
      if (res.statusCode == 201) {
        // Recarregar
        await fetchMyBinder(reset: true);
        await fetchStats();
        return true;
      } else {
        _error = res.data?['error'] ?? 'Erro ao adicionar';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] addItem: $e');
      _error = 'Erro de conexão';
      notifyListeners();
      return false;
    }
  }

  /// Atualizar item do binder
  Future<bool> updateItem(String itemId, Map<String, dynamic> updates) async {
    try {
      final res = await _api.put('/binder/$itemId', updates);
      if (res.statusCode == 200) {
        // Atualizar local
        final idx = _items.indexWhere((i) => i.id == itemId);
        if (idx != -1) {
          final item = _items[idx];
          if (updates.containsKey('quantity')) {
            item.quantity = updates['quantity'] as int;
          }
          if (updates.containsKey('condition')) {
            item.condition = updates['condition'] as String;
          }
          if (updates.containsKey('is_foil')) {
            item.isFoil = updates['is_foil'] as bool;
          }
          if (updates.containsKey('for_trade')) {
            item.forTrade = updates['for_trade'] as bool;
          }
          if (updates.containsKey('for_sale')) {
            item.forSale = updates['for_sale'] as bool;
          }
          if (updates.containsKey('price')) {
            item.price = updates['price'] != null
                ? (updates['price'] as num).toDouble()
                : null;
          }
          if (updates.containsKey('notes')) {
            item.notes = updates['notes'] as String?;
          }
          notifyListeners();
        }
        await fetchStats();
        return true;
      } else {
        _error = res.data?['error'] ?? 'Erro ao atualizar';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] updateItem: $e');
      _error = 'Erro de conexão';
      notifyListeners();
      return false;
    }
  }

  /// Remover item do binder
  Future<bool> removeItem(String itemId) async {
    try {
      final res = await _api.delete('/binder/$itemId');
      if (res.statusCode == 200) {
        _items.removeWhere((i) => i.id == itemId);
        notifyListeners();
        await fetchStats();
        return true;
      } else {
        _error = res.data?['error'] ?? 'Erro ao remover';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] removeItem: $e');
      _error = 'Erro de conexão';
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Direct fetch (for independent list views by list_type)
  // ---------------------------------------------------------------

  /// Fetches binder items directly without updating shared provider state.
  /// Returns a list of BinderItem or null on error.
  /// Used by _BinderListView to manage its own state independently.
  Future<List<BinderItem>?> fetchBinderDirect({
    required String listType,
    int page = 1,
    int limit = 20,
    String? condition,
    String? search,
    bool? forTrade,
    bool? forSale,
  }) async {
    try {
      var endpoint = '/binder?page=$page&limit=$limit&list_type=$listType';
      if (condition != null) endpoint += '&condition=$condition';
      if (search != null && search.isNotEmpty) {
        endpoint += '&search=${Uri.encodeComponent(search)}';
      }
      if (forTrade == true) endpoint += '&for_trade=true';
      if (forSale == true) endpoint += '&for_sale=true';

      final res = await _api.get(endpoint);
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        return (data['data'] as List<dynamic>? ?? [])
            .map((e) => BinderItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return null;
    } catch (e) {
      debugPrint('[❌ BinderProvider] fetchBinderDirect($listType): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------
  // Public Binder Direct (for independent tabs by list_type)
  // ---------------------------------------------------------------

  /// Fetches a public user's binder items directly without updating shared state.
  /// Returns a list of BinderItem or null on error.
  Future<List<BinderItem>?> fetchPublicBinderDirect({
    required String userId,
    required String listType,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _api.get(
        '/community/binders/$userId?page=$page&limit=$limit&list_type=$listType',
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        // Update owner if not set yet
        _publicOwner ??= data['owner'] as Map<String, dynamic>?;
        return (data['data'] as List<dynamic>? ?? [])
            .map((e) => BinderItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return null;
    } catch (e) {
      debugPrint('[❌ BinderProvider] fetchPublicBinderDirect($userId, $listType): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------
  // Public Binder (outro usuário)
  // ---------------------------------------------------------------

  Future<void> fetchPublicBinder(String userId, {bool reset = false}) async {
    if (_isLoadingPublic) return;
    if (!reset && !_hasMorePublic) return;

    if (reset) {
      _publicPage = 1;
      _publicItems = [];
      _hasMorePublic = true;
      _publicOwner = null;
    }

    _isLoadingPublic = true;
    _publicError = null;
    notifyListeners();

    try {
      final res = await _api.get(
        '/community/binders/$userId?page=$_publicPage&limit=20',
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        _publicOwner = data['owner'] as Map<String, dynamic>?;
        final list = (data['data'] as List<dynamic>? ?? [])
            .map((e) => BinderItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _publicItems.addAll(list);
        _hasMorePublic = list.length >= 20;
        _publicPage++;
      } else {
        _publicError = res.data?['error'] ?? 'Erro ao carregar fichário';
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] fetchPublicBinder: $e');
      _publicError = 'Não foi possível conectar ao servidor';
    } finally {
      _isLoadingPublic = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------
  // Marketplace (global)
  // ---------------------------------------------------------------

  Future<void> fetchMarketplace({
    String? search,
    String? condition,
    bool? forTrade,
    bool? forSale,
    bool reset = false,
  }) async {
    if (_isLoadingMarket) return;
    if (!reset && !_hasMoreMarket) return;

    if (reset) {
      _marketPage = 1;
      _marketItems = [];
      _hasMoreMarket = true;
    }

    _isLoadingMarket = true;
    _marketError = null;
    notifyListeners();

    try {
      var endpoint = '/community/marketplace?page=$_marketPage&limit=20';
      if (search != null && search.isNotEmpty) {
        endpoint += '&search=${Uri.encodeComponent(search)}';
      }
      if (condition != null) endpoint += '&condition=$condition';
      if (forTrade == true) endpoint += '&for_trade=true';
      if (forSale == true) endpoint += '&for_sale=true';

      final res = await _api.get(endpoint);
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        final list = (data['data'] as List<dynamic>? ?? [])
            .map((e) => MarketplaceItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _marketItems.addAll(list);
        _hasMoreMarket = list.length >= 20;
        _marketPage++;
      } else {
        _marketError = res.data?['error'] ?? 'Erro ao carregar marketplace';
      }
    } catch (e) {
      debugPrint('[❌ BinderProvider] fetchMarketplace: $e');
      _marketError = 'Não foi possível conectar ao servidor';
    } finally {
      _isLoadingMarket = false;
      notifyListeners();
    }
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    _items = [];
    _stats = null;
    _isLoading = false;
    _error = null;
    _page = 1;
    _hasMore = true;
    _currentFilter = null;
    _currentSearch = null;
    _filterForTrade = null;
    _filterForSale = null;
    _currentListType = null;
    _marketItems = [];
    _isLoadingMarket = false;
    _marketError = null;
    _marketPage = 1;
    _hasMoreMarket = true;
    _publicItems = [];
    _isLoadingPublic = false;
    _publicError = null;
    _publicPage = 1;
    _hasMorePublic = true;
    _publicOwner = null;
    notifyListeners();
  }
}
