import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../models/deck.dart';

/// Widget Card para exibir um deck na listagem.
///
/// Layout:
/// ┌───────────────────────────────────────────┐
/// │ [img]  Nome do Deck                   [⋮] │
/// │        COMMANDER · 🔴⚪                    │
/// │        Descrição curta...                  │
/// │ ──────────────────── progress bar ──────── │
/// │ 87/100 cartas            Sinergia 72%     │
/// └───────────────────────────────────────────┘
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
      case 'commander':
        return AppTheme.formatCommander;
      case 'standard':
        return AppTheme.formatStandard;
      case 'modern':
        return AppTheme.formatModern;
      case 'pioneer':
        return AppTheme.formatPioneer;
      case 'legacy':
        return AppTheme.formatLegacy;
      case 'vintage':
        return AppTheme.formatVintage;
      case 'pauper':
        return AppTheme.formatPauper;
      default:
        return AppTheme.manaViolet;
    }
  }

  int? _getMaxCards(String format) {
    final fmt = format.toLowerCase();
    if (fmt == 'commander') return 100;
    if (fmt == 'brawl') return 60;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commanderImageUrl = deck.commanderImageUrl?.trim();
    final hasCommander =
        (deck.commanderName?.trim().isNotEmpty ?? false) ||
        (commanderImageUrl?.isNotEmpty ?? false);
    final accentColor = _formatAccentColor(deck.format);
    final maxCards = _getMaxCards(deck.format);
    final progress =
        maxCards != null ? (deck.cardCount / maxCards).clamp(0.0, 1.0) : null;
    final isComplete = maxCards != null && deck.cardCount == maxCards;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          splashColor: accentColor.withValues(alpha: 0.08),
          highlightColor: accentColor.withValues(alpha: 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 6, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Commander thumbnail ──
                    if (hasCommander) ...[
                      Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(
                            color: AppTheme.outlineMuted,
                            width: 0.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          child: CachedCardImage(
                            imageUrl: commanderImageUrl,
                            width: 48,
                            height: 67,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // ── Name + meta ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deck.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // Format chip + color identity + public icon
                          Row(
                            children: [
                              Flexible(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _FormatChip(
                                        format: deck.format,
                                        accentColor: accentColor,
                                      ),
                                      if (deck.colorIdentity.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        _ColorIdentityRow(
                                          colors: deck.colorIdentity,
                                        ),
                                      ],
                                      if (deck.isPublic) ...[
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.public,
                                          size: 14,
                                          color: AppTheme.textHint,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Menu button ──
                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: () => _showDeckMenu(context),
                      color: AppTheme.textHint,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Description ──
              if (deck.description != null &&
                  deck.description!.trim().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Text(
                    deck.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              // ── Progress bar (thin) ──
              if (progress != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor:
                          AppTheme.outlineMuted.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isComplete ? AppTheme.success : accentColor,
                      ),
                    ),
                  ),
                ),
              ],

              // ── Footer stats ──
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Row(
                  children: [
                    // Card count
                    Icon(
                      isComplete
                          ? Icons.check_circle_outline
                          : Icons.layers_outlined,
                      size: 14,
                      color: isComplete
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      maxCards != null
                          ? '${deck.cardCount}/$maxCards'
                          : '${deck.cardCount} cartas',
                      style: TextStyle(
                        fontSize: AppTheme.fontSm,
                        fontWeight: FontWeight.w600,
                        color: isComplete
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                      ),
                    ),

                    // Synergy score
                    if (deck.synergyScore != null &&
                        deck.synergyScore! > 0) ...[
                      const SizedBox(width: 16),
                      Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: AppTheme.scoreColor(deck.synergyScore!),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${deck.synergyScore}%',
                        style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.scoreColor(deck.synergyScore!),
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Time ago
                    Text(
                      _timeAgo(deck.createdAt),
                      style: TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}a';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}m';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min';
    return 'agora';
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline,
                  size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text('Excluir',
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') onDelete();
    });
  }
}

// ── Color Identity Row (WUBRG pips) ─────────────────────────────────────────

class _ColorIdentityRow extends StatelessWidget {
  final List<String> colors;
  const _ColorIdentityRow({required this.colors});

  static const _wubrgOrder = ['W', 'U', 'B', 'R', 'G'];

  @override
  Widget build(BuildContext context) {
    // Sort by WUBRG order
    final sorted = List<String>.from(colors)
      ..sort((a, b) {
        final ai = _wubrgOrder.indexOf(a);
        final bi = _wubrgOrder.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: sorted.map((c) {
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: SizedBox(
            width: 16,
            height: 16,
            child: SvgPicture.asset(
              'assets/symbols/$c.svg',
              placeholderBuilder: (_) => _FallbackPip(letter: c),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FallbackPip extends StatelessWidget {
  final String letter;
  const _FallbackPip({required this.letter});

  static const _colorMap = {
    'W': Color(0xFFF9FAF4),
    'U': Color(0xFF0E68AB),
    'B': Color(0xFF150B00),
    'R': Color(0xFFD3202A),
    'G': Color(0xFF00733E),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: _colorMap[letter] ?? AppTheme.textHint,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.outlineMuted,
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: letter == 'W' || letter == 'R'
              ? Colors.black87
              : Colors.white,
        ),
      ),
    );
  }
}

// ── Format Chip ──────────────────────────────────────────────────────────────

class _FormatChip extends StatelessWidget {
  final String format;
  final Color accentColor;

  const _FormatChip({required this.format, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        format.toUpperCase(),
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w700,
          fontSize: AppTheme.fontXs,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
