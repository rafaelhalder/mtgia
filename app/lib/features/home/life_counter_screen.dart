import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Snapshot of all player state for undo support.
class _GameSnapshot {
  final List<int> lives;
  final List<int> poison;
  final List<int> energy;
  final List<int> experience;
  final List<List<int>> commanderDamage;

  _GameSnapshot({
    required this.lives,
    required this.poison,
    required this.energy,
    required this.experience,
    required this.commanderDamage,
  });
}

/// Contador de vida completo para partidas de Magic: The Gathering.
///
/// Suporta 2, 3 ou 4 jogadores, com:
/// - Vida (life total)
/// - Veneno / Poison counters (10 = derrota)
/// - Dano de Comandante por oponente (21 = derrota)
/// - Energy e Experience counters
/// - Histórico com undo
class LifeCounterScreen extends StatefulWidget {
  const LifeCounterScreen({super.key});

  @override
  State<LifeCounterScreen> createState() => _LifeCounterScreenState();
}

class _LifeCounterScreenState extends State<LifeCounterScreen> {
  int _playerCount = 2;
  int _startingLife = 20;

  late List<int> _lives;
  late List<int> _poison;
  late List<int> _energy;
  late List<int> _experience;
  // _commanderDamage[target][source] = damage dealt by source's commander to target
  late List<List<int>> _commanderDamage;

  final List<_GameSnapshot> _history = [];
  static const int _maxHistory = 50;

  static const _playerColors = [
    AppTheme.manaViolet,
    AppTheme.primarySoft,
    AppTheme.mythicGold,
    Color(0xFFEF4444),
  ];

  static const _playerLabels = [
    'Jogador 1',
    'Jogador 2',
    'Jogador 3',
    'Jogador 4',
  ];

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  void _initAll() {
    _lives = List.generate(_playerCount, (_) => _startingLife);
    _poison = List.generate(_playerCount, (_) => 0);
    _energy = List.generate(_playerCount, (_) => 0);
    _experience = List.generate(_playerCount, (_) => 0);
    _commanderDamage = List.generate(
      _playerCount,
      (_) => List.generate(_playerCount, (_) => 0),
    );
    _history.clear();
  }

  void _saveSnapshot() {
    _history.add(_GameSnapshot(
      lives: List.of(_lives),
      poison: List.of(_poison),
      energy: List.of(_energy),
      experience: List.of(_experience),
      commanderDamage: _commanderDamage.map((row) => List.of(row)).toList(),
    ));
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;
    HapticFeedback.selectionClick();
    final snap = _history.removeLast();
    setState(() {
      _lives = snap.lives;
      _poison = snap.poison;
      _energy = snap.energy;
      _experience = snap.experience;
      _commanderDamage = snap.commanderDamage;
    });
  }

  void _reset() {
    HapticFeedback.mediumImpact();
    _saveSnapshot();
    setState(() {
      _initAll();
    });
  }

  void _changeLife(int player, int delta) {
    HapticFeedback.selectionClick();
    _saveSnapshot();
    setState(() {
      _lives[player] += delta;
    });
  }

  void _changePoison(int player, int delta) {
    HapticFeedback.selectionClick();
    _saveSnapshot();
    setState(() {
      _poison[player] = (_poison[player] + delta).clamp(0, 99);
    });
  }

  void _changeEnergy(int player, int delta) {
    HapticFeedback.selectionClick();
    _saveSnapshot();
    setState(() {
      _energy[player] = (_energy[player] + delta).clamp(0, 999);
    });
  }

  void _changeExperience(int player, int delta) {
    HapticFeedback.selectionClick();
    _saveSnapshot();
    setState(() {
      _experience[player] = (_experience[player] + delta).clamp(0, 999);
    });
  }

  void _changeCommanderDamage(int target, int source, int delta) {
    HapticFeedback.selectionClick();
    _saveSnapshot();
    setState(() {
      _commanderDamage[target][source] =
          (_commanderDamage[target][source] + delta).clamp(0, 99);
    });
  }

  void _setPlayerCount(int count) {
    setState(() {
      _playerCount = count;
      _initAll();
    });
  }

  void _setStartingLife(int life) {
    setState(() {
      _startingLife = life;
      _initAll();
    });
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceSlate,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (ctx) => _SettingsSheet(
        playerCount: _playerCount,
        startingLife: _startingLife,
        onPlayerCountChanged: (count) {
          _setPlayerCount(count);
          Navigator.pop(ctx);
        },
        onStartingLifeChanged: (life) {
          _setStartingLife(life);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showCountersSheet(int playerIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceSlate,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (ctx) => _CountersSheet(
        playerIndex: playerIndex,
        playerCount: _playerCount,
        playerColor: _playerColors[playerIndex],
        playerLabel: _playerLabels[playerIndex],
        initialPoison: _poison[playerIndex],
        initialEnergy: _energy[playerIndex],
        initialExperience: _experience[playerIndex],
        initialCommanderDamage: List.of(_commanderDamage[playerIndex]),
        playerColors: _playerColors,
        playerLabels: _playerLabels,
        onPoisonChanged: (delta) => _changePoison(playerIndex, delta),
        onEnergyChanged: (delta) => _changeEnergy(playerIndex, delta),
        onExperienceChanged: (delta) =>
            _changeExperience(playerIndex, delta),
        onCommanderDamageChanged: (source, delta) =>
            _changeCommanderDamage(playerIndex, source, delta),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('Contador de Vida'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.undo,
              color: _history.isNotEmpty
                  ? AppTheme.textPrimary
                  : AppTheme.textHint,
            ),
            tooltip: 'Desfazer',
            onPressed: _history.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
            tooltip: 'Configurações',
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            tooltip: 'Resetar tudo',
            onPressed: _reset,
          ),
        ],
      ),
      body: _playerCount <= 2 ? _buildTwoPlayers() : _buildGridPlayers(),
    );
  }

  Widget _buildTwoPlayers() {
    return Column(
      children: List.generate(_playerCount, (i) {
        return Expanded(
          child: _PlayerPanel(
            label: _playerLabels[i],
            life: _lives[i],
            poison: _poison[i],
            commanderDamageTotal: _totalCommanderDamage(i),
            color: _playerColors[i],
            onIncrement: () => _changeLife(i, 1),
            onDecrement: () => _changeLife(i, -1),
            onCountersTap: () => _showCountersSheet(i),
            isRotated: i == 0 && _playerCount == 2,
          ),
        );
      }),
    );
  }

  Widget _buildGridPlayers() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _PlayerPanel(
                  label: _playerLabels[0],
                  life: _lives[0],
                  poison: _poison[0],
                  commanderDamageTotal: _totalCommanderDamage(0),
                  color: _playerColors[0],
                  onIncrement: () => _changeLife(0, 1),
                  onDecrement: () => _changeLife(0, -1),
                  onCountersTap: () => _showCountersSheet(0),
                  compact: true,
                ),
              ),
              Expanded(
                child: _PlayerPanel(
                  label: _playerLabels[1],
                  life: _lives[1],
                  poison: _poison[1],
                  commanderDamageTotal: _totalCommanderDamage(1),
                  color: _playerColors[1],
                  onIncrement: () => _changeLife(1, 1),
                  onDecrement: () => _changeLife(1, -1),
                  onCountersTap: () => _showCountersSheet(1),
                  compact: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _PlayerPanel(
                  label: _playerLabels[2],
                  life: _lives[2],
                  poison: _poison[2],
                  commanderDamageTotal: _totalCommanderDamage(2),
                  color: _playerColors[2],
                  onIncrement: () => _changeLife(2, 1),
                  onDecrement: () => _changeLife(2, -1),
                  onCountersTap: () => _showCountersSheet(2),
                  compact: true,
                ),
              ),
              if (_playerCount >= 4)
                Expanded(
                  child: _PlayerPanel(
                    label: _playerLabels[3],
                    life: _lives[3],
                    poison: _poison[3],
                    commanderDamageTotal: _totalCommanderDamage(3),
                    color: _playerColors[3],
                    onIncrement: () => _changeLife(3, 1),
                    onDecrement: () => _changeLife(3, -1),
                    onCountersTap: () => _showCountersSheet(3),
                    compact: true,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  int _totalCommanderDamage(int player) {
    int total = 0;
    for (int i = 0; i < _playerCount; i++) {
      total += _commanderDamage[player][i];
    }
    return total;
  }
}

// ---------------------------------------------------------------------------
// Player Panel
// ---------------------------------------------------------------------------

/// Painel de um jogador individual com vida, indicadores de poison/commander,
/// e botão para abrir contadores extras.
class _PlayerPanel extends StatelessWidget {
  final String label;
  final int life;
  final int poison;
  final int commanderDamageTotal;
  final Color color;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onCountersTap;
  final bool isRotated;
  final bool compact;

  const _PlayerPanel({
    required this.label,
    required this.life,
    required this.poison,
    required this.commanderDamageTotal,
    required this.color,
    required this.onIncrement,
    required this.onDecrement,
    required this.onCountersTap,
    this.isRotated = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Stack(
        children: [
          // Main life controls
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // + button (top area)
              Expanded(
                child: InkWell(
                  onTap: onIncrement,
                  child: Center(
                    child: Icon(
                      Icons.add,
                      color: color.withValues(alpha: 0.6),
                      size: compact ? 28 : 40,
                    ),
                  ),
                ),
              ),

              // Life total + label
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: compact ? AppTheme.fontXs : AppTheme.fontSm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$life',
                      style: TextStyle(
                        color: life <= 0 ? AppTheme.error : color,
                        fontSize: compact ? 44 : 64,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    // Badges row: poison + commander damage
                    _buildBadgesRow(),
                  ],
                ),
              ),

              // - button (bottom area)
              Expanded(
                child: InkWell(
                  onTap: onDecrement,
                  child: Center(
                    child: Icon(
                      Icons.remove,
                      color: color.withValues(alpha: 0.6),
                      size: compact ? 28 : 40,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Counters button (bottom-right corner)
          Positioned(
            right: 4,
            bottom: 4,
            child: _CountersButton(
              onTap: onCountersTap,
              compact: compact,
            ),
          ),
        ],
      ),
    );

    if (isRotated) {
      return RotatedBox(quarterTurns: 2, child: content);
    }
    return content;
  }

  Widget _buildBadgesRow() {
    final badges = <Widget>[];

    if (poison > 0) {
      badges.add(_BadgeChip(
        icon: Icons.coronavirus,
        value: poison,
        color: const Color(0xFF10B981), // green for poison
        isLethal: poison >= 10,
        compact: compact,
      ));
    }

    if (commanderDamageTotal > 0) {
      badges.add(_BadgeChip(
        icon: Icons.shield,
        value: commanderDamageTotal,
        color: AppTheme.mythicGold,
        isLethal: commanderDamageTotal >= 21,
        compact: compact,
      ));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: badges
            .expand((w) => [w, const SizedBox(width: 6)])
            .toList()
          ..removeLast(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Badge Chip (poison/commander indicators on player panel)
// ---------------------------------------------------------------------------
class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  final bool isLethal;
  final bool compact;

  const _BadgeChip({
    required this.icon,
    required this.value,
    required this.color,
    required this.isLethal,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isLethal ? AppTheme.error : color.withValues(alpha: 0.2);
    final fgColor = isLethal ? Colors.white : color;
    final sz = compact ? 10.0 : 12.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: sz, color: fgColor),
          const SizedBox(width: 3),
          Text(
            '$value',
            style: TextStyle(
              color: fgColor,
              fontSize: sz,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Counters button (opens the counters bottom sheet)
// ---------------------------------------------------------------------------
class _CountersButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const _CountersButton({required this.onTap, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(compact ? 4 : 6),
          decoration: BoxDecoration(
            color: AppTheme.outlineMuted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(
            Icons.dashboard_customize,
            color: AppTheme.textSecondary,
            size: compact ? 16 : 20,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Counters Bottom Sheet (poison, commander damage, energy, experience)
// ---------------------------------------------------------------------------
class _CountersSheet extends StatefulWidget {
  final int playerIndex;
  final int playerCount;
  final Color playerColor;
  final String playerLabel;
  final int initialPoison;
  final int initialEnergy;
  final int initialExperience;
  final List<int> initialCommanderDamage;
  final List<Color> playerColors;
  final List<String> playerLabels;
  final ValueChanged<int> onPoisonChanged;
  final ValueChanged<int> onEnergyChanged;
  final ValueChanged<int> onExperienceChanged;
  final Function(int source, int delta) onCommanderDamageChanged;

  const _CountersSheet({
    required this.playerIndex,
    required this.playerCount,
    required this.playerColor,
    required this.playerLabel,
    required this.initialPoison,
    required this.initialEnergy,
    required this.initialExperience,
    required this.initialCommanderDamage,
    required this.playerColors,
    required this.playerLabels,
    required this.onPoisonChanged,
    required this.onEnergyChanged,
    required this.onExperienceChanged,
    required this.onCommanderDamageChanged,
  });

  @override
  State<_CountersSheet> createState() => _CountersSheetState();
}

class _CountersSheetState extends State<_CountersSheet> {
  late int _poison;
  late int _energy;
  late int _experience;
  late List<int> _cmdDamage;

  @override
  void initState() {
    super.initState();
    _poison = widget.initialPoison;
    _energy = widget.initialEnergy;
    _experience = widget.initialExperience;
    _cmdDamage = List.of(widget.initialCommanderDamage);
  }

  void _updatePoison(int delta) {
    setState(() {
      _poison = (_poison + delta).clamp(0, 99);
    });
    widget.onPoisonChanged(delta);
  }

  void _updateEnergy(int delta) {
    setState(() {
      _energy = (_energy + delta).clamp(0, 999);
    });
    widget.onEnergyChanged(delta);
  }

  void _updateExperience(int delta) {
    setState(() {
      _experience = (_experience + delta).clamp(0, 999);
    });
    widget.onExperienceChanged(delta);
  }

  void _updateCmdDamage(int source, int delta) {
    setState(() {
      _cmdDamage[source] = (_cmdDamage[source] + delta).clamp(0, 99);
    });
    widget.onCommanderDamageChanged(source, delta);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ListView(
          controller: scrollController,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.outlineMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Contadores — ${widget.playerLabel}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: widget.playerColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // ── Poison ──
            _CounterRow(
              icon: Icons.coronavirus,
              label: 'Veneno (Poison)',
              sublabel: _poison >= 10 ? '☠ LETAL (≥10)' : '10 = derrota',
              value: _poison,
              color: const Color(0xFF10B981),
              isLethal: _poison >= 10,
              onIncrement: () => _updatePoison(1),
              onDecrement: () => _updatePoison(-1),
            ),
            const SizedBox(height: 12),

            // ── Commander Damage ──
            Text(
              '⚔ Dano de Comandante',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.mythicGold,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '21 de uma mesma fonte = derrota',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textHint,
              ),
            ),
            const SizedBox(height: 8),
            ...List.generate(widget.playerCount, (sourceIdx) {
              if (sourceIdx == widget.playerIndex) {
                return const SizedBox.shrink();
              }
              final dmg = _cmdDamage[sourceIdx];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CounterRow(
                  icon: Icons.shield,
                  label: 'De ${widget.playerLabels[sourceIdx]}',
                  sublabel: dmg >= 21 ? '☠ LETAL (≥21)' : null,
                  value: dmg,
                  color: widget.playerColors[sourceIdx],
                  isLethal: dmg >= 21,
                  onIncrement: () => _updateCmdDamage(sourceIdx, 1),
                  onDecrement: () => _updateCmdDamage(sourceIdx, -1),
                ),
              );
            }),
            const SizedBox(height: 12),

            // ── Energy ──
            _CounterRow(
              icon: Icons.bolt,
              label: 'Energia (Energy)',
              value: _energy,
              color: AppTheme.mythicGold,
              onIncrement: () => _updateEnergy(1),
              onDecrement: () => _updateEnergy(-1),
            ),
            const SizedBox(height: 12),

            // ── Experience ──
            _CounterRow(
              icon: Icons.star,
              label: 'Experiência (Experience)',
              value: _experience,
              color: AppTheme.primarySoft,
              onIncrement: () => _updateExperience(1),
              onDecrement: () => _updateExperience(-1),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Counter Row (reusable +/- row for any counter type)
// ---------------------------------------------------------------------------
class _CounterRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final int value;
  final Color color;
  final bool isLethal;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _CounterRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onIncrement,
    required this.onDecrement,
    this.sublabel,
    this.isLethal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLethal
            ? AppTheme.error.withValues(alpha: 0.15)
            : AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: isLethal
              ? AppTheme.error.withValues(alpha: 0.5)
              : color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: isLethal ? AppTheme.error : color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sublabel != null)
                  Text(
                    sublabel!,
                    style: TextStyle(
                      color: isLethal ? AppTheme.error : AppTheme.textHint,
                      fontSize: AppTheme.fontXs,
                    ),
                  ),
              ],
            ),
          ),
          // Minus button
          _RoundButton(
            icon: Icons.remove,
            color: color,
            onTap: value > 0 ? onDecrement : null,
          ),
          // Value
          SizedBox(
            width: 40,
            child: Center(
              child: Text(
                '$value',
                style: TextStyle(
                  color: isLethal ? AppTheme.error : color,
                  fontSize: AppTheme.fontXl,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Plus button
          _RoundButton(
            icon: Icons.add,
            color: color,
            onTap: onIncrement,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Round + / - button for counter rows
// ---------------------------------------------------------------------------
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _RoundButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? color.withValues(alpha: 0.15)
                : AppTheme.outlineMuted.withValues(alpha: 0.3),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? color : AppTheme.textHint,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings Sheet
// ---------------------------------------------------------------------------

/// Bottom sheet para configurar número de jogadores e vida inicial.
class _SettingsSheet extends StatelessWidget {
  final int playerCount;
  final int startingLife;
  final ValueChanged<int> onPlayerCountChanged;
  final ValueChanged<int> onStartingLifeChanged;

  const _SettingsSheet({
    required this.playerCount,
    required this.startingLife,
    required this.onPlayerCountChanged,
    required this.onStartingLifeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configurações',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Player count
          Text(
            'Jogadores',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [2, 3, 4].map((count) {
              final isSelected = count == playerCount;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('$count'),
                    selected: isSelected,
                    onSelected: (_) => onPlayerCountChanged(count),
                    selectedColor: AppTheme.manaViolet,
                    labelStyle: TextStyle(
                      color:
                          isSelected ? Colors.white : AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Starting life
          Text(
            'Vida Inicial',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [20, 25, 30, 40].map((life) {
              final isSelected = life == startingLife;
              return ChoiceChip(
                label: Text('$life'),
                selected: isSelected,
                onSelected: (_) => onStartingLifeChanged(life),
                selectedColor: AppTheme.manaViolet,
                labelStyle: TextStyle(
                  color:
                      isSelected ? Colors.white : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            '20 = Standard/Modern • 25 = Brawl\n30 = Oathbreaker • 40 = Commander',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.textHint,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
