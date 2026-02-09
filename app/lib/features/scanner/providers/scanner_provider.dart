import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/card_recognition_result.dart';
import '../services/card_recognition_service.dart';
import '../services/image_preprocessor.dart';
import '../services/fuzzy_card_matcher.dart';
import '../../cards/providers/card_provider.dart';
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
  final CardProvider _cardProvider;
  final CardRecognitionService _recognitionService = CardRecognitionService();
  late final FuzzyCardMatcher _fuzzyMatcher;

  ScannerState _state = ScannerState.idle;
  CardRecognitionResult? _lastResult;
  List<DeckCardItem> _foundCards = [];
  String? _errorMessage;
  bool _useFoilMode = false;

  ScannerState get state => _state;
  CardRecognitionResult? get lastResult => _lastResult;
  List<DeckCardItem> get foundCards => _foundCards;
  String? get errorMessage => _errorMessage;
  bool get useFoilMode => _useFoilMode;

  ScannerProvider(this._cardProvider) {
    _fuzzyMatcher = FuzzyCardMatcher(_cardProvider);
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
      
      // Tenta busca com fuzzy matching
      final cards = await _fuzzyMatcher.searchWithFuzzy(result.primaryName!);

      if (cards.isNotEmpty) {
        _foundCards = cards;
        _setState(ScannerState.found);
      } else {
        // Tenta alternativas se houver
        for (final alt in result.alternatives) {
          final altCards = await _fuzzyMatcher.searchWithFuzzy(alt);
          if (altCards.isNotEmpty) {
            _foundCards = altCards;
            _lastResult = CardRecognitionResult.success(
              primaryName: alt,
              alternatives: [result.primaryName!, ...result.alternatives.where((a) => a != alt)],
              confidence: result.confidence * 0.9,
              allCandidates: result.allCandidates,
            );
            _setState(ScannerState.found);
            return;
          }
        }

        _errorMessage = 'Carta "${result.primaryName}" não encontrada no banco';
        _setState(ScannerState.notFound);
      }
    } catch (e) {
      _errorMessage = 'Erro ao processar: $e';
      _setState(ScannerState.error);
    }
  }

  /// Busca manual por um nome alternativo
  Future<void> searchAlternative(String name) async {
    _setState(ScannerState.searching);
    _errorMessage = null;

    try {
      final cards = await _fuzzyMatcher.searchWithFuzzy(name);
      
      if (cards.isNotEmpty) {
        _foundCards = cards;
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
