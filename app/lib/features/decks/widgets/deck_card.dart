import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../models/deck.dart';
import 'deck_progress_indicator.dart';

/// Widget Card para exibir um deck na listagem
class DeckCard extends StatelessWidget {
  final Deck deck;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const DeckCard({
    super.key,
    required this.deck,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commanderImageUrl = deck.commanderImageUrl?.trim();
    final hasCommander =
        (deck.commanderName?.trim().isNotEmpty ?? false) ||
        (commanderImageUrl?.isNotEmpty ?? false);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (Nome + Formato)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasCommander) ...[
                    CachedCardImage(
                      imageUrl: commanderImageUrl,
                      width: 44,
                      height: 62,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deck.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _FormatChip(format: deck.format),
                            const SizedBox(width: 8),
                            if (deck.isPublic)
                              Icon(
                                Icons.public,
                                size: 16,
                                color: theme.colorScheme.secondary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () => _showDeckMenu(context),
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),

              // Descrição
              if (deck.description != null && deck.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  deck.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Footer (Stats)
              Row(
                children: [
                  DeckProgressChip(
                    totalCards: deck.cardCount,
                    maxCards: _getMaxCards(deck.format),
                    hasCommander: hasCommander,
                    format: deck.format,
                  ),
                  const SizedBox(width: 12),
                  if (deck.synergyScore != null && deck.synergyScore! > 0)
                    _StatChip(
                      icon: Icons.auto_awesome,
                      label: 'Sinergia ${deck.synergyScore}%',
                      color: _getSynergyColor(deck.synergyScore!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeckMenu(BuildContext context) {
    final theme = Theme.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + renderBox.size.width - 48,
        offset.dy,
        offset.dx + renderBox.size.width,
        offset.dy + renderBox.size.height,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text('Excluir', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') onDelete();
    });
  }

  Color _getSynergyColor(int score) {
    return AppTheme.scoreColor(score);
  }

  int? _getMaxCards(String format) {
    final fmt = format.toLowerCase();
    if (fmt == 'commander') return 100;
    if (fmt == 'brawl') return 60;
    return null;
  }
}

class _FormatChip extends StatelessWidget {
  final String format;

  const _FormatChip({required this.format});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        format.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _StatChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = color ?? AppTheme.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: chipColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: chipColor),
        ),
      ],
    );
  }
}
