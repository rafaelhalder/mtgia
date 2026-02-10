import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/market_provider.dart';
import '../models/card_mover.dart';

/// Tela de Market — exibe variações de preço diárias (gainers/losers)
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketProvider>().fetchMovers();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundAbyss,
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.trending_up, color: AppTheme.mythicGold, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Market',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            backgroundColor: AppTheme.backgroundAbyss,
            elevation: 0,
            actions: [
              if (provider.moversData != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      '${provider.moversData!.totalTracked} cartas',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontSm,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
                onPressed: provider.isLoading ? null : () => provider.refresh(),
                tooltip: 'Atualizar',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.mythicGold,
              labelColor: AppTheme.mythicGold,
              unselectedLabelColor: AppTheme.textSecondary,
              tabs: const [
                Tab(
                  icon: Icon(Icons.arrow_upward, size: 18),
                  text: 'Valorizando',
                ),
                Tab(
                  icon: Icon(Icons.arrow_downward, size: 18),
                  text: 'Desvalorizando',
                ),
              ],
            ),
          ),
          body: _buildBody(provider),
        );
      },
    );
  }

  Widget _buildBody(MarketProvider provider) {
    if (provider.isLoading && provider.moversData == null) {
      return _buildLoading();
    }

    if (provider.errorMessage != null && provider.moversData == null) {
      return _buildError(provider);
    }

    final data = provider.moversData;
    if (data == null) {
      return _buildEmpty();
    }

    if (data.needsMoreData) {
      return _buildNeedsData(data.message!);
    }

    return Column(
      children: [
        // Header com datas
        _buildDateHeader(data),
        // Conteúdo das tabs
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab Gainers
              data.gainers.isEmpty
                  ? _buildEmptyTab('Nenhuma carta valorizou hoje')
                  : _buildMoversList(data.gainers, isGainer: true, provider: provider),
              // Tab Losers
              data.losers.isEmpty
                  ? _buildEmptyTab('Nenhuma carta desvalorizou hoje')
                  : _buildMoversList(data.losers, isGainer: false, provider: provider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateHeader(MarketMoversData data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surfaceSlate2,
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            data.date != null ? _formatDate(data.date!) : 'Hoje',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
          ),
          if (data.previousDate != null) ...[
            const Text(
              '  vs  ',
              style: TextStyle(color: AppTheme.outlineMuted, fontSize: AppTheme.fontSm),
            ),
            Text(
              _formatDate(data.previousDate!),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.mythicGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(
              'USD',
              style: TextStyle(
                color: AppTheme.mythicGold,
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoversList(List<CardMover> movers,
      {required bool isGainer, required MarketProvider provider}) {
    return RefreshIndicator(
      color: AppTheme.mythicGold,
      backgroundColor: AppTheme.surfaceSlate,
      onRefresh: () => provider.refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: movers.length,
        itemBuilder: (context, index) {
          return _MoverCard(
            mover: movers[index],
            rank: index + 1,
            isGainer: isGainer,
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.mythicGold),
          SizedBox(height: 16),
          Text(
            'Carregando dados do mercado...',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildError(MarketProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              provider.errorMessage ?? 'Erro desconhecido',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.manaViolet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        'Sem dados de mercado disponíveis',
        style: TextStyle(color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildNeedsData(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_top, size: 48, color: AppTheme.mythicGold),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
            ),
            const SizedBox(height: 8),
            const Text(
              'Os preços são atualizados diariamente.\nAmanhã teremos dados de variação!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTab(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.trending_flat, size: 40, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final parts = isoDate.split('-');
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {
      return isoDate;
    }
  }
}

/// Card individual de um mover (gainer ou loser)
class _MoverCard extends StatelessWidget {
  final CardMover mover;
  final int rank;
  final bool isGainer;

  const _MoverCard({
    required this.mover,
    required this.rank,
    required this.isGainer,
  });

  @override
  Widget build(BuildContext context) {
    final changeColor = isGainer ? AppTheme.success : AppTheme.error;
    final changeIcon = isGainer ? Icons.arrow_upward : Icons.arrow_downward;
    final changePrefix = isGainer ? '+' : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: rank <= 3
              ? changeColor.withValues(alpha: 0.3)
              : AppTheme.outlineMuted.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? changeColor.withValues(alpha: 0.2)
                    : AppTheme.surfaceSlate2,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              alignment: Alignment.center,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: rank <= 3 ? changeColor : AppTheme.textSecondary,
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Card image (thumbnail)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: SizedBox(
                width: 36,
                height: 50,
                child: mover.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: mover.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppTheme.surfaceSlate2,
                          child: const Icon(
                            Icons.style,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.surfaceSlate2,
                          child: const Icon(
                            Icons.style,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : Container(
                        color: AppTheme.surfaceSlate2,
                        child: const Icon(
                          Icons.style,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),

            // Nome e detalhes
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mover.name,
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
                      if (mover.setCode != null)
                        Text(
                          mover.setCode!.toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
                      if (mover.rarity != null) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: AppTheme.outlineMuted, fontSize: AppTheme.fontSm),
                        ),
                        Text(
                          _rarityLabel(mover.rarity!),
                          style: TextStyle(
                            color: _rarityColor(mover.rarity!),
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Preços e variação
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Preço atual
                Text(
                  '\$${mover.priceToday.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontLg,
                  ),
                ),
                const SizedBox(height: 2),
                // Variação
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: changeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(changeIcon, size: 12, color: changeColor),
                      const SizedBox(width: 2),
                      Text(
                        '$changePrefix${mover.changePct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: changeColor,
                          fontSize: AppTheme.fontSm,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                // Variação em USD
                Text(
                  '$changePrefix\$${mover.changeUsd.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: changeColor.withValues(alpha: 0.7),
                    fontSize: AppTheme.fontXs,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _rarityLabel(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'mythic':
        return 'Mítica';
      case 'rare':
        return 'Rara';
      case 'uncommon':
        return 'Incomum';
      case 'common':
        return 'Comum';
      default:
        return rarity;
    }
  }

  Color _rarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'mythic':
        return AppTheme.mythicGold;
      case 'rare':
        return AppTheme.mythicGold.withValues(alpha: 0.7);
      case 'uncommon':
        return AppTheme.loomCyan;
      case 'common':
        return AppTheme.textSecondary;
      default:
        return AppTheme.textSecondary;
    }
  }
}
