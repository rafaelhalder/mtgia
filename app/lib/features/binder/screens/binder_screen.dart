import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../providers/binder_provider.dart';
import '../widgets/binder_item_editor.dart';
import '../../cards/screens/card_search_screen.dart';

/// Tela "Meu Fichário" — coleção pessoal de cartas
class BinderScreen extends StatefulWidget {
  const BinderScreen({super.key});

  @override
  State<BinderScreen> createState() => _BinderScreenState();
}

class _BinderScreenState extends State<BinderScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String? _conditionFilter;
  bool? _tradeFilter;
  bool? _saleFilter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BinderProvider>();
      provider.fetchMyBinder(reset: true);
      provider.fetchStats();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<BinderProvider>();
      if (provider.hasMore && !provider.isLoading) {
        provider.fetchMyBinder();
      }
    }
  }

  void _applyFilters() {
    context.read<BinderProvider>().applyFilters(
          search: _searchController.text.trim(),
          condition: _conditionFilter,
          forTrade: _tradeFilter,
          forSale: _saleFilter,
        );
  }

  void _openAddCard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CardSearchScreen(
          deckId: '',
          mode: 'binder',
          onCardSelectedForBinder: (card) {
            if (!mounted) return;
            final provider = context.read<BinderProvider>();
            BinderItemEditor.show(
              context,
              cardId: card['id'] as String,
              cardName: card['name'] as String?,
              onSave: (data) async {
                return provider.addItem(
                  cardId: data['card_id'] as String,
                  quantity: data['quantity'] as int? ?? 1,
                  condition: data['condition'] as String? ?? 'NM',
                  isFoil: data['is_foil'] as bool? ?? false,
                  forTrade: data['for_trade'] as bool? ?? false,
                  forSale: data['for_sale'] as bool? ?? false,
                  price: data['price'] != null
                      ? (data['price'] as num).toDouble()
                      : null,
                  notes: data['notes'] as String?,
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _editItem(BinderItem item) {
    final provider = context.read<BinderProvider>();
    BinderItemEditor.show(
      context,
      item: item,
      onSave: (data) => provider.updateItem(item.id, data),
      onDelete: () => provider.removeItem(item.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Meu Fichário'),
        backgroundColor: AppTheme.surfaceSlate2,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.manaViolet),
            tooltip: 'Adicionar carta',
            onPressed: _openAddCard,
          ),
        ],
      ),
      body: Consumer<BinderProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // Stats bar
              if (provider.stats != null) _StatsBar(stats: provider.stats!),

              // Search + filters
              _SearchFilterBar(
                searchController: _searchController,
                conditionFilter: _conditionFilter,
                tradeFilter: _tradeFilter,
                saleFilter: _saleFilter,
                onSearch: _applyFilters,
                onConditionChanged: (v) {
                  setState(() => _conditionFilter = v);
                  _applyFilters();
                },
                onTradeToggle: () {
                  setState(() {
                    _tradeFilter =
                        _tradeFilter == true ? null : true;
                  });
                  _applyFilters();
                },
                onSaleToggle: () {
                  setState(() {
                    _saleFilter =
                        _saleFilter == true ? null : true;
                  });
                  _applyFilters();
                },
              ),

              // List
              Expanded(child: _buildList(provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(BinderProvider provider) {
    if (provider.isLoading && provider.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.manaViolet),
      );
    }

    if (provider.error != null && provider.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(provider.error!,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => provider.fetchMyBinder(reset: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (provider.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.collections_bookmark,
                size: 64,
                color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Seu fichário está vazio',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Adicione cartas da sua coleção!',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openAddCard,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar carta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.manaViolet,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.fetchMyBinder(reset: true);
        await provider.fetchStats();
      },
      color: AppTheme.manaViolet,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: provider.items.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= provider.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child:
                    CircularProgressIndicator(color: AppTheme.manaViolet),
              ),
            );
          }
          return _BinderItemCard(
            item: provider.items[index],
            onTap: () => _editItem(provider.items[index]),
          );
        },
      ),
    );
  }
}

// =====================================================================
// Stats Bar
// =====================================================================

class _StatsBar extends StatelessWidget {
  final BinderStats stats;
  const _StatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surfaceSlate2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatChip(
            icon: Icons.collections_bookmark,
            label: '${stats.totalItems}',
            tooltip: 'Total de cartas',
          ),
          _StatChip(
            icon: Icons.style,
            label: '${stats.uniqueCards}',
            tooltip: 'Cartas únicas',
          ),
          _StatChip(
            icon: Icons.swap_horiz,
            label: '${stats.forTradeCount}',
            tooltip: 'Para troca',
            color: AppTheme.loomCyan,
          ),
          _StatChip(
            icon: Icons.sell,
            label: '${stats.forSaleCount}',
            tooltip: 'Para venda',
            color: AppTheme.mythicGold,
          ),
          _StatChip(
            icon: Icons.attach_money,
            label: 'R\$ ${stats.estimatedValue.toStringAsFixed(0)}',
            tooltip: 'Valor estimado',
            color: AppTheme.mythicGold,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color = AppTheme.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: AppTheme.fontSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Search + Filter bar
// =====================================================================

class _SearchFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String? conditionFilter;
  final bool? tradeFilter;
  final bool? saleFilter;
  final VoidCallback onSearch;
  final ValueChanged<String?> onConditionChanged;
  final VoidCallback onTradeToggle;
  final VoidCallback onSaleToggle;

  const _SearchFilterBar({
    required this.searchController,
    required this.conditionFilter,
    required this.tradeFilter,
    required this.saleFilter,
    required this.onSearch,
    required this.onConditionChanged,
    required this.onTradeToggle,
    required this.onSaleToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.backgroundAbyss,
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: searchController,
            onSubmitted: (_) => onSearch(),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: AppTheme.fontMd),
            decoration: InputDecoration(
              hintText: 'Buscar carta...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon:
                  const Icon(Icons.search, color: AppTheme.textSecondary),
              suffixIcon: IconButton(
                icon:
                    const Icon(Icons.clear, color: AppTheme.textSecondary),
                onPressed: () {
                  searchController.clear();
                  onSearch();
                },
              ),
              filled: true,
              fillColor: AppTheme.surfaceSlate,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Condition dropdown
                _FilterDropdown(
                  value: conditionFilter,
                  items: const ['NM', 'LP', 'MP', 'HP', 'DMG'],
                  hint: 'Condição',
                  onChanged: onConditionChanged,
                ),
                const SizedBox(width: 8),

                // Trade filter
                FilterChip(
                  label: const Text('Troca'),
                  selected: tradeFilter == true,
                  onSelected: (_) => onTradeToggle(),
                  selectedColor: AppTheme.loomCyan.withValues(alpha: 0.3),
                  backgroundColor: AppTheme.surfaceSlate,
                  labelStyle: TextStyle(
                    color: tradeFilter == true
                        ? AppTheme.loomCyan
                        : AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                  ),
                  side: BorderSide(
                    color: tradeFilter == true
                        ? AppTheme.loomCyan
                        : AppTheme.outlineMuted,
                  ),
                  avatar: Icon(Icons.swap_horiz,
                      size: 14,
                      color: tradeFilter == true
                          ? AppTheme.loomCyan
                          : AppTheme.textSecondary),
                ),
                const SizedBox(width: 8),

                // Sale filter
                FilterChip(
                  label: const Text('Venda'),
                  selected: saleFilter == true,
                  onSelected: (_) => onSaleToggle(),
                  selectedColor:
                      AppTheme.mythicGold.withValues(alpha: 0.3),
                  backgroundColor: AppTheme.surfaceSlate,
                  labelStyle: TextStyle(
                    color: saleFilter == true
                        ? AppTheme.mythicGold
                        : AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                  ),
                  side: BorderSide(
                    color: saleFilter == true
                        ? AppTheme.mythicGold
                        : AppTheme.outlineMuted,
                  ),
                  avatar: Icon(Icons.sell,
                      size: 14,
                      color: saleFilter == true
                          ? AppTheme.mythicGold
                          : AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.outlineMuted),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: AppTheme.fontSm)),
          dropdownColor: AppTheme.surfaceSlate,
          icon: const Icon(Icons.arrow_drop_down,
              color: AppTheme.textSecondary, size: 18),
          style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: AppTheme.fontSm),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Todas',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ...items.map(
              (c) => DropdownMenuItem(value: c, child: Text(c)),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// =====================================================================
// Binder Item Card
// =====================================================================

class _BinderItemCard extends StatelessWidget {
  final BinderItem item;
  final VoidCallback onTap;

  const _BinderItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.surfaceSlate,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Card image
              CachedCardImage(
                imageUrl: item.cardImageUrl,
                width: 46,
                height: 64,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.cardName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: AppTheme.fontMd,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Qty badge
                        _badge('×${item.quantity}', AppTheme.manaViolet),
                        const SizedBox(width: 6),
                        // Condition
                        _badge(item.condition, _conditionColor(item.condition)),
                        if (item.isFoil) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.auto_awesome,
                              size: 14, color: AppTheme.mythicGold.withValues(alpha: 0.8)),
                        ],
                        if (item.cardSetCode != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            item.cardSetCode!.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: AppTheme.fontXs,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Status tags
                    Row(
                      children: [
                        if (item.forTrade)
                          _statusTag('Troca', AppTheme.loomCyan),
                        if (item.forSale) ...[
                          if (item.forTrade) const SizedBox(width: 6),
                          _statusTag('Venda', AppTheme.mythicGold),
                        ],
                        if (item.price != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            'R\$ ${item.price!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppTheme.mythicGold,
                              fontSize: AppTheme.fontSm,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: AppTheme.fontXs, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _statusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: AppTheme.fontXs, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _conditionColor(String c) {
    return AppTheme.conditionColor(c);
  }
}
