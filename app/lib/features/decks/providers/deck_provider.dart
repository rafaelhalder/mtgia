import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/logger.dart';
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

  // Cache de detalhes do deck (evita recarregar se já temos os dados)
  final Map<String, DeckDetails> _deckDetailsCache = {};
  final Map<String, DateTime> _deckDetailsCacheTime = {};
  static const _cacheDuration = Duration(minutes: 5);

  List<Deck> get decks => _decks;
  DeckDetails? get selectedDeck => _selectedDeck;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get detailsErrorMessage => _detailsErrorMessage;
  int? get detailsStatusCode => _detailsStatusCode;
  bool get hasError => _errorMessage != null;

  DeckProvider({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Map<String, Map<String, dynamic>> _buildCurrentCardsMap(DeckDetails deck) {
    final currentCards = <String, Map<String, dynamic>>{};

    for (final commander in deck.commander) {
      currentCards[commander.id] = {
        'card_id': commander.id,
        'quantity': commander.quantity,
        'is_commander': true,
      };
    }

    for (final entry in deck.mainBoard.entries) {
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

    return currentCards;
  }

  Future<void> removeCardFromDeck({
    required String deckId,
    required String cardId,
  }) async {
    if (_selectedDeck == null || _selectedDeck!.id != deckId) {
      await fetchDeckDetails(deckId);
    }
    final deck = _selectedDeck;
    if (deck == null) throw Exception('Deck não encontrado');

    final currentCards = _buildCurrentCardsMap(deck);
    currentCards.remove(cardId);

    final response = await _apiClient.put('/decks/$deckId', {
      'cards': currentCards.values.toList(),
    });

    if (response.statusCode != 200) {
      final data = response.data;
      final msg =
          (data is Map && data['error'] != null)
              ? data['error'].toString()
              : 'Falha ao remover carta: ${response.statusCode}';
      throw Exception(msg);
    }

    invalidateDeckCache(deckId);
    await fetchDeckDetails(deckId);
  }

  Future<void> updateDeckCardEntry({
    required String deckId,
    required String oldCardId,
    required String newCardId,
    required int quantity,
    String? cardName,
    bool consolidateSameName = false,
    String condition = 'NM',
  }) async {
    if (quantity <= 0) {
      throw Exception('Quantidade deve ser > 0');
    }

    // Commander/Brawl (ou quando explicitamente pedido): resolve duplicatas por NOME no backend.
    // Isso garante que, se o deck já estiver com 2 edições da mesma carta, o usuário consegue corrigir.
    if (consolidateSameName) {
      final response = await _apiClient.post('/decks/$deckId/cards/set', {
        'card_id': newCardId,
        'quantity': quantity,
        'replace_same_name': true,
        'condition': condition,
      });

      if (response.statusCode != 200) {
        final data = response.data;
        final msg =
            (data is Map && data['error'] != null)
                ? data['error'].toString()
                : 'Falha ao atualizar carta: ${response.statusCode}';
        throw Exception(msg);
      }
    } else {
      // Outros formatos: se trocou a edição, troca primeiro; depois faz SET absoluto.
      if (oldCardId != newCardId) {
        await replaceCardEdition(
          deckId: deckId,
          oldCardId: oldCardId,
          newCardId: newCardId,
        );
      }

      final response = await _apiClient.post('/decks/$deckId/cards/set', {
        'card_id': newCardId,
        'quantity': quantity,
        'replace_same_name': false,
        'condition': condition,
      });

      if (response.statusCode != 200) {
        final data = response.data;
        final msg =
            (data is Map && data['error'] != null)
                ? data['error'].toString()
                : 'Falha ao atualizar carta: ${response.statusCode}';
        throw Exception(msg);
      }
    }

    invalidateDeckCache(deckId);
    await fetchDeckDetails(deckId);
  }

  /// Busca detalhes de um deck específico (com cache)
  Future<void> fetchDeckDetails(
    String deckId, {
    bool forceRefresh = false,
  }) async {
    // Verifica cache primeiro (se não for forceRefresh)
    if (!forceRefresh && _deckDetailsCache.containsKey(deckId)) {
      final cacheTime = _deckDetailsCacheTime[deckId];
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheDuration) {
        _selectedDeck = _deckDetailsCache[deckId];
        _detailsErrorMessage = null;
        _detailsStatusCode = 200;
        notifyListeners();
        return;
      }
    }

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
        // Salva no cache
        _deckDetailsCache[deckId] = _selectedDeck!;
        _deckDetailsCacheTime[deckId] = DateTime.now();

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
    bool isPublic = false,
  }) async {
    try {
      final normalizedCards = await _normalizeCreateDeckCards(cards ?? []);
      final response = await _apiClient.post('/decks', {
        'name': name,
        'format': format,
        'description': description,
        'is_public': isPublic,
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
    String condition = 'NM',
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
        'condition': condition,
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
        invalidateDeckCache(deckId);
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
    String archetype, {
    int? bracket,
    bool keepTheme = true,
  }) async {
    try {
      final payload = <String, dynamic>{
        'deck_id': deckId,
        'archetype': archetype,
        if (bracket != null) 'bracket': bracket,
        'keep_theme': keepTheme,
      };

      // Debug snapshot (sem token): útil para você colar o JSON de request/response.
      await _saveOptimizeDebug(request: payload);
      AppLogger.debug('🧪 [AI Optimize] request=${jsonEncode(payload)}');

      final response = await _apiClient.post('/ai/optimize', payload);

      if (response.statusCode == 200) {
        final data = (response.data as Map).cast<String, dynamic>();
        await _saveOptimizeDebug(response: data);
        AppLogger.debug('🧪 [AI Optimize] response=${jsonEncode(data)}');
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
      invalidateDeckCache(deckId);
      await fetchDeckDetails(deckId);
      return true;
    }
    if (response.data is Map && (response.data as Map)['error'] != null) {
      throw Exception((response.data as Map)['error'].toString());
    }
    throw Exception('Falha ao adicionar em lote : ${response.statusCode}');
  }

  /// Atualiza apenas a descrição do deck via PUT
  Future<bool> updateDeckDescription({
    required String deckId,
    required String description,
  }) async {
    final response = await _apiClient.put('/decks/$deckId', {
      'description': description,
    });

    if (response.statusCode == 200) {
      invalidateDeckCache(deckId);
      await fetchDeckDetails(deckId);
      return true;
    }

    final data = response.data;
    final msg =
        (data is Map && data['error'] != null)
            ? data['error'].toString()
            : 'Falha ao atualizar descrição: ${response.statusCode}';
    throw Exception(msg);
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

    // Recarrega detalhes para refletir chips/estado.
    invalidateDeckCache(deckId);
    await fetchDeckDetails(deckId);
  }

  /// Valida o deck no servidor (modo estrito: Commander=100 e com comandante).
  Future<Map<String, dynamic>> validateDeck(String deckId) async {
    final response = await _apiClient.post('/decks/$deckId/validate', {});
    if (response.statusCode == 200) {
      return (response.data as Map).cast<String, dynamic>();
    }

    // Retorna o body completo (com card_name) em vez de lançar exceção,
    // para que a UI consiga identificar a carta problemática.
    if (response.data is Map) {
      final body = (response.data as Map).cast<String, dynamic>();
      if (body['ok'] == false) return body;
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

    invalidateDeckCache(deckId);
    await fetchDeckDetails(deckId);
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
      AppLogger.debug('🔄 [DeckProvider] Iniciando otimização do deck $deckId');
      AppLogger.debug(
        '📋 [DeckProvider] Remover: ${cardsToRemove.length} cartas | Adicionar: ${cardsToAdd.length} cartas',
      );

      // 1. Buscar o deck atual para pegar a lista de cartas
      if (_selectedDeck == null || _selectedDeck!.id != deckId) {
        AppLogger.debug('📥 [DeckProvider] Buscando detalhes do deck...');
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
      AppLogger.debug(
        '🔍 [DeckProvider] Buscando IDs das cartas a adicionar...',
      );
      final cardsToAddIds = <Map<String, dynamic>>[];

      final addFutures = cardsToAdd.map((cardName) async {
        try {
          AppLogger.debug('  🔎 Buscando: $cardName');
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
              AppLogger.debug('  ✅ Encontrado: $cardName -> ${card['id']}');
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
              AppLogger.debug('  ❌ Não encontrado: $cardName');
            }
          }
        } catch (e) {
          AppLogger.warning('Erro ao buscar $cardName: $e');
        }
        return null;
      });

      final addResults = await Future.wait(addFutures);
      cardsToAddIds.addAll(addResults.whereType<Map<String, dynamic>>());

      // 4. Buscar IDs das cartas a remover pelo nome (EM PARALELO)
      AppLogger.debug('🔍 [DeckProvider] Buscando IDs das cartas a remover...');
      final cardsToRemoveIds = <String>[];

      final removeFutures = cardsToRemove.map((cardName) async {
        try {
          AppLogger.debug('  🔎 Buscando para remover: $cardName');
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
              AppLogger.debug(
                '  ✅ Encontrado para remoção: $cardName -> ${card['id']}',
              );
              return card['id'] as String;
            }
          }
        } catch (e) {
          AppLogger.warning('Erro ao buscar $cardName: $e');
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
      AppLogger.debug('✂️ [DeckProvider] Removendo cartas...');

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
      AppLogger.debug(
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
            AppLogger.debug(
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
      AppLogger.debug('💾 [DeckProvider] Salvando alterações no servidor...');
      final stopwatch = Stopwatch()..start();
      final response = await _apiClient.put('/decks/$deckId', {
        'cards': currentCards.values.toList(),
      });
      stopwatch.stop();
      AppLogger.debug(
        '⏱️ [DeckProvider] Tempo de resposta do servidor: ${stopwatch.elapsedMilliseconds}ms',
      );

      if (response.statusCode == 200) {
        AppLogger.debug('✅ [DeckProvider] Deck atualizado com sucesso!');

        // 8. Validar o deck após salvar (garante integridade)
        try {
          final validation = await validateDeck(deckId);
          final isValid = validation['valid'] as bool? ?? false;
          if (!isValid) {
            final errors = (validation['errors'] as List?)?.join(', ') ?? '';
            AppLogger.warning(
              '[DeckProvider] Deck salvo mas com avisos de validação: $errors',
            );
          }
        } catch (validationError) {
          // Validação falhou, mas deck já foi salvo - apenas log
          AppLogger.warning(
            '[DeckProvider] Não foi possível validar deck após salvar: $validationError',
          );
        }

        invalidateDeckCache(deckId);
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
      AppLogger.error('[DeckProvider] Erro fatal na otimização', e);
      rethrow;
    }
  }

  /// Aplica otimização usando IDs diretamente (versão rápida)
  /// Evita N chamadas HTTP para buscar cartas por nome
  Future<bool> applyOptimizationWithIds({
    required String deckId,
    required List<Map<String, dynamic>> removalsDetailed,
    required List<Map<String, dynamic>> additionsDetailed,
  }) async {
    try {
      AppLogger.debug('🚀 [DeckProvider] Otimização rápida com IDs diretos');

      // 1. Buscar deck atual
      if (_selectedDeck == null || _selectedDeck!.id != deckId) {
        await fetchDeckDetails(deckId);
      }
      if (_selectedDeck == null) throw Exception('Deck não encontrado');

      // 2. Construir mapa de cartas atuais
      final currentCards = <String, Map<String, dynamic>>{};
      
      // Primeiro: adicionar commanders
      final commanderIds = <String>{};
      AppLogger.debug('👑 [DeckProvider] Commanders no deck: ${_selectedDeck!.commander.length}');
      for (final commander in _selectedDeck!.commander) {
        AppLogger.debug('  Commander: ${commander.name} (id=${commander.id}, qty=${commander.quantity})');
        commanderIds.add(commander.id);
        // Commander SEMPRE deve ter quantity=1
        currentCards[commander.id] = {
          'card_id': commander.id,
          'quantity': 1, // Forçar 1, independente do valor original
          'is_commander': true,
        };
      }
      
      // Segundo: adicionar mainBoard, mas NUNCA sobrescrever commanders
      AppLogger.debug('🃏 [DeckProvider] MainBoard entries: ${_selectedDeck!.mainBoard.length}');
      for (final entry in _selectedDeck!.mainBoard.entries) {
        for (final card in entry.value) {
          // Pular se já é commander (evita duplicatas)
          if (commanderIds.contains(card.id)) {
            AppLogger.debug('  ⚠️ SKIP (é commander): ${card.name} (id=${card.id})');
            continue;
          }
          
          currentCards[card.id] = {
            'card_id': card.id,
            'quantity': card.quantity,
            'is_commander': false,
          };
        }
      }

      // 3. Remover cartas usando IDs diretos
      for (final removal in removalsDetailed) {
        final cardId = removal['card_id'] as String?;
        if (cardId == null) continue;
        if (currentCards.containsKey(cardId)) {
          final existing = currentCards[cardId]!;
          final qty = (existing['quantity'] as int) - 1;
          if (qty <= 0) {
            currentCards.remove(cardId);
          } else {
            currentCards[cardId] = {...existing, 'quantity': qty};
          }
        }
      }

      // 4. Adicionar cartas usando IDs diretos
      final format = _selectedDeck?.format.toLowerCase() ?? '';
      final isCommander = format == 'commander' || format == 'brawl';
      final defaultLimit = isCommander ? 1 : 4;

      for (final addition in additionsDetailed) {
        final cardId = addition['card_id'] as String?;
        if (cardId == null) continue;

        final typeLine =
            ((addition['type_line'] as String?) ?? '').toLowerCase();
        final isBasicLand = typeLine.contains('basic land');
        final limit = isBasicLand ? 99 : defaultLimit;

        if (currentCards.containsKey(cardId)) {
          final existing = currentCards[cardId]!;
          final newQty = (existing['quantity'] as int) + 1;
          if (newQty <= limit) {
            currentCards[cardId] = {...existing, 'quantity': newQty};
          }
        } else {
          currentCards[cardId] = {
            'card_id': cardId,
            'quantity': 1,
            'is_commander': false,
          };
        }
      }

      // 5. Salvar no servidor
      AppLogger.debug('💾 [DeckProvider] Salvando...');
      
      // DEBUG: Log todas as cartas que serão enviadas
      AppLogger.debug('📦 [DeckProvider] Total de cartas a enviar: ${currentCards.length}');
      for (final entry in currentCards.entries) {
        final v = entry.value;
        AppLogger.debug('  📌 ${entry.key}: qty=${v['quantity']}, is_commander=${v['is_commander']}');
      }
      
      final response = await _apiClient.put('/decks/$deckId', {
        'cards': currentCards.values.toList(),
      });

      if (response.statusCode == 200) {
        AppLogger.debug('✅ Otimização aplicada!');
        invalidateDeckCache(deckId);
        await fetchDeckDetails(deckId);
        return true;
      } else {
        throw Exception('Falha: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('[DeckProvider] Erro na otimização rápida', e);
      rethrow;
    }
  }

  /// Limpa o erro
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Invalida o cache de um deck específico (chamar após updates)
  void invalidateDeckCache(String deckId) {
    _deckDetailsCache.remove(deckId);
    _deckDetailsCacheTime.remove(deckId);
  }

  /// Limpa todo o cache de detalhes
  void clearAllCache() {
    _deckDetailsCache.clear();
    _deckDetailsCacheTime.clear();
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

  /// Importa um deck a partir de uma lista de texto (ex: "1 Sol Ring")
  /// Retorna um Map com:
  /// - 'success': bool
  /// - 'deck': dados do deck criado (se sucesso)
  /// - 'cards_imported': quantidade de cartas importadas
  /// - 'not_found_lines': lista de linhas não encontradas
  /// - 'warnings': lista de avisos
  /// - 'error': mensagem de erro (se falhou)
  Future<Map<String, dynamic>> importDeckFromList({
    required String name,
    required String format,
    required String list,
    String? description,
    String? commander,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiClient.post('/import', {
        'name': name,
        'format': format,
        'list': list,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (commander != null && commander.isNotEmpty) 'commander': commander,
      });

      _isLoading = false;
      notifyListeners();

      if (response.statusCode == 200) {
        // Recarrega a lista de decks
        await fetchDecks();

        final data = response.data as Map<String, dynamic>;
        return {
          'success': true,
          'deck': data['deck'],
          'cards_imported': data['cards_imported'] ?? 0,
          'not_found_lines': data['not_found_lines'] ?? [],
          'warnings': data['warnings'] ?? [],
        };
      } else {
        final data = response.data;
        final error =
            (data is Map && data['error'] != null)
                ? data['error'].toString()
                : 'Erro ao importar deck: ${response.statusCode}';
        final notFound =
            (data is Map && data['not_found'] != null)
                ? List<String>.from(data['not_found'])
                : <String>[];

        _errorMessage = error;
        return {'success': false, 'error': error, 'not_found_lines': notFound};
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Erro de conexão: $e';
      notifyListeners();
      return {'success': false, 'error': 'Erro de conexão: $e'};
    }
  }

  /// Valida uma lista de cartas sem criar o deck (preview)
  /// Útil para mostrar ao usuário quais cartas foram encontradas e quais não
  Future<Map<String, dynamic>> validateImportList({
    required String format,
    required String list,
  }) async {
    try {
      final response = await _apiClient.post('/import/validate', {
        'format': format,
        'list': list,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return {
          'success': true,
          'found_cards': data['found_cards'] ?? [],
          'not_found_lines': data['not_found_lines'] ?? [],
          'warnings': data['warnings'] ?? [],
        };
      } else {
        final data = response.data;
        return {
          'success': false,
          'error':
              (data is Map && data['error'] != null)
                  ? data['error'].toString()
                  : 'Erro ao validar lista',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Erro de conexão: $e'};
    }
  }

  /// Importa uma lista de cartas para um deck EXISTENTE
  /// Se replaceAll=true, substitui todas as cartas; senão, adiciona às existentes
  Future<Map<String, dynamic>> importListToDeck({
    required String deckId,
    required String list,
    bool replaceAll = false,
  }) async {
    try {
      final response = await _apiClient.post('/import/to-deck', {
        'deck_id': deckId,
        'list': list,
        'replace_all': replaceAll,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        // Invalida cache do deck
        invalidateDeckCache(deckId);

        return {
          'success': true,
          'cards_imported': data['cards_imported'] ?? 0,
          'not_found_lines': data['not_found_lines'] ?? [],
          'warnings': data['warnings'] ?? [],
        };
      } else {
        final data = response.data;
        final error =
            (data is Map && data['error'] != null)
                ? data['error'].toString()
                : 'Erro ao importar: ${response.statusCode}';
        final notFound =
            (data is Map && data['not_found_lines'] != null)
                ? List<String>.from(data['not_found_lines'])
                : <String>[];

        return {'success': false, 'error': error, 'not_found_lines': notFound};
      }
    } catch (e) {
      return {'success': false, 'error': 'Erro de conexão: $e'};
    }
  }

  // ───── Social / Sharing ─────

  /// Alterna visibilidade pública/privada do deck via PUT /decks/:id
  Future<bool> togglePublic(String deckId, {required bool isPublic}) async {
    try {
      final response = await _apiClient.put('/decks/$deckId', {
        'is_public': isPublic,
      });
      if (response.statusCode == 200) {
        // Atualiza cache local
        if (_selectedDeck != null && _selectedDeck!.id == deckId) {
          _selectedDeck = _selectedDeck!.copyWith(isPublic: isPublic);
        }
        final idx = _decks.indexWhere((d) => d.id == deckId);
        if (idx >= 0) {
          _decks[idx] = _decks[idx].copyWith(isPublic: isPublic);
        }
        invalidateDeckCache(deckId);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('[DeckProvider] togglePublic error: $e');
      return false;
    }
  }

  /// Exporta deck como texto (lista de cartas)
  Future<Map<String, dynamic>> exportDeckAsText(String deckId) async {
    try {
      final response = await _apiClient.get('/decks/$deckId/export');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      return {
        'error': 'Falha ao exportar deck: ${response.statusCode}',
      };
    } catch (e) {
      return {'error': 'Erro de conexão: $e'};
    }
  }

  /// Copia um deck público para a conta do usuário autenticado
  Future<Map<String, dynamic>> copyPublicDeck(String deckId) async {
    try {
      final response = await _apiClient.post(
        '/community/decks/$deckId',
        {},
      );
      if (response.statusCode == 201 && response.data is Map) {
        // Recarrega lista de decks do usuário
        await fetchDecks();
        return {
          'success': true,
          'deck': response.data['deck'],
        };
      }
      final data = response.data;
      final error = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Falha ao copiar deck: ${response.statusCode}';
      return {'success': false, 'error': error};
    } catch (e) {
      return {'success': false, 'error': 'Erro de conexão: $e'};
    }
  }

  /// Limpa todo o estado do provider (chamado no logout)
  void clearAllState() {
    _decks = [];
    _selectedDeck = null;
    _isLoading = false;
    _errorMessage = null;
    _detailsErrorMessage = null;
    _detailsStatusCode = null;
    _deckDetailsCache.clear();
    _deckDetailsCacheTime.clear();
    notifyListeners();
  }
}
