import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../models/deck.dart';
import '../models/deck_details.dart';
import '../models/deck_card_item.dart';

/// Provider para gerenciar estado da listagem de decks
class DeckProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  List<Deck> _decks = [];
  DeckDetails? _selectedDeck;
  bool _isLoading = false;
  String? _errorMessage; // Erro geral ou de lista
  String? _detailsErrorMessage; // Erro específico de detalhes

  List<Deck> get decks => _decks;
  DeckDetails? get selectedDeck => _selectedDeck;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get detailsErrorMessage => _detailsErrorMessage;
  bool get hasError => _errorMessage != null;

  DeckProvider({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// Busca detalhes de um deck específico
  Future<void> fetchDeckDetails(String deckId) async {
    _isLoading = true;
    _detailsErrorMessage = null;
    _selectedDeck = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/decks/$deckId');
      
      if (response.statusCode == 200) {
        _selectedDeck = DeckDetails.fromJson(response.data as Map<String, dynamic>);
        _detailsErrorMessage = null;
      } else {
        _detailsErrorMessage = 'Erro ao carregar detalhes do deck: ${response.statusCode}';
      }
    } catch (e) {
      _detailsErrorMessage = 'Erro de conexão: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Busca todos os decks do usuário
  Future<void> fetchDecks() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/decks');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data as List<dynamic>;
        _decks = data.map((json) => Deck.fromJson(json as Map<String, dynamic>)).toList();
        _errorMessage = null;
      } else if (response.statusCode == 401) {
        _errorMessage = 'Sessão expirada. Faça login novamente.';
      } else {
        _errorMessage = 'Erro ao carregar decks: ${response.statusCode}';
      }
    } catch (e) {
      _errorMessage = 'Erro de conexão: $e';
      // Não limpa _decks para permitir cache visual em caso de erro
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cria um novo deck
  Future<bool> createDeck({
    required String name,
    required String format,
    String? description,
    List<Map<String, dynamic>>? cards,
  }) async {
    try {
      final response = await _apiClient.post('/decks', {
        'name': name,
        'format': format,
        'description': description,
        'cards': cards ?? [],
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchDecks(); // Recarrega a lista
        return true;
      }
      
      String msg = 'Erro ao criar deck: ${response.statusCode}';
      if (response.data is Map && response.data['error'] != null) {
        msg = response.data['error'];
      }
      _errorMessage = msg;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Erro ao criar deck: $e';
      notifyListeners();
      return false;
    }
  }

  /// Deleta um deck
  Future<bool> deleteDeck(String deckId) async {
    try {
      final response = await _apiClient.delete('/decks/$deckId');
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        _decks.removeWhere((deck) => deck.id == deckId);
        notifyListeners();
        return true;
      }
      _errorMessage = 'Erro ao deletar deck: ${response.statusCode}';
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Erro ao deletar deck: $e';
      notifyListeners();
      return false;
    }
  }

  /// Adiciona uma carta ao deck
  Future<bool> addCardToDeck(String deckId, DeckCardItem card, int quantity, {bool isCommander = false}) async {
    if (_selectedDeck == null || _selectedDeck!.id != deckId) {
      // Se o deck não estiver carregado, não podemos adicionar (segurança)
      return false;
    }

    try {
      // 1. Reconstrói a lista plana de cartas atual
      final List<Map<String, dynamic>> currentCards = [];
      
      // Adiciona comandantes
      for (var c in _selectedDeck!.commander) {
        currentCards.add({
          'card_id': c.id,
          'quantity': c.quantity,
          'is_commander': true,
        });
      }
      
      // Adiciona main board
      _selectedDeck!.mainBoard.forEach((key, list) {
        for (var c in list) {
          currentCards.add({
            'card_id': c.id,
            'quantity': c.quantity,
            'is_commander': false,
          });
        }
      });

      // 2. Verifica se a carta já existe no deck
      final existingIndex = currentCards.indexWhere((c) => c['card_id'] == card.id && c['is_commander'] == isCommander);

      if (existingIndex >= 0) {
        // Atualiza quantidade
        currentCards[existingIndex]['quantity'] = (currentCards[existingIndex]['quantity'] as int) + quantity;
      } else {
        // Adiciona nova carta
        currentCards.add({
          'card_id': card.id,
          'quantity': quantity,
          'is_commander': isCommander,
        });
      }

      // 3. Envia a lista atualizada para o backend
      final response = await _apiClient.put('/decks/$deckId', {
        'cards': currentCards,
      });

      if (response.statusCode == 200) {
        // 4. Atualiza a contagem na lista localmente IMEDIATAMENTE
        final index = _decks.indexWhere((d) => d.id == deckId);
        if (index != -1) {
          final oldDeck = _decks[index];
          _decks[index] = Deck(
            id: oldDeck.id,
            name: oldDeck.name,
            format: oldDeck.format,
            description: oldDeck.description,
            synergyScore: oldDeck.synergyScore,
            strengths: oldDeck.strengths,
            weaknesses: oldDeck.weaknesses,
            isPublic: oldDeck.isPublic,
            createdAt: oldDeck.createdAt,
            cardCount: oldDeck.cardCount + quantity,
          );
          notifyListeners();
        }

        // 5. Recarrega os detalhes para atualizar a UI de detalhes
        await fetchDeckDetails(deckId);
        
        return true;
      } else {
        String msg = 'Erro ao adicionar carta: ${response.statusCode}';
        if (response.data is Map && response.data['error'] != null) {
          msg = response.data['error'];
        }
        _errorMessage = msg;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erro ao adicionar carta: $e';
      notifyListeners();
      return false;
    }
  }

  /// Busca opções de otimização (arquétipos) para o deck
  Future<List<Map<String, dynamic>>> fetchOptimizationOptions(String deckId) async {
    try {
      final response = await _apiClient.post('/ai/archetypes', {
        'deck_id': deckId,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final options = (data['options'] as List).cast<Map<String, dynamic>>();
        return options;
      } else {
        throw Exception('Falha ao buscar opções: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Solicita sugestões de otimização para um arquétipo específico
  Future<Map<String, dynamic>> optimizeDeck(String deckId, String archetype) async {
    try {
      final response = await _apiClient.post('/ai/optimize', {
        'deck_id': deckId,
        'archetype': archetype,
      });

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Falha ao otimizar deck: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Gera um deck do zero usando IA baseado em um prompt de texto
  Future<Map<String, dynamic>> generateDeck({
    required String prompt,
    required String format,
  }) async {
    try {
      final response = await _apiClient.post('/ai/generate', {
        'prompt': prompt,
        'format': format,
      });

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Falha ao gerar deck: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Aplica as sugestões de otimização ao deck
  /// Recebe uma lista de cartas para remover e adicionar (por nome)
  /// Busca os IDs das cartas e atualiza o deck
  Future<bool> applyOptimization({
    required String deckId,
    required List<String> cardsToRemove,
    required List<String> cardsToAdd,
  }) async {
    try {
      // 1. Buscar o deck atual para pegar a lista de cartas
      if (_selectedDeck == null || _selectedDeck!.id != deckId) {
        await fetchDeckDetails(deckId);
      }
      
      if (_selectedDeck == null) {
        throw Exception('Deck não encontrado');
      }

      // 2. Construir lista atual de cartas em formato de map
      final currentCards = <String, Map<String, dynamic>>{};
      
      for (final commander in _selectedDeck!.commander) {
        currentCards[commander.id] = {
          'card_id': commander.id,
          'quantity': commander.quantity,
          'is_commander': true,
        };
      }
      
      for (final entry in _selectedDeck!.mainBoard.entries) {
        for (final card in entry.value) {
          if (!card.isCommander) {
            currentCards[card.id] = {
              'card_id': card.id,
              'quantity': card.quantity,
              'is_commander': false,
            };
          }
        }
      }

      // 3. Buscar IDs das cartas a adicionar pelo nome
      final cardsToAddIds = <Map<String, dynamic>>[];
      
      for (final cardName in cardsToAdd) {
        try {
          // Buscar carta pelo nome na API
          final searchResponse = await _apiClient.get('/cards?name=$cardName&limit=1');
          
          if (searchResponse.statusCode == 200 && searchResponse.data is List) {
            final results = searchResponse.data as List;
            if (results.isNotEmpty) {
              final card = results[0] as Map<String, dynamic>;
              cardsToAddIds.add({
                'card_id': card['id'],
                'quantity': 1,
                'is_commander': false,
              });
            }
          }
        } catch (e) {
          // Se não conseguir encontrar a carta, ignora
          if (kDebugMode) {
            debugPrint('Erro ao buscar carta $cardName: $e');
          }
        }
      }

      // 4. Buscar IDs das cartas a remover pelo nome
      final cardsToRemoveIds = <String>{};
      
      for (final cardName in cardsToRemove) {
        try {
          final searchResponse = await _apiClient.get('/cards?name=$cardName&limit=1');
          
          if (searchResponse.statusCode == 200 && searchResponse.data is List) {
            final results = searchResponse.data as List;
            if (results.isNotEmpty) {
              final card = results[0] as Map<String, dynamic>;
              cardsToRemoveIds.add(card['id'] as String);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Erro ao buscar carta $cardName: $e');
          }
        }
      }

      // 5. Remover as cartas da lista atual
      currentCards.removeWhere((key, value) => cardsToRemoveIds.contains(key));

      // 6. Adicionar as novas cartas
      for (final cardToAdd in cardsToAddIds) {
        final cardId = cardToAdd['card_id'] as String;
        
        // Se a carta já existe, aumenta a quantidade (até o limite)
        if (currentCards.containsKey(cardId)) {
          final existing = currentCards[cardId]!;
          final newQuantity = (existing['quantity'] as int) + 1;
          // Limite básico (não aplica regras complexas aqui)
          if (newQuantity <= 4) {
            currentCards[cardId] = {
              ...existing,
              'quantity': newQuantity,
            };
          }
        } else {
          currentCards[cardId] = cardToAdd;
        }
      }

      // 7. Atualizar o deck via API
      final response = await _apiClient.put('/decks/$deckId', {
        'cards': currentCards.values.toList(),
      });

      if (response.statusCode == 200) {
        // Recarregar os detalhes do deck
        await fetchDeckDetails(deckId);
        return true;
      } else {
        throw Exception('Falha ao atualizar deck: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Limpa o erro
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
