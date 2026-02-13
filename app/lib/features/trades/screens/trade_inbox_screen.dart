import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/trade_provider.dart';

/// Widget embeddable para uso como tab dentro do CollectionScreen.
/// Contém seu próprio TabBar aninhado (Recebidas / Enviadas / Finalizadas).
class TradeInboxTabContent extends StatefulWidget {
  const TradeInboxTabContent({super.key});

  @override
  State<TradeInboxTabContent> createState() => _TradeInboxTabContentState();
}

class _TradeInboxTabContentState extends State<TradeInboxTabContent>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForTab(0));
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadForTab(_tabController.index);
    }
  }

  void _loadForTab(int index) {
    final provider = context.read<TradeProvider>();
    switch (index) {
      case 0:
        provider.fetchTrades(role: 'receiver', status: 'pending');
        break;
      case 1:
        provider.fetchTrades(role: 'sender');
        break;
      case 2:
        provider.fetchTrades(status: 'completed');
        break;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Sub-tabs dentro da tab Trades
        Material(
          color: AppTheme.surfaceSlate2,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.manaViolet,
            labelColor: AppTheme.manaViolet,
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: const [
              Tab(text: 'Recebidas', icon: Icon(Icons.inbox, size: 18)),
              Tab(text: 'Enviadas', icon: Icon(Icons.send, size: 18)),
              Tab(text: 'Finalizadas', icon: Icon(Icons.done_all, size: 18)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _TradeListView(onRefresh: () => _loadForTab(0), role: 'receiver', status: 'pending'),
              _TradeListView(onRefresh: () => _loadForTab(1), role: 'sender'),
              _TradeListView(onRefresh: () => _loadForTab(2), status: 'completed'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tela principal de Trades — 3 tabs: Recebidas / Enviadas / Finalizadas (rota standalone)
class TradeInboxScreen extends StatefulWidget {
  const TradeInboxScreen({super.key});

  @override
  State<TradeInboxScreen> createState() => _TradeInboxScreenState();
}

class _TradeInboxScreenState extends State<TradeInboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Carregar trades recebidos inicialmente
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForTab(0));
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _loadForTab(_tabController.index);
    }
  }

  void _loadForTab(int index) {
    final provider = context.read<TradeProvider>();
    switch (index) {
      case 0:
        provider.fetchTrades(role: 'receiver', status: 'pending');
        break;
      case 1:
        provider.fetchTrades(role: 'sender');
        break;
      case 2:
        provider.fetchTrades(status: 'completed');
        break;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trades'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.manaViolet,
          labelColor: AppTheme.manaViolet,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Recebidas', icon: Icon(Icons.inbox, size: 18)),
            Tab(text: 'Enviadas', icon: Icon(Icons.send, size: 18)),
            Tab(text: 'Finalizadas', icon: Icon(Icons.done_all, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TradeListView(onRefresh: () => _loadForTab(0), role: 'receiver', status: 'pending'),
          _TradeListView(onRefresh: () => _loadForTab(1), role: 'sender'),
          _TradeListView(onRefresh: () => _loadForTab(2), status: 'completed'),
        ],
      ),
    );
  }
}

class _TradeListView extends StatefulWidget {
  final VoidCallback onRefresh;
  final String role;
  final String? status;
  const _TradeListView({required this.onRefresh, this.role = 'all', this.status});

  @override
  State<_TradeListView> createState() => _TradeListViewState();
}

class _TradeListViewState extends State<_TradeListView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = context.read<TradeProvider>();
      if (!provider.isLoading &&
          provider.trades.length < provider.totalTrades) {
        provider.fetchMoreTrades(
          role: widget.role,
          status: widget.status,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TradeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: widget.onRefresh, child: const Text('Tentar novamente')),
              ],
            ),
          );
        }
        if (provider.trades.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz, size: 64, color: AppTheme.outlineMuted),
                const SizedBox(height: 12),
                const Text(
                  'Nenhum trade encontrado',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontLg),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => widget.onRefresh(),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: provider.trades.length,
            itemBuilder: (context, index) {
              final trade = provider.trades[index];
              return _TradeCard(trade: trade);
            },
          ),
        );
      },
    );
  }
}

class _TradeCard extends StatelessWidget {
  final TradeOffer trade;
  const _TradeCard({required this.trade});

  @override
  Widget build(BuildContext context) {
    final statusColor = TradeStatusHelper.color(trade.status);
    final statusIcon = TradeStatusHelper.icon(trade.status);
    final statusLabel = TradeStatusHelper.label(trade.status);
    final currentUserId = context.read<AuthProvider>().user?.id;
    final otherUser = trade.sender.id == currentUserId
        ? trade.receiver
        : trade.sender;

    return Card(
      color: AppTheme.surfaceSlate,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () {
          context.push('/trades/${trade.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: user + status badge
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.outlineMuted,
                    child: Text(
                      otherUser.label[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          otherUser.label,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _typeLabel(trade.type),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: AppTheme.fontSm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Info row: items counts + messages
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.upload,
                    label: '${trade.offeringCount ?? 0} oferecendo',
                  ),
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.download,
                    label: '${trade.requestingCount ?? 0} pedindo',
                  ),
                  const Spacer(),
                  if ((trade.messageCount ?? 0) > 0)
                    _InfoChip(
                      icon: Icons.chat_bubble_outline,
                      label: '${trade.messageCount}',
                    ),
                ],
              ),
              if (trade.message != null && trade.message!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  trade.message!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'trade':
        return 'Troca';
      case 'sale':
        return 'Compra/Venda';
      case 'mixed':
        return 'Misto';
      default:
        return type;
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm),
        ),
      ],
    );
  }
}
