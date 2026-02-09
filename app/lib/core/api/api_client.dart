import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Response wrapper para padronizar respostas da API
class ApiResponse {
  final int statusCode;
  final dynamic data;

  ApiResponse(this.statusCode, this.data);
}

class ApiClient {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// URL do servidor de produção (EasyPanel / Digital Ocean).
  static const String _productionUrl = 'https://evolution-cartinhas.8ktevp.easypanel.host';

  // Retorna a URL correta dependendo do ambiente
  static String get baseUrl {
    if (_envBaseUrl.trim().isNotEmpty) {
      return _envBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    }
    // Em produção ou dispositivo físico, usar o servidor remoto.
    // Em desktop/web local com servidor local, usar localhost.
    if (kIsWeb) {
      return 'http://localhost:8080';
    }
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      // Desktop: usar localhost se estiver rodando servidor local,
      // senão usar produção.
      return 'http://localhost:8080';
    }
    // Mobile (iOS / Android): sempre usar servidor remoto
    return _productionUrl;
  }

  /// Log da URL base resolvida (chamado uma vez no boot)
  static void debugLogBaseUrl() {
    debugPrint('[🌐 ApiClient] baseUrl = $baseUrl');
    debugPrint('[🌐 ApiClient] platform = $defaultTargetPlatform | kIsWeb=$kIsWeb | kDebugMode=$kDebugMode');
  }

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<ApiResponse> get(String endpoint) async {
    final headers = await _getHeaders();
    debugPrint('[🌐 ApiClient] GET $baseUrl$endpoint');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      debugPrint('[🌐 ApiClient] GET $endpoint → ${response.statusCode}');
      return _parseResponse(response);
    } catch (e) {
      debugPrint('[❌ ApiClient] GET $endpoint FALHOU: $e');
      rethrow;
    }
  }

  Future<ApiResponse> post(String endpoint, Map<String, dynamic> body) async {
    final url = '$baseUrl$endpoint';
    debugPrint('[🌐 ApiClient] POST $url');
    final headers = await _getHeaders();
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[🌐 ApiClient] POST $endpoint → ${response.statusCode}');
      return _parseResponse(response);
    } catch (e) {
      debugPrint('[❌ ApiClient] POST $endpoint FALHOU: $e');
      rethrow;
    }
  }

  Future<ApiResponse> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    return _parseResponse(response);
  }

  Future<ApiResponse> patch(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    return _parseResponse(response);
  }

  Future<ApiResponse> delete(String endpoint) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
    return _parseResponse(response);
  }

  ApiResponse _parseResponse(http.Response response) {
    dynamic data;
    
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } catch (e) {
        data = response.body;
      }
    }
    
    return ApiResponse(response.statusCode, data);
  }
}
