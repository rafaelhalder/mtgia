import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../decks/models/deck_card_item.dart';
import '../models/card_recognition_result.dart';

/// Preview do resultado do escaneamento — layout ManaBox-style.
///
/// Exibe a carta encontrada em tela cheia com:
/// - Imagem grande da carta
/// - Barra de info (nome + mana + tipo)
/// - Barra de ações (Foil, Condição, Set, Retry, +1)
class ScannedCardPreview extends StatefulWidget {
  final CardRecognitionResult result;
  final List<DeckCardItem> foundCards;
  final Function(DeckCardItem) onCardSelected;
  final Function(String) onAlternativeSelected;
  final VoidCallback onRetry;

  const ScannedCardPreview({
    super.key,
    required this.result,
    required this.foundCards,
    required this.onCardSelected,
    required this.onAlternativeSelected,
    required this.onRetry,
  });

  @override
  State<ScannedCardPreview> createState() => _ScannedCardPreviewState();
}

class _ScannedCardPreviewState extends State<ScannedCardPreview>
    with SingleTickerProviderStateMixin {
  late int _selectedIndex;
  bool _showEditions = false;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  DeckCardItem get _currentCard => widget.foundCards[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _selectedIndex = 0;
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.foundCards.isEmpty) return const SizedBox.shrink();

    final card = _currentCard;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        color: AppTheme.backgroundAbyss,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCardImage(card),
            _buildInfoBar(card),
            _buildActionBar(card, bottomPad),
            if (_showEditions) _buildEditionList(),
          ],
        ),
      ),
    );
  }

  // ── Imagem grande da carta ──
  Widget _buildCardImage(DeckCardItem card) {
    return GestureDetector(
      onTap: () => setState(() => _showEditions = !_showEditions),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 360),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
        child: card.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                child: CachedNetworkImage(
                  imageUrl: card.imageUrl!,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => _imagePlaceholder(),
                  errorWidget: (_, __, ___) => _imagePlaceholder(
                    icon: Icons.image_not_supported,
                  ),
                ),
              )
            : _imagePlaceholder(icon: Icons.style),
      ),
    );
  }

  Widget _imagePlaceholder({IconData icon = Icons.hourglass_empty}) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Center(
        child: icon == Icons.hourglass_empty
            ? const CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.loomCyan)
            : Icon(icon, size: 48, color: AppTheme.textSecondary),
      ),
    );
  }

  // ── Info bar: nome + mana + tipo ──
  Widget _buildInfoBar(DeckCardItem card) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.backgroundAbyss,
      child: Row(
        children: [
          _RarityDot(rarity: card.rarity),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        card.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTheme.fontLg,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ManaCostIcons(cost: card.manaCost),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  card.typeLine,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Confidence badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _confidenceColor(widget.result.confidence)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: _confidenceColor(widget.result.confidence)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              '${widget.result.confidence.toStringAsFixed(0)}%',
              style: TextStyle(
                color: _confidenceColor(widget.result.confidence),
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action bar (estilo ManaBox) ──
  Widget _buildActionBar(DeckCardItem card, double bottomPad) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8 + bottomPad),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSlate,
        border: Border(top: BorderSide(color: AppTheme.outlineMuted, width: 0.5)),
      ),
      child: Row(
        children: [
          // Foil
          if (card.foil == true) ...[
            _badge(Icons.auto_awesome, 'Foil',
                AppTheme.manaViolet.withValues(alpha: 0.7), AppTheme.manaViolet.withValues(alpha: 0.2)),
            const SizedBox(width: 8),
          ],
          // Condition
          _badge(
            Icons.shield_outlined,
            card.condition.code,
            _conditionColor(card.condition),
            _conditionColor(card.condition).withValues(alpha: 0.12),
          ),
          const SizedBox(width: 8),
          // Set code (tappable)
          GestureDetector(
            onTap: () {
              setState(() => _showEditions = !_showEditions);
              HapticFeedback.selectionClick();
            },
            child: _badge(
              Icons.layers_outlined,
              card.setCode.toUpperCase(),
              AppTheme.textSecondary,
              AppTheme.outlineMuted,
              chevron: widget.foundCards.length > 1,
            ),
          ),
          const Spacer(),
          // Retry
          _iconBtn(Icons.refresh_rounded, widget.onRetry),
          const SizedBox(width: 8),
          // +1 add
          _addButton(() {
            HapticFeedback.mediumImpact();
            widget.onCardSelected(_currentCard);
          }),
        ],
      ),
    );
  }

  // ── Edition list (expandable) ──
  Widget _buildEditionList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceSlate,
        border: Border(top: BorderSide(color: AppTheme.outlineMuted, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.layers, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${widget.foundCards.length} edições',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showEditions = false),
                  child: const Icon(Icons.keyboard_arrow_down,
                      size: 20, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount:
                  widget.foundCards.length > 10 ? 10 : widget.foundCards.length,
              itemBuilder: (context, index) {
                final ed = widget.foundCards[index];
                final sel = index == _selectedIndex;
                return _EditionTile(
                  card: ed,
                  isSelected: sel,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedIndex = index;
                      _showEditions = false;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  Color _confidenceColor(double c) {
    if (c >= 80) return AppTheme.success;
    if (c >= 60) return AppTheme.mythicGold;
    return AppTheme.error;
  }

  Color _conditionColor(CardCondition c) {
    switch (c) {
      case CardCondition.nm:
        return AppTheme.success;
      case CardCondition.lp:
        return AppTheme.loomCyan;
      case CardCondition.mp:
        return AppTheme.mythicGold;
      case CardCondition.hp:
        return AppTheme.warning;
      case CardCondition.dmg:
        return AppTheme.error;
    }
  }

  // Small reusable builders to avoid deep widget trees
  Widget _badge(IconData icon, String label, Color color, Color bg,
      {bool chevron = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: AppTheme.fontSm, fontWeight: FontWeight.w600)),
          if (chevron) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 14, color: color),
          ],
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppTheme.outlineMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _addButton(VoidCallback onTap) {
    return Material(
      color: AppTheme.manaViolet,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: Colors.white),
              SizedBox(width: 2),
              Text('+1',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: AppTheme.fontLg,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════

class _RarityDot extends StatelessWidget {
  final String rarity;
  const _RarityDot({required this.rarity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
    );
  }

  Color get _color {
    switch (rarity.toLowerCase()) {
      case 'mythic':
        return AppTheme.warning;
      case 'rare':
        return AppTheme.mythicGold;
      case 'uncommon':
        return AppTheme.textSecondary;
      default:
        return AppTheme.outlineMuted;
    }
  }
}

class _ManaCostIcons extends StatelessWidget {
  final String? cost;
  const _ManaCostIcons({this.cost});

  @override
  Widget build(BuildContext context) {
    if (cost == null || cost!.isEmpty) return const SizedBox.shrink();
    final symbols = RegExp(r'\{(.+?)\}').allMatches(cost!);
    if (symbols.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: symbols.map((m) {
        final s = m.group(1)!;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _manaColor(s),
          ),
          child: Center(
            child: Text(
              s,
              style: TextStyle(
                fontSize: AppTheme.fontXs,
                fontWeight: FontWeight.w700,
                color: s.toUpperCase() == 'B' ? Colors.white : Colors.black87,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _manaColor(String s) {
    switch (s.toUpperCase()) {
      case 'W': return AppTheme.manaW;
      case 'U': return AppTheme.manaU;
      case 'B': return AppTheme.manaB;
      case 'R': return AppTheme.manaR;
      case 'G': return AppTheme.manaG;
      case 'C': return AppTheme.manaC;
      default:  return AppTheme.disabled;
    }
  }
}

class _EditionTile extends StatelessWidget {
  final DeckCardItem card;
  final bool isSelected;
  final VoidCallback onTap;

  const _EditionTile({
    required this.card,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppTheme.manaViolet.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                child: SizedBox(
                  width: 28,
                  height: 40,
                  child: card.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: card.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AppTheme.surfaceSlate),
                          errorWidget: (_, __, ___) =>
                              Container(color: AppTheme.surfaceSlate),
                        )
                      : Container(color: AppTheme.surfaceSlate),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.setCode.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? AppTheme.manaViolet : Colors.white,
                        fontSize: AppTheme.fontMd,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (card.setName != null && card.setName!.isNotEmpty)
                      Text(
                        card.setName!,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: AppTheme.fontSm,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _RarityDot(rarity: card.rarity),
              const SizedBox(width: 8),
              if (isSelected)
                const Icon(Icons.check_circle,
                    size: 16, color: AppTheme.manaViolet),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget para quando não encontra a carta
class CardNotFoundWidget extends StatelessWidget {
  final String? detectedName;
  final String? errorMessage;
  final VoidCallback onRetry;
  final Function(String) onManualSearch;

  const CardNotFoundWidget({
    super.key,
    this.detectedName,
    this.errorMessage,
    required this.onRetry,
    required this.onManualSearch,
  });

  @override
  Widget build(BuildContext context) {
    final searchController = TextEditingController(text: detectedName);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border:
            Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            errorMessage ?? 'Carta não encontrada',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppTheme.fontLg,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (detectedName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Detectado: "$detectedName"',
              style: const TextStyle(color: Colors.white70, fontSize: AppTheme.fontSm),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Digite o nome correto',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () => onManualSearch(searchController.text),
              ),
            ),
            onSubmitted: onManualSearch,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tentar Novamente'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
