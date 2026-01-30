/// Deck Model - Representa um deck do usuário
class Deck {
  final String id;
  final String name;
  final String format;
  final String? description;
  final String?
  archetype; // Arquétipo do deck (aggro, control, midrange, combo, etc)
  final int? bracket; // 1..4 (EDH bracket)
  final int? synergyScore;
  final String? strengths;
  final String? weaknesses;
  final String? pricingCurrency;
  final double? pricingTotal;
  final int? pricingMissingCards;
  final DateTime? pricingUpdatedAt;
  final bool isPublic;
  final DateTime createdAt;
  final int cardCount;

  Deck({
    required this.id,
    required this.name,
    required this.format,
    this.description,
    this.archetype,
    this.bracket,
    this.synergyScore,
    this.strengths,
    this.weaknesses,
    this.pricingCurrency,
    this.pricingTotal,
    this.pricingMissingCards,
    this.pricingUpdatedAt,
    required this.isPublic,
    required this.createdAt,
    this.cardCount = 0,
  });

  /// Factory para criar Deck a partir de JSON (API response)
  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      id: json['id'] as String,
      name: json['name'] as String,
      format: json['format'] as String,
      description: json['description'] as String?,
      archetype: json['archetype'] as String?,
      bracket: json['bracket'] as int?,
      synergyScore: json['synergy_score'] as int?,
      strengths: json['strengths'] as String?,
      weaknesses: json['weaknesses'] as String?,
      pricingCurrency: json['pricing_currency'] as String?,
      pricingTotal: (json['pricing_total'] as num?)?.toDouble(),
      pricingMissingCards: json['pricing_missing_cards'] as int?,
      pricingUpdatedAt:
          (json['pricing_updated_at'] != null)
              ? DateTime.tryParse(json['pricing_updated_at'] as String)
              : null,
      isPublic: json['is_public'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      cardCount: json['card_count'] as int? ?? 0,
    );
  }

  /// Converte o Deck para JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'format': format,
      'description': description,
      'archetype': archetype,
      'bracket': bracket,
      'synergy_score': synergyScore,
      'strengths': strengths,
      'weaknesses': weaknesses,
      'pricing_currency': pricingCurrency,
      'pricing_total': pricingTotal,
      'pricing_missing_cards': pricingMissingCards,
      'pricing_updated_at': pricingUpdatedAt?.toIso8601String(),
      'is_public': isPublic,
      'created_at': createdAt.toIso8601String(),
      'card_count': cardCount,
    };
  }

  /// Cria uma cópia do Deck com modificações
  Deck copyWith({
    String? id,
    String? name,
    String? format,
    String? description,
    String? archetype,
    int? bracket,
    int? synergyScore,
    String? strengths,
    String? weaknesses,
    String? pricingCurrency,
    double? pricingTotal,
    int? pricingMissingCards,
    DateTime? pricingUpdatedAt,
    bool? isPublic,
    DateTime? createdAt,
    int? cardCount,
  }) {
    return Deck(
      id: id ?? this.id,
      name: name ?? this.name,
      format: format ?? this.format,
      description: description ?? this.description,
      archetype: archetype ?? this.archetype,
      bracket: bracket ?? this.bracket,
      synergyScore: synergyScore ?? this.synergyScore,
      strengths: strengths ?? this.strengths,
      weaknesses: weaknesses ?? this.weaknesses,
      pricingCurrency: pricingCurrency ?? this.pricingCurrency,
      pricingTotal: pricingTotal ?? this.pricingTotal,
      pricingMissingCards: pricingMissingCards ?? this.pricingMissingCards,
      pricingUpdatedAt: pricingUpdatedAt ?? this.pricingUpdatedAt,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      cardCount: cardCount ?? this.cardCount,
    );
  }
}
