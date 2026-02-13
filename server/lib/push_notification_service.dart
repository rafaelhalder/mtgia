import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Serviço para enviar push notifications via Firebase Cloud Messaging (FCM).
///
/// Usa FCM HTTP v1 API com Service Account (OAuth2).
/// Requer arquivo `firebase-service-account.json` na raiz do server.
///
/// Doc: https://firebase.google.com/docs/cloud-messaging/send-message
class PushNotificationService {
  static String? _cachedAccessToken;
  static DateTime? _tokenExpiry;
  static Map<String, dynamic>? _serviceAccount;

  /// Carrega o Service Account JSON
  static Map<String, dynamic>? _loadServiceAccount() {
    if (_serviceAccount != null) return _serviceAccount;

    // Tenta vários caminhos possíveis
    final paths = [
      'firebase-service-account.json',
      '/app/firebase-service-account.json',
      '../firebase-service-account.json',
    ];

    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          _serviceAccount =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          print('[FCM] Service Account carregado de: $path');
          return _serviceAccount;
        } catch (e) {
          print('[⚠️ FCM] Erro ao ler Service Account: $e');
        }
      }
    }

    // Também aceita via variável de ambiente (base64 encoded)
    final envSa = Platform.environment['FIREBASE_SERVICE_ACCOUNT_BASE64'];
    if (envSa != null && envSa.isNotEmpty) {
      try {
        final decoded = utf8.decode(base64Decode(envSa));
        _serviceAccount = jsonDecode(decoded) as Map<String, dynamic>;
        print('[FCM] Service Account carregado de env var');
        return _serviceAccount;
      } catch (e) {
        print('[⚠️ FCM] Erro ao decodificar Service Account da env: $e');
      }
    }

    print('[⚠️ FCM] Service Account não encontrado - push desabilitado');
    return null;
  }

  /// Gera JWT para autenticação OAuth2
  static String _createJwt(Map<String, dynamic> sa) {
    final now = DateTime.now().toUtc();
    final exp = now.add(const Duration(hours: 1));

    final header = {'alg': 'RS256', 'typ': 'JWT'};

    final payload = {
      'iss': sa['client_email'],
      'sub': sa['client_email'],
      'aud': 'https://oauth2.googleapis.com/token',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': exp.millisecondsSinceEpoch ~/ 1000,
      'scope': 'https://www.googleapis.com/auth/firebase.messaging',
    };

    final headerB64 = base64Url.encode(utf8.encode(jsonEncode(header)));
    final payloadB64 = base64Url.encode(utf8.encode(jsonEncode(payload)));

    final signInput = '$headerB64.$payloadB64';

    // Assinar com RSA-SHA256 usando a private_key
    final privateKeyPem = sa['private_key'] as String;
    final signature = _signWithRsa256(signInput, privateKeyPem);

    return '$signInput.$signature';
  }

  /// Assina dados com RSA-SHA256 usando PEM private key
  static String _signWithRsa256(String data, String privateKeyPem) {
    // Usar dart:io para assinar (mais simples que importar crypto pesado)
    // Alternativa: usar package:pointycastle ou package:crypto_keys
    // Aqui usamos uma abordagem via Process (openssl)
    try {
      // Criar arquivos temporários
      final tempDir = Directory.systemTemp.createTempSync('fcm_');
      final keyFile = File('${tempDir.path}/key.pem')
        ..writeAsStringSync(privateKeyPem);
      final dataFile = File('${tempDir.path}/data.txt')
        ..writeAsStringSync(data);
      final sigFile = File('${tempDir.path}/sig.bin');

      // Assinar com openssl
      final result = Process.runSync('openssl', [
        'dgst',
        '-sha256',
        '-sign',
        keyFile.path,
        '-out',
        sigFile.path,
        dataFile.path,
      ]);

      if (result.exitCode != 0) {
        print('[⚠️ FCM] Erro ao assinar JWT: ${result.stderr}');
        return '';
      }

      final signature = sigFile.readAsBytesSync();
      final sigB64 = base64Url.encode(signature).replaceAll('=', '');

      // Limpar arquivos temporários
      tempDir.deleteSync(recursive: true);

      return sigB64;
    } catch (e) {
      print('[⚠️ FCM] Exceção ao assinar JWT: $e');
      return '';
    }
  }

  /// Obtém Access Token OAuth2 (com cache)
  static Future<String?> _getAccessToken() async {
    final sa = _loadServiceAccount();
    if (sa == null) return null;

    // Usar token em cache se ainda válido (com margem de 5 min)
    if (_cachedAccessToken != null && _tokenExpiry != null) {
      if (DateTime.now()
          .toUtc()
          .isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        return _cachedAccessToken;
      }
    }

    try {
      final jwt = _createJwt(sa);
      if (jwt.isEmpty) return null;

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': jwt,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedAccessToken = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
        print('[FCM] Access Token obtido (expira em ${expiresIn}s)');
        return _cachedAccessToken;
      } else {
        print('[⚠️ FCM] Falha ao obter token: ${response.statusCode}');
        print('[⚠️ FCM] Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('[⚠️ FCM] Exceção ao obter Access Token: $e');
      return null;
    }
  }

  /// Envia push notification para um usuário específico.
  /// Busca o fcm_token do usuário no banco.
  /// Silencioso: nunca lança exceção.
  static Future<void> sendToUser({
    required Pool pool,
    required String userId,
    required String title,
    String? body,
    Map<String, String>? data,
  }) async {
    final sa = _loadServiceAccount();
    if (sa == null) {
      // FCM não configurado — pula silenciosamente (dev mode)
      return;
    }

    try {
      // Busca FCM token do usuário
      final result = await pool.execute(
        Sql.named('SELECT fcm_token FROM users WHERE id = @id LIMIT 1'),
        parameters: {'id': userId},
      );

      if (result.isEmpty) return;
      final fcmToken = result.first.toColumnMap()['fcm_token'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) return;

      // Envia via FCM HTTP v1 API
      await _sendFcmMessageV1(
        projectId: sa['project_id'] as String,
        token: fcmToken,
        title: title,
        body: body,
        data: data,
      );
    } catch (e) {
      print('[⚠️ PushNotificationService] Falha ao enviar push: $e');
    }
  }

  /// Envia mensagem FCM via HTTP v1 API
  static Future<void> _sendFcmMessageV1({
    required String projectId,
    required String token,
    required String title,
    String? body,
    Map<String, String>? data,
  }) async {
    final accessToken = await _getAccessToken();
    if (accessToken == null) {
      print('[⚠️ FCM] Sem Access Token, abortando envio');
      return;
    }

    final payload = {
      'message': {
        'token': token,
        'notification': {
          'title': title,
          if (body != null) 'body': body,
        },
        if (data != null) 'data': data,
        'android': {
          'priority': 'high',
          'notification': {
            'sound': 'default',
            'channel_id': 'manaloom_notifications',
          },
        },
        'apns': {
          'payload': {
            'aps': {
              'sound': 'default',
              'badge': 1,
            },
          },
        },
      },
    };

    try {
      final url =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print('[FCM] ✅ Push enviado com sucesso');
      } else {
        print('[⚠️ FCM] Status ${response.statusCode}: ${response.body}');

        // Erros de token inválido
        if (response.statusCode == 404 || response.statusCode == 400) {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          final error = errorBody['error'] as Map<String, dynamic>?;
          final details = error?['details'] as List?;
          final errorCode = details?.firstOrNull?['errorCode'] as String?;

          if (errorCode == 'UNREGISTERED' || errorCode == 'INVALID_ARGUMENT') {
            print('[FCM] Token inválido ou expirado');
            // Aqui poderíamos limpar o token do banco se tivéssemos o pool
          }
        }
      }
    } catch (e) {
      print('[⚠️ FCM] Erro na request v1: $e');
    }
  }

  /// Envia push para múltiplos tokens (batch)
  static Future<void> sendToMultipleTokens({
    required List<String> tokens,
    required String title,
    String? body,
    Map<String, String>? data,
  }) async {
    final sa = _loadServiceAccount();
    if (sa == null) return;

    final projectId = sa['project_id'] as String;

    // FCM v1 não tem envio em batch direto, então enviamos um por um
    // mas em paralelo com limite de 10 simultâneos
    final futures = <Future>[];
    for (final token in tokens) {
      futures.add(_sendFcmMessageV1(
        projectId: projectId,
        token: token,
        title: title,
        body: body,
        data: data,
      ));

      // Limitar paralelismo
      if (futures.length >= 10) {
        await Future.wait(futures);
        futures.clear();
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }
}
