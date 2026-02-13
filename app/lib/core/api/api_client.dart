import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_performance/firebase_performance.dart';

/// Response wrapper para padronizar respostas da API
class ApiResponse {
  final int statusCode;
  final dynamic data;
  final int durationMs; // Tempo da requisição em ms

  ApiResponse(this.statusCode, this.data, {this.durationMs = 0});
}

class ApiClient {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// URL do servidor de produção (EasyPanel / Digital Ocean).
  static const String _productionUrl = 'https://evolution-cartinhas.8ktevp.easypanel.host';

  // ──────────────────────────────────────────
  // Cache do token em memória (evita SharedPreferences a cada request)
  // ──────────────────────────────────────────
  static String? _cachedToken;

  /// Atualiza o token em memória (chamar no login/register/logout).
  static void setToken(String? token) {
    _cachedToken = token;
  }

  /// Instância singleton do http.Client para reutilizar conexões TCP.
  static final http.Client _httpClient = http.Client();

  // Retorna a URL correta dependendo do ambiente
  static String get baseUrl {
    if (_envBaseUrl.trim().isNotEmpty) {
      return _envBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    }
    // Todas as plataformas usam o servidor de produção (EasyPanel).
    // Para dev local, passe --dart-define=API_BASE_URL=http://localhost:8080
    return _productionUrl;
  }

  /// Log da URL base resolvida (chamado uma vez no boot)
  static void debugLogBaseUrl() {
    debugPrint('[🌐 ApiClient] baseUrl = $baseUrl');
    debugPrint('[🌐 ApiClient] platform = $defaultTargetPlatform | kIsWeb=$kIsWeb | kDebugMode=$kDebugMode');
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_cachedToken != null) 'Authorization': 'Bearer $_cachedToken',
    };
  }

  /// Carrega token do disco para o cache (chamado 1x no boot).
  static Future<void> loadTokenFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('auth_token');
  }

  /// Cria um HttpMetric para rastrear a requisição no Firebase Performance
  HttpMetric? _createMetric(String url, HttpMethod method) {
    try {
      return FirebasePerformance.instance.newHttpMetric(url, method);
    } catch (e) {
      debugPrint('[⚠️ ApiClient] Firebase Performance não disponível: $e');
      return null;
    }
  }

  Future<ApiResponse> get(String endpoint) async {
    final url = '$baseUrl$endpoint';
    final headers = _getHeaders();
    final metric = _createMetric(url, HttpMethod.Get);
    final stopwatch = Stopwatch()..start();
    
    debugPrint('[🌐 ApiClient] GET $url');
    
    try {
      await metric?.start();
      
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      
      stopwatch.stop();
      
      // Registra métricas
      metric?.responseContentType = response.headers['content-type'];
      metric?.httpResponseCode = response.statusCode;
      metric?.responsePayloadSize = response.contentLength ?? response.bodyBytes.length;
      await metric?.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds;
      debugPrint('[🌐 ApiClient] GET $endpoint → ${response.statusCode} (${durationMs}ms)');
      
      // Alerta requisições lentas
      if (durationMs > 2000) {
        debugPrint('[⚠️ SLOW REQUEST] GET $endpoint demorou ${durationMs}ms');
      }
      
      return _parseResponse(response, durationMs: durationMs);
    } catch (e) {
      stopwatch.stop();
      await metric?.stop();
      debugPrint('[❌ ApiClient] GET $endpoint FALHOU após ${stopwatch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  Future<ApiResponse> post(String endpoint, Map<String, dynamic> body, {Duration? timeout}) async {
    final url = '$baseUrl$endpoint';
    final headers = _getHeaders();
    final metric = _createMetric(url, HttpMethod.Post);
    final stopwatch = Stopwatch()..start();
    final bodyBytes = utf8.encode(jsonEncode(body));
    
    // Endpoints de IA têm timeout maior (2 minutos)
    final isAiEndpoint = endpoint.startsWith('/ai/');
    final effectiveTimeout = timeout ?? (isAiEndpoint ? const Duration(minutes: 2) : const Duration(seconds: 15));
    
    debugPrint('[🌐 ApiClient] POST $url');
    
    try {
      await metric?.start();
      metric?.requestPayloadSize = bodyBytes.length;
      
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(effectiveTimeout);
      
      stopwatch.stop();
      
      metric?.responseContentType = response.headers['content-type'];
      metric?.httpResponseCode = response.statusCode;
      metric?.responsePayloadSize = response.contentLength ?? response.bodyBytes.length;
      await metric?.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds;
      debugPrint('[🌐 ApiClient] POST $endpoint → ${response.statusCode} (${durationMs}ms)');
      
      if (durationMs > 2000) {
        debugPrint('[⚠️ SLOW REQUEST] POST $endpoint demorou ${durationMs}ms');
      }
      
      return _parseResponse(response, durationMs: durationMs);
    } catch (e) {
      stopwatch.stop();
      await metric?.stop();
      debugPrint('[❌ ApiClient] POST $endpoint FALHOU após ${stopwatch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  Future<ApiResponse> put(String endpoint, Map<String, dynamic> body) async {
    final url = '$baseUrl$endpoint';
    final headers = _getHeaders();
    final metric = _createMetric(url, HttpMethod.Put);
    final stopwatch = Stopwatch()..start();
    
    debugPrint('[🌐 ApiClient] PUT $url');
    
    try {
      await metric?.start();
      
      final response = await _httpClient.put(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      
      stopwatch.stop();
      
      metric?.httpResponseCode = response.statusCode;
      await metric?.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds;
      debugPrint('[🌐 ApiClient] PUT $endpoint → ${response.statusCode} (${durationMs}ms)');
      
      if (durationMs > 2000) {
        debugPrint('[⚠️ SLOW REQUEST] PUT $endpoint demorou ${durationMs}ms');
      }
      
      return _parseResponse(response, durationMs: durationMs);
    } catch (e) {
      stopwatch.stop();
      await metric?.stop();
      debugPrint('[❌ ApiClient] PUT $endpoint FALHOU: $e');
      rethrow;
    }
  }

  Future<ApiResponse> patch(String endpoint, Map<String, dynamic> body) async {
    final url = '$baseUrl$endpoint';
    final headers = _getHeaders();
    final metric = _createMetric(url, HttpMethod.Patch);
    final stopwatch = Stopwatch()..start();
    
    debugPrint('[🌐 ApiClient] PATCH $url');
    
    try {
      await metric?.start();
      
      final response = await _httpClient.patch(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      
      stopwatch.stop();
      
      metric?.httpResponseCode = response.statusCode;
      await metric?.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds;
      debugPrint('[🌐 ApiClient] PATCH $endpoint → ${response.statusCode} (${durationMs}ms)');
      
      return _parseResponse(response, durationMs: durationMs);
    } catch (e) {
      stopwatch.stop();
      await metric?.stop();
      debugPrint('[❌ ApiClient] PATCH $endpoint FALHOU: $e');
      rethrow;
    }
  }

  Future<ApiResponse> delete(String endpoint) async {
    final url = '$baseUrl$endpoint';
    final headers = _getHeaders();
    final metric = _createMetric(url, HttpMethod.Delete);
    final stopwatch = Stopwatch()..start();
    
    debugPrint('[🌐 ApiClient] DELETE $url');
    
    try {
      await metric?.start();
      
      final response = await _httpClient.delete(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      
      stopwatch.stop();
      
      metric?.httpResponseCode = response.statusCode;
      await metric?.stop();
      
      final durationMs = stopwatch.elapsedMilliseconds;
      debugPrint('[🌐 ApiClient] DELETE $endpoint → ${response.statusCode} (${durationMs}ms)');
      
      return _parseResponse(response, durationMs: durationMs);
    } catch (e) {
      stopwatch.stop();
      await metric?.stop();
      debugPrint('[❌ ApiClient] DELETE $endpoint FALHOU: $e');
      rethrow;
    }
  }

  ApiResponse _parseResponse(http.Response response, {int durationMs = 0}) {
    dynamic data;
    
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } catch (e) {
        data = response.body;
      }
    }
    
    return ApiResponse(response.statusCode, data, durationMs: durationMs);
  }
}
