import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/card_recognition_result.dart';
import '../services/card_recognition_service.dart';
import '../services/image_preprocessor.dart';
import '../services/fuzzy_card_matcher.dart';
import '../services/scanner_card_search_service.dart';
import '../../decks/models/deck_card_item.dart';

enum ScannerState {
  idle,
  capturing,
  processing,
  searching,
  found,
  notFound,
  error,
}

/// Provider para gerenciar estado do scanner de cartas
class ScannerProvider extends ChangeNotifier {
  final CardRecognitionService _recognitionService = CardRecognitionService();
  late final FuzzyCardMatcher _fuzzyMatcher;
  final ScannerCardSearchService _searchService;

  ScannerState _state = ScannerState.idle;
  CardRecognitionResult? _lastResult;
  List<DeckCardItem> _foundCards = [];
  DeckCardItem? _autoSelectedCard;
  String? _errorMessage;
  bool _useFoilMode = false;

  ScannerState get state => _state;
  CardRecognitionResult? get lastResult => _lastResult;
  List<DeckCardItem> get foundCards => _foundCards;
  DeckCardItem? get autoSelectedCard => _autoSelectedCard;
  String? get errorMessage => _errorMessage;
  bool get useFoilMode => _useFoilMode;

  ScannerProvider({ScannerCardSearchService? searchService})
    : _searchService = searchService ?? ScannerCardSearchService() {
    _fuzzyMatcher = FuzzyCardMatcher(_searchService);
  }

  /// Alterna modo foil (processamento mais agressivo)
  void toggleFoilMode() {
    _useFoilMode = !_useFoilMode;
    notifyListeners();
  }

  /// Processa uma imagem capturada
  Future<void> processImage(File imageFile) async {
    _setState(ScannerState.processing);
    _errorMessage = null;
    _foundCards = [];
    _lastResult = null;
    _autoSelectedCard = null;

    try {
      // Pré-processa a imagem
      File processedFile;
      if (_useFoilMode) {
        processedFile = await ImagePreprocessor.preprocessFoil(imageFile);
      } else {
        processedFile = await ImagePreprocessor.preprocess(imageFile);
      }

      // Reconhece o texto
      final result = await _recognitionService.recognizeCard(processedFile);
      _lastResult = result;

      // Limpa arquivo processado
      if (processedFile.path != imageFile.path) {
        try {
          await processedFile.delete();
        } catch (_) {}
      }

      if (!result.success || result.primaryName == null) {
        _errorMessage = result.error ?? 'Nome não reconhecido';
        _setState(ScannerState.notFound);
        return;
      }

      // Busca a carta na API
      _setState(ScannerState.searching);

      final resolved = await _resolveBestPrintings(result);
      if (resolved.isNotEmpty) {
        _foundCards = resolved;
        _autoSelectedCard = _tryAutoSelectEdition(
          printings: resolved,
          setCodeCandidates: result.setCodeCandidates,
        );
        _setState(ScannerState.found);
        return;
      }

      _errorMessage = 'Carta "${result.primaryName}" não encontrada no banco';
      _setState(ScannerState.notFound);
    } catch (e) {
      _errorMessage = 'Erro ao processar: $e';
      _setState(ScannerState.error);
    }
  }

  Future<List<DeckCardItem>> _resolveBestPrintings(
    CardRecognitionResult result,
  ) async {
    final primary = result.primaryName?.trim();
    if (primary == null || primary.isEmpty) return const [];

    // 1) Tenta printings por nome exato (melhor para selecionar edição).
    final exact = await _searchService.fetchPrintingsByExactName(primary);
    if (exact.isNotEmpty) return exact;

    for (final alt in result.alternatives) {
      final a = alt.trim();
      if (a.isEmpty) continue;
      final altExact = await _searchService.fetchPrintingsByExactName(a);
      if (altExact.isNotEmpty) {
        _lastResult = CardRecognitionResult.success(
          primaryName: a,
          alternatives: [
            if (primary != a) primary,
            ...result.alternatives.where((x) => x != a),
          ],
          setCodeCandidates: result.setCodeCandidates,
          confidence: result.confidence * 0.9,
          allCandidates: result.allCandidates,
        );
        return altExact;
      }
    }

    // 2) Fallback: fuzzy search para achar o nome "correto", depois busca printings exatos.
    final fuzzy = await _fuzzyMatcher.searchWithFuzzy(primary);
    if (fuzzy.isNotEmpty) {
      final bestName = fuzzy.first.name.trim();
      if (bestName.isNotEmpty) {
        final bestExact = await _searchService.fetchPrintingsByExactName(
          bestName,
        );
        if (bestExact.isNotEmpty) {
          _lastResult = CardRecognitionResult.success(
            primaryName: bestName,
            alternatives:
                [
                  primary,
                  ...result.alternatives,
                ].where((x) => x.trim().isNotEmpty && x != bestName).toList(),
            setCodeCandidates: result.setCodeCandidates,
            confidence: result.confidence * 0.8,
            allCandidates: result.allCandidates,
          );
          return bestExact;
        }
      }
      return fuzzy;
    }

    return const [];
  }

  DeckCardItem? _tryAutoSelectEdition({
    required List<DeckCardItem> printings,
    required List<String> setCodeCandidates,
  }) {
    if (printings.isEmpty) return null;

    if (printings.length == 1) return printings.first;

    for (final code in setCodeCandidates) {
      final matches =
          printings
              .where((p) => p.setCode.trim().isNotEmpty)
              .where((p) => p.setCode.toUpperCase() == code.toUpperCase())
              .toList();
      if (matches.length == 1) return matches.first;
    }

    return null;
  }

  /// Busca manual por um nome alternativo
  Future<void> searchAlternative(String name) async {
    _setState(ScannerState.searching);
    _errorMessage = null;
    _autoSelectedCard = null;

    try {
      final exact = await _searchService.fetchPrintingsByExactName(name);
      final cards =
          exact.isNotEmpty ? exact : await _fuzzyMatcher.searchWithFuzzy(name);

      if (cards.isNotEmpty) {
        _foundCards = cards;
        _autoSelectedCard = _tryAutoSelectEdition(
          printings: cards,
          setCodeCandidates: _lastResult?.setCodeCandidates ?? const [],
        );
        _setState(ScannerState.found);
      } else {
        _errorMessage = 'Carta "$name" não encontrada';
        _setState(ScannerState.notFound);
      }
    } catch (e) {
      _errorMessage = 'Erro na busca: $e';
      _setState(ScannerState.error);
    }
  }

  /// Reseta o estado para nova captura
  void reset() {
    _state = ScannerState.idle;
    _lastResult = null;
    _foundCards = [];
    _autoSelectedCard = null;
    _errorMessage = null;
    notifyListeners();
  }

  void _setState(ScannerState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _recognitionService.dispose();
    super.dispose();
  }
}
