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

  // Cor de destaque baseada no formato do deck
  Color _formatAccentColor(String format) {
    switch (format.toLowerCase()) {
      case 'commander': return AppTheme.mythicGold;
      case 'standard': return AppTheme.loomCyan;
      case 'modern': return AppTheme.manaViolet;
      case 'pioneer': return const Color(0xFF34D399); // verde esmeralda
      case 'legacy': return const Color(0xFFEC4899);  // rosa
      case 'vintage': return const Color(0xFFF97316); // laranja
      case 'pauper': return AppTheme.textSecondary;
      default: return AppTheme.manaViolet;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commanderImageUrl = deck.commanderImageUrl?.trim();
    final hasCommander =
        (deck.commanderName?.trim().isNotEmpty ?? false) ||
        (commanderImageUrl?.isNotEmpty ?? false);
    final accentColor = _formatAccentColor(deck.format);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
          top: BorderSide(color: AppTheme.outlineMuted, width: 0.5),
          right: BorderSide(color: AppTheme.outlineMuted, width: 0.5),
          bottom: BorderSide(color: AppTheme.outlineMuted, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(-2, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: accentColor.withValues(alpha: 0.1),
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
                                _FormatChip(format: deck.format, accentColor: accentColor),
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
                        color: AppTheme.textHint,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),

                  // Descrição
                  if (deck.description != null && deck.description!.isNotEmpty) ...[
                    const SizedBox(height: 10),
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
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 10),

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
  final Color accentColor;

  const _FormatChip({required this.format, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        format.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: accentColor,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
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
        Icon(icon, size: 14, color: chipColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: chipColor),
        ),
      ],
    );
  }
}
