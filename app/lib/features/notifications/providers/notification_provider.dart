import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';

// ─── Model ───────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String type;
  final String? referenceId;
  final String title;
  final String? body;
  final String? readAt;
  final String createdAt;

  AppNotification({
    required this.id,
    required this.type,
    this.referenceId,
    required this.title,
    this.body,
    this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String? ?? '',
      referenceId: json['reference_id'] as String?,
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      readAt: json['read_at'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

// ─── Provider ────────────────────────────────────────────────

class NotificationProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => _notifications;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Timer? _pollTimer;

  /// Inicia polling de contagem de não-lidas a cada 30s
  void startPolling() {
    _pollTimer?.cancel();
    fetchUnreadCount();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchUnreadCount();
    });
  }

  /// Para o polling
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  /// Busca contagem de não-lidas (badge)
  Future<void> fetchUnreadCount() async {
    try {
      final resp = await _api.get('/notifications/count');
      if (resp.statusCode == 200 && resp.data is Map) {
        final newCount = (resp.data as Map)['unread'] as int? ?? 0;
        if (newCount != _unreadCount) {
          _unreadCount = newCount;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[NotificationProvider] fetchUnreadCount error: $e');
    }
  }

  /// Busca lista de notificações
  Future<void> fetchNotifications({
    int page = 1,
    int limit = 30,
    bool unreadOnly = false,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final query = 'page=$page&limit=$limit${unreadOnly ? '&unread_only=true' : ''}';
      final resp = await _api.get('/notifications?$query');
      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['data'] as List?) ?? [];
        _notifications = list
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[NotificationProvider] fetchNotifications error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Marca uma notificação como lida
  Future<void> markAsRead(String notificationId) async {
    try {
      await _api.put('/notifications/$notificationId/read', {});
      final idx = _notifications.indexWhere((n) => n.id == notificationId);
      if (idx >= 0) {
        final old = _notifications[idx];
        _notifications[idx] = AppNotification(
          id: old.id,
          type: old.type,
          referenceId: old.referenceId,
          title: old.title,
          body: old.body,
          readAt: DateTime.now().toIso8601String(),
          createdAt: old.createdAt,
        );
        _unreadCount = (_unreadCount - 1).clamp(0, 999);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[NotificationProvider] markAsRead error: $e');
    }
  }

  /// Marca todas como lidas
  Future<void> markAllAsRead() async {
    try {
      await _api.put('/notifications/read-all', {});
      for (var i = 0; i < _notifications.length; i++) {
        final old = _notifications[i];
        if (!old.isRead) {
          _notifications[i] = AppNotification(
            id: old.id,
            type: old.type,
            referenceId: old.referenceId,
            title: old.title,
            body: old.body,
            readAt: DateTime.now().toIso8601String(),
            createdAt: old.createdAt,
          );
        }
      }
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationProvider] markAllAsRead error: $e');
    }
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    stopPolling();
    _notifications = [];
    _unreadCount = 0;
    _isLoading = false;
    notifyListeners();
  }
}
