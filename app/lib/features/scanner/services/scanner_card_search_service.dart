import '../../../core/api/api_client.dart';
import '../../decks/models/deck_card_item.dart';

/// Busca de cartas para o scanner sem depender do estado global do CardProvider.
class ScannerCardSearchService {
  final ApiClient _apiClient;

  ScannerCardSearchService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  Future<List<DeckCardItem>> searchByName(
    String name, {
    int limit = 50,
    int page = 1,
  }) async {
    final q = name.trim();
    if (q.isEmpty) return const [];

    final encoded = Uri.encodeQueryComponent(q);
    final response = await _apiClient.get(
      '/cards?name=$encoded&limit=$limit&page=$page',
    );

    if (response.statusCode != 200) {
      return const [];
    }

    final data = response.data;
    if (data is! Map) return const [];
    final List<dynamic> cardsJson = (data['data'] as List?) ?? const [];

    return cardsJson
        .whereType<Map>()
        .map((json) {
          return DeckCardItem(
            id: json['id']?.toString() ?? '',
            name: json['name']?.toString() ?? '',
            manaCost: json['mana_cost']?.toString(),
            typeLine: json['type_line']?.toString() ?? '',
            oracleText: json['oracle_text']?.toString(),
            colors:
                (json['colors'] as List?)?.map((e) => e.toString()).toList() ??
                [],
            colorIdentity:
                (json['color_identity'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            imageUrl: json['image_url']?.toString(),
            setCode: json['set_code']?.toString() ?? '',
            setName: json['set_name']?.toString(),
            setReleaseDate: json['set_release_date']?.toString(),
            rarity: json['rarity']?.toString() ?? '',
            quantity: 1,
            isCommander: false,
          );
        })
        .where((c) => c.id.isNotEmpty && c.name.trim().isNotEmpty)
        .toList();
  }

  Future<List<DeckCardItem>> fetchPrintingsByExactName(
    String name, {
    int limit = 50,
  }) async {
    final q = name.trim();
    if (q.isEmpty) return const [];

    final encoded = Uri.encodeQueryComponent(q);
    final response = await _apiClient.get(
      '/cards/printings?name=$encoded&limit=$limit',
    );

    if (response.statusCode != 200) {
      return const [];
    }

    final data = response.data;
    if (data is! Map) return const [];
    final List<dynamic> cardsJson = (data['data'] as List?) ?? const [];

    return cardsJson
        .whereType<Map>()
        .map((json) {
          return DeckCardItem(
            id: json['id']?.toString() ?? '',
            name: json['name']?.toString() ?? '',
            manaCost: json['mana_cost']?.toString(),
            typeLine: json['type_line']?.toString() ?? '',
            oracleText: json['oracle_text']?.toString(),
            colors:
                (json['colors'] as List?)?.map((e) => e.toString()).toList() ??
                [],
            colorIdentity:
                (json['color_identity'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            imageUrl: json['image_url']?.toString(),
            setCode: json['set_code']?.toString() ?? '',
            setName: json['set_name']?.toString(),
            setReleaseDate: json['set_release_date']?.toString(),
            rarity: json['rarity']?.toString() ?? '',
            quantity: 1,
            isCommander: false,
          );
        })
        .where((c) => c.id.isNotEmpty && c.name.trim().isNotEmpty)
        .toList();
  }

  /// Resolve uma carta pelo nome usando o endpoint de fallback Scryfall.
  ///
  /// O server busca primeiro no banco local. Se não encontrar, consulta a
  /// Scryfall API, insere a carta no banco e retorna. Isso garante que
  /// qualquer carta real de MTG seja encontrada, mesmo que ainda não esteja
  /// no nosso banco de dados.
  ///
  /// Retorna a lista de printings encontradas ou lista vazia.
  Future<List<DeckCardItem>> resolveCard(String name) async {
    final q = name.trim();
    if (q.isEmpty) return const [];

    try {
      final response = await _apiClient.post(
        '/cards/resolve',
        {'name': q},
      );

      if (response.statusCode != 200) {
        return const [];
      }

      final data = response.data;
      if (data is! Map) return const [];
      final List<dynamic> cardsJson = (data['data'] as List?) ?? const [];

      return cardsJson
          .whereType<Map>()
          .map((json) {
            return DeckCardItem(
              id: json['id']?.toString() ?? '',
              name: json['name']?.toString() ?? '',
              manaCost: json['mana_cost']?.toString(),
              typeLine: json['type_line']?.toString() ?? '',
              oracleText: json['oracle_text']?.toString(),
              colors:
                  (json['colors'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              colorIdentity:
                  (json['color_identity'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              imageUrl: json['image_url']?.toString(),
              setCode: json['set_code']?.toString() ?? '',
              setName: json['set_name']?.toString(),
              setReleaseDate: json['set_release_date']?.toString(),
              rarity: json['rarity']?.toString() ?? '',
              quantity: 1,
              isCommander: false,
            );
          })
          .where((c) => c.id.isNotEmpty && c.name.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
