class DeckCardItem {
  final String id;
  final String name;
  final String? manaCost;
  final String typeLine;
  final String? oracleText;
  final List<String> colors;
  final String? imageUrl;
  final String setCode;
  final String? setName;
  final String? setReleaseDate; // yyyy-mm-dd
  final String rarity;
  final int quantity;
  final bool isCommander;

  DeckCardItem({
    required this.id,
    required this.name,
    this.manaCost,
    required this.typeLine,
    this.oracleText,
    this.colors = const [],
    this.imageUrl,
    required this.setCode,
    this.setName,
    this.setReleaseDate,
    required this.rarity,
    required this.quantity,
    required this.isCommander,
  });

  factory DeckCardItem.fromJson(Map<String, dynamic> json) {
    return DeckCardItem(
      id: json['id'] as String,
      name: json['name'] as String,
      manaCost: json['mana_cost'] as String?,
      typeLine: json['type_line'] as String? ?? '',
      oracleText: json['oracle_text'] as String?,
      colors: (json['colors'] as List?)?.map((e) => e as String).toList() ?? [],
      imageUrl: json['image_url'] as String?,
      setCode: json['set_code'] as String? ?? '',
      setName: json['set_name'] as String?,
      setReleaseDate: json['set_release_date'] as String?,
      rarity: json['rarity'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 1,
      isCommander: json['is_commander'] as bool? ?? false,
    );
  }
}
