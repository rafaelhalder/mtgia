import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Contador de vida para partidas de Magic: The Gathering.
///
/// Suporta 2, 3 ou 4 jogadores, com controles rápidos de +/- vida,
/// reset, e histórico básico. Essencial para jogadores reais em partidas.
class LifeCounterScreen extends StatefulWidget {
  const LifeCounterScreen({super.key});

  @override
  State<LifeCounterScreen> createState() => _LifeCounterScreenState();
}

class _LifeCounterScreenState extends State<LifeCounterScreen> {
  int _playerCount = 2;
  late List<int> _lives;
  late List<int> _startingLives;
  int _startingLife = 20;

  // Colors for each player position
  static const _playerColors = [
    AppTheme.manaViolet,
    AppTheme.loomCyan,
    AppTheme.mythicGold,
    Color(0xFFEF4444), // red
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
    _initLives();
  }

  void _initLives() {
    _lives = List.generate(_playerCount, (_) => _startingLife);
    _startingLives = List.generate(_playerCount, (_) => _startingLife);
  }

  void _reset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _lives = List.generate(_playerCount, (i) => _startingLives[i]);
    });
  }

  void _changeLife(int playerIndex, int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _lives[playerIndex] += delta;
    });
  }

  void _setPlayerCount(int count) {
    setState(() {
      _playerCount = count;
      _initLives();
    });
  }

  void _setStartingLife(int life) {
    setState(() {
      _startingLife = life;
      _initLives();
    });
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceSlate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceSlate2,
        title: const Text('Contador de Vida'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
            tooltip: 'Configurações',
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            tooltip: 'Resetar',
            onPressed: _reset,
          ),
        ],
      ),
      body: _playerCount <= 2
          ? Column(
              children: List.generate(_playerCount, (i) {
                return Expanded(
                  child: _PlayerPanel(
                    label: _playerLabels[i],
                    life: _lives[i],
                    color: _playerColors[i],
                    onIncrement: () => _changeLife(i, 1),
                    onDecrement: () => _changeLife(i, -1),
                    isRotated: i == 0 && _playerCount == 2,
                  ),
                );
              }),
            )
          : Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _PlayerPanel(
                          label: _playerLabels[0],
                          life: _lives[0],
                          color: _playerColors[0],
                          onIncrement: () => _changeLife(0, 1),
                          onDecrement: () => _changeLife(0, -1),
                          compact: true,
                        ),
                      ),
                      Expanded(
                        child: _PlayerPanel(
                          label: _playerLabels[1],
                          life: _lives[1],
                          color: _playerColors[1],
                          onIncrement: () => _changeLife(1, 1),
                          onDecrement: () => _changeLife(1, -1),
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
                          color: _playerColors[2],
                          onIncrement: () => _changeLife(2, 1),
                          onDecrement: () => _changeLife(2, -1),
                          compact: true,
                        ),
                      ),
                      if (_playerCount >= 4)
                        Expanded(
                          child: _PlayerPanel(
                            label: _playerLabels[3],
                            life: _lives[3],
                            color: _playerColors[3],
                            onIncrement: () => _changeLife(3, 1),
                            onDecrement: () => _changeLife(3, -1),
                            compact: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Painel de um jogador individual com controles + / -
class _PlayerPanel extends StatelessWidget {
  final String label;
  final int life;
  final Color color;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool isRotated;
  final bool compact;

  const _PlayerPanel({
    required this.label,
    required this.life,
    required this.color,
    required this.onIncrement,
    required this.onDecrement,
    this.isRotated = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate2,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
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
                  size: compact ? 32 : 40,
                ),
              ),
            ),
          ),

          // Life total + label
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
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
                    fontSize: compact ? 48 : 72,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
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
                  size: compact ? 32 : 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (isRotated) {
      return RotatedBox(
        quarterTurns: 2,
        child: content,
      );
    }

    return content;
  }
}

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
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
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
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
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
