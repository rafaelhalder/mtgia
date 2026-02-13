import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

// ─── Models ──────────────────────────────────────────────────

class ConversationUser {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  ConversationUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  String get label => displayName ?? username;

  factory ConversationUser.fromJson(Map<String, dynamic> json) {
    return ConversationUser(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class Conversation {
  final String id;
  final ConversationUser otherUser;
  final String? lastMessage;
  final String? lastMessageSenderId;
  final int unreadCount;
  final String? lastMessageAt;
  final String? createdAt;

  Conversation({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.lastMessageAt,
    this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      otherUser: ConversationUser.fromJson(
        json['other_user'] as Map<String, dynamic>? ?? {},
      ),
      lastMessage: json['last_message'] as String?,
      lastMessageSenderId: json['last_message_sender_id'] as String?,
      unreadCount: json['unread_count'] as int? ?? 0,
      lastMessageAt: json['last_message_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

class DirectMessage {
  final String id;
  final String senderId;
  final String? senderUsername;
  final String? senderDisplayName;
  final String? senderAvatarUrl;
  final String message;
  final String? readAt;
  final String createdAt;

  DirectMessage({
    required this.id,
    required this.senderId,
    this.senderUsername,
    this.senderDisplayName,
    this.senderAvatarUrl,
    required this.message,
    this.readAt,
    required this.createdAt,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    return DirectMessage(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      senderUsername: json['sender_username'] as String?,
      senderDisplayName: json['sender_display_name'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      message: json['message'] as String? ?? '',
      readAt: json['read_at'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

// ─── Provider ────────────────────────────────────────────────

class MessageProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  List<DirectMessage> _messages = [];
  List<DirectMessage> get messages => _messages;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMessages = false;
  bool get isLoadingMessages => _isLoadingMessages;

  bool _isSending = false;
  bool get isSending => _isSending;

  String? _error;
  String? get error => _error;

  int _totalConversations = 0;
  int get totalConversations => _totalConversations;

  int _totalMessages = 0;
  int get totalMessages => _totalMessages;

  /// Contagem global de mensagens não-lidas (para badge no AppBar)
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  Timer? _pollTimer;

  /// Inicia polling global de unread count a cada 30s (chamado no login)
  void startPolling() {
    _pollTimer?.cancel();
    fetchUnreadCount();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchUnreadCount();
    });
  }

  /// Para o polling (chamado no logout)
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  /// Busca contagem de mensagens não-lidas (leve — só GET /conversations com limit pequeno)
  Future<void> fetchUnreadCount() async {
    try {
      final resp = await _api.get('/conversations?page=1&limit=50');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        int count = 0;
        for (final item in list) {
          count += (item['unread_count'] as int? ?? 0);
        }
        if (count != _unreadCount) {
          _unreadCount = count;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[MessageProvider] fetchUnreadCount error: $e');
    }
  }

  /// Busca lista de conversas do usuário
  Future<void> fetchConversations({int page = 1, int limit = 20}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _api.get('/conversations?page=$page&limit=$limit');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        _conversations = list
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList();
        _totalConversations = data['total'] as int? ?? list.length;
        // Sincronizar badge de unread
        _unreadCount = _conversations.fold(0, (sum, c) => sum + c.unreadCount);
      }
    } catch (e) {
      _error = '$e';
      debugPrint('[MessageProvider] fetchConversations error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cria ou obtém conversa com um usuário
  Future<Conversation?> getOrCreateConversation(String otherUserId) async {
    try {
      final resp = await _api.post('/conversations', {'user_id': otherUserId});
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final convData = resp.data as Map<String, dynamic>;
        final conv = Conversation(
          id: convData['id'] as String,
          otherUser: ConversationUser.fromJson(
            convData['other_user'] as Map<String, dynamic>? ?? {},
          ),
          createdAt: convData['created_at'] as String?,
        );
        return conv;
      }
    } catch (e) {
      debugPrint('[MessageProvider] getOrCreateConversation error: $e');
    }
    return null;
  }

  /// Busca mensagens de uma conversa
  Future<void> fetchMessages(String conversationId, {int page = 1, int limit = 50}) async {
    _isLoadingMessages = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _api.get(
        '/conversations/$conversationId/messages?page=$page&limit=$limit',
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        _messages = list
            .map((e) => DirectMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        _totalMessages = data['total'] as int? ?? list.length;
      }
    } catch (e) {
      _error = '$e';
      debugPrint('[MessageProvider] fetchMessages error: $e');
    } finally {
      _isLoadingMessages = false;
      notifyListeners();
    }
  }

  /// Envia mensagem em uma conversa
  Future<bool> sendMessage(String conversationId, String message) async {
    _isSending = true;
    notifyListeners();

    try {
      final resp = await _api.post(
        '/conversations/$conversationId/messages',
        {'message': message},
      );
      if (resp.statusCode == 201 && resp.data is Map) {
        final dm = DirectMessage.fromJson(resp.data as Map<String, dynamic>);
        _messages.insert(0, dm); // Mensagens em DESC, nova no topo
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[MessageProvider] sendMessage error: $e');
    } finally {
      _isSending = false;
      notifyListeners();
    }
    return false;
  }

  /// Marca mensagens da conversa como lidas
  Future<void> markAsRead(String conversationId) async {
    try {
      await _api.put('/conversations/$conversationId/read', {});
      // Atualizar o unread count local
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) {
        final old = _conversations[idx];
        _conversations[idx] = Conversation(
          id: old.id,
          otherUser: old.otherUser,
          lastMessage: old.lastMessage,
          lastMessageSenderId: old.lastMessageSenderId,
          unreadCount: 0,
          lastMessageAt: old.lastMessageAt,
          createdAt: old.createdAt,
        );
        // Recalcular badge global
        _unreadCount = _conversations.fold(0, (sum, c) => sum + c.unreadCount);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[MessageProvider] markAsRead error: $e');
    }
  }

  /// Total de mensagens não lidas em todas as conversas
  int get totalUnread =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    stopPolling();
    _conversations = [];
    _messages = [];
    _isLoading = false;
    _isLoadingMessages = false;
    _isSending = false;
    _error = null;
    _totalConversations = 0;
    _totalMessages = 0;
    _unreadCount = 0;
    notifyListeners();
  }
}
