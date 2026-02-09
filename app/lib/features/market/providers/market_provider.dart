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

  /// Busca os market movers (gainers/losers do dia).
  /// [minPrice] filtra penny stocks (default: 1.00 USD)
  /// [limit] quantidade por categoria (default: 20)
  Future<void> fetchMovers({double minPrice = 1.0, int limit = 20}) async {
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

  /// Força atualização dos dados
  Future<void> refresh() async {
    await fetchMovers();
  }
}
