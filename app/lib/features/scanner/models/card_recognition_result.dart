import 'dart:ui';

/// Informações do colecionador extraídas da parte inferior da carta
/// Formato moderno (2020+): "157/274 • BLB • EN" ou "157/274 ★ BLB • EN"
class CollectorInfo {
  /// Número de colecionador (ex: "157")
  final String? collectorNumber;

  /// Total de cartas na edição (ex: "274")
  final String? totalInSet;

  /// Código de set detectado na parte inferior (ex: "BLB")
  final String? setCode;

  /// Se a carta é foil (★ = foil, • = non-foil)
  final bool? isFoil;

  /// Idioma detectado (ex: "EN", "PT", "JP")
  final String? language;

  /// Texto bruto da região inferior usado para extração
  final String? rawBottomText;

  const CollectorInfo({
    this.collectorNumber,
    this.totalInSet,
    this.setCode,
    this.isFoil,
    this.language,
    this.rawBottomText,
  });

  /// Verifica se temos informação útil
  bool get hasData =>
      collectorNumber != null || setCode != null || isFoil != null;

  @override
  String toString() =>
      'CollectorInfo(#$collectorNumber/$totalInSet '
      '${isFoil == true ? "★" : "•"} $setCode $language)';
}

/// Resultado do reconhecimento de carta
class CardRecognitionResult {
  final bool success;
  final String? primaryName;
  final List<String> alternatives;
  final List<String> setCodeCandidates;
  final double confidence;
  final String? error;
  final List<CardNameCandidate> allCandidates;

  /// Informações do colecionador (número, set code, foil) extraídas da
  /// parte inferior da carta via OCR
  final CollectorInfo? collectorInfo;

  CardRecognitionResult._({
    required this.success,
    this.primaryName,
    this.alternatives = const [],
    this.setCodeCandidates = const [],
    this.confidence = 0,
    this.error,
    this.allCandidates = const [],
    this.collectorInfo,
  });

  factory CardRecognitionResult.success({
    required String primaryName,
    List<String> alternatives = const [],
    List<String> setCodeCandidates = const [],
    double confidence = 0,
    List<CardNameCandidate> allCandidates = const [],
    CollectorInfo? collectorInfo,
  }) {
    return CardRecognitionResult._(
      success: true,
      primaryName: primaryName,
      alternatives: alternatives,
      setCodeCandidates: setCodeCandidates,
      confidence: confidence,
      allCandidates: allCandidates,
      collectorInfo: collectorInfo,
    );
  }

  factory CardRecognitionResult.failed(String error) {
    return CardRecognitionResult._(success: false, error: error);
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
