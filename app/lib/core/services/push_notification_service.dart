import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../firebase_options.dart';
import '../api/api_client.dart';

/// Handler de background — precisa ser top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[Push] Background message: ${message.messageId}');
}

/// Serviço centralizado para Push Notifications via Firebase.
///
/// Fluxo:
/// 1. `init()` → inicializa Firebase + solicita permissão
/// 2. `registerToken()` → envia FCM token pro server
/// 3. Escuta mensagens foreground/background/terminated
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final _api = ApiClient();
  FirebaseMessaging? _messaging;
  String? _currentToken;

  /// Callback para quando uma notificação é recebida em foreground.
  /// O consumer pode mostrar um snackbar ou atualizar badge.
  void Function(RemoteMessage message)? onForegroundMessage;

  /// Callback para quando o usuário toca na notificação.
  void Function(RemoteMessage message)? onMessageTap;

  /// Inicializa Firebase e configura handlers.
  /// Chamar uma vez no app startup.
  Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _messaging = FirebaseMessaging.instance;

      // Handler de background (top-level function)
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // Handler de foreground
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handler quando o app é aberto via tap na notificação
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Checa se o app foi aberto por notificação (terminated state)
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      debugPrint('[Push] Firebase inicializado');
    } catch (e) {
      debugPrint('[Push] Erro ao inicializar Firebase: $e');
    }
  }

  /// Solicita permissão e registra FCM token no server.
  /// Chamar após o login do usuário.
  Future<void> requestPermissionAndRegister() async {
    if (_messaging == null) {
      debugPrint('[Push] Firebase não inicializado');
      return;
    }

    try {
      // Solicita permissão (iOS requer, Android auto-concede)
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[Push] Permissão negada pelo usuário');
        return;
      }

      debugPrint(
          '[Push] Permissão: ${settings.authorizationStatus}');

      // Obtém FCM token
      final token = await _messaging!.getToken();
      if (token != null) {
        _currentToken = token;
        await _sendTokenToServer(token);
      }

      // Escuta mudanças de token (rotação automática do Firebase)
      _messaging!.onTokenRefresh.listen((newToken) {
        _currentToken = newToken;
        _sendTokenToServer(newToken);
      });
    } catch (e) {
      debugPrint('[Push] Erro ao registrar: $e');
    }
  }

  /// Remove o token do server (chamar no logout).
  Future<void> unregister() async {
    try {
      await _api.delete('/users/me/fcm-token');
      _currentToken = null;
      debugPrint('[Push] Token removido do server');
    } catch (e) {
      debugPrint('[Push] Erro ao remover token: $e');
    }
  }

  /// Envia o FCM token para o server.
  Future<void> _sendTokenToServer(String token) async {
    try {
      await _api.put('/users/me/fcm-token', {'token': token});
      debugPrint('[Push] Token registrado: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[Push] Erro ao enviar token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
        '[Push] Foreground: ${message.notification?.title}');
    onForegroundMessage?.call(message);
  }

  void _handleMessageTap(RemoteMessage message) {
    debugPrint(
        '[Push] Tap: ${message.data}');
    onMessageTap?.call(message);
  }

  String? get currentToken => _currentToken;
}
