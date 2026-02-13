import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../models/card_mover.dart';

/// Provider para dados de mercado (variações de preço diárias)
class MarketProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  MarketMoversData? _moversData;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetch;

  MarketMoversData? get moversData => _moversData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastFetch => _lastFetch;

  MarketProvider({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Cache TTL de 5 minutos para evitar refetch a cada troca de tab
  static const _cacheTtl = Duration(minutes: 5);

  /// Retorna true se o cache ainda é válido
  bool get _isCacheValid =>
      _lastFetch != null &&
      _moversData != null &&
      DateTime.now().difference(_lastFetch!) < _cacheTtl;

  /// Busca os market movers (gainers/losers do dia).
  /// Retorna do cache se ainda válido (use [force] para ignorar cache).
  /// [minPrice] filtra penny stocks (default: 1.00 USD)
  /// [limit] quantidade por categoria (default: 20)
  Future<void> fetchMovers({
    double minPrice = 1.0,
    int limit = 20,
    bool force = false,
  }) async {
    // Retornar do cache se válido e não forçado
    if (!force && _isCacheValid) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.get(
        '/market/movers?limit=$limit&min_price=$minPrice',
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        _moversData = MarketMoversData.fromJson(response.data);
        _lastFetch = DateTime.now();
        _errorMessage = null;
      } else {
        _errorMessage = 'Erro ao carregar dados do mercado';
      }
    } catch (e) {
      debugPrint('[❌ MarketProvider] fetchMovers error: $e');
      _errorMessage = 'Não foi possível conectar ao servidor';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Força atualização dos dados (ignora cache)
  Future<void> refresh() async {
    await fetchMovers(force: true);
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    _moversData = null;
    _isLoading = false;
    _errorMessage = null;
    _lastFetch = null;
    notifyListeners();
  }
}
