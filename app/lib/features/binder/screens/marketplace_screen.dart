import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../../trades/screens/create_trade_screen.dart';
import '../providers/binder_provider.dart';

/// Widget embeddable para uso como tab dentro do CollectionScreen.
/// Não possui Scaffold/AppBar — apenas o body content.
class MarketplaceTabContent extends StatefulWidget {
  const MarketplaceTabContent({super.key});

  @override
  State<MarketplaceTabContent> createState() => _MarketplaceTabContentState();
}

class _MarketplaceTabContentState extends State<MarketplaceTabContent>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String? _conditionFilter;
  bool _onlyTrade = false;
  bool _onlySale = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _doSearch();
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
      if (provider.hasMoreMarket && !provider.isLoadingMarket) {
        provider.fetchMarketplace(
          search: _searchController.text.trim(),
          condition: _conditionFilter,
          forTrade: _onlyTrade ? true : null,
          forSale: _onlySale ? true : null,
        );
      }
    }
  }

  void _doSearch() {
    context.read<BinderProvider>().fetchMarketplace(
          search: _searchController.text.trim(),
          condition: _conditionFilter,
          forTrade: _onlyTrade ? true : null,
          forSale: _onlySale ? true : null,
          reset: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Search bar (local state only — no provider rebuild needed)
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _searchController,
            onSubmitted: (_) => _doSearch(),
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: AppTheme.fontMd),
            decoration: InputDecoration(
              hintText: 'Buscar carta no marketplace...',
              hintStyle:
                  const TextStyle(color: AppTheme.textSecondary),
              prefixIcon: const Icon(Icons.search,
                  color: AppTheme.textSecondary),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear,
                    color: AppTheme.textSecondary),
                onPressed: () {
                  _searchController.clear();
                  _doSearch();
                },
              ),
              filled: true,
              fillColor: AppTheme.surfaceSlate,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Filter chips (local state only)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ConditionDropdown(
                  value: _conditionFilter,
                  onChanged: (v) {
                    setState(() => _conditionFilter = v);
                    _doSearch();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Troca'),
                  selected: _onlyTrade,
                  onSelected: (v) {
                    setState(() => _onlyTrade = v);
                    _doSearch();
                  },
                  selectedColor:
                      AppTheme.loomCyan.withValues(alpha: 0.3),
                  backgroundColor: AppTheme.surfaceSlate,
                  labelStyle: TextStyle(
                    color: _onlyTrade
                        ? AppTheme.loomCyan
                        : AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                  ),
                  side: BorderSide(
                    color: _onlyTrade
                        ? AppTheme.loomCyan
                        : AppTheme.outlineMuted,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Venda'),
                  selected: _onlySale,
                  onSelected: (v) {
                    setState(() => _onlySale = v);
                    _doSearch();
                  },
                  selectedColor:
                      AppTheme.mythicGold.withValues(alpha: 0.3),
                  backgroundColor: AppTheme.surfaceSlate,
                  labelStyle: TextStyle(
                    color: _onlySale
                        ? AppTheme.mythicGold
                        : AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                  ),
                  side: BorderSide(
                    color: _onlySale
                        ? AppTheme.mythicGold
                        : AppTheme.outlineMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // List — only this part needs provider data
        Expanded(child: _buildMarketList(context.watch<BinderProvider>())),
      ],
    );
  }

  Widget _buildMarketList(BinderProvider provider) {
    if (provider.isLoadingMarket && provider.marketItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.manaViolet),
      );
    }

    if (provider.marketError != null && provider.marketItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(provider.marketError!,
                style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _doSearch,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (provider.marketItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store,
                size: 64,
                color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma carta encontrada',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppTheme.fontLg,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tente outra busca ou filtro',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount:
          provider.marketItems.length + (provider.hasMoreMarket ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= provider.marketItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child:
                  CircularProgressIndicator(color: AppTheme.manaViolet),
            ),
          );
        }
        return _MarketplaceCard(
          item: provider.marketItems[index],
          onOwnerTap: () {
            final ownerId = provider.marketItems[index].ownerId;
            context.push('/community/user/$ownerId');
          },
          onTradeTap: () {
            final mktItem = provider.marketItems[index];
            // Convert to BinderItem for CreateTradeScreen
            final binderItem = BinderItem(
              id: mktItem.id,
              cardId: mktItem.cardId,
              cardName: mktItem.cardName,
              cardImageUrl: mktItem.cardImageUrl,
              cardSetCode: mktItem.cardSetCode,
              quantity: mktItem.quantity,
              condition: mktItem.condition,
              isFoil: mktItem.isFoil,
              forTrade: mktItem.forTrade,
              forSale: mktItem.forSale,
              price: mktItem.price,
              listType: 'have',
            );
            final type = mktItem.forSale && !mktItem.forTrade
                ? 'sale'
                : mktItem.forTrade && !mktItem.forSale
                    ? 'trade'
                    : 'mixed';
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateTradeScreen(
                  receiverId: mktItem.ownerId,
                  initialType: type,
                  preselectedItem: binderItem,
                ),
              ),
            );
          },
        );
      },
    );
  }
}


class _ConditionDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ConditionDropdown({required this.value, required this.onChanged});

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
          hint: const Text('Condição',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm)),
          dropdownColor: AppTheme.surfaceSlate,
          icon: const Icon(Icons.arrow_drop_down,
              color: AppTheme.textSecondary, size: 18),
          style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: AppTheme.fontSm),
          items: const [
            DropdownMenuItem(
              value: null,
              child: Text('Todas',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            DropdownMenuItem(value: 'NM', child: Text('NM')),
            DropdownMenuItem(value: 'LP', child: Text('LP')),
            DropdownMenuItem(value: 'MP', child: Text('MP')),
            DropdownMenuItem(value: 'HP', child: Text('HP')),
            DropdownMenuItem(value: 'DMG', child: Text('DMG')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// =====================================================================
// Marketplace item card
// =====================================================================

class _MarketplaceCard extends StatelessWidget {
  final MarketplaceItem item;
  final VoidCallback? onOwnerTap;
  final VoidCallback? onTradeTap;

  const _MarketplaceCard({required this.item, this.onOwnerTap, this.onTradeTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.surfaceSlate,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Card image
            CachedCardImage(
              imageUrl: item.cardImageUrl,
              width: 50,
              height: 70,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card name
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

                  // Badges
                  Row(
                    children: [
                      _badge('×${item.quantity}', AppTheme.manaViolet),
                      const SizedBox(width: 6),
                      _badge(item.condition, _condColor(item.condition)),
                      if (item.isFoil) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.auto_awesome,
                            size: 14,
                            color:
                                AppTheme.mythicGold.withValues(alpha: 0.8)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Trade / Sale tags + price
                  Row(
                    children: [
                      if (item.forTrade) _statusTag('Troca', AppTheme.loomCyan),
                      if (item.forSale) ...[
                        if (item.forTrade) const SizedBox(width: 6),
                        _statusTag('Venda', AppTheme.mythicGold),
                      ],
                      if (item.price != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'R\$ ${item.price!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppTheme.mythicGold,
                            fontSize: AppTheme.fontMd,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Owner + location
                  GestureDetector(
                    onTap: onOwnerTap,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor:
                              AppTheme.manaViolet.withValues(alpha: 0.3),
                          backgroundImage: item.ownerAvatarUrl != null
                              ? CachedNetworkImageProvider(item.ownerAvatarUrl!)
                              : null,
                          child: item.ownerAvatarUrl == null
                              ? Text(
                                  item.ownerUsername.isNotEmpty
                                      ? item.ownerUsername[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: AppTheme.fontXs,
                                    color: AppTheme.manaViolet,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.ownerDisplayLabel,
                            style: const TextStyle(
                              color: AppTheme.loomCyan,
                              fontSize: AppTheme.fontSm,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.ownerLocationLabel != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.location_on,
                              size: 12, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              item.ownerLocationLabel!,
                              style: TextStyle(
                                color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                fontSize: AppTheme.fontXs,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Trade notes
                  if (item.ownerTradeNotes != null &&
                      item.ownerTradeNotes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 12,
                            color: AppTheme.textSecondary.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.ownerTradeNotes!,
                            style: TextStyle(
                              color: AppTheme.textSecondary.withValues(alpha: 0.7),
                              fontSize: AppTheme.fontXs,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ── Interaction button ──
                  if (onTradeTap != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: OutlinedButton.icon(
                        onPressed: onTradeTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: item.forSale
                              ? AppTheme.mythicGold
                              : AppTheme.loomCyan,
                          side: BorderSide(
                            color: (item.forSale
                                    ? AppTheme.mythicGold
                                    : AppTheme.loomCyan)
                                .withValues(alpha: 0.5),
                          ),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                          ),
                        ),
                        icon: Icon(
                          item.forSale
                              ? Icons.shopping_cart_outlined
                              : Icons.swap_horiz,
                          size: 14,
                        ),
                        label: Text(
                          item.forSale ? 'Quero comprar' : 'Propor troca',
                          style:
                              const TextStyle(fontSize: AppTheme.fontSm),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
            color: color, fontSize: AppTheme.fontXs, fontWeight: FontWeight.w600),
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
            color: color, fontSize: AppTheme.fontXs, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _condColor(String c) {
    return AppTheme.conditionColor(c);
  }
}
