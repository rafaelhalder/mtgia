import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  int? _detailsStatusCode;

  List<Deck> get decks => _decks;
  DeckDetails? get selectedDeck => _selectedDeck;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get detailsErrorMessage => _detailsErrorMessage;
  int? get detailsStatusCode => _detailsStatusCode;
  bool get hasError => _errorMessage != null;

  DeckProvider({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Busca detalhes de um deck específico
  Future<void> fetchDeckDetails(String deckId) async {
    _isLoading = true;
    _detailsErrorMessage = null;
    _detailsStatusCode = null;
    _selectedDeck = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/decks/$deckId');

      if (response.statusCode == 200) {
        _selectedDeck = DeckDetails.fromJson(
          response.data as Map<String, dynamic>,
        );
        _detailsErrorMessage = null;
        _detailsStatusCode = 200;
      } else {
        _detailsStatusCode = response.statusCode;
        if (response.statusCode == 401) {
          final data = response.data;
          final message =
              (data is Map && data['message'] != null)
                  ? data['message'].toString()
                  : 'Sessão expirada. Faça login novamente.';
          _detailsErrorMessage = message;
        } else {
          _detailsErrorMessage =
              'Erro ao carregar detalhes do deck: ${response.statusCode}';
        }
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
        _decks =
            data
                .map((json) => Deck.fromJson(json as Map<String, dynamic>))
                .toList();
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
      final normalizedCards = await _normalizeCreateDeckCards(cards ?? []);
      final response = await _apiClient.post('/decks', {
        'name': name,
        'format': format,
        'description': description,
        'cards': normalizedCards,
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

  Future<List<Map<String, dynamic>>> _normalizeCreateDeckCards(
    List<Map<String, dynamic>> cards,
  ) async {
    if (cards.isEmpty) return const [];

    final hasCardId = cards.any((c) => c['card_id'] != null);
    final hasName = cards.any((c) => c['name'] != null);

    if (hasCardId && !hasName) {
      return cards;
    }

    final aggregatedByName = <String, Map<String, dynamic>>{};
    for (final card in cards) {
      final name = (card['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;

      final quantity = (card['quantity'] as int?) ?? 1;
      final isCommander = (card['is_commander'] as bool?) ?? false;

      final key = '${name.toLowerCase()}::$isCommander';
      final existing = aggregatedByName[key];
      if (existing == null) {
        aggregatedByName[key] = {
          'name': name,
          'quantity': quantity,
          'is_commander': isCommander,
        };
      } else {
        aggregatedByName[key] = {
          ...existing,
          'quantity': (existing['quantity'] as int) + quantity,
        };
      }
    }

    final lookups = aggregatedByName.values.map((card) async {
      final name = card['name'] as String;
      final encodedName = Uri.encodeQueryComponent(name);
      final response = await _apiClient.get('/cards?name=$encodedName&limit=1');

      if (response.statusCode != 200) return null;

      final data = response.data;
      final List results;
      if (data is Map && data['data'] is List) {
        results = data['data'] as List;
      } else if (data is List) {
        results = data;
      } else {
        results = const [];
      }

      if (results.isEmpty) return null;
      final cardJson = results.first as Map<String, dynamic>;
      final cardId = cardJson['id'] as String?;
      if (cardId == null || cardId.isEmpty) return null;

      return {
        'card_id': cardId,
        'quantity': card['quantity'] ?? 1,
        'is_commander': card['is_commander'] ?? false,
      };
    });

    final resolved = await Future.wait(lookups);
    return resolved.whereType<Map<String, dynamic>>().toList();
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
  Future<bool> addCardToDeck(
    String deckId,
    DeckCardItem card,
    int quantity, {
    bool isCommander = false,
  }) async {
    if (_selectedDeck == null || _selectedDeck!.id != deckId) {
      await fetchDeckDetails(deckId);
    }
    if (_selectedDeck == null || _selectedDeck!.id != deckId) {
      _errorMessage =
          'Deck não carregado. Abra os detalhes do deck e tente novamente.';
      notifyListeners();
      return false;
    }

    try {
      // Usa endpoint incremental (muito mais rápido do que reenviar o deck inteiro).
      final response = await _apiClient.post('/decks/$deckId/cards', {
        'card_id': card.id,
        'quantity': quantity,
        'is_commander': isCommander,
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
            cardCount: oldDeck.cardCount + (isCommander ? 1 : quantity),
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
  Future<List<Map<String, dynamic>>> fetchOptimizationOptions(
    String deckId,
  ) async {
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
  Future<Map<String, dynamic>> optimizeDeck(
    String deckId,
    String archetype, [
    int? bracket,
  ]) async {
    try {
      final payload = <String, dynamic>{
        'deck_id': deckId,
        'archetype': archetype,
        if (bracket != null) 'bracket': bracket,
      };

      // Debug snapshot (sem token): útil para você colar o JSON de request/response.
      await _saveOptimizeDebug(request: payload);
      debugPrint('🧪 [AI Optimize] request=${jsonEncode(payload)}');

      final response = await _apiClient.post('/ai/optimize', payload);

      if (response.statusCode == 200) {
        final data = (response.data as Map).cast<String, dynamic>();
        await _saveOptimizeDebug(response: data);
        debugPrint('🧪 [AI Optimize] response=${jsonEncode(data)}');
        return data;
      } else {
        await _saveOptimizeDebug(
          response: {'statusCode': response.statusCode, 'data': response.data},
        );
        throw Exception('Falha ao otimizar deck: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveOptimizeDebug({
    Map<String, dynamic>? request,
    Map<String, dynamic>? response,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (request != null) {
        await prefs.setString(
          'debug_last_ai_optimize_request',
          jsonEncode(request),
        );
      }
      if (response != null) {
        await prefs.setString(
          'debug_last_ai_optimize_response',
          jsonEncode(response),
        );
      }
      await prefs.setString(
        'debug_last_ai_optimize_at',
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Silencioso: não deve quebrar fluxo do app.
    }
  }

  Future<bool> addCardsBulk({
    required String deckId,
    required List<Map<String, dynamic>> cards,
  }) async {
    final response = await _apiClient.post('/decks/$deckId/cards/bulk', {
      'cards': cards,
    });
    if (response.statusCode == 200) {
      await fetchDeckDetails(deckId);
      return true;
    }
    if (response.data is Map && (response.data as Map)['error'] != null) {
      throw Exception((response.data as Map)['error'].toString());
    }
    throw Exception('Falha ao adicionar em lote: ${response.statusCode}');
  }

  Future<void> updateDeckStrategy({
    required String deckId,
    required String archetype,
    required int bracket,
  }) async {
    final response = await _apiClient.put('/decks/$deckId', {
      'archetype': archetype,
      'bracket': bracket,
    });

    if (response.statusCode != 200) {
      final data = response.data;
      final msg =
          (data is Map && data['error'] != null)
              ? data['error'].toString()
              : 'Falha ao salvar estratégia: ${response.statusCode}';
      throw Exception(msg);
    }

    // Recarrega detalhes e lista para refletir chips/estado.
    await fetchDeckDetails(deckId);
    await fetchDecks();
  }

  /// Valida o deck no servidor (modo estrito: Commander=100 e com comandante).
  Future<Map<String, dynamic>> validateDeck(String deckId) async {
    final response = await _apiClient.post('/decks/$deckId/validate', {});
    if (response.statusCode == 200) {
      return (response.data as Map).cast<String, dynamic>();
    }

    if (response.data is Map && (response.data as Map)['error'] != null) {
      throw Exception((response.data as Map)['error'].toString());
    }
    throw Exception('Falha ao validar deck: ${response.statusCode}');
  }

  Future<bool> replaceCardEdition({
    required String deckId,
    required String oldCardId,
    required String newCardId,
  }) async {
    final response = await _apiClient.post('/decks/$deckId/cards/replace', {
      'old_card_id': oldCardId,
      'new_card_id': newCardId,
    });

    if (response.statusCode != 200) {
      final data = response.data;
      final msg =
          (data is Map && data['error'] != null)
              ? data['error'].toString()
              : 'Falha ao trocar edição: ${response.statusCode}';
      throw Exception(msg);
    }

    await fetchDeckDetails(deckId);
    await fetchDecks();
    return true;
  }

  Future<Map<String, dynamic>> fetchDeckPricing(
    String deckId, {
    bool force = false,
  }) async {
    final response = await _apiClient.post('/decks/$deckId/pricing', {
      'force': force,
    });
    if (response.statusCode == 200) {
      return (response.data as Map).cast<String, dynamic>();
    }
    final data = response.data;
    final msg =
        (data is Map && data['error'] != null)
            ? data['error'].toString()
            : 'Falha ao calcular custo: ${response.statusCode}';
    throw Exception(msg);
  }

  /// Atualiza/gera análise de sinergia (IA) e persiste no deck.
  /// Endpoint: POST /decks/:id/ai-analysis
  Future<Map<String, dynamic>> refreshAiAnalysis(
    String deckId, {
    bool force = false,
  }) async {
    final response = await _apiClient.post('/decks/$deckId/ai-analysis', {
      'force': force,
    });

    if (response.statusCode != 200) {
      final data = response.data;
      final msg =
          (data is Map && data['error'] != null)
              ? data['error'].toString()
              : 'Falha ao analisar deck: ${response.statusCode}';
      throw Exception(msg);
    }

    final data = (response.data as Map).cast<String, dynamic>();
    final synergyScore = data['synergy_score'] as int?;
    final strengths = data['strengths'] as String?;
    final weaknesses = data['weaknesses'] as String?;

    if (_selectedDeck != null && _selectedDeck!.id == deckId) {
      _selectedDeck = _selectedDeck!.copyWith(
        synergyScore: synergyScore,
        strengths: strengths,
        weaknesses: weaknesses,
      );
      notifyListeners();
    }

    final index = _decks.indexWhere((d) => d.id == deckId);
    if (index != -1) {
      _decks[index] = _decks[index].copyWith(
        synergyScore: synergyScore,
        strengths: strengths,
        weaknesses: weaknesses,
      );
      notifyListeners();
    }

    return data;
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
      debugPrint('🔄 [DeckProvider] Iniciando otimização do deck $deckId');
      debugPrint(
        '📋 [DeckProvider] Remover: ${cardsToRemove.length} cartas | Adicionar: ${cardsToAdd.length} cartas',
      );

      // 1. Buscar o deck atual para pegar a lista de cartas
      if (_selectedDeck == null || _selectedDeck!.id != deckId) {
        debugPrint('📥 [DeckProvider] Buscando detalhes do deck...');
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

      // 3. Buscar IDs das cartas a adicionar pelo nome (EM PARALELO)
      debugPrint('🔍 [DeckProvider] Buscando IDs das cartas a adicionar...');
      final cardsToAddIds = <Map<String, dynamic>>[];

      final addFutures = cardsToAdd.map((cardName) async {
        try {
          debugPrint('  🔎 Buscando: $cardName');
          final encoded = Uri.encodeQueryComponent(cardName);
          final searchResponse = await _apiClient.get(
            '/cards?name=$encoded&limit=1',
          );

          if (searchResponse.statusCode == 200) {
            // Verifica se o corpo da resposta é um Map com chave 'data' (formato paginado) ou Lista direta
            List results = [];
            if (searchResponse.data is Map &&
                searchResponse.data['data'] is List) {
              results = searchResponse.data['data'] as List;
            } else if (searchResponse.data is List) {
              results = searchResponse.data as List;
            }

            if (results.isNotEmpty) {
              final card = results[0] as Map<String, dynamic>;
              debugPrint('  ✅ Encontrado: $cardName -> ${card['id']}');
              return {
                'card_id': card['id'],
                'quantity': 1,
                'is_commander': false,
                'type_line': card['type_line'] ?? '',
                'color_identity':
                    (card['color_identity'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    const <String>[],
              };
            } else {
              debugPrint('  ❌ Não encontrado: $cardName');
            }
          }
        } catch (e) {
          debugPrint('  ⚠️ Erro ao buscar $cardName: $e');
        }
        return null;
      });

      final addResults = await Future.wait(addFutures);
      cardsToAddIds.addAll(addResults.whereType<Map<String, dynamic>>());

      // 4. Buscar IDs das cartas a remover pelo nome (EM PARALELO)
      debugPrint('🔍 [DeckProvider] Buscando IDs das cartas a remover...');
      final cardsToRemoveIds = <String>[];

      final removeFutures = cardsToRemove.map((cardName) async {
        try {
          debugPrint('  🔎 Buscando para remover: $cardName');
          final encoded = Uri.encodeQueryComponent(cardName);
          final searchResponse = await _apiClient.get(
            '/cards?name=$encoded&limit=1',
          );

          if (searchResponse.statusCode == 200) {
            List results = [];
            if (searchResponse.data is Map &&
                searchResponse.data['data'] is List) {
              results = searchResponse.data['data'] as List;
            } else if (searchResponse.data is List) {
              results = searchResponse.data as List;
            }

            if (results.isNotEmpty) {
              final card = results[0] as Map<String, dynamic>;
              debugPrint(
                '  ✅ Encontrado para remoção: $cardName -> ${card['id']}',
              );
              return card['id'] as String;
            }
          }
        } catch (e) {
          debugPrint('  ⚠️ Erro ao buscar $cardName: $e');
        }
        return null;
      });

      final removeResults = await Future.wait(removeFutures);
      cardsToRemoveIds.addAll(removeResults.whereType<String>());

      if (cardsToAdd.isNotEmpty && cardsToAddIds.isEmpty) {
        throw Exception(
          'Nenhuma das cartas sugeridas para adicionar foi encontrada no banco. Tente novamente.',
        );
      }
      if (cardsToRemove.isNotEmpty && cardsToRemoveIds.isEmpty) {
        throw Exception(
          'Nenhuma das cartas sugeridas para remover foi encontrada no banco. Tente novamente.',
        );
      }

      // 5. Remover as cartas da lista atual
      debugPrint('✂️ [DeckProvider] Removendo cartas...');

      final beforeSnapshot =
          currentCards.values
              .map(
                (c) =>
                    '${c['card_id']}::${c['quantity']}::${c['is_commander']}',
              )
              .toSet();

      // Contar quantas cópias de cada ID devem ser removidas
      final removalCounts = <String, int>{};
      for (final id in cardsToRemoveIds) {
        removalCounts[id] = (removalCounts[id] ?? 0) + 1;
      }

      // Aplicar remoção (decrementando quantidade ou removendo item)
      for (final idToRemove in removalCounts.keys) {
        if (currentCards.containsKey(idToRemove)) {
          final existing = currentCards[idToRemove]!;
          final currentQty = existing['quantity'] as int;
          final removeQty = removalCounts[idToRemove]!;

          final newQty = currentQty - removeQty;

          if (newQty <= 0) {
            currentCards.remove(idToRemove);
          } else {
            currentCards[idToRemove] = {...existing, 'quantity': newQty};
          }
        }
      }

      // 6. Adicionar as novas cartas
      debugPrint(
        '➕ [DeckProvider] Adicionando ${cardsToAddIds.length} cartas...',
      );

      final format = _selectedDeck?.format.toLowerCase() ?? '';
      final isCommander = format == 'commander' || format == 'brawl';
      final defaultLimit = isCommander ? 1 : 4;
      final commanderIdentity =
          isCommander ? _getCommanderIdentitySet(_selectedDeck) : null;

      for (final cardToAdd in cardsToAddIds) {
        final cardId = cardToAdd['card_id'] as String;
        final typeLine =
            (cardToAdd['type_line'] as String? ?? '').toLowerCase();
        final isBasicLand = typeLine.contains('basic land');
        final limit = isBasicLand ? 99 : defaultLimit;

        if (commanderIdentity != null) {
          final identity =
              (cardToAdd['color_identity'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const <String>[];
          final ok = identity.every(
            (c) => commanderIdentity.contains(c.toUpperCase()),
          );
          if (!ok) {
            debugPrint(
              '⛔️ [DeckProvider] Pulando fora da identidade do comandante: $cardId',
            );
            continue;
          }
        }

        if (currentCards.containsKey(cardId)) {
          final existing = currentCards[cardId]!;
          final newQuantity = (existing['quantity'] as int) + 1;
          if (newQuantity <= limit) {
            currentCards[cardId] = {...existing, 'quantity': newQuantity};
          }
        } else {
          currentCards[cardId] = cardToAdd;
        }
      }

      final afterSnapshot =
          currentCards.values
              .map(
                (c) =>
                    '${c['card_id']}::${c['quantity']}::${c['is_commander']}',
              )
              .toSet();
      if (beforeSnapshot.length == afterSnapshot.length &&
          beforeSnapshot.containsAll(afterSnapshot)) {
        throw Exception(
          'Nenhuma mudança aplicável foi encontrada para este deck.',
        );
      }

      // 7. Atualizar o deck via API
      debugPrint('💾 [DeckProvider] Salvando alterações no servidor...');
      final stopwatch = Stopwatch()..start();
      final response = await _apiClient.put('/decks/$deckId', {
        'cards': currentCards.values.toList(),
      });
      stopwatch.stop();
      debugPrint(
        '⏱️ [DeckProvider] Tempo de resposta do servidor: ${stopwatch.elapsedMilliseconds}ms',
      );

      if (response.statusCode == 200) {
        debugPrint('✅ [DeckProvider] Deck atualizado com sucesso!');
        await fetchDeckDetails(deckId);
        return true;
      } else {
        String errorMsg = 'Falha ao atualizar deck: ${response.statusCode}';
        if (response.data is Map && response.data['error'] != null) {
          errorMsg = response.data['error'].toString();
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('❌ [DeckProvider] Erro fatal na otimização: $e');
      rethrow;
    }
  }

  /// Limpa o erro
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Set<String>? _getCommanderIdentitySet(DeckDetails? deck) {
    if (deck == null) return null;
    if (deck.commander.isEmpty) return null;
    final commander = deck.commander.first;
    final identity =
        commander.colorIdentity.isNotEmpty
            ? commander.colorIdentity
            : commander.colors;
    return identity.map((e) => e.toUpperCase()).toSet();
  }
}
