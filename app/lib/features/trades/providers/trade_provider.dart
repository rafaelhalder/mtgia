import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// =====================================================================
// Models
// =====================================================================

class TradeUser {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  TradeUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  String get label => displayName ?? username;

  factory TradeUser.fromJson(Map<String, dynamic> json) {
    return TradeUser(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class TradeItemCard {
  final String id;
  final String name;
  final String? imageUrl;
  final String? setCode;
  final String? manaCost;
  final String? rarity;

  TradeItemCard({
    required this.id,
    required this.name,
    this.imageUrl,
    this.setCode,
    this.manaCost,
    this.rarity,
  });

  factory TradeItemCard.fromJson(Map<String, dynamic> json) {
    return TradeItemCard(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      setCode: json['set_code'] as String?,
      manaCost: json['mana_cost'] as String?,
      rarity: json['rarity'] as String?,
    );
  }
}

class TradeItem {
  final String id;
  final String binderItemId;
  final String direction; // 'offering' | 'requesting'
  final int quantity;
  final double? agreedPrice;
  final String? condition;
  final bool? isFoil;
  final TradeItemCard card;

  TradeItem({
    required this.id,
    required this.binderItemId,
    required this.direction,
    required this.quantity,
    this.agreedPrice,
    this.condition,
    this.isFoil,
    required this.card,
  });

  factory TradeItem.fromJson(Map<String, dynamic> json) {
    return TradeItem(
      id: json['id'] as String,
      binderItemId: json['binder_item_id'] as String? ?? '',
      direction: json['direction'] as String? ?? 'offering',
      quantity: json['quantity'] as int? ?? 1,
      agreedPrice: json['agreed_price'] != null
          ? (json['agreed_price'] as num).toDouble()
          : null,
      condition: json['condition'] as String?,
      isFoil: json['is_foil'] as bool?,
      card: TradeItemCard.fromJson(
        json['card'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class TradeMessage {
  final String id;
  final String senderId;
  final String? senderUsername;
  final String? senderDisplayName;
  final String? senderAvatar;
  final String? message;
  final String? attachmentUrl;
  final String? attachmentType;
  final DateTime createdAt;

  TradeMessage({
    required this.id,
    required this.senderId,
    this.senderUsername,
    this.senderDisplayName,
    this.senderAvatar,
    this.message,
    this.attachmentUrl,
    this.attachmentType,
    required this.createdAt,
  });

  factory TradeMessage.fromJson(Map<String, dynamic> json) {
    return TradeMessage(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      senderUsername: json['sender_username'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
      message: json['message'] as String?,
      attachmentUrl: json['attachment_url'] as String?,
      attachmentType: json['attachment_type'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class TradeStatusEntry {
  final String id;
  final String? oldStatus;
  final String newStatus;
  final String? notes;
  final String? changedByUsername;
  final DateTime createdAt;

  TradeStatusEntry({
    required this.id,
    this.oldStatus,
    required this.newStatus,
    this.notes,
    this.changedByUsername,
    required this.createdAt,
  });

  factory TradeStatusEntry.fromJson(Map<String, dynamic> json) {
    return TradeStatusEntry(
      id: json['id'] as String,
      oldStatus: json['old_status'] as String?,
      newStatus: json['new_status'] as String,
      notes: json['notes'] as String?,
      changedByUsername: json['changed_by_username'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class TradeOffer {
  final String id;
  final String status;
  final String type; // 'trade', 'sale', 'mixed'
  final String? message;
  final double? paymentAmount;
  final String? paymentCurrency;
  final String? paymentMethod;
  final String? deliveryMethod;
  final String? trackingCode;
  final TradeUser sender;
  final TradeUser receiver;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Preenchido no detail
  final List<TradeItem> myItems;
  final List<TradeItem> theirItems;
  final List<TradeMessage> messages;
  final List<TradeStatusEntry> statusHistory;

  // Preenchido na listagem
  final int? offeringCount;
  final int? requestingCount;
  final int? messageCount;

  TradeOffer({
    required this.id,
    required this.status,
    required this.type,
    this.message,
    this.paymentAmount,
    this.paymentCurrency,
    this.paymentMethod,
    this.deliveryMethod,
    this.trackingCode,
    required this.sender,
    required this.receiver,
    required this.createdAt,
    required this.updatedAt,
    this.myItems = const [],
    this.theirItems = const [],
    this.messages = const [],
    this.statusHistory = const [],
    this.offeringCount,
    this.requestingCount,
    this.messageCount,
  });

  /// Factory para a listagem (GET /trades)
  factory TradeOffer.fromListJson(Map<String, dynamic> json) {
    return TradeOffer(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'pending',
      type: json['type'] as String? ?? 'trade',
      message: json['message'] as String?,
      paymentAmount: json['payment_amount'] != null
          ? (json['payment_amount'] as num).toDouble()
          : null,
      paymentCurrency: json['payment_currency'] as String?,
      trackingCode: json['tracking_code'] as String?,
      deliveryMethod: json['delivery_method'] as String?,
      sender: TradeUser.fromJson(json['sender'] as Map<String, dynamic>),
      receiver: TradeUser.fromJson(json['receiver'] as Map<String, dynamic>),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      offeringCount: json['offering_count'] as int?,
      requestingCount: json['requesting_count'] as int?,
      messageCount: json['message_count'] as int?,
    );
  }

  /// Factory para o detalhe (GET /trades/:id)
  factory TradeOffer.fromDetailJson(Map<String, dynamic> json) {
    return TradeOffer(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'pending',
      type: json['type'] as String? ?? 'trade',
      message: json['message'] as String?,
      paymentAmount: json['payment_amount'] != null
          ? (json['payment_amount'] as num).toDouble()
          : null,
      paymentCurrency: json['payment_currency'] as String?,
      paymentMethod: json['payment_method'] as String?,
      deliveryMethod: json['delivery_method'] as String?,
      trackingCode: json['tracking_code'] as String?,
      sender: TradeUser.fromJson(json['sender'] as Map<String, dynamic>),
      receiver: TradeUser.fromJson(json['receiver'] as Map<String, dynamic>),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      myItems: (json['my_items'] as List<dynamic>?)
              ?.map((e) => TradeItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      theirItems: (json['their_items'] as List<dynamic>?)
              ?.map((e) => TradeItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => TradeMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      statusHistory: (json['status_history'] as List<dynamic>?)
              ?.map((e) => TradeStatusEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// =====================================================================
// Helper: cores/ícones por status
// =====================================================================

class TradeStatusHelper {
  static Color color(String status) {
    switch (status) {
      case 'pending':
        return AppTheme.mythicGold;
      case 'accepted':
        return AppTheme.loomCyan;
      case 'shipped':
        return AppTheme.manaViolet;
      case 'delivered':
        return AppTheme.success;
      case 'completed':
        return AppTheme.success;
      case 'declined':
        return AppTheme.error;
      case 'cancelled':
        return AppTheme.disabled;
      case 'disputed':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  static IconData icon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top;
      case 'accepted':
        return Icons.handshake;
      case 'shipped':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.inventory_2;
      case 'completed':
        return Icons.check_circle;
      case 'declined':
        return Icons.cancel;
      case 'cancelled':
        return Icons.block;
      case 'disputed':
        return Icons.warning_amber;
      default:
        return Icons.help_outline;
    }
  }

  static String label(String status) {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'accepted':
        return 'Aceito';
      case 'shipped':
        return 'Enviado';
      case 'delivered':
        return 'Entregue';
      case 'completed':
        return 'Concluído';
      case 'declined':
        return 'Recusado';
      case 'cancelled':
        return 'Cancelado';
      case 'disputed':
        return 'Disputado';
      default:
        return status;
    }
  }
}

// =====================================================================
// Provider
// =====================================================================

class TradeProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  // ─── State ──────────────────────────────────────────────────
  List<TradeOffer> _trades = [];
  TradeOffer? _selectedTrade;
  bool _isLoading = false;
  String? _errorMessage;
  int _totalTrades = 0;
  int _currentPage = 1;

  // Chat messages (for polling / incremental fetch)
  List<TradeMessage> _chatMessages = [];
  int _chatTotal = 0;

  // ─── Getters ────────────────────────────────────────────────
  List<TradeOffer> get trades => _trades;
  TradeOffer? get selectedTrade => _selectedTrade;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get totalTrades => _totalTrades;
  int get currentPage => _currentPage;
  List<TradeMessage> get chatMessages => _chatMessages;
  int get chatTotal => _chatTotal;

  // ─── Fetch trades (list) ────────────────────────────────────
  Future<void> fetchTrades({
    String? status,
    String role = 'all',
    int page = 1,
    int limit = 20,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queryParts = <String>[
        'page=$page',
        'limit=$limit',
        'role=$role',
      ];
      if (status != null && status.isNotEmpty) {
        queryParts.add('status=$status');
      }
      final query = queryParts.join('&');
      final res = await _api.get('/trades?$query');

      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        final list = (data['data'] as List<dynamic>?) ?? [];
        _trades = list
            .map((e) => TradeOffer.fromListJson(e as Map<String, dynamic>))
            .toList();
        _totalTrades = data['total'] as int? ?? _trades.length;
        _currentPage = data['page'] as int? ?? page;
      } else {
        _errorMessage = (res.data is Map)
            ? res.data['error']?.toString()
            : 'Erro ao carregar trades';
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carrega próxima página de trades (append, para scroll infinito)
  Future<void> fetchMoreTrades({
    String? status,
    String role = 'all',
    int limit = 20,
  }) async {
    if (_isLoading) return;
    final nextPage = _currentPage + 1;

    _isLoading = true;
    notifyListeners();

    try {
      final queryParts = <String>[
        'page=$nextPage',
        'limit=$limit',
        'role=$role',
      ];
      if (status != null && status.isNotEmpty) {
        queryParts.add('status=$status');
      }
      final query = queryParts.join('&');
      final res = await _api.get('/trades?$query');

      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        final list = (data['data'] as List<dynamic>?) ?? [];
        final newTrades = list
            .map((e) => TradeOffer.fromListJson(e as Map<String, dynamic>))
            .toList();
        _trades.addAll(newTrades);
        _totalTrades = data['total'] as int? ?? _trades.length;
        _currentPage = data['page'] as int? ?? nextPage;
      }
    } catch (e) {
      debugPrint('[TradeProvider] fetchMoreTrades error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Fetch trade detail ─────────────────────────────────────
  Future<void> fetchTradeDetail(String tradeId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _api.get('/trades/$tradeId');

      if (res.statusCode == 200) {
        _selectedTrade = TradeOffer.fromDetailJson(
          res.data as Map<String, dynamic>,
        );
        // Também popula o chat
        _chatMessages = _selectedTrade!.messages;
        _chatTotal = _chatMessages.length;
      } else {
        _errorMessage = (res.data is Map)
            ? res.data['error']?.toString()
            : 'Erro ao carregar trade';
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Create trade proposal ──────────────────────────────────
  Future<bool> createTrade({
    required String receiverId,
    String type = 'trade',
    String? message,
    List<Map<String, dynamic>> myItems = const [],
    List<Map<String, dynamic>> requestedItems = const [],
    double? paymentAmount,
    String? paymentMethod,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final body = <String, dynamic>{
        'receiver_id': receiverId,
        'type': type,
        'my_items': myItems,
        'requested_items': requestedItems,
      };
      if (message != null) body['message'] = message;
      if (paymentAmount != null) body['payment_amount'] = paymentAmount;
      if (paymentMethod != null) body['payment_method'] = paymentMethod;

      final res = await _api.post('/trades', body);

      if (res.statusCode == 201) {
        // Recarregar a lista
        await fetchTrades();
        return true;
      } else {
        _errorMessage = (res.data is Map)
            ? res.data['error']?.toString()
            : 'Erro ao criar trade';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Respond (accept / decline) ─────────────────────────────
  Future<bool> respondToTrade(String tradeId, String action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _api.put('/trades/$tradeId/respond', {
        'action': action,
      });

      if (res.statusCode == 200) {
        // Recarregar detalhe
        await fetchTradeDetail(tradeId);
        return true;
      } else {
        _errorMessage = (res.data is Map)
            ? res.data['error']?.toString()
            : 'Erro ao responder trade';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Update status (ship, deliver, complete, etc.) ──────────
  Future<bool> updateTradeStatus(
    String tradeId,
    String status, {
    String? trackingCode,
    String? deliveryMethod,
    String? notes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final body = <String, dynamic>{'status': status};
      if (trackingCode != null) body['tracking_code'] = trackingCode;
      if (deliveryMethod != null) body['delivery_method'] = deliveryMethod;
      if (notes != null) body['notes'] = notes;

      final res = await _api.put('/trades/$tradeId/status', body);

      if (res.statusCode == 200) {
        await fetchTradeDetail(tradeId);
        return true;
      } else {
        _errorMessage = (res.data is Map)
            ? res.data['error']?.toString()
            : 'Erro ao atualizar status';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Fetch chat messages ────────────────────────────────────
  Future<void> fetchMessages(String tradeId, {int page = 1, int limit = 50}) async {
    try {
      final res = await _api.get('/trades/$tradeId/messages?page=$page&limit=$limit');

      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        final list = (data['data'] as List<dynamic>?) ?? [];
        _chatMessages = list
            .map((e) => TradeMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        _chatTotal = data['total'] as int? ?? _chatMessages.length;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TradeProvider] fetchMessages error: $e');
    }
  }

  // ─── Send chat message ──────────────────────────────────────
  Future<bool> sendMessage(
    String tradeId,
    String message, {
    String? attachmentUrl,
    String? attachmentType,
  }) async {
    try {
      final body = <String, dynamic>{'message': message};
      if (attachmentUrl != null) body['attachment_url'] = attachmentUrl;
      if (attachmentType != null) body['attachment_type'] = attachmentType;

      final res = await _api.post('/trades/$tradeId/messages', body);

      if (res.statusCode == 201) {
        // Adicionar localmente para feedback imediato
        final msgData = res.data as Map<String, dynamic>;
        _chatMessages.add(TradeMessage.fromJson(msgData));
        _chatTotal++;
        notifyListeners();
        return true;
      } else {
        _errorMessage = (res.data is Map)
            ? res.data['error']?.toString()
            : 'Erro ao enviar mensagem';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      notifyListeners();
      return false;
    }
  }

  // ─── Clear ──────────────────────────────────────────────────
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearSelectedTrade() {
    _selectedTrade = null;
    _chatMessages = [];
    _chatTotal = 0;
    notifyListeners();
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    _trades = [];
    _selectedTrade = null;
    _isLoading = false;
    _errorMessage = null;
    _totalTrades = 0;
    _currentPage = 1;
    _chatMessages = [];
    _chatTotal = 0;
    notifyListeners();
  }
}
