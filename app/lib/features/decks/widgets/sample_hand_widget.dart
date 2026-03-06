import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../models/deck_card_item.dart';
import '../models/deck_details.dart';

/// Simulador de mão inicial — permite ao jogador "testar" mãos de 7 cartas
/// aleatórias do deck, com opção de mulligan (nova mão com -1 carta).
///
/// Fundamental para qualquer jogador de MTG avaliar a consistência do deck.
class SampleHandWidget extends StatefulWidget {
  final DeckDetails deck;

  const SampleHandWidget({super.key, required this.deck});

  @override
  State<SampleHandWidget> createState() => _SampleHandWidgetState();
}

class _SampleHandWidgetState extends State<SampleHandWidget>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  List<DeckCardItem> _hand = [];
  int _handSize = 7;
  bool _isDrawn = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Constroi a lista expandida de cartas (respeitando quantity).
  List<DeckCardItem> _buildPool() {
    final pool = <DeckCardItem>[];
    for (final card in widget.deck.commander) {
      pool.add(card);
    }
    for (final cards in widget.deck.mainBoard.values) {
      for (final card in cards) {
        for (var i = 0; i < card.quantity; i++) {
          pool.add(card);
        }
      }
    }
    return pool;
  }

  void _drawHand(int size) {
    final pool = _buildPool();
    if (pool.isEmpty) return;

    pool.shuffle(_random);
    final drawSize = min(size, pool.length);
    setState(() {
      _hand = pool.take(drawSize).toList();
      _handSize = size;
      _isDrawn = true;
    });
    _animController.forward(from: 0);
  }

  void _mulligan() {
    final newSize = max(1, _handSize - 1);
    _drawHand(newSize);
  }

  void _newHand() {
    _drawHand(7);
  }

  int get _landCount => _hand.where(
        (c) => c.typeLine.toLowerCase().contains('land'),
      ).length;

  int get _nonLandCount => _hand.length - _landCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.outlineMuted.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.back_hand, color: AppTheme.mythicGold, size: 22),
              const SizedBox(width: 8),
              Text(
                'Testar Mão Inicial',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isDrawn)
                Text(
                  '$_handSize cartas',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (!_isDrawn) ...[
            // Draw button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _drawHand(7),
                icon: const Icon(Icons.casino, size: 20),
                label: const Text('Comprar 7 cartas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.manaViolet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Simula uma mão inicial aleatória do seu deck.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          if (_isDrawn) ...[
            // Stats bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceSlate2,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatChip(
                    label: 'Terrenos',
                    value: '$_landCount',
                    color: AppTheme.mythicGold,
                  ),
                  _StatChip(
                    label: 'Magias',
                    value: '$_nonLandCount',
                    color: AppTheme.loomCyan,
                  ),
                  _StatChip(
                    label: 'Total',
                    value: '${_hand.length}',
                    color: AppTheme.manaViolet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Hand display
            FadeTransition(
              opacity: _fadeAnim,
              child: SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _hand.length,
                  itemBuilder: (context, index) {
                    final card = _hand[index];
                    final isLand =
                        card.typeLine.toLowerCase().contains('land');
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index < _hand.length - 1 ? 8 : 0,
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                            child: CachedCardImage(
                              imageUrl: card.imageUrl,
                              width: 90,
                              height: 126,
                              fit: BoxFit.cover,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSm),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 90,
                            child: Text(
                              card.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isLand
                                    ? AppTheme.mythicGold
                                    : AppTheme.textPrimary,
                                fontSize: AppTheme.fontXs,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handSize > 1 ? _mulligan : null,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(
                      'Mulligan (${max(1, _handSize - 1)})',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.mythicGold,
                      side: BorderSide(
                        color: _handSize > 1
                            ? AppTheme.mythicGold.withValues(alpha: 0.5)
                            : AppTheme.outlineMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _newHand,
                    icon: const Icon(Icons.casino, size: 18),
                    label: const Text('Nova Mão'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.manaViolet,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: AppTheme.fontLg,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: AppTheme.fontXs,
          ),
        ),
      ],
    );
  }
}
