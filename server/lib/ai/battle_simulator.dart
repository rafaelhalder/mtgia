import 'dart:math';

/// Simulador de batalha turno-a-turno simplificado.
///
/// Implementa regras básicas de MTG para simular partidas IA vs IA,
/// gerando game_logs detalhados para treinamento de ML.
///
/// Simplificações:
/// - Sem stack complexo (resolução imediata)
/// - Criaturas atacam se tiverem vantagem numérica
/// - Sem habilidades especiais (keywords como flying, trample simplificadas)
/// - Remoções são jogadas quando há alvo válido
/// - Card draw é prioritário nos primeiros turnos

// ═══════════════════════════════════════════════════════════════════════════
// MODELOS
// ═══════════════════════════════════════════════════════════════════════════

/// Representa uma carta no jogo.
class GameCard {
  final String id;
  final String name;
  final int cmc;
  final String typeLine;
  final String? oracleText;
  final List<String> colors;
  final int? power;
  final int? toughness;

  // Estado durante o jogo
  bool isTapped = false;
  int damage = 0;
  bool summoningSickness = true;
  bool hasAttacked = false;

  GameCard({
    required this.id,
    required this.name,
    required this.cmc,
    required this.typeLine,
    this.oracleText,
    required this.colors,
    this.power,
    this.toughness,
  });

  bool get isLand => typeLine.toLowerCase().contains('land');
  bool get isCreature => typeLine.toLowerCase().contains('creature');
  bool get isInstant => typeLine.toLowerCase().contains('instant');
  bool get isSorcery => typeLine.toLowerCase().contains('sorcery');
  bool get isEnchantment => typeLine.toLowerCase().contains('enchantment');
  bool get isArtifact => typeLine.toLowerCase().contains('artifact');
  bool get isPlaneswalker => typeLine.toLowerCase().contains('planeswalker');

  // Keywords simplificadas
  bool get hasFlying =>
      oracleText?.toLowerCase().contains('flying') ?? false;
  bool get hasHaste =>
      oracleText?.toLowerCase().contains('haste') ?? false;
  bool get hasVigilance =>
      oracleText?.toLowerCase().contains('vigilance') ?? false;
  bool get hasLifelink =>
      oracleText?.toLowerCase().contains('lifelink') ?? false;
  bool get hasDeathtouch =>
      oracleText?.toLowerCase().contains('deathtouch') ?? false;
  bool get hasTrample =>
      oracleText?.toLowerCase().contains('trample') ?? false;
  bool get hasFirstStrike =>
      oracleText?.toLowerCase().contains('first strike') ?? false;

  bool get isRemoval {
    final text = oracleText?.toLowerCase() ?? '';
    return text.contains('destroy target') ||
        text.contains('exile target') ||
        text.contains('deals') && text.contains('damage to target');
  }

  bool get isCardDraw {
    final text = oracleText?.toLowerCase() ?? '';
    return text.contains('draw a card') ||
        text.contains('draw two') ||
        text.contains('draw three');
  }

  bool get isRamp {
    final text = oracleText?.toLowerCase() ?? '';
    return text.contains('add {') ||
        text.contains('search your library for a') &&
            text.contains('land');
  }

  bool get isBoardWipe {
    final text = oracleText?.toLowerCase() ?? '';
    return text.contains('destroy all') || text.contains('exile all');
  }

  bool get canAttack => isCreature && !isTapped && !summoningSickness;

  int get effectiveToughness => (toughness ?? 0) - damage;

  void resetForNewTurn() {
    isTapped = false;
    hasAttacked = false;
    summoningSickness = false;
  }

  GameCard copy() => GameCard(
        id: id,
        name: name,
        cmc: cmc,
        typeLine: typeLine,
        oracleText: oracleText,
        colors: colors,
        power: power,
        toughness: toughness,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cmc': cmc,
        'type': typeLine,
        'power': power,
        'toughness': toughness,
      };

  @override
  String toString() =>
      isCreature ? '$name ($power/$toughness)' : name;
}

/// Estado de um jogador durante a partida.
class PlayerState {
  final String name;
  int life;
  int manaAvailable = 0;
  int landsPlayedThisTurn = 0;
  int poisonCounters = 0;

  final List<GameCard> library = [];
  final List<GameCard> hand = [];
  final List<GameCard> battlefield = [];
  final List<GameCard> graveyard = [];

  PlayerState(this.name, {this.life = 40}); // Commander default

  List<GameCard> get creatures =>
      battlefield.where((c) => c.isCreature).toList();

  List<GameCard> get lands => battlefield.where((c) => c.isLand).toList();

  List<GameCard> get untappedCreatures =>
      creatures.where((c) => !c.isTapped).toList();

  int get totalPower =>
      creatures.fold(0, (sum, c) => sum + (c.power ?? 0));

  void drawCard() {
    if (library.isNotEmpty) {
      hand.add(library.removeAt(0));
    }
  }

  void shuffle(Random random) {
    library.shuffle(random);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'life': life,
        'mana': manaAvailable,
        'hand_size': hand.length,
        'library_size': library.length,
        'creatures': creatures.map((c) => c.toJson()).toList(),
        'lands': lands.length,
        'graveyard_size': graveyard.length,
      };
}

/// Ação executada durante o jogo (para logging).
class GameAction {
  final int turn;
  final String player;
  final String phase;
  final String action;
  final Map<String, dynamic>? details;

  GameAction({
    required this.turn,
    required this.player,
    required this.phase,
    required this.action,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'turn': turn,
        'player': player,
        'phase': phase,
        'action': action,
        if (details != null) ...details!,
      };
}

/// Resultado da simulação.
class BattleResult {
  final String winner;
  final String loser;
  final int turns;
  final String winCondition;
  final List<GameAction> actions;
  final Map<String, dynamic> finalState;

  BattleResult({
    required this.winner,
    required this.loser,
    required this.turns,
    required this.winCondition,
    required this.actions,
    required this.finalState,
  });

  Map<String, dynamic> toJson() => {
        'winner': winner,
        'loser': loser,
        'turns': turns,
        'win_condition': winCondition,
        'action_count': actions.length,
        'final_state': finalState,
        'game_log': actions.map((a) => a.toJson()).toList(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// SIMULADOR
// ═══════════════════════════════════════════════════════════════════════════

/// Motor de simulação turno-a-turno.
class BattleSimulator {
  final List<Map<String, dynamic>> deckACards;
  final List<Map<String, dynamic>> deckBCards;
  final int maxTurns;
  final Random _random;

  late PlayerState playerA;
  late PlayerState playerB;
  final List<GameAction> _actions = [];
  int _currentTurn = 0;

  BattleSimulator({
    required this.deckACards,
    required this.deckBCards,
    this.maxTurns = 30,
    Random? random,
  }) : _random = random ?? Random();

  /// Executa a simulação e retorna o resultado.
  BattleResult simulate() {
    _initGame();

    while (_currentTurn < maxTurns) {
      _currentTurn++;

      // Turno do jogador A
      if (!_playTurn(playerA, playerB)) break;
      if (_checkGameOver() != null) break;

      // Turno do jogador B
      if (!_playTurn(playerB, playerA)) break;
      if (_checkGameOver() != null) break;
    }

    final winner = _determineWinner();
    return BattleResult(
      winner: winner.name,
      loser: winner == playerA ? playerB.name : playerA.name,
      turns: _currentTurn,
      winCondition: _getWinCondition(winner),
      actions: _actions,
      finalState: {
        'player_a': playerA.toJson(),
        'player_b': playerB.toJson(),
      },
    );
  }

  void _initGame() {
    playerA = PlayerState('Deck A');
    playerB = PlayerState('Deck B');

    // Monta bibliotecas
    playerA.library.addAll(_expandDeck(deckACards));
    playerB.library.addAll(_expandDeck(deckBCards));

    // Shuffle
    playerA.shuffle(_random);
    playerB.shuffle(_random);

    // Mãos iniciais (7 cartas)
    for (var i = 0; i < 7; i++) {
      playerA.drawCard();
      playerB.drawCard();
    }

    _log(playerA, 'setup', 'game_start',
        details: {'hand_size': 7, 'library_size': playerA.library.length});
    _log(playerB, 'setup', 'game_start',
        details: {'hand_size': 7, 'library_size': playerB.library.length});
  }

  List<GameCard> _expandDeck(List<Map<String, dynamic>> cards) {
    final expanded = <GameCard>[];
    for (final card in cards) {
      final qty = (card['quantity'] as int?) ?? 1;
      for (var i = 0; i < qty; i++) {
        expanded.add(_parseCard(card));
      }
    }
    return expanded;
  }

  GameCard _parseCard(Map<String, dynamic> card) {
    final typeLine = (card['type_line'] ?? '').toString();
    int? power, toughness;

    // Parse P/T para criaturas
    if (typeLine.toLowerCase().contains('creature')) {
      final pt = RegExp(r'(\d+)/(\d+)').firstMatch(
          card['power']?.toString() ?? card['toughness']?.toString() ?? '');
      if (pt != null) {
        power = int.tryParse(pt.group(1) ?? '');
        toughness = int.tryParse(pt.group(2) ?? '');
      }
      // Tenta campos separados
      power ??= _parseInt(card['power']);
      toughness ??= _parseInt(card['toughness']);
      // Default para criaturas sem P/T definido
      power ??= 2;
      toughness ??= 2;
    }

    return GameCard(
      id: (card['id'] ?? '').toString(),
      name: (card['name'] ?? 'Unknown').toString(),
      cmc: _parseInt(card['cmc']) ?? 0,
      typeLine: typeLine,
      oracleText: card['oracle_text']?.toString(),
      colors: (card['colors'] as List?)?.cast<String>() ?? [],
      power: power,
      toughness: toughness,
    );
  }

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Executa um turno completo para um jogador.
  bool _playTurn(PlayerState active, PlayerState opponent) {
    // Untap
    _untapPhase(active);

    // Upkeep (simplificado)
    _log(active, 'upkeep', 'phase_start');

    // Draw (exceto primeiro turno do primeiro jogador)
    if (!(_currentTurn == 1 && active == playerA)) {
      _drawPhase(active);
    }

    // Main phase 1
    _mainPhase(active, opponent, 1);

    // Combat
    _combatPhase(active, opponent);

    // Check game over
    if (opponent.life <= 0 || opponent.library.isEmpty) return false;

    // Main phase 2
    _mainPhase(active, opponent, 2);

    // End step
    _endPhase(active);

    return true;
  }

  void _untapPhase(PlayerState player) {
    for (final card in player.battlefield) {
      card.resetForNewTurn();
    }
    player.landsPlayedThisTurn = 0;
    player.manaAvailable = player.lands.length;

    _log(player, 'untap', 'untap_all',
        details: {'mana_available': player.manaAvailable});
  }

  void _drawPhase(PlayerState player) {
    if (player.library.isNotEmpty) {
      final drawn = player.library.first;
      player.drawCard();
      _log(player, 'draw', 'draw_card', details: {'card': drawn.name});
    } else {
      _log(player, 'draw', 'deck_empty');
    }
  }

  void _mainPhase(PlayerState active, PlayerState opponent, int phase) {
    _log(active, 'main$phase', 'phase_start');

    // IA: decide o que jogar
    final decisions = _aiDecideMain(active, opponent);

    for (final decision in decisions) {
      _executeDecision(active, opponent, decision);
    }
  }

  void _combatPhase(PlayerState active, PlayerState opponent) {
    final attackers = _aiDecideAttackers(active, opponent);
    if (attackers.isEmpty) {
      _log(active, 'combat', 'no_attack');
      return;
    }

    _log(active, 'combat', 'declare_attackers',
        details: {'attackers': attackers.map((c) => c.name).toList()});

    // Marca atacantes como tapped (exceto vigilance)
    for (final attacker in attackers) {
      if (!attacker.hasVigilance) {
        attacker.isTapped = true;
      }
      attacker.hasAttacked = true;
    }

    // IA: bloqueadores
    final blocks = _aiDecideBlockers(opponent, attackers);

    _log(opponent, 'combat', 'declare_blockers',
        details: {
          'blocks': blocks.entries
              .map((e) => {'attacker': e.key.name, 'blocker': e.value.name})
              .toList()
        });

    // Resolve combate
    _resolveCombat(active, opponent, attackers, blocks);
  }

  void _resolveCombat(
    PlayerState active,
    PlayerState opponent,
    List<GameCard> attackers,
    Map<GameCard, GameCard> blocks,
  ) {
    var damageToOpponent = 0;
    var lifeGained = 0;

    for (final attacker in attackers) {
      final blocker = blocks[attacker];

      if (blocker == null) {
        // Dano direto
        damageToOpponent += attacker.power ?? 0;
        if (attacker.hasLifelink) {
          lifeGained += attacker.power ?? 0;
        }
      } else {
        // Combate
        final attackerPower = attacker.power ?? 0;
        final attackerToughness = attacker.toughness ?? 0;
        final blockerPower = blocker.power ?? 0;
        final blockerToughness = blocker.toughness ?? 0;

        // First strike simplificado
        if (attacker.hasFirstStrike && !blocker.hasFirstStrike) {
          blocker.damage += attackerPower;
          if (blocker.effectiveToughness <= 0 || attacker.hasDeathtouch) {
            _destroyCreature(opponent, blocker);
          } else {
            attacker.damage += blockerPower;
            if (attacker.effectiveToughness <= 0 || blocker.hasDeathtouch) {
              _destroyCreature(active, attacker);
            }
          }
        } else {
          // Dano simultâneo
          blocker.damage += attackerPower;
          attacker.damage += blockerPower;

          if (blocker.effectiveToughness <= 0 || attacker.hasDeathtouch) {
            _destroyCreature(opponent, blocker);
          }
          if (attacker.effectiveToughness <= 0 || blocker.hasDeathtouch) {
            _destroyCreature(active, attacker);
          }

          // Trample
          if (attacker.hasTrample && attackerPower > blockerToughness) {
            damageToOpponent += attackerPower - blockerToughness;
          }
        }

        if (attacker.hasLifelink) {
          lifeGained += attackerPower;
        }
      }
    }

    if (damageToOpponent > 0) {
      opponent.life -= damageToOpponent;
      _log(active, 'combat', 'deal_damage',
          details: {'damage': damageToOpponent, 'opponent_life': opponent.life});
    }

    if (lifeGained > 0) {
      active.life += lifeGained;
      _log(active, 'combat', 'gain_life',
          details: {'life_gained': lifeGained, 'life': active.life});
    }
  }

  void _destroyCreature(PlayerState owner, GameCard creature) {
    owner.battlefield.remove(creature);
    owner.graveyard.add(creature);
    _log(owner, 'combat', 'creature_dies', details: {'creature': creature.name});
  }

  void _endPhase(PlayerState player) {
    // Discard to hand size (7)
    while (player.hand.length > 7) {
      final discarded = _aiChooseDiscard(player);
      player.hand.remove(discarded);
      player.graveyard.add(discarded);
      _log(player, 'end', 'discard', details: {'card': discarded.name});
    }

    // Limpa dano de criaturas
    for (final creature in player.creatures) {
      creature.damage = 0;
    }

    _log(player, 'end', 'phase_end');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IA DECISIONS
  // ═══════════════════════════════════════════════════════════════════════════

  List<_PlayDecision> _aiDecideMain(PlayerState active, PlayerState opponent) {
    final decisions = <_PlayDecision>[];

    // 1. Jogar terreno (sempre se possível)
    if (active.landsPlayedThisTurn < 1) {
      final land = active.hand.where((c) => c.isLand).firstOrNull;
      if (land != null) {
        decisions.add(_PlayDecision(card: land, type: 'play_land'));
      }
    }

    // 2. Prioriza ramp nos primeiros turnos
    if (_currentTurn <= 4) {
      for (final card in active.hand) {
        if (card.isRamp && card.cmc <= active.manaAvailable) {
          decisions.add(_PlayDecision(card: card, type: 'play_ramp'));
          break;
        }
      }
    }

    // 3. Card draw se mão pequena
    if (active.hand.length <= 3) {
      for (final card in active.hand) {
        if (card.isCardDraw && card.cmc <= active.manaAvailable) {
          decisions.add(_PlayDecision(card: card, type: 'play_draw'));
          break;
        }
      }
    }

    // 4. Remoção se oponente tem ameaça
    final threats = opponent.creatures.where((c) => (c.power ?? 0) >= 4).toList();
    if (threats.isNotEmpty) {
      for (final card in active.hand) {
        if (card.isRemoval && card.cmc <= active.manaAvailable) {
          decisions.add(_PlayDecision(
            card: card,
            type: 'play_removal',
            target: threats.first,
          ));
          break;
        }
      }
    }

    // 5. Board wipe se oponente tem muitas criaturas
    if (opponent.creatures.length >= 3 &&
        opponent.creatures.length > active.creatures.length + 1) {
      for (final card in active.hand) {
        if (card.isBoardWipe && card.cmc <= active.manaAvailable) {
          decisions.add(_PlayDecision(card: card, type: 'play_wipe'));
          break;
        }
      }
    }

    // 6. Criaturas (curva de mana)
    final playableCreatures = active.hand
        .where((c) => c.isCreature && c.cmc <= active.manaAvailable)
        .toList()
      ..sort((a, b) => b.cmc.compareTo(a.cmc)); // Maiores primeiro

    for (final creature in playableCreatures) {
      if (creature.cmc <= active.manaAvailable) {
        decisions.add(_PlayDecision(card: creature, type: 'play_creature'));
        break; // Uma criatura por main phase (simplificado)
      }
    }

    return decisions;
  }

  void _executeDecision(
    PlayerState active,
    PlayerState opponent,
    _PlayDecision decision,
  ) {
    final card = decision.card;

    switch (decision.type) {
      case 'play_land':
        active.hand.remove(card);
        active.battlefield.add(card);
        active.landsPlayedThisTurn++;
        active.manaAvailable++;
        _log(active, 'main', 'play_land', details: {'card': card.name});

      case 'play_creature':
        if (card.cmc <= active.manaAvailable) {
          active.hand.remove(card);
          active.battlefield.add(card);
          active.manaAvailable -= card.cmc;
          if (!card.hasHaste) {
            card.summoningSickness = true;
          }
          _log(active, 'main', 'play_creature',
              details: {'card': card.name, 'cmc': card.cmc});
        }

      case 'play_removal':
        if (card.cmc <= active.manaAvailable && decision.target != null) {
          active.hand.remove(card);
          active.graveyard.add(card);
          active.manaAvailable -= card.cmc;

          final target = decision.target!;
          opponent.battlefield.remove(target);
          opponent.graveyard.add(target);
          _log(active, 'main', 'cast_removal',
              details: {'card': card.name, 'target': target.name});
        }

      case 'play_wipe':
        if (card.cmc <= active.manaAvailable) {
          active.hand.remove(card);
          active.graveyard.add(card);
          active.manaAvailable -= card.cmc;

          // Destrói todas as criaturas
          final destroyedA = active.creatures.toList();
          final destroyedB = opponent.creatures.toList();

          active.battlefield.removeWhere((c) => c.isCreature);
          opponent.battlefield.removeWhere((c) => c.isCreature);
          active.graveyard.addAll(destroyedA);
          opponent.graveyard.addAll(destroyedB);

          _log(active, 'main', 'cast_wipe',
              details: {
                'card': card.name,
                'destroyed_own': destroyedA.length,
                'destroyed_opponent': destroyedB.length,
              });
        }

      case 'play_ramp':
      case 'play_draw':
        if (card.cmc <= active.manaAvailable) {
          active.hand.remove(card);
          if (card.isInstant || card.isSorcery) {
            active.graveyard.add(card);
          } else {
            active.battlefield.add(card);
          }
          active.manaAvailable -= card.cmc;

          // Efeito simplificado
          if (card.isCardDraw) {
            active.drawCard();
            if (card.oracleText?.contains('two') ?? false) {
              active.drawCard();
            }
          }
          if (card.isRamp) {
            // Busca terreno básico
            final basicLand = active.library
                .where((c) => c.isLand && c.typeLine.contains('Basic'))
                .firstOrNull;
            if (basicLand != null) {
              active.library.remove(basicLand);
              active.battlefield.add(basicLand);
            }
          }

          _log(active, 'main', 'cast_spell',
              details: {'card': card.name, 'type': decision.type});
        }
    }
  }

  List<GameCard> _aiDecideAttackers(PlayerState active, PlayerState opponent) {
    final potentialAttackers = active.creatures.where((c) => c.canAttack).toList();
    if (potentialAttackers.isEmpty) return [];

    final attackers = <GameCard>[];
    final totalAttackPower = potentialAttackers.fold(
        0, (sum, c) => sum + (c.power ?? 0));
    final opponentBlockers = opponent.untappedCreatures;
    final opponentBlockPower = opponentBlockers.fold(
        0, (sum, c) => sum + (c.power ?? 0));

    // Estratégia simplificada:
    // - Ataca com tudo se tem vantagem significativa
    // - Ataca com flyers se oponente não tem bloqueadores voadores
    // - Ataca com criaturas grandes que passam

    if (totalAttackPower > opponentBlockPower + 5) {
      // Alpha strike
      return potentialAttackers;
    }

    for (final attacker in potentialAttackers) {
      // Flyers sem bloqueadores
      if (attacker.hasFlying) {
        final flyingBlockers =
            opponentBlockers.where((c) => c.hasFlying).length;
        if (flyingBlockers == 0) {
          attackers.add(attacker);
          continue;
        }
      }

      // Criaturas que matam qualquer bloqueador
      if (attacker.hasDeathtouch || (attacker.power ?? 0) >= 5) {
        attackers.add(attacker);
      }
    }

    return attackers;
  }

  Map<GameCard, GameCard> _aiDecideBlockers(
    PlayerState defender,
    List<GameCard> attackers,
  ) {
    final blocks = <GameCard, GameCard>{};
    final availableBlockers = defender.untappedCreatures.toList();

    // Ordena atacantes por ameaça (power)
    final sortedAttackers = attackers.toList()
      ..sort((a, b) => (b.power ?? 0).compareTo(a.power ?? 0));

    for (final attacker in sortedAttackers) {
      if (availableBlockers.isEmpty) break;

      // Flyers só podem ser bloqueados por flyers
      final validBlockers = attacker.hasFlying
          ? availableBlockers.where((b) => b.hasFlying).toList()
          : availableBlockers;

      if (validBlockers.isEmpty) continue;

      // Escolhe bloqueador que mata o atacante sem morrer (se possível)
      GameCard? bestBlocker;
      for (final blocker in validBlockers) {
        final blockerKillsAttacker =
            (blocker.power ?? 0) >= (attacker.toughness ?? 0) ||
                blocker.hasDeathtouch;
        final blockerSurvives =
            (attacker.power ?? 0) < (blocker.toughness ?? 0) &&
                !attacker.hasDeathtouch;

        if (blockerKillsAttacker && blockerSurvives) {
          bestBlocker = blocker;
          break;
        }
      }

      // Se não há bloqueador perfeito, bloqueia se o dano é muito alto
      if (bestBlocker == null && (attacker.power ?? 0) >= 4) {
        // Bloqueia com a menor criatura
        bestBlocker = validBlockers
            .reduce((a, b) => (a.power ?? 0) < (b.power ?? 0) ? a : b);
      }

      if (bestBlocker != null) {
        blocks[attacker] = bestBlocker;
        availableBlockers.remove(bestBlocker);
      }
    }

    return blocks;
  }

  GameCard _aiChooseDiscard(PlayerState player) {
    // Descarta terrenos extras ou cartas de custo alto que não pode jogar
    final lands = player.hand.where((c) => c.isLand).toList();
    if (lands.length > 2) return lands.last;

    final expensive = player.hand.where((c) => c.cmc > 6).toList();
    if (expensive.isNotEmpty) return expensive.first;

    return player.hand.last;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILS
  // ═══════════════════════════════════════════════════════════════════════════

  void _log(PlayerState player, String phase, String action,
      {Map<String, dynamic>? details}) {
    _actions.add(GameAction(
      turn: _currentTurn,
      player: player.name,
      phase: phase,
      action: action,
      details: details,
    ));
  }

  String? _checkGameOver() {
    if (playerA.life <= 0) return playerB.name;
    if (playerB.life <= 0) return playerA.name;
    if (playerA.library.isEmpty) return playerB.name;
    if (playerB.library.isEmpty) return playerA.name;
    return null;
  }

  PlayerState _determineWinner() {
    if (playerA.life <= 0 || playerA.library.isEmpty) return playerB;
    if (playerB.life <= 0 || playerB.library.isEmpty) return playerA;

    // Timeout: quem tem mais vida ganha
    if (playerA.life > playerB.life) return playerA;
    if (playerB.life > playerA.life) return playerB;

    // Empate: quem tem mais cartas no campo
    if (playerA.battlefield.length > playerB.battlefield.length) return playerA;
    return playerB;
  }

  String _getWinCondition(PlayerState winner) {
    final loser = winner == playerA ? playerB : playerA;
    if (loser.life <= 0) return 'life_depletion';
    if (loser.library.isEmpty) return 'deck_out';
    if (_currentTurn >= maxTurns) return 'timeout';
    return 'unknown';
  }
}

class _PlayDecision {
  final GameCard card;
  final String type;
  final GameCard? target;

  _PlayDecision({required this.card, required this.type, this.target});
}
