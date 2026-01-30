import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../decks/models/deck_card_item.dart';

class CardProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  List<DeckCardItem> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<DeckCardItem> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  CardProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  Future<void> searchCards(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/cards?name=$query');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final List<dynamic> cardsJson = data['data'];
        
        _searchResults = cardsJson.map((json) {
          // O endpoint /cards retorna objetos de carta, mas DeckCardItem espera
          // alguns campos que podem não vir exatamente iguais ou precisar de adaptação.
          // Vamos garantir que o JSON bata com o DeckCardItem ou criar um modelo Card separado.
          // Por simplicidade, vamos usar DeckCardItem e preencher quantity/isCommander com defaults.
          return DeckCardItem(
            id: json['id'],
            name: json['name'],
            manaCost: json['mana_cost'],
            typeLine: json['type_line'] ?? '',
            oracleText: json['oracle_text'],
            colors: (json['colors'] as List?)?.map((e) => e.toString()).toList() ?? [],
            colorIdentity: (json['color_identity'] as List?)?.map((e) => e.toString()).toList() ?? [],
            imageUrl: json['image_url'],
            setCode: json['set_code'] ?? '',
            setName: json['set_name'],
            setReleaseDate: json['set_release_date'],
            rarity: json['rarity'] ?? '',
            quantity: 1, // Default para busca
            isCommander: false, // Default
          );
        }).toList();
      } else {
        _errorMessage = 'Erro ao buscar cartas: ${response.statusCode}';
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _errorMessage = null;
    notifyListeners();
  }

  /// Solicita uma explicação da carta via IA
  Future<String?> explainCard(DeckCardItem card) async {
    try {
      final response = await _apiClient.post('/ai/explain', {
        'card_id': card.id,
        'card_name': card.name,
        'oracle_text': card.oracleText,
        'type_line': card.typeLine,
      });

      if (response.statusCode == 200) {
        return response.data['explanation'] as String;
      }
      return null;
    } catch (e) {
      return 'Erro ao obter explicação: $e';
    }
  }
}
