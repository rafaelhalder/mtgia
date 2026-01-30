import 'package:postgres/postgres.dart';

class DeckRulesService {
  DeckRulesService(this._session);

  final Session _session;

  Future<void> validateAndThrow({
    required String format,
    required List<Map<String, dynamic>>
        cards, // {card_id, quantity, is_commander}
    bool strict = false,
  }) async {
    final normalizedFormat = format.toLowerCase();

    final cardIds = cards.map((c) => c['card_id']).whereType<String>().toList();
    if (cardIds.isEmpty) return;

    final cardsData = await _loadCardsData(cardIds);
    final legalities = await _loadLegalities(cardIds, normalizedFormat);

    // Regras gerais: limite de cópias por NOME (para suportar múltiplas edições)
    final copiesByName = <String, Map<String, dynamic>>{};
    for (final item in cards) {
      final cardId = item['card_id'] as String?;
      if (cardId == null || cardId.isEmpty) continue;

      final quantity = item['quantity'] as int? ?? 1;
      final isCommander = item['is_commander'] as bool? ?? false;

      final info = cardsData[cardId];
      if (info == null) continue;

      // Commander é validado separadamente (quantidade=1).
      if (isCommander) continue;

      final typeLine = info.typeLine.toLowerCase();
      final isBasicLand = typeLine.contains('basic land');
      if (isBasicLand) continue;

      final key = info.name.trim().toLowerCase();
      final existing = copiesByName[key];
      if (existing == null) {
        copiesByName[key] = {'name': info.name.trim(), 'qty': quantity};
      } else {
        copiesByName[key] = {
          'name': existing['name'] as String,
          'qty': (existing['qty'] as int) + quantity,
        };
      }
    }

    final limit =
        (normalizedFormat == 'commander' || normalizedFormat == 'brawl')
            ? 1
            : 4;
    for (final entry in copiesByName.entries) {
      final value = entry.value;
      final name = value['name'] as String? ?? entry.key;
      final qty = value['qty'] as int? ?? 0;
      if (qty > limit) {
        throw DeckRulesException(
          'Regra violada: "$name" excede o limite de $limit cópia(s) para o formato $normalizedFormat.',
        );
      }
    }

    // Regras gerais (limite de cópias + banlist/restrita)
    for (final item in cards) {
      final cardId = item['card_id'] as String?;
      final quantity = item['quantity'] as int? ?? 1;
      final isCommander = item['is_commander'] as bool? ?? false;

      if (cardId == null || cardId.isEmpty) {
        throw DeckRulesException('Carta sem card_id.');
      }
      if (quantity <= 0) {
        throw DeckRulesException('Quantidade inválida para card_id=$cardId.');
      }

      final info = cardsData[cardId];
      if (info == null) {
        throw DeckRulesException('Carta não encontrada (card_id=$cardId).');
      }

      final typeLine = info.typeLine.toLowerCase();
      final isBasicLand = typeLine.contains('basic land');

      final limit =
          (normalizedFormat == 'commander' || normalizedFormat == 'brawl')
              ? 1
              : 4;
      if (!isBasicLand && quantity > limit) {
        throw DeckRulesException(
          'Regra violada: "${info.name}" excede o limite de $limit cópia(s) para o formato $normalizedFormat.',
        );
      }

      if (isCommander && quantity != 1) {
        throw DeckRulesException(
            'Regra violada: comandante deve ter quantidade 1 ("${info.name}").');
      }

      final status = legalities[cardId];
      if (status == null) continue;
      if (status == 'banned') {
        throw DeckRulesException(
            'Regra violada: "${info.name}" é BANIDA no formato $normalizedFormat.');
      }
      if (status == 'not_legal') {
        throw DeckRulesException(
            'Regra violada: "${info.name}" não é válida no formato $normalizedFormat.');
      }
      if (status == 'restricted' && quantity > 1) {
        throw DeckRulesException(
            'Regra violada: "${info.name}" é RESTRITA no formato $normalizedFormat (máx. 1).');
      }
    }

    // Regras específicas de Commander/Brawl (MVP para o fluxo que você descreveu)
    if (normalizedFormat == 'commander' || normalizedFormat == 'brawl') {
      await _validateCommanderStyle(
        format: normalizedFormat,
        cards: cards,
        cardsData: cardsData,
        strict: strict,
      );
    }
  }

  Future<void> _validateCommanderStyle({
    required String format,
    required List<Map<String, dynamic>> cards,
    required Map<String, _CardData> cardsData,
    required bool strict,
  }) async {
    final commanders =
        cards.where((c) => (c['is_commander'] as bool?) ?? false).toList();

    if (commanders.isEmpty) {
      if (strict) {
        throw DeckRulesException(
            'Regra violada: deck $format precisa de 1 comandante selecionado.');
      }
      final total =
          cards.fold<int>(0, (sum, c) => sum + ((c['quantity'] as int?) ?? 1));
      final maxTotal = format == 'commander' ? 100 : 60;
      if (total > maxTotal) {
        throw DeckRulesException(
            'Regra violada: deck $format não pode exceder $maxTotal cartas (atual: $total).');
      }
      return;
    }
    if (commanders.length != 1) {
      throw DeckRulesException(
        'Regra violada: deck $format suporta exatamente 1 comandante (parceiros/background não implementados ainda).',
      );
    }

    final commanderId = commanders.first['card_id'] as String?;
    if (commanderId == null || commanderId.isEmpty) {
      throw DeckRulesException('Regra violada: comandante sem card_id.');
    }
    final commanderInfo = cardsData[commanderId];
    if (commanderInfo == null) {
      throw DeckRulesException('Regra violada: comandante não encontrado.');
    }

    if (!_isCommanderEligible(commanderInfo)) {
      throw DeckRulesException(
        'Regra violada: "${commanderInfo.name}" não pode ser comandante (precisa ser criatura lendária ou dizer "can be your commander").',
      );
    }

    final commanderIdentity = commanderInfo.colorIdentity.isNotEmpty
        ? commanderInfo.colorIdentity
        : commanderInfo.colors;
    final commanderSet = commanderIdentity.map((e) => e.toUpperCase()).toSet();

    for (final item in cards) {
      final cardId = item['card_id'] as String?;
      if (cardId == null) continue;
      final info = cardsData[cardId];
      if (info == null) continue;

      final identity =
          info.colorIdentity.isNotEmpty ? info.colorIdentity : info.colors;
      for (final c in identity) {
        if (!commanderSet.contains(c.toUpperCase())) {
          throw DeckRulesException(
            'Regra violada: "${info.name}" tem identidade de cor fora do comandante (${commanderIdentity.join(', ')}).',
          );
        }
      }
    }

    final total =
        cards.fold<int>(0, (sum, c) => sum + ((c['quantity'] as int?) ?? 1));
    final maxTotal = format == 'commander' ? 100 : 60;
    if (strict && total != maxTotal) {
      throw DeckRulesException(
          'Regra violada: deck $format deve ter exatamente $maxTotal cartas (atual: $total).');
    }
    if (total > maxTotal) {
      throw DeckRulesException(
          'Regra violada: deck $format não pode exceder $maxTotal cartas (atual: $total).');
    }
  }

  bool _isCommanderEligible(_CardData card) {
    final typeLine = card.typeLine.toLowerCase();
    final oracle = (card.oracleText ?? '').toLowerCase();

    final isLegendary = typeLine.contains('legendary');
    final isCreature = typeLine.contains('creature');
    if (isLegendary && isCreature) return true;

    // Planeswalkers e outras exceções com texto “can be your commander”.
    if (oracle.contains('can be your commander')) return true;

    return false;
  }

  Future<Map<String, _CardData>> _loadCardsData(List<String> cardIds) async {
    final result = await _session.execute(
      Sql.named('''
        SELECT id::text, name, type_line, oracle_text, colors, color_identity
        FROM cards
        WHERE id = ANY(@ids)
      '''),
      parameters: {'ids': cardIds},
    );

    final map = <String, _CardData>{};
    for (final row in result) {
      final id = row[0] as String;
      final name = row[1] as String;
      final typeLine = row[2] as String? ?? '';
      final oracleText = row[3] as String?;
      final colors = (row[4] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      final colorIdentity =
          (row[5] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];

      map[id] = _CardData(
        id: id,
        name: name,
        typeLine: typeLine,
        oracleText: oracleText,
        colors: colors,
        colorIdentity: colorIdentity,
      );
    }

    return map;
  }

  Future<Map<String, String>> _loadLegalities(
      List<String> cardIds, String format) async {
    final result = await _session.execute(
      Sql.named('''
        SELECT card_id::text, status
        FROM card_legalities
        WHERE card_id = ANY(@ids) AND format = @format
      '''),
      parameters: {'ids': cardIds, 'format': format},
    );

    return {
      for (final row in result)
        row[0] as String: (row[1] as String).toLowerCase()
    };
  }
}

class DeckRulesException implements Exception {
  DeckRulesException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _CardData {
  const _CardData({
    required this.id,
    required this.name,
    required this.typeLine,
    required this.oracleText,
    required this.colors,
    required this.colorIdentity,
  });

  final String id;
  final String name;
  final String typeLine;
  final String? oracleText;
  final List<String> colors;
  final List<String> colorIdentity;
}
