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
    debugPrint('[🔑 Auth] initialize() → loading');
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('auth_token');
      final savedUserJson = prefs.getString('user_data');
      debugPrint('[🔑 Auth] savedToken exists: ${savedToken != null}, savedUser exists: ${savedUserJson != null}');

      if (savedToken != null && savedUserJson != null) {
        _token = savedToken;
        _user = User.fromJson(jsonDecode(savedUserJson));
        debugPrint('[🔑 Auth] validando token com backend...');
        final isValid = await _validateTokenWithBackend();
        debugPrint('[🔑 Auth] token válido: $isValid');
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
      debugPrint('[❌ Auth] initialize() erro: $e');
      _status = AuthStatus.unauthenticated;
    }
    
    debugPrint('[🔑 Auth] initialize() concluído → $_status');
    notifyListeners();
  }

  /// Login
  Future<bool> login(String email, String password) async {
    debugPrint('[🔑 Auth] login() chamado com email=$email');
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('[🔑 Auth] enviando POST /auth/login...');
      final response = await _apiClient.post('/auth/login', {
        'email': email,
        'password': password,
      });
      debugPrint('[🔑 Auth] resposta recebida: statusCode=${response.statusCode}');
      debugPrint('[🔑 Auth] resposta body: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        _token = data['token'] as String?;
        debugPrint('[🔑 Auth] token recebido: ${_token != null ? "sim (${_token!.substring(0, 20)}...)" : "NÃO"}');
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        debugPrint('[🔑 Auth] user parsed: ${_user?.username}');
        
        // Salvar credenciais
        await _saveCredentials();
        debugPrint('[🔑 Auth] credenciais salvas');
        
        _status = AuthStatus.authenticated;
        debugPrint('[🔑 Auth] status → authenticated ✅');
        notifyListeners();
        return true;
      } else {
        if (response.data is Map && response.data['message'] != null) {
          _errorMessage = response.data['message'].toString();
        } else {
          _errorMessage = 'Credenciais inválidas';
        }
        debugPrint('[🔑 Auth] login falhou: $_errorMessage');
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      debugPrint('[❌ Auth] login() EXCEPTION: $e');
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
      if (response.statusCode != 200) return false;
      if (response.data is Map && (response.data as Map).containsKey('user')) {
        final userJson = (response.data as Map)['user'];
        if (userJson is Map<String, dynamic>) {
          _user = User.fromJson(userJson);
          await _saveCredentials();
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> refreshProfile() async {
    try {
      final response = await _apiClient.get('/users/me');
      if (response.statusCode != 200) return false;
      final data = response.data;
      if (data is Map && data['user'] is Map<String, dynamic>) {
        _user = User.fromJson((data['user'] as Map<String, dynamic>));
        await _saveCredentials();
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateProfile({String? displayName, String? avatarUrl}) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.patch('/users/me', {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      });
      if (response.statusCode != 200) {
        if (response.data is Map && response.data['error'] != null) {
          _errorMessage = response.data['error'].toString();
        } else {
          _errorMessage = 'Falha ao atualizar perfil';
        }
        notifyListeners();
        return false;
      }
      final data = response.data;
      if (data is Map && data['user'] is Map<String, dynamic>) {
        _user = User.fromJson((data['user'] as Map<String, dynamic>));
        await _saveCredentials();
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      notifyListeners();
      return false;
    }
  }
}
