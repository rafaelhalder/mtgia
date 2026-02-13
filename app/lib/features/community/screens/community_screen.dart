import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cached_network_image/cached_network_image.dart' show CachedNetworkImage;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../providers/community_provider.dart';
import '../../market/models/card_mover.dart';
import '../../market/providers/market_provider.dart';
import '../../social/providers/social_provider.dart';
import '../../social/screens/user_profile_screen.dart';
import 'community_deck_detail_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommunityProvider>().fetchPublicDecks(reset: true);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      // Aba "Seguindo": carregar feed
      context.read<SocialProvider>().fetchFollowingFeed(reset: true);
    } else if (_tabController.index == 3) {
      // Aba "Cotações": carregar market movers
      context.read<MarketProvider>().fetchMovers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Comunidade'),
        backgroundColor: AppTheme.surfaceSlate2,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.manaViolet,
          labelColor: AppTheme.textPrimary,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: const TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w600),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.public, size: 18), text: 'Explorar'),
            Tab(icon: Icon(Icons.people, size: 18), text: 'Seguindo'),
            Tab(icon: Icon(Icons.person_search, size: 18), text: 'Usuários'),
            Tab(icon: Icon(Icons.trending_up, size: 18), text: 'Cotações'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ExploreTab(),
          _FollowingFeedTab(),
          _UserSearchTab(),
          _CotacoesTab(),
        ],
      ),
    );
  }
}

// =====================================================================
// TAB 1: Explorar (decks públicos — antigo conteúdo da CommunityScreen)
// =====================================================================
class _ExploreTab extends StatefulWidget {
  const _ExploreTab();

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String? _selectedFormat;

  static const _formats = [
    'commander',
    'standard',
    'modern',
    'pioneer',
    'pauper',
    'legacy',
    'vintage',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<CommunityProvider>().fetchPublicDecks();
    }
  }

  void _doSearch() {
    final query = _searchController.text.trim();
    context.read<CommunityProvider>().fetchPublicDecks(
          search: query.isEmpty ? null : query,
          format: _selectedFormat,
          reset: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Search bar + filters
        Container(
          padding: const EdgeInsets.all(12),
          color: AppTheme.surfaceSlate2,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Pesquisar decks públicos...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon:
                      const Icon(Icons.search, color: AppTheme.loomCyan),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear,
                        color: AppTheme.textSecondary, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _doSearch();
                    },
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceSlate,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _doSearch(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFormatChip(null, 'Todos'),
                    ..._formats.map((f) => _buildFormatChip(f, _capitalize(f))),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Deck list
        Expanded(
          child: Consumer<CommunityProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.decks.isEmpty) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.manaViolet),
                );
              }

              if (provider.errorMessage != null && provider.decks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: 12),
                      Text(provider.errorMessage!,
                          style:
                              const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () =>
                            provider.fetchPublicDecks(reset: true),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                );
              }

              if (provider.decks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_off,
                          size: 64,
                          color:
                              AppTheme.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenhum deck público encontrado',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: AppTheme.fontLg),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Compartilhe seus decks para aparecerem aqui!',
                        style: TextStyle(
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.7),
                            fontSize: AppTheme.fontMd),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount:
                    provider.decks.length + (provider.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= provider.decks.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                            color: AppTheme.manaViolet),
                      ),
                    );
                  }

                  final deck = provider.decks[index];
                  return _CommunityDeckCard(
                    deck: deck,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CommunityDeckDetailScreen(deckId: deck.id),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFormatChip(String? format, String label) {
    final isSelected = _selectedFormat == format;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label,
            style: TextStyle(
              color: isSelected
                  ? AppTheme.backgroundAbyss
                  : AppTheme.textPrimary,
              fontSize: AppTheme.fontSm,
            )),
        selected: isSelected,
        selectedColor: AppTheme.loomCyan,
        backgroundColor: AppTheme.surfaceSlate,
        checkmarkColor: AppTheme.backgroundAbyss,
        side: BorderSide(
          color: isSelected ? AppTheme.loomCyan : AppTheme.outlineMuted,
        ),
        onSelected: (_) {
          setState(() => _selectedFormat = format);
          _doSearch();
        },
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// =====================================================================
// TAB 2: Seguindo (feed de decks dos usuários que sigo)
// =====================================================================
class _FollowingFeedTab extends StatefulWidget {
  const _FollowingFeedTab();

  @override
  State<_FollowingFeedTab> createState() => _FollowingFeedTabState();
}

class _FollowingFeedTabState extends State<_FollowingFeedTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocialProvider>().fetchFollowingFeed(reset: true);
    });
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
      context.read<SocialProvider>().fetchFollowingFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<SocialProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingFeed && provider.followingFeed.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.manaViolet),
          );
        }

        if (provider.followingFeed.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64,
                      color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text(
                    'Nenhum deck dos seus seguidos',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: AppTheme.fontLg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Siga outros jogadores na aba "Usuários" para ver os decks públicos deles aqui!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                      fontSize: AppTheme.fontMd,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () =>
              provider.fetchFollowingFeed(reset: true),
          color: AppTheme.manaViolet,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount:
                provider.followingFeed.length + (provider.hasMoreFeed ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= provider.followingFeed.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: AppTheme.manaViolet),
                  ),
                );
              }

              final deck = provider.followingFeed[index];
              return _FollowingDeckCard(
                deck: deck,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CommunityDeckDetailScreen(deckId: deck.id),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// =====================================================================
// TAB 3: Buscar Usuários (inline, sem navegar para outra tela)
// =====================================================================
class _UserSearchTab extends StatefulWidget {
  const _UserSearchTab();

  @override
  State<_UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends State<_UserSearchTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<SocialProvider>().searchUsers(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.all(12),
          color: AppTheme.surfaceSlate2,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Buscar por nick ou nome de usuário...',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              prefixIcon:
                  const Icon(Icons.person_search, color: AppTheme.loomCyan),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear,
                    color: AppTheme.textSecondary, size: 18),
                onPressed: () {
                  _searchController.clear();
                  context.read<SocialProvider>().clearSearch();
                },
              ),
              filled: true,
              fillColor: AppTheme.surfaceSlate,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        // Results
        Expanded(
          child: Consumer<SocialProvider>(
            builder: (context, provider, _) {
              if (provider.isSearching) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.manaViolet),
                );
              }

              if (provider.searchError != null) {
                return Center(
                  child: Text(
                    provider.searchError!,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                );
              }

              if (_searchController.text.trim().isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search,
                            size: 64,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        const Text(
                          'Encontre outros jogadores',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontLg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Busque pelo nick ou nome de usuário para ver perfis, decks e seguir jogadores.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.7),
                            fontSize: AppTheme.fontMd,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (provider.searchResults.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off,
                          size: 48,
                          color:
                              AppTheme.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhum usuário encontrado',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: AppTheme.fontLg),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: provider.searchResults.length,
                itemBuilder: (context, index) {
                  final user = provider.searchResults[index];
                  return _UserCard(
                    user: user,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserProfileScreen(userId: user.id),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Widgets compartilhados
// =====================================================================

class _CommunityDeckCard extends StatelessWidget {
  final CommunityDeck deck;
  final VoidCallback onTap;

  const _CommunityDeckCard({required this.deck, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.surfaceSlate,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Commander image
              CachedCardImage(
                imageUrl: deck.commanderImageUrl,
                width: 56,
                height: 78,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontLg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 14,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: deck.ownerId != null
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(
                                          userId: deck.ownerId!),
                                    ),
                                  );
                                }
                              : null,
                          child: Text(
                            deck.ownerUsername ?? 'Anônimo',
                            style: TextStyle(
                              color: deck.ownerId != null
                                  ? AppTheme.loomCyan
                                  : AppTheme.textSecondary.withValues(
                                      alpha: 0.8),
                              fontSize: AppTheme.fontSm,
                              decoration: deck.ownerId != null
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: AppTheme.loomCyan,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.manaViolet.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                          ),
                          child: Text(
                            _capitalize(deck.format),
                            style: const TextStyle(
                              color: AppTheme.manaViolet,
                              fontSize: AppTheme.fontXs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${deck.cardCount} cartas',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
                        if (deck.synergyScore != null) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color:
                                AppTheme.mythicGold.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${deck.synergyScore}%',
                            style: TextStyle(
                              color:
                                  AppTheme.mythicGold.withValues(alpha: 0.8),
                              fontSize: AppTheme.fontSm,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (deck.description != null &&
                        deck.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        deck.description!,
                        style: TextStyle(
                          color:
                              AppTheme.textSecondary.withValues(alpha: 0.7),
                          fontSize: AppTheme.fontSm,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _FollowingDeckCard extends StatelessWidget {
  final PublicDeckSummary deck;
  final VoidCallback onTap;

  const _FollowingDeckCard({required this.deck, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.surfaceSlate,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CachedCardImage(
                imageUrl: deck.commanderImageUrl,
                width: 56,
                height: 78,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontLg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.manaViolet.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                          ),
                          child: Text(
                            _capitalize(deck.format),
                            style: const TextStyle(
                              color: AppTheme.manaViolet,
                              fontSize: AppTheme.fontXs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${deck.cardCount} cartas',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
                        if (deck.synergyScore != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.auto_awesome,
                              size: 12,
                              color:
                                  AppTheme.mythicGold.withValues(alpha: 0.8)),
                          const SizedBox(width: 2),
                          Text(
                            '${deck.synergyScore}%',
                            style: TextStyle(
                              color:
                                  AppTheme.mythicGold.withValues(alpha: 0.8),
                              fontSize: AppTheme.fontSm,
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

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _UserCard extends StatelessWidget {
  final PublicUser user;
  final VoidCallback onTap;

  const _UserCard({required this.user, required this.onTap});

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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.manaViolet.withValues(alpha: 0.3),
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        user.username[0].toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.manaViolet,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTheme.fontXl,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? user.username,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontLg,
                      ),
                    ),
                    if (user.displayName != null)
                      Text(
                        '@${user.username}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: AppTheme.fontSm,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.style,
                            size: 13,
                            color: AppTheme.loomCyan.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          '${user.publicDeckCount} decks',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.people,
                            size: 13,
                            color:
                                AppTheme.manaViolet.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          '${user.followerCount} seguidores',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontSm,
                          ),
                        ),
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
}

// =====================================================================
// TAB 4: Cotações (Market Movers — variações de preço diárias)
// =====================================================================
class _CotacoesTab extends StatefulWidget {
  const _CotacoesTab();

  @override
  State<_CotacoesTab> createState() => _CotacoesTabState();
}

class _CotacoesTabState extends State<_CotacoesTab>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _subTabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketProvider>().fetchMovers();
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
    return Consumer<MarketProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.moversData == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.mythicGold),
                SizedBox(height: 16),
                Text('Carregando cotações...', style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          );
        }

        if (provider.errorMessage != null && provider.moversData == null) {
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
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.manaViolet),
                  ),
                ],
              ),
            ),
          );
        }

        final data = provider.moversData;
        if (data == null) {
          return const Center(
            child: Text('Sem dados de mercado', style: TextStyle(color: AppTheme.textSecondary)),
          );
        }

        if (data.needsMoreData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.hourglass_top, size: 48, color: AppTheme.mythicGold),
                  const SizedBox(height: 16),
                  Text(
                    data.message ?? 'Aguardando dados...',
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

        return Column(
          children: [
            // Header com datas + info
            _buildDateHeader(data, provider),
            // Sub-tabs Valorizando / Desvalorizando
            Container(
              color: AppTheme.surfaceSlate2,
              child: TabBar(
                controller: _subTabController,
                indicatorColor: AppTheme.mythicGold,
                labelColor: AppTheme.mythicGold,
                unselectedLabelColor: AppTheme.textSecondary,
                tabs: const [
                  Tab(icon: Icon(Icons.arrow_upward, size: 16), text: 'Valorizando'),
                  Tab(icon: Icon(Icons.arrow_downward, size: 16), text: 'Desvalorizando'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _subTabController,
                children: [
                  data.gainers.isEmpty
                      ? const Center(child: Text('Nenhuma carta valorizou hoje', style: TextStyle(color: AppTheme.textSecondary)))
                      : _buildMoversList(data.gainers, isGainer: true, provider: provider),
                  data.losers.isEmpty
                      ? const Center(child: Text('Nenhuma carta desvalorizou hoje', style: TextStyle(color: AppTheme.textSecondary)))
                      : _buildMoversList(data.losers, isGainer: false, provider: provider),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(MarketMoversData data, MarketProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.surfaceSlate2.withValues(alpha: 0.5),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            data.date != null ? _formatDate(data.date!) : 'Hoje',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
          ),
          if (data.previousDate != null) ...[
            const Text(' vs ', style: TextStyle(color: AppTheme.outlineMuted, fontSize: AppTheme.fontSm)),
            Text(
              _formatDate(data.previousDate!),
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.mythicGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(
              '${data.totalTracked} cartas',
              style: const TextStyle(color: AppTheme.mythicGold, fontSize: AppTheme.fontSm, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: provider.isLoading ? null : () => provider.refresh(),
            child: Icon(
              Icons.refresh,
              size: 20,
              color: provider.isLoading ? AppTheme.outlineMuted : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoversList(List<CardMover> movers, {required bool isGainer, required MarketProvider provider}) {
    return RefreshIndicator(
      color: AppTheme.mythicGold,
      backgroundColor: AppTheme.surfaceSlate,
      onRefresh: () => provider.refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: movers.length,
        itemBuilder: (context, index) {
          final mover = movers[index];
          final changeColor = isGainer ? AppTheme.success : AppTheme.error;
          final changeIcon = isGainer ? Icons.arrow_upward : Icons.arrow_downward;
          final changePrefix = isGainer ? '+' : '';

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSlate,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: index < 3
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
                      color: index < 3 ? changeColor.withValues(alpha: 0.2) : AppTheme.surfaceSlate2,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: index < 3 ? changeColor : AppTheme.textSecondary,
                        fontSize: AppTheme.fontSm,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Card image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: SizedBox(
                      width: 36,
                      height: 50,
                      child: mover.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: mover.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: AppTheme.surfaceSlate2, child: const Icon(Icons.style, size: 16, color: AppTheme.textSecondary)),
                              errorWidget: (_, __, ___) => Container(color: AppTheme.surfaceSlate2, child: const Icon(Icons.style, size: 16, color: AppTheme.textSecondary)),
                            )
                          : Container(color: AppTheme.surfaceSlate2, child: const Icon(Icons.style, size: 16, color: AppTheme.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name + details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mover.name,
                          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: AppTheme.fontMd),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(children: [
                          if (mover.setCode != null)
                            Text(mover.setCode!.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm)),
                          if (mover.rarity != null) ...[
                            const Text(' • ', style: TextStyle(color: AppTheme.outlineMuted, fontSize: AppTheme.fontSm)),
                            Text(_rarityLabel(mover.rarity!), style: TextStyle(color: _rarityColor(mover.rarity!), fontSize: AppTheme.fontSm)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                  // Price + change
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${mover.priceToday.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: AppTheme.fontLg),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: changeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(changeIcon, size: 12, color: changeColor),
                          const SizedBox(width: 2),
                          Text('$changePrefix${mover.changePct.toStringAsFixed(1)}%', style: TextStyle(color: changeColor, fontSize: AppTheme.fontSm, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$changePrefix\$${mover.changeUsd.toStringAsFixed(2)}',
                        style: TextStyle(color: changeColor.withValues(alpha: 0.7), fontSize: AppTheme.fontXs),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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

  String _rarityLabel(String rarity) {
    return switch (rarity.toLowerCase()) {
      'mythic' => 'Mítica',
      'rare' => 'Rara',
      'uncommon' => 'Incomum',
      'common' => 'Comum',
      _ => rarity,
    };
  }

  Color _rarityColor(String rarity) {
    return switch (rarity.toLowerCase()) {
      'mythic' => AppTheme.mythicGold,
      'rare' => AppTheme.mythicGold.withValues(alpha: 0.7),
      'uncommon' => AppTheme.loomCyan,
      _ => AppTheme.textSecondary,
    };
  }
}

