/// Modelo para um card mover (variação de preço)
class CardMover {
  final String cardId;
  final String name;
  final String? setCode;
  final String? imageUrl;
  final String? rarity;
  final String? typeLine;
  final double priceToday;
  final double priceYesterday;
  final double changeUsd;
  final double changePct;

  CardMover({
    required this.cardId,
    required this.name,
    this.setCode,
    this.imageUrl,
    this.rarity,
    this.typeLine,
    required this.priceToday,
    required this.priceYesterday,
    required this.changeUsd,
    required this.changePct,
  });

  bool get isGainer => changeUsd > 0;
  bool get isLoser => changeUsd < 0;

  factory CardMover.fromJson(Map<String, dynamic> json) {
    return CardMover(
      cardId: json['card_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      setCode: json['set_code'] as String?,
      imageUrl: json['image_url'] as String?,
      rarity: json['rarity'] as String?,
      typeLine: json['type_line'] as String?,
      priceToday: (json['price_today'] as num?)?.toDouble() ?? 0.0,
      priceYesterday: (json['price_yesterday'] as num?)?.toDouble() ?? 0.0,
      changeUsd: (json['change_usd'] as num?)?.toDouble() ?? 0.0,
      changePct: (json['change_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Resposta do endpoint /market/movers
class MarketMoversData {
  final String? date;
  final String? previousDate;
  final List<CardMover> gainers;
  final List<CardMover> losers;
  final int totalTracked;
  final String? message;

  MarketMoversData({
    this.date,
    this.previousDate,
    required this.gainers,
    required this.losers,
    this.totalTracked = 0,
    this.message,
  });

  bool get hasData => gainers.isNotEmpty || losers.isNotEmpty;
  bool get needsMoreData => message != null && !hasData;

  factory MarketMoversData.fromJson(Map<String, dynamic> json) {
    return MarketMoversData(
      date: json['date'] as String?,
      previousDate: json['previous_date'] as String?,
      gainers: (json['gainers'] as List<dynamic>?)
              ?.map((e) => CardMover.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      losers: (json['losers'] as List<dynamic>?)
              ?.map((e) => CardMover.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalTracked: json['total_tracked'] as int? ?? 0,
      message: json['message'] as String?,
    );
  }
}
