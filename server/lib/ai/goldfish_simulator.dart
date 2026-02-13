import 'dart:math';

/// Resultado da simulação Goldfish (jogar sozinho)
class GoldfishResult {
  final int simulations;
  final double screwRate; // % de mãos com 0-1 terrenos
  final double floodRate; // % de mãos com 6-7 terrenos
  final double keepableRate; // % de mãos com 2-5 terrenos
  final double turn1PlayRate;
  final double turn2PlayRate;
  final double turn3PlayRate;
  final double turn4PlayRate;
  final double avgCmc;
  final int landCount;
  final Map<int, int> cmcDistribution; // CMC -> quantidade

  GoldfishResult({
    required this.simulations,
    required this.screwRate,
    required this.floodRate,
    required this.keepableRate,
    required this.turn1PlayRate,
    required this.turn2PlayRate,
    required this.turn3PlayRate,
    required this.turn4PlayRate,
    required this.avgCmc,
    required this.landCount,
    required this.cmcDistribution,
  });

  /// Score de consistência (0-100)
  int get consistencyScore {
    final score = (keepableRate * 40) + // 40% peso em mãos jogáveis
        (turn2PlayRate * 25) + // 25% em ter jogada no T2
        (turn3PlayRate * 20) + // 20% em ter jogada no T3
        ((1 - screwRate) * 10) + // 10% em evitar screw
        ((1 - floodRate) * 5); // 5% em evitar flood

    return (score * 100).round().clamp(0, 100);
  }

  /// Gera recomendações baseadas nas métricas
  List<String> get recommendations {
    final recs = <String>[];

    // Análise de terrenos
    if (screwRate > 0.15) {
      recs.add(
          'Alta taxa de mana screw (${(screwRate * 100).toStringAsFixed(1)}%). Considere adicionar 2-4 terrenos.');
    }
    if (floodRate > 0.12) {
      recs.add(
          'Alta taxa de mana flood (${(floodRate * 100).toStringAsFixed(1)}%). Considere remover 2-3 terrenos ou adicionar card draw.');
    }
    if (landCount < 33) {
      recs.add(
          'Apenas $landCount terrenos. Commander geralmente precisa de 35-38.');
    }
    if (landCount > 40) {
      recs.add(
          '$landCount terrenos é acima do ideal. Considere trocar alguns por mana rocks.');
    }

    // Análise de curva
    if (turn1PlayRate < 0.20) {
      recs.add(
          'Poucas jogadas de 1 mana (${(turn1PlayRate * 100).toStringAsFixed(0)}%). Adicione mana rocks ou cantrips de 1 CMC.');
    }
    if (turn2PlayRate < 0.60) {
      recs.add(
          'Curva de 2 mana fraca (${(turn2PlayRate * 100).toStringAsFixed(0)}%). Adicione mais cartas de 2 CMC.');
    }
    if (avgCmc > 3.5) {
      recs.add(
          'CMC médio alto (${avgCmc.toStringAsFixed(2)}). Deck pode ser lento; adicione mais cartas baratas.');
    }

    // Distribuição de CMC
    final lowCmc = (cmcDistribution[0] ?? 0) +
        (cmcDistribution[1] ?? 0) +
        (cmcDistribution[2] ?? 0);
    if (lowCmc < 20) {
      recs.add(
          'Apenas $lowCmc cartas com CMC 0-2. Considere mais early game.');
    }

    if (recs.isEmpty) {
      recs.add('Deck bem balanceado! Métricas dentro do ideal para Commander.');
    }

    return recs;
  }

  Map<String, dynamic> toJson() => {
        'simulations': simulations,
        'consistency_score': consistencyScore,
        'mana_analysis': {
          'land_count': landCount,
          'screw_rate': double.parse(screwRate.toStringAsFixed(3)),
          'flood_rate': double.parse(floodRate.toStringAsFixed(3)),
          'keepable_rate': double.parse(keepableRate.toStringAsFixed(3)),
        },
        'curve_analysis': {
          'avg_cmc': double.parse(avgCmc.toStringAsFixed(2)),
          'turn_1_play': double.parse(turn1PlayRate.toStringAsFixed(3)),
          'turn_2_play': double.parse(turn2PlayRate.toStringAsFixed(3)),
          'turn_3_play': double.parse(turn3PlayRate.toStringAsFixed(3)),
          'turn_4_play': double.parse(turn4PlayRate.toStringAsFixed(3)),
          'cmc_distribution': cmcDistribution.map((k, v) => MapEntry(k.toString(), v)),
        },
        'recommendations': recommendations,
      };
}

/// Simulador Monte Carlo para análise de consistência de decks
class GoldfishSimulator {
  final List<Map<String, dynamic>> cards;
  final int simulations;
  final Random _random;

  GoldfishSimulator(
    this.cards, {
    this.simulations = 1000,
    Random? random,
  }) : _random = random ?? Random();

  /// Executa a simulação e retorna métricas
  GoldfishResult simulate() {
    int screwHands = 0; // 0-1 lands
    int floodHands = 0; // 6-7 lands
    int keepableHands = 0; // 2-5 lands
    int turn1Plays = 0;
    int turn2Plays = 0;
    int turn3Plays = 0;
    int turn4Plays = 0;

    // Expande o deck (quantidade de cada carta)
    final expandedDeck = _expandDeck();

    for (var i = 0; i < simulations; i++) {
      // Shuffle
      final shuffled = List<Map<String, dynamic>>.from(expandedDeck)
        ..shuffle(_random);

      // Mão inicial (7 cartas)
      final hand = shuffled.take(7).toList();

      // Próximas compras (turnos 2-5)
      final draws = shuffled.skip(7).take(4).toList();

      // Conta terrenos na mão
      final landsInHand = hand.where(_isLand).length;

      if (landsInHand <= 1) screwHands++;
      if (landsInHand >= 6) floodHands++;
      if (landsInHand >= 2 && landsInHand <= 5) keepableHands++;

      // Simula jogabilidade por turno
      var cardsAvailable = List<Map<String, dynamic>>.from(hand);
      var landsPlayed = 0;
      final colorSources = <String, int>{}; // Rastreia fontes de mana colorida

      // Turno 1
      landsPlayed = _playLandIfPossible(cardsAvailable, landsPlayed, colorSources: colorSources);
      if (_canPlayOnTurn(cardsAvailable, 1, landsPlayed, colorSources: colorSources)) {
        turn1Plays++;
      }

      // Turno 2
      if (draws.isNotEmpty) cardsAvailable.add(draws[0]);
      landsPlayed = _playLandIfPossible(cardsAvailable, landsPlayed, colorSources: colorSources);
      if (_canPlayOnTurn(cardsAvailable, 2, landsPlayed, colorSources: colorSources)) turn2Plays++;

      // Turno 3
      if (draws.length > 1) cardsAvailable.add(draws[1]);
      landsPlayed = _playLandIfPossible(cardsAvailable, landsPlayed, colorSources: colorSources);
      if (_canPlayOnTurn(cardsAvailable, 3, landsPlayed, colorSources: colorSources)) turn3Plays++;

      // Turno 4
      if (draws.length > 2) cardsAvailable.add(draws[2]);
      landsPlayed = _playLandIfPossible(cardsAvailable, landsPlayed, colorSources: colorSources);
      if (_canPlayOnTurn(cardsAvailable, 4, landsPlayed, colorSources: colorSources)) turn4Plays++;
    }

    return GoldfishResult(
      simulations: simulations,
      screwRate: screwHands / simulations,
      floodRate: floodHands / simulations,
      keepableRate: keepableHands / simulations,
      turn1PlayRate: turn1Plays / simulations,
      turn2PlayRate: turn2Plays / simulations,
      turn3PlayRate: turn3Plays / simulations,
      turn4PlayRate: turn4Plays / simulations,
      avgCmc: _calculateAvgCmc(),
      landCount: _countLands(),
      cmcDistribution: _getCmcDistribution(),
    );
  }

  /// Expande o deck considerando quantidade de cada carta
  List<Map<String, dynamic>> _expandDeck() {
    final expanded = <Map<String, dynamic>>[];
    for (final card in cards) {
      final qty = (card['quantity'] as int?) ?? 1;
      for (var i = 0; i < qty; i++) {
        expanded.add(card);
      }
    }
    return expanded;
  }

  /// Verifica se a carta é um terreno
  bool _isLand(Map<String, dynamic> card) {
    final typeLine = (card['type_line'] ?? '').toString().toLowerCase();
    return typeLine.contains('land');
  }

  /// Obtém o CMC de uma carta
  int _getCmc(Map<String, dynamic> card) {
    final cmc = card['cmc'];
    if (cmc == null) return 0;
    if (cmc is int) return cmc;
    if (cmc is double) return cmc.toInt();
    return int.tryParse(cmc.toString()) ?? 0;
  }

  /// Extrai requisitos de mana colorida do mana_cost (ex: "{2}{U}{U}" → {U: 2})
  Map<String, int> _getColorRequirements(Map<String, dynamic> card) {
    final manaCost = (card['mana_cost'] ?? '').toString();
    if (manaCost.isEmpty) return const {};
    final colorCounts = <String, int>{};
    final matches = RegExp(r'\{([^}]+)\}').allMatches(manaCost);
    for (final m in matches) {
      final symbol = m.group(1)!.toUpperCase();
      if ({'W', 'U', 'B', 'R', 'G'}.contains(symbol)) {
        colorCounts[symbol] = (colorCounts[symbol] ?? 0) + 1;
      }
      // Phyrexian mana (W/P, U/P, etc.) — counts as the color
      if (symbol.contains('/P') && symbol.length >= 3) {
        final color = symbol.substring(0, 1);
        if ({'W', 'U', 'B', 'R', 'G'}.contains(color)) {
          colorCounts[color] = (colorCounts[color] ?? 0) + 1;
        }
      }
      // Hybrid mana (W/U) — requires EITHER, pick the one we have more of.
      // For simulation simplicity, treat as generic (no strict color req).
    }
    return colorCounts;
  }

  /// Determina quais cores um terreno pode produzir (heurística via oracle/type/name)
  Set<String> _getLandColors(Map<String, dynamic> card) {
    final oracle = (card['oracle_text'] ?? '').toString().toLowerCase();
    final typeLine = (card['type_line'] ?? '').toString().toLowerCase();
    final producedColors = <String>{};

    // Basic land types in type_line (Dual lands, Shocks, etc.)
    if (typeLine.contains('plains')) producedColors.add('W');
    if (typeLine.contains('island')) producedColors.add('U');
    if (typeLine.contains('swamp')) producedColors.add('B');
    if (typeLine.contains('mountain')) producedColors.add('R');
    if (typeLine.contains('forest')) producedColors.add('G');

    // "Add {X}" patterns in oracle text
    if (oracle.contains('{w}') || oracle.contains('add {w')) producedColors.add('W');
    if (oracle.contains('{u}') || oracle.contains('add {u')) producedColors.add('U');
    if (oracle.contains('{b}') || oracle.contains('add {b')) producedColors.add('B');
    if (oracle.contains('{r}') || oracle.contains('add {r')) producedColors.add('R');
    if (oracle.contains('{g}') || oracle.contains('add {g')) producedColors.add('G');

    // "Mana of any color" / "mana of any type"
    if (oracle.contains('any color') || oracle.contains('any type')) {
      producedColors.addAll(['W', 'U', 'B', 'R', 'G']);
    }

    // Wastes / colorless lands: produce no color (just generic mana)
    // If we couldn't detect any color, it's a colorless source
    return producedColors;
  }

  /// Verifica se há jogada válida no turno, considerando mana colorida
  bool _canPlayOnTurn(
      List<Map<String, dynamic>> cards, int turn, int landsPlayed,
      {Map<String, int> colorSources = const {}}) {
    // Mana total disponível = terrenos jogados
    final manaAvailable = turn == 1 ? 1 : landsPlayed;

    return cards.any((c) {
      if (_isLand(c)) return false;
      final cmc = _getCmc(c);
      if (cmc > manaAvailable) return false;

      // Verificar requisitos de mana colorida
      final colorReqs = _getColorRequirements(c);
      if (colorReqs.isEmpty) return true; // Carta genérica/colorless: ok

      for (final entry in colorReqs.entries) {
        final available = colorSources[entry.key] ?? 0;
        if (available < entry.value) return false;
      }
      return true;
    });
  }

  /// Simula jogar um terreno se possível, rastreando cores produzidas
  int _playLandIfPossible(List<Map<String, dynamic>> cards, int landsPlayed,
      {Map<String, int>? colorSources}) {
    final landIndex = cards.indexWhere(_isLand);
    if (landIndex != -1) {
      final land = cards.removeAt(landIndex);
      // Rastrear que cores este terreno produz
      if (colorSources != null) {
        final colors = _getLandColors(land);
        for (final color in colors) {
          colorSources[color] = (colorSources[color] ?? 0) + 1;
        }
      }
      return landsPlayed + 1;
    }
    return landsPlayed;
  }

  /// Calcula CMC médio (excluindo terrenos)
  double _calculateAvgCmc() {
    final nonLands = cards.where((c) => !_isLand(c)).toList();
    if (nonLands.isEmpty) return 0;

    var totalCmc = 0;
    var totalCards = 0;

    for (final card in nonLands) {
      final qty = (card['quantity'] as int?) ?? 1;
      totalCmc += _getCmc(card) * qty;
      totalCards += qty;
    }

    return totalCards > 0 ? totalCmc / totalCards : 0;
  }

  /// Conta total de terrenos no deck
  int _countLands() {
    var count = 0;
    for (final card in cards) {
      if (_isLand(card)) {
        count += (card['quantity'] as int?) ?? 1;
      }
    }
    return count;
  }

  /// Gera distribuição de CMC
  Map<int, int> _getCmcDistribution() {
    final dist = <int, int>{};
    for (final card in cards) {
      if (_isLand(card)) continue;
      final cmc = _getCmc(card).clamp(0, 10); // 10+ agrupa em 10
      final qty = (card['quantity'] as int?) ?? 1;
      dist[cmc] = (dist[cmc] ?? 0) + qty;
    }
    return dist;
  }
}

/// Analisador de matchup entre dois decks
class MatchupAnalyzer {
  /// Analisa matchup usando heurísticas
  static MatchupResult analyze(
    List<Map<String, dynamic>> deckA,
    List<Map<String, dynamic>> deckB,
  ) {
    final statsA = _DeckStats.from(deckA);
    final statsB = _DeckStats.from(deckB);

    var winRateA = 0.5;
    final notes = <String>[];

    // Velocidade (CMC mais baixo = mais rápido)
    if (statsA.avgCmc < statsB.avgCmc - 0.5) {
      winRateA += 0.05;
      notes.add('Deck A é mais rápido (CMC médio menor).');
    } else if (statsA.avgCmc > statsB.avgCmc + 0.5) {
      winRateA -= 0.05;
      notes.add('Deck B é mais rápido (CMC médio menor).');
    }

    // Removal vs Creatures
    if (statsA.removalCount > statsB.removalCount &&
        statsB.creatureCount > 25) {
      winRateA += 0.08;
      notes.add('Deck A tem mais remoções contra deck creature-heavy.');
    }
    if (statsB.removalCount > statsA.removalCount &&
        statsA.creatureCount > 25) {
      winRateA -= 0.08;
      notes.add('Deck B tem mais remoções contra deck creature-heavy.');
    }

    // Board wipes vs Go-wide
    if (statsA.boardWipeCount > statsB.boardWipeCount &&
        statsB.creatureCount > 30) {
      winRateA += 0.10;
      notes.add('Deck A tem board wipes contra estratégia go-wide.');
    }
    if (statsB.boardWipeCount > statsA.boardWipeCount &&
        statsA.creatureCount > 30) {
      winRateA -= 0.10;
      notes.add('Deck B tem board wipes contra estratégia go-wide.');
    }

    // Card draw (vantagem em jogos longos)
    if (statsA.cardDrawCount > statsB.cardDrawCount + 5) {
      winRateA += 0.05;
      notes.add('Deck A tem vantagem em jogos longos (mais card draw).');
    }
    if (statsB.cardDrawCount > statsA.cardDrawCount + 5) {
      winRateA -= 0.05;
      notes.add('Deck B tem vantagem em jogos longos (mais card draw).');
    }

    // Ramp
    if (statsA.rampCount > statsB.rampCount + 3) {
      winRateA += 0.04;
      notes.add('Deck A acelera mais rápido (mais ramp).');
    }

    if (notes.isEmpty) {
      notes.add('Matchup equilibrado. Resultado depende mais do draw.');
    }

    return MatchupResult(
      winRateA: winRateA.clamp(0.20, 0.80),
      winRateB: (1 - winRateA).clamp(0.20, 0.80),
      notes: notes,
      statsA: statsA.toJson(),
      statsB: statsB.toJson(),
    );
  }
}

class _DeckStats {
  final double avgCmc;
  final int creatureCount;
  final int removalCount;
  final int boardWipeCount;
  final int cardDrawCount;
  final int rampCount;
  final int landCount;

  _DeckStats({
    required this.avgCmc,
    required this.creatureCount,
    required this.removalCount,
    required this.boardWipeCount,
    required this.cardDrawCount,
    required this.rampCount,
    required this.landCount,
  });

  factory _DeckStats.from(List<Map<String, dynamic>> cards) {
    var totalCmc = 0;
    var nonLandCount = 0;
    var creatures = 0;
    var removal = 0;
    var wipes = 0;
    var draw = 0;
    var ramp = 0;
    var lands = 0;

    // Keywords para detecção
    const removalKeywords = ['destroy', 'exile', 'sacrifice', '-x/-x', 'damage'];
    const wipeKeywords = ['destroy all', 'exile all', 'all creatures'];
    const drawKeywords = ['draw', 'scry', 'look at'];
    const rampKeywords = ['add {', 'search your library for a', 'mana'];

    for (final card in cards) {
      final qty = (card['quantity'] as int?) ?? 1;
      final typeLine = (card['type_line'] ?? '').toString().toLowerCase();
      final oracleText = (card['oracle_text'] ?? '').toString().toLowerCase();
      final cmc = _getCmc(card);

      if (typeLine.contains('land')) {
        lands += qty;
        continue;
      }

      totalCmc += cmc * qty;
      nonLandCount += qty;

      if (typeLine.contains('creature')) creatures += qty;

      // Detecta removal
      if (removalKeywords.any((k) => oracleText.contains(k))) {
        removal += qty;
      }

      // Detecta board wipes
      if (wipeKeywords.any((k) => oracleText.contains(k))) {
        wipes += qty;
      }

      // Detecta card draw
      if (drawKeywords.any((k) => oracleText.contains(k))) {
        draw += qty;
      }

      // Detecta ramp
      if (rampKeywords.any((k) => oracleText.contains(k)) ||
          typeLine.contains('mana dork')) {
        ramp += qty;
      }
    }

    return _DeckStats(
      avgCmc: nonLandCount > 0 ? totalCmc / nonLandCount : 0,
      creatureCount: creatures,
      removalCount: removal,
      boardWipeCount: wipes,
      cardDrawCount: draw,
      rampCount: ramp,
      landCount: lands,
    );
  }

  static int _getCmc(Map<String, dynamic> card) {
    final cmc = card['cmc'];
    if (cmc == null) return 0;
    if (cmc is int) return cmc;
    if (cmc is double) return cmc.toInt();
    return int.tryParse(cmc.toString()) ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'avg_cmc': double.parse(avgCmc.toStringAsFixed(2)),
        'creature_count': creatureCount,
        'removal_count': removalCount,
        'board_wipe_count': boardWipeCount,
        'card_draw_count': cardDrawCount,
        'ramp_count': rampCount,
        'land_count': landCount,
      };
}

class MatchupResult {
  final double winRateA;
  final double winRateB;
  final List<String> notes;
  final Map<String, dynamic> statsA;
  final Map<String, dynamic> statsB;

  MatchupResult({
    required this.winRateA,
    required this.winRateB,
    required this.notes,
    required this.statsA,
    required this.statsB,
  });

  Map<String, dynamic> toJson() => {
        'win_rate_deck_a': double.parse(winRateA.toStringAsFixed(3)),
        'win_rate_deck_b': double.parse(winRateB.toStringAsFixed(3)),
        'deck_a_stats': statsA,
        'deck_b_stats': statsB,
        'notes': notes,
      };
}
