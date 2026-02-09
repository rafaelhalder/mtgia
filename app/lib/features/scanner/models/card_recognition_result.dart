import 'dart:ui';

/// Resultado do reconhecimento de carta
class CardRecognitionResult {
  final bool success;
  final String? primaryName;
  final List<String> alternatives;
  final double confidence;
  final String? error;
  final List<CardNameCandidate> allCandidates;

  CardRecognitionResult._({
    required this.success,
    this.primaryName,
    this.alternatives = const [],
    this.confidence = 0,
    this.error,
    this.allCandidates = const [],
  });

  factory CardRecognitionResult.success({
    required String primaryName,
    List<String> alternatives = const [],
    double confidence = 0,
    List<CardNameCandidate> allCandidates = const [],
  }) {
    return CardRecognitionResult._(
      success: true,
      primaryName: primaryName,
      alternatives: alternatives,
      confidence: confidence,
      allCandidates: allCandidates,
    );
  }

  factory CardRecognitionResult.failed(String error) {
    return CardRecognitionResult._(
      success: false,
      error: error,
    );
  }
}

/// Candidato a nome de carta detectado
class CardNameCandidate {
  final String text;
  final String rawText;
  final double score;
  final Rect boundingBox;

  CardNameCandidate({
    required this.text,
    required this.rawText,
    required this.score,
    required this.boundingBox,
  });
}
