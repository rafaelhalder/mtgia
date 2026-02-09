/// Funções utilitárias de parsing/extração para sync de cartas.
///
/// Extraídas do sync_cards.dart para serem testáveis independentemente
/// do Postgres e HTTP.

/// Extrai dados de uma carta do AtomicCards para upsert no banco.
///
/// Recebe o nome da carta e a lista de printings do MTGJSON.
/// Retorna uma lista de parâmetros prontos para prepared statement,
/// ou `null` se a carta não tiver oracleId válido.
///
/// Índices do retorno:
/// [0] oracleId, [1] name, [2] manaCost, [3] typeLine, [4] oracleText,
/// [5] colors, [6] colorIdentity, [7] imageUrl, [8] setCode, [9] rarity
List<Object?>? extractCardRow(String cardName, List<dynamic> printings) {
  Map<String, dynamic>? chosen;
  for (final p in printings) {
    if (p is! Map<String, dynamic>) continue;
    final ids = p['identifiers'] as Map<String, dynamic>?;
    if (ids?['scryfallOracleId'] != null &&
        (ids!['scryfallOracleId'] as String).isNotEmpty) {
      chosen = p;
      break;
    }
  }
  if (chosen == null) return null;

  final ids = chosen['identifiers'] as Map<String, dynamic>?;
  final oracleId = ids?['scryfallOracleId'] as String?;
  if (oracleId == null || oracleId.isEmpty) return null;

  final name = (chosen['name'] ?? cardName).toString();
  final manaCost = chosen['manaCost']?.toString();
  final typeLine = chosen['type']?.toString();
  final oracleText = chosen['text']?.toString();
  final colors =
      (chosen['colors'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
  final colorIdentity =
      (chosen['colorIdentity'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
  final setCode =
      (chosen['printings'] as List?)?.cast<dynamic>().firstOrNull?.toString();
  final rarity = chosen['rarity']?.toString();

  final encodedName = Uri.encodeQueryComponent(name);
  final setParam =
      setCode != null && setCode.isNotEmpty ? '&set=$setCode' : '';
  final imageUrl =
      'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

  return [
    oracleId, name, manaCost, typeLine, oracleText,
    colors, colorIdentity, imageUrl, setCode, rarity,
  ];
}

/// Filtra sets novos a partir dos dados do SetList.json em memória.
///
/// [setListData] é a lista `data` decodificada do SetList.json.
/// [since] é a data de corte (último sync).
/// Retorna lista de set codes ordenada.
List<String> getNewSetCodesSinceFromData(
    List<dynamic> setListData, DateTime since) {
  final cutoff = since.subtract(const Duration(days: 2));
  final codes = <String>[];
  for (final item in setListData) {
    if (item is! Map) continue;
    final code = item['code']?.toString();
    final releaseDateStr = item['releaseDate']?.toString();
    if (code == null || releaseDateStr == null) continue;
    final releaseDate = DateTime.tryParse(releaseDateStr);
    if (releaseDate != null && releaseDate.isAfter(cutoff)) {
      codes.add(code);
    }
  }
  codes.sort();
  return codes;
}

/// Parseia o argumento --since-days=<N> dos args da CLI.
/// Retorna null se não encontrado ou inválido.
int? parseSinceDays(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--since-days=')) {
      final parsed = int.tryParse(arg.split('=').last.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return null;
}

/// Extrai dados de uma carta de um set para upsert incremental.
///
/// Diferente de [extractCardRow], recebe o JSON direto do set
/// (não do AtomicCards).
List<Object?>? extractSetCardRow(Map<String, dynamic> card, String setCode) {
  final ids = card['identifiers'] as Map<String, dynamic>?;
  final oracleId = ids?['scryfallOracleId']?.toString();
  if (oracleId == null || oracleId.isEmpty) return null;

  final name = card['name']?.toString();
  if (name == null || name.isEmpty) return null;

  final colors =
      (card['colors'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
  final colorIdentity =
      (card['colorIdentity'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];

  final encodedName = Uri.encodeQueryComponent(name);
  final setParam = setCode.isNotEmpty ? '&set=$setCode' : '';
  final imageUrl =
      'https://api.scryfall.com/cards/named?exact=$encodedName$setParam&format=image';

  return [
    oracleId, name, card['manaCost']?.toString(),
    card['type']?.toString(), card['text']?.toString(),
    colors, colorIdentity, imageUrl, setCode,
    card['rarity']?.toString(),
  ];
}

/// Extrai oracle IDs de uma lista de cartas de um set.
Set<String> extractOracleIds(List<Map<String, dynamic>> cards) {
  final oracleIds = <String>{};
  for (final card in cards) {
    final ids = card['identifiers'] as Map<String, dynamic>?;
    final oid = ids?['scryfallOracleId']?.toString();
    if (oid != null && oid.isNotEmpty) oracleIds.add(oid);
  }
  return oracleIds;
}

/// Extrai pares (formato, status) de legalidades de uma carta.
List<MapEntry<String, String>> extractLegalities(Map<String, dynamic> card) {
  final legalities = card['legalities'] as Map<String, dynamic>?;
  if (legalities == null) return const [];
  return legalities.entries
      .map((e) => MapEntry(e.key, e.value.toString().toLowerCase()))
      .toList();
}
