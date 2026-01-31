import 'package:flutter/material.dart';
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header (Nome + Formato)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deck.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    color: theme.colorScheme.error,
                  ),
                ],
              ),

              // Descrição
              if (deck.description != null && deck.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  deck.description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF94A3B8),
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
                    hasCommander: true, // Não temos essa info na listagem, assumimos true
                    format: deck.format,
                  ),
                  const SizedBox(width: 12),
                  if (deck.synergyScore != null)
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

  Color _getSynergyColor(int score) {
    if (score >= 80) return const Color(0xFF10B981); // Verde
    if (score >= 60) return const Color(0xFFF59E0B); // Amarelo
    return const Color(0xFFEF4444); // Vermelho
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
        borderRadius: BorderRadius.circular(4),
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

  const _StatChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = color ?? const Color(0xFF94A3B8);

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
