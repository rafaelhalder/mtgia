import 'package:flutter/material.dart';
import '../models/deck_details.dart';

/// Enum para representar o status de completude do deck
enum DeckStatus {
  incomplete, // Faltam cartas
  complete, // Número correto de cartas
  invalid, // Problema de validação (sem comandante, identidade, etc)
  unknown, // Formato sem limite definido
}

/// Widget que mostra o progresso e status do deck
class DeckProgressIndicator extends StatelessWidget {
  final DeckDetails deck;
  final int totalCards;
  final int? maxCards;
  final bool hasCommander;
  final VoidCallback? onTap;

  const DeckProgressIndicator({
    super.key,
    required this.deck,
    required this.totalCards,
    required this.maxCards,
    required this.hasCommander,
    this.onTap,
  });

  DeckStatus get status {
    final format = deck.format.toLowerCase();
    final isCommanderFormat = format == 'commander' || format == 'brawl';

    if (maxCards == null) return DeckStatus.unknown;

    // Valida se tem comandante em formatos que exigem
    if (isCommanderFormat && !hasCommander) {
      return DeckStatus.invalid;
    }

    if (totalCards < maxCards!) {
      return DeckStatus.incomplete;
    }

    if (totalCards == maxCards) {
      return DeckStatus.complete;
    }

    // Mais cartas que o permitido
    return DeckStatus.invalid;
  }

  Color _getStatusColor(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case DeckStatus.complete:
        return Colors.green;
      case DeckStatus.incomplete:
        return theme.colorScheme.primary;
      case DeckStatus.invalid:
        return theme.colorScheme.error;
      case DeckStatus.unknown:
        return theme.colorScheme.outline;
    }
  }

  IconData _getStatusIcon() {
    switch (status) {
      case DeckStatus.complete:
        return Icons.check_circle;
      case DeckStatus.incomplete:
        return Icons.pending;
      case DeckStatus.invalid:
        return Icons.error;
      case DeckStatus.unknown:
        return Icons.help_outline;
    }
  }

  String _getStatusText() {
    final format = deck.format.toLowerCase();
    final isCommanderFormat = format == 'commander' || format == 'brawl';

    switch (status) {
      case DeckStatus.complete:
        return 'Deck completo!';
      case DeckStatus.incomplete:
        final missing = maxCards! - totalCards;
        return 'Faltam $missing carta${missing > 1 ? 's' : ''}';
      case DeckStatus.invalid:
        if (isCommanderFormat && !hasCommander) {
          return 'Selecione um comandante';
        }
        if (totalCards > maxCards!) {
          final excess = totalCards - maxCards!;
          return 'Excede em $excess carta${excess > 1 ? 's' : ''}';
        }
        return 'Deck inválido';
      case DeckStatus.unknown:
        return '$totalCards cartas';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getStatusColor(context);
    final progress = maxCards != null ? (totalCards / maxCards!).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(_getStatusIcon(), color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    maxCards != null ? '$totalCards / $maxCards cartas' : '$totalCards cartas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (status == DeckStatus.complete)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Pronto',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (maxCards != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: color.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              _getStatusText(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget compacto para exibição em cards/listas
class DeckProgressChip extends StatelessWidget {
  final int totalCards;
  final int? maxCards;
  final bool hasCommander;
  final String format;

  const DeckProgressChip({
    super.key,
    required this.totalCards,
    required this.maxCards,
    required this.hasCommander,
    required this.format,
  });

  DeckStatus get status {
    final fmt = format.toLowerCase();
    final isCommanderFormat = fmt == 'commander' || fmt == 'brawl';

    if (maxCards == null) return DeckStatus.unknown;

    if (isCommanderFormat && !hasCommander) {
      return DeckStatus.invalid;
    }

    if (totalCards < maxCards!) {
      return DeckStatus.incomplete;
    }

    if (totalCards == maxCards) {
      return DeckStatus.complete;
    }

    return DeckStatus.invalid;
  }

  Color _getColor() {
    switch (status) {
      case DeckStatus.complete:
        return Colors.green;
      case DeckStatus.incomplete:
        return Colors.blue;
      case DeckStatus.invalid:
        return Colors.red;
      case DeckStatus.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        maxCards != null ? '$totalCards/$maxCards' : '$totalCards',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
