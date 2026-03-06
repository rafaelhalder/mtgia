import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mana_helper.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../../decks/models/deck_card_item.dart';

class CardDetailScreen extends StatelessWidget {
  final DeckCardItem card;

  /// Standard MTG card proportion: 63mm wide × 88mm tall → width/height.
  static const double _mtgCardAspectRatio = 63 / 88;
  static final RegExp _manaSymbolRegex = RegExp(r'\{([^\}]+)\}');

  const CardDetailScreen({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 0,
            pinned: true,
            backgroundColor: AppTheme.surfaceSlate2,
            title: Text(
              card.name,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardImage(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(theme),
                      const SizedBox(height: 20),
                      _buildDivider(),
                      const SizedBox(height: 16),
                      _buildOracleText(theme),
                      const SizedBox(height: 16),
                      _buildDivider(),
                      const SizedBox(height: 16),
                      _buildDetailsGrid(theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card image (tappable for fullscreen)
  // ---------------------------------------------------------------------------
  Widget _buildCardImage(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullscreenImage(context),
      child: AspectRatio(
        aspectRatio: _mtgCardAspectRatio,
        child: card.imageUrl != null && card.imageUrl!.isNotEmpty
            ? ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppTheme.radiusLg),
                  bottomRight: Radius.circular(AppTheme.radiusLg),
                ),
                child: CachedCardImage(
                  imageUrl: card.imageUrl,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSlate,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppTheme.radiusLg),
                    bottomRight: Radius.circular(AppTheme.radiusLg),
                  ),
                  border: Border.all(
                    color: AppTheme.outlineMuted.withValues(alpha: 0.5),
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.style, size: 48, color: AppTheme.textSecondary),
                      SizedBox(height: 8),
                      Text(
                        'Sem imagem',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: AppTheme.fontMd,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _showFullscreenImage(BuildContext context) {
    if (card.imageUrl == null || card.imageUrl!.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            child: CachedCardImage(
              imageUrl: card.imageUrl,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header: name + mana cost + type line
  // ---------------------------------------------------------------------------
  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                card.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (card.manaCost != null && card.manaCost!.isNotEmpty) ...[
              const SizedBox(width: 12),
              _buildManaCostWidget(card.manaCost!),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Type line
        Text(
          card.typeLine,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mana cost symbols
  // ---------------------------------------------------------------------------
  Widget _buildManaCostWidget(String manaCost) {
    final matches = _manaSymbolRegex.allMatches(manaCost);
    if (matches.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: matches.map((m) {
        final symbol = m.group(1)!.toUpperCase();
        final config = _manaSymbolConfig(symbol);
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: config.background,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: config.background.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            config.label,
            style: TextStyle(
              color: config.foreground,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        );
      }).toList(),
    );
  }

  _ManaSymbolStyle _manaSymbolConfig(String symbol) {
    switch (symbol) {
      case 'W':
        return _ManaSymbolStyle(
          const Color(0xFFF0F2C0),
          const Color(0xFF3D3000),
          'W',
        );
      case 'U':
        return _ManaSymbolStyle(
          const Color(0xFFB3CEEA),
          const Color(0xFF0A2340),
          'U',
        );
      case 'B':
        return _ManaSymbolStyle(
          const Color(0xFFA69F9D),
          const Color(0xFF1A1A1A),
          'B',
        );
      case 'R':
        return _ManaSymbolStyle(
          const Color(0xFFEB9F82),
          const Color(0xFF3D1005),
          'R',
        );
      case 'G':
        return _ManaSymbolStyle(
          const Color(0xFFC4D3CA),
          const Color(0xFF0C2E1A),
          'G',
        );
      case 'C':
        return _ManaSymbolStyle(
          const Color(0xFFB8C0CC),
          const Color(0xFF2A2A2A),
          'C',
        );
      case 'X':
        return _ManaSymbolStyle(
          const Color(0xFF94A3B8),
          Colors.white,
          'X',
        );
      default:
        // Numeric or other generic symbols
        return _ManaSymbolStyle(
          const Color(0xFF94A3B8),
          Colors.white,
          symbol,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Oracle text
  // ---------------------------------------------------------------------------
  Widget _buildOracleText(ThemeData theme) {
    final hasText = card.oracleText != null && card.oracleText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Texto de Regras',
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppTheme.loomCyan,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSlate2,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: AppTheme.outlineMuted.withValues(alpha: 0.4),
            ),
          ),
          child: hasText
              ? Text(
                  card.oracleText!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textPrimary,
                    height: 1.5,
                  ),
                )
              : Text(
                  'Sem texto de regras',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textHint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Details grid
  // ---------------------------------------------------------------------------
  Widget _buildDetailsGrid(ThemeData theme) {
    final cmc = ManaHelper.calculateCMC(card.manaCost);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detalhes',
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppTheme.loomCyan,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSlate2,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: AppTheme.outlineMuted.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              _detailRow(
                theme,
                icon: Icons.collections_bookmark,
                label: 'Set',
                value: card.setName ?? card.setCode,
              ),
              _detailDivider(),
              _detailRowWithWidget(
                theme,
                icon: Icons.auto_awesome,
                label: 'Raridade',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _rarityColor(card.rarity),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _capitalizeRarity(card.rarity),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _detailDivider(),
              _detailRowWithWidget(
                theme,
                icon: Icons.palette,
                label: 'Cores',
                child: _buildColorBadges(),
              ),
              _detailDivider(),
              _detailRow(
                theme,
                icon: Icons.speed,
                label: 'CMC',
                value: cmc.toString(),
              ),
              if (card.collectorNumber != null &&
                  card.collectorNumber!.isNotEmpty) ...[
                _detailDivider(),
                _detailRow(
                  theme,
                  icon: Icons.tag,
                  label: 'Número',
                  value: card.collectorNumber!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRowWithWidget(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }

  Widget _detailDivider() {
    return Divider(
      height: 1,
      color: AppTheme.outlineMuted.withValues(alpha: 0.3),
    );
  }

  // ---------------------------------------------------------------------------
  // Color identity badges
  // ---------------------------------------------------------------------------
  Widget _buildColorBadges() {
    // Prefer colorIdentity (full commander identity) over colors (cast colors),
    // falling back to colors when identity data is absent.
    final identityColors =
        card.colorIdentity.isNotEmpty ? card.colorIdentity : card.colors;

    if (identityColors.isEmpty) {
      return _colorCircle('C', const Color(0xFFB8C0CC), const Color(0xFF2A2A2A));
    }

    return Wrap(
      spacing: 4,
      children: identityColors.map((c) {
        final upper = c.toUpperCase();
        final config = _manaSymbolConfig(upper);
        return _colorCircle(upper, config.background, config.foreground);
      }).toList(),
    );
  }

  Widget _colorCircle(String label, Color bg, Color fg) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Divider helper
  // ---------------------------------------------------------------------------
  Widget _buildDivider() {
    return Divider(
      color: AppTheme.outlineMuted.withValues(alpha: 0.4),
      height: 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Rarity helpers
  // ---------------------------------------------------------------------------
  Color _rarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'common':
        return Colors.grey;
      case 'uncommon':
        return const Color(0xFFC0C0C0);
      case 'rare':
        return const Color(0xFFFFD700);
      case 'mythic':
        return AppTheme.mythicGold;
      default:
        return Colors.grey;
    }
  }

  String _capitalizeRarity(String rarity) {
    if (rarity.isEmpty) return rarity;
    return rarity[0].toUpperCase() + rarity.substring(1);
  }
}

// ---------------------------------------------------------------------------
// Internal helper class for mana symbol styling
// ---------------------------------------------------------------------------
class _ManaSymbolStyle {
  final Color background;
  final Color foreground;
  final String label;

  const _ManaSymbolStyle(this.background, this.foreground, this.label);
}
