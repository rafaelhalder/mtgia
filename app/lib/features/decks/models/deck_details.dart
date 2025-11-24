import 'deck.dart';
import 'deck_card_item.dart';

class DeckDetails extends Deck {
  final Map<String, dynamic> stats;
  final List<DeckCardItem> commander;
  final Map<String, List<DeckCardItem>> mainBoard;

  DeckDetails({
    required super.id,
    required super.name,
    required super.format,
    super.description,
    super.archetype,
    super.synergyScore,
    super.strengths,
    super.weaknesses,
    required super.isPublic,
    required super.createdAt,
    super.cardCount,
    required this.stats,
    required this.commander,
    required this.mainBoard,
  });

  factory DeckDetails.fromJson(Map<String, dynamic> json) {
    // Parse commander list
    final commanderList = (json['commander'] as List?)
            ?.map((e) => DeckCardItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    // Parse main board map
    final mainBoardMap = <String, List<DeckCardItem>>{};
    if (json['main_board'] != null) {
      (json['main_board'] as Map<String, dynamic>).forEach((key, value) {
        mainBoardMap[key] = (value as List)
            .map((e) => DeckCardItem.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }

    return DeckDetails(
      id: json['id'] as String,
      name: json['name'] as String,
      format: json['format'] as String,
      description: json['description'] as String?,
      archetype: json['archetype'] as String?,
      synergyScore: json['synergy_score'] as int?,
      strengths: json['strengths'] as String?,
      weaknesses: json['weaknesses'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      cardCount: json['stats']?['total_cards'] as int? ?? 0,
      stats: json['stats'] as Map<String, dynamic>? ?? {},
      commander: commanderList,
      mainBoard: mainBoardMap,
    );
  }
}
