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

  // Retorna a URL correta dependendo do ambiente (Android Emulator vs Outros)
  static String get baseUrl {
    if (_envBaseUrl.trim().isNotEmpty) {
      return _envBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    }
    if (kIsWeb) {
      return 'http://localhost:8080';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 é o endereço especial do emulador para acessar o localhost do PC
      return 'http://10.0.2.2:8080';
    }
    // Para iOS, Windows, Linux, macOS
    return 'http://localhost:8080';
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
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
    return _parseResponse(response);
  }

  Future<ApiResponse> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
    return _parseResponse(response);
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
