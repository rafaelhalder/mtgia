/// Condições de carta no padrão TCGPlayer.
/// NM = Near Mint, LP = Lightly Played, MP = Moderately Played,
/// HP = Heavily Played, DMG = Damaged.
enum CardCondition {
  nm('NM', 'Near Mint'),
  lp('LP', 'Lightly Played'),
  mp('MP', 'Moderately Played'),
  hp('HP', 'Heavily Played'),
  dmg('DMG', 'Damaged');

  const CardCondition(this.code, this.label);
  final String code;
  final String label;

  static CardCondition fromCode(String? code) {
    if (code == null) return CardCondition.nm;
    final upper = code.trim().toUpperCase();
    return CardCondition.values.firstWhere(
      (c) => c.code == upper,
      orElse: () => CardCondition.nm,
    );
  }
}

class DeckCardItem {
  final String id;
  final String name;
  final String? manaCost;
  final String typeLine;
  final String? oracleText;
  final List<String> colors;
  final List<String> colorIdentity;
  final String? imageUrl;
  final String setCode;
  final String? setName;
  final String? setReleaseDate; // yyyy-mm-dd
  final String rarity;
  final int quantity;
  final bool isCommander;

  /// Número de colecionador (ex: "157", "157a")
  final String? collectorNumber;

  /// Status foil: true=foil, false=non-foil, null=desconhecido
  final bool? foil;

  /// Condição física da carta (TCGPlayer standard)
  final CardCondition condition;

  DeckCardItem({
    required this.id,
    required this.name,
    this.manaCost,
    required this.typeLine,
    this.oracleText,
    this.colors = const [],
    this.colorIdentity = const [],
    this.imageUrl,
    required this.setCode,
    this.setName,
    this.setReleaseDate,
    required this.rarity,
    required this.quantity,
    required this.isCommander,
    this.collectorNumber,
    this.foil,
    this.condition = CardCondition.nm,
  });

  /// Cria cópia com campos alterados.
  DeckCardItem copyWith({
    String? id,
    String? name,
    String? manaCost,
    String? typeLine,
    String? oracleText,
    List<String>? colors,
    List<String>? colorIdentity,
    String? imageUrl,
    String? setCode,
    String? setName,
    String? setReleaseDate,
    String? rarity,
    int? quantity,
    bool? isCommander,
    String? collectorNumber,
    bool? foil,
    CardCondition? condition,
  }) {
    return DeckCardItem(
      id: id ?? this.id,
      name: name ?? this.name,
      manaCost: manaCost ?? this.manaCost,
      typeLine: typeLine ?? this.typeLine,
      oracleText: oracleText ?? this.oracleText,
      colors: colors ?? this.colors,
      colorIdentity: colorIdentity ?? this.colorIdentity,
      imageUrl: imageUrl ?? this.imageUrl,
      setCode: setCode ?? this.setCode,
      setName: setName ?? this.setName,
      setReleaseDate: setReleaseDate ?? this.setReleaseDate,
      rarity: rarity ?? this.rarity,
      quantity: quantity ?? this.quantity,
      isCommander: isCommander ?? this.isCommander,
      collectorNumber: collectorNumber ?? this.collectorNumber,
      foil: foil ?? this.foil,
      condition: condition ?? this.condition,
    );
  }

  factory DeckCardItem.fromJson(Map<String, dynamic> json) {
    return DeckCardItem(
      id: json['id'] as String,
      name: json['name'] as String,
      manaCost: json['mana_cost'] as String?,
      typeLine: json['type_line'] as String? ?? '',
      oracleText: json['oracle_text'] as String?,
      colors: (json['colors'] as List?)?.map((e) => e as String).toList() ?? [],
      colorIdentity: (json['color_identity'] as List?)?.map((e) => e as String).toList() ?? [],
      imageUrl: json['image_url'] as String?,
      setCode: json['set_code'] as String? ?? '',
      setName: json['set_name'] as String?,
      setReleaseDate: json['set_release_date'] as String?,
      rarity: json['rarity'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 1,
      isCommander: json['is_commander'] as bool? ?? false,
      collectorNumber: json['collector_number'] as String?,
      foil: json['foil'] as bool?,
      condition: CardCondition.fromCode(json['condition'] as String?),
    );
  }
}
