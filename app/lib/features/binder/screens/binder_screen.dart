import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../providers/binder_provider.dart';
import '../widgets/binder_item_editor.dart';
import '../../cards/screens/card_search_screen.dart';
import '../../scanner/screens/card_scanner_screen.dart';

/// Widget embeddable para uso como tab dentro do CollectionScreen.
/// Não possui Scaffold/AppBar — apenas o body content.
/// Agora possui 2 sub-tabs: "Tenho" (have) e "Quero" (want).
class BinderTabContent extends StatefulWidget {
  const BinderTabContent({super.key});

  @override
  State<BinderTabContent> createState() => _BinderTabContentState();
}

class _BinderTabContentState extends State<BinderTabContent>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  late TabController _subTabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
    _subTabController.addListener(() {
      if (!_subTabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        // Sub-tabs: Tenho / Quero
        Container(
          color: AppTheme.surfaceSlate2,
          child: TabBar(
            controller: _subTabController,
            indicatorColor: _subTabController.index == 0
                ? AppTheme.loomCyan
                : AppTheme.mythicGold,
            labelColor: _subTabController.index == 0
                ? AppTheme.loomCyan
                : AppTheme.mythicGold,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTheme.fontMd,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.inventory_2, size: 18),
                text: 'Tenho',
                height: 52,
              ),
              Tab(
                icon: Icon(Icons.favorite_border, size: 18),
                text: 'Quero',
                height: 52,
              ),
            ],
          ),
        ),

        // Content area
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: const [
              _BinderListView(listType: 'have'),
              _BinderListView(listType: 'want'),
            ],
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// _BinderListView — Lista de itens filtrada por list_type
// =====================================================================

class _BinderListView extends StatefulWidget {
  final String listType; // 'have' or 'want'
  const _BinderListView({required this.listType});

  @override
  State<_BinderListView> createState() => _BinderListViewState();
}

class _BinderListViewState extends State<_BinderListView>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String? _conditionFilter;
  bool? _tradeFilter;
  bool? _saleFilter;

  // Each list_type has its own items, pagination, and loading state
  List<BinderItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchItems(reset: true);
      // Fetch global stats once
      context.read<BinderProvider>().fetchStats();
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
      if (_hasMore && !_isLoading) {
        _fetchItems();
      }
    }
  }

  Future<void> _fetchItems({bool reset = false}) async {
    if (_isLoading) return;
    if (!reset && !_hasMore) return;

    if (reset) {
      _page = 1;
      _items = [];
      _hasMore = true;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<BinderProvider>();
      final res = await provider.fetchBinderDirect(
        listType: widget.listType,
        page: _page,
        condition: _conditionFilter,
        search: _searchController.text.trim(),
        forTrade: _tradeFilter,
        forSale: _saleFilter,
      );
      if (res != null) {
        _items.addAll(res);
        _hasMore = res.length >= 20;
        _page++;
        _error = null;
      } else {
        _error = 'Erro ao carregar';
      }
    } catch (e) {
      debugPrint('[❌ BinderList] fetchItems (${widget.listType}): $e');
      _error = 'Não foi possível conectar ao servidor';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    _fetchItems(reset: true);
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
              initialListType: widget.listType,
              onSave: (data) async {
                final ok = await provider.addItem(
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
                  listType: data['list_type'] as String? ?? widget.listType,
                );
                if (ok && mounted) {
                  _fetchItems(reset: true);
                }
                return ok;
              },
            );
          },
        ),
      ),
    );
  }

  void _openScanCard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CardScannerScreen(
          deckId: '',
          mode: 'binder',
          onCardScannedForBinder: (card) {
            if (!mounted) return;
            final provider = context.read<BinderProvider>();
            BinderItemEditor.show(
              context,
              cardId: card['id'] as String,
              cardName: card['name'] as String?,
              initialListType: widget.listType,
              onSave: (data) async {
                final ok = await provider.addItem(
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
                  listType: data['list_type'] as String? ?? widget.listType,
                );
                if (ok && mounted) {
                  _fetchItems(reset: true);
                }
                return ok;
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
      onSave: (data) async {
        final ok = await provider.updateItem(item.id, data);
        if (ok && mounted) {
          _fetchItems(reset: true);
        }
        return ok;
      },
      onDelete: () async {
        final ok = await provider.removeItem(item.id);
        if (ok && mounted) {
          _fetchItems(reset: true);
        }
        return ok;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isHave = widget.listType == 'have';
    final stats = context.select<BinderProvider, BinderStats?>((p) => p.stats);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showStats = stats != null && constraints.maxHeight > 300;

        return Column(
          children: [
            // Stats bar
            if (showStats)
              _StatsBar(stats: stats, onAdd: _openAddCard, onScan: _openScanCard),

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
                  _tradeFilter = _tradeFilter == true ? null : true;
                });
                _applyFilters();
              },
              onSaleToggle: () {
                setState(() {
                  _saleFilter = _saleFilter == true ? null : true;
                });
                _applyFilters();
              },
            ),

            // List
            Expanded(child: _buildList(isHave)),
          ],
        );
      },
    );
  }

  Widget _buildList(bool isHave) {
    if (_isLoading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.manaViolet),
      );
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetchItems(reset: true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isHave ? Icons.inventory_2 : Icons.favorite_border,
                size: 64,
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                isHave
                    ? 'Nenhuma carta em "Tenho"'
                    : 'Nenhuma carta em "Quero"',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: AppTheme.fontXl,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isHave
                    ? 'Adicione cartas que você possui!'
                    : 'Adicione cartas que você procura!',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _openAddCard,
                    icon: const Icon(Icons.add),
                    label: const Text('Buscar carta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isHave ? AppTheme.loomCyan : AppTheme.mythicGold,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _openScanCard,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Escanear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.manaViolet,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchItems(reset: true);
        await context.read<BinderProvider>().fetchStats();
      },
      color: AppTheme.manaViolet,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.manaViolet),
              ),
            );
          }
          return _BinderItemCard(
            item: _items[index],
            onTap: () => _editItem(_items[index]),
          );
        },
      ),
    );
  }
}

// =====================================================================
// Stats bar
// =====================================================================

class _StatsBar extends StatelessWidget {
  final BinderStats stats;
  final VoidCallback? onAdd;
  final VoidCallback? onScan;
  const _StatsBar({required this.stats, this.onAdd, this.onScan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surfaceSlate2,
      child: Row(
        children: [
          Expanded(
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
          ),
          if (onScan != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.camera_alt, color: AppTheme.loomCyan),
              tooltip: 'Escanear carta',
              onPressed: onScan,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
          ],
          if (onAdd != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add, color: AppTheme.manaViolet),
              tooltip: 'Adicionar carta',
              onPressed: onAdd,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
          ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: searchController,
            onSubmitted: (_) => onSearch(),
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: AppTheme.fontMd),
            decoration: InputDecoration(
              hintText: 'Buscar carta...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon:
                  const Icon(Icons.search, color: AppTheme.textSecondary),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterDropdown(
                  value: conditionFilter,
                  items: const ['NM', 'LP', 'MP', 'HP', 'DMG'],
                  hint: 'Condição',
                  onChanged: onConditionChanged,
                ),
                const SizedBox(width: 8),
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
                FilterChip(
                  label: const Text('Venda'),
                  selected: saleFilter == true,
                  onSelected: (_) => onSaleToggle(),
                  selectedColor: AppTheme.mythicGold.withValues(alpha: 0.3),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CachedCardImage(
                imageUrl: item.cardImageUrl,
                width: 46,
                height: 64,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _badge('×${item.quantity}', AppTheme.manaViolet),
                        const SizedBox(width: 6),
                        _badge(item.condition, _conditionColor(item.condition)),
                        if (item.isFoil) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.auto_awesome,
                              size: 14,
                              color: AppTheme.mythicGold.withValues(alpha: 0.8)),
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
                    if (item.forTrade || item.forSale || item.price != null) ...[
                      const SizedBox(height: 2),
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
        style: TextStyle(
            color: color,
            fontSize: AppTheme.fontXs,
            fontWeight: FontWeight.w600),
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
        style: TextStyle(
            color: color,
            fontSize: AppTheme.fontXs,
            fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _conditionColor(String c) {
    return AppTheme.conditionColor(c);
  }
}
