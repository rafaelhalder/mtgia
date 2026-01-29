import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../models/user.dart';

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  
  User? _user;
  String? _token;
  AuthStatus _status = AuthStatus.initial;
  String? _errorMessage;

  User? get user => _user;
  String? get token => _token;
  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  AuthProvider({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Inicializa o provider verificando se há token salvo
  Future<void> initialize() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      final savedUserJson = prefs.getString('user_data');

      if (savedToken != null && savedUserJson != null) {
        _token = savedToken;
        _user = User.fromJson(jsonDecode(savedUserJson));
        final isValid = await _validateTokenWithBackend();
        _status = isValid ? AuthStatus.authenticated : AuthStatus.unauthenticated;
        if (!isValid) {
          await prefs.remove('auth_token');
          await prefs.remove('user_data');
          _token = null;
          _user = null;
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }
    
    notifyListeners();
  }

  /// Login
  Future<bool> login(String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.post('/auth/login', {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        _token = data['token'] as String?;
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        
        // Salvar credenciais
        await _saveCredentials();
        
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      } else {
        if (response.data is Map && response.data['message'] != null) {
          _errorMessage = response.data['message'].toString();
        } else {
          _errorMessage = 'Credenciais inválidas';
        }
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Registro
  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.post('/auth/register', {
        'username': username,
        'email': email,
        'password': password,
      });

      if (response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        _token = data['token'] as String?;
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        
        await _saveCredentials();
        
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      } else {
        if (response.data is Map && response.data['message'] != null) {
          _errorMessage = response.data['message'].toString();
        } else {
          _errorMessage = 'Erro ao criar conta';
        }
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    
    _token = null;
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Salva credenciais localmente
  Future<void> _saveCredentials() async {
    if (_token != null && _user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      await prefs.setString('user_data', jsonEncode(_user!.toJson()));
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _validateTokenWithBackend() async {
    try {
      final response = await _apiClient.get('/auth/me');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
