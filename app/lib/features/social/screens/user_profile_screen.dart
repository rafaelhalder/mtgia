import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../../community/screens/community_deck_detail_screen.dart';
import '../../binder/providers/binder_provider.dart';
import '../providers/social_provider.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Carregar perfil
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocialProvider>().fetchUserProfile(widget.userId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _toggleFollow() async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    final provider = context.read<SocialProvider>();
    if (provider.isFollowingVisited) {
      await provider.unfollowUser(widget.userId);
    } else {
      await provider.followUser(widget.userId);
    }

    if (mounted) setState(() => _isToggling = false);
  }

  void _loadTab(int index) {
    final provider = context.read<SocialProvider>();
    if (index == 1) {
      provider.fetchFollowers(widget.userId, reset: true);
    } else if (index == 2) {
      provider.fetchFollowing(widget.userId, reset: true);
    } else if (index == 3) {
      context.read<BinderProvider>().fetchPublicBinder(widget.userId, reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: AppTheme.surfaceSlate2,
      ),
      body: Consumer<SocialProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingProfile) {
            return const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.manaViolet),
            );
          }

          if (provider.profileError != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 12),
                  Text(provider.profileError!,
                      style:
                          const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        provider.fetchUserProfile(widget.userId),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }

          final user = provider.visitedUser;
          if (user == null) return const SizedBox.shrink();

          return Column(
            children: [
              // === Header do perfil ===
              Container(
                padding: const EdgeInsets.all(20),
                color: AppTheme.surfaceSlate2,
                child: Column(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppTheme.manaViolet.withValues(
                          alpha: 0.3),
                      backgroundImage: user.avatarUrl != null
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? Text(
                              user.username[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.manaViolet,
                                fontSize: AppTheme.fontDisplay,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    // Display name
                    Text(
                      user.displayName ?? user.username,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: AppTheme.fontXxl,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (user.displayName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '@${user.username}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: AppTheme.fontMd,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatItem(
                          label: 'Decks',
                          value: user.publicDeckCount,
                          icon: Icons.style,
                        ),
                        const SizedBox(width: 24),
                        _StatItem(
                          label: 'Seguidores',
                          value: user.followerCount,
                          icon: Icons.people,
                          onTap: () {
                            _tabController.animateTo(1);
                            _loadTab(1);
                          },
                        ),
                        const SizedBox(width: 24),
                        _StatItem(
                          label: 'Seguindo',
                          value: user.followingCount,
                          icon: Icons.person_add,
                          onTap: () {
                            _tabController.animateTo(2);
                            _loadTab(2);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Follow button (only if not own profile)
                    if (provider.isOwnProfile != true)
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _isToggling ? null : _toggleFollow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: provider.isFollowingVisited
                                ? AppTheme.surfaceSlate
                                : AppTheme.manaViolet,
                            foregroundColor: AppTheme.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                              side: provider.isFollowingVisited
                                  ? const BorderSide(
                                      color: AppTheme.outlineMuted)
                                  : BorderSide.none,
                            ),
                          ),
                          icon: _isToggling
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textPrimary,
                                  ),
                                )
                              : Icon(
                                  provider.isFollowingVisited
                                      ? Icons.person_remove
                                      : Icons.person_add,
                                  size: 18,
                                ),
                          label: Text(
                            provider.isFollowingVisited
                                ? 'Deixar de seguir'
                                : 'Seguir',
                            style: const TextStyle(fontSize: AppTheme.fontMd),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // === Tabs ===
              Container(
                color: AppTheme.surfaceSlate2,
                child: TabBar(
                  controller: _tabController,
                  onTap: _loadTab,
                  indicatorColor: AppTheme.manaViolet,
                  labelColor: AppTheme.textPrimary,
                  unselectedLabelColor: AppTheme.textSecondary,
                  tabs: [
                    Tab(
                        text:
                            'Decks (${provider.visitedUserDecks.length})'),
                    const Tab(text: 'Seguidores'),
                    const Tab(text: 'Seguindo'),
                    const Tab(text: 'Fichário'),
                  ],
                ),
              ),
              // === Tab content ===
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _DecksTab(decks: provider.visitedUserDecks),
                    _UsersListTab(
                      users: provider.followers,
                      isLoading: provider.isLoadingFollowers,
                      emptyMessage: 'Nenhum seguidor ainda',
                      hasMore: provider.hasMoreFollowers,
                      onLoadMore: () => provider.fetchFollowers(widget.userId),
                    ),
                    _UsersListTab(
                      users: provider.following,
                      isLoading: provider.isLoadingFollowing,
                      emptyMessage: 'Não segue ninguém ainda',
                      hasMore: provider.hasMoreFollowing,
                      onLoadMore: () => provider.fetchFollowing(widget.userId),
                    ),
                    Consumer<BinderProvider>(
                      builder: (context, binder, _) {
                        return _PublicBinderTab(
                          items: binder.publicItems,
                          isLoading: binder.isLoadingPublic,
                          hasMore: binder.hasMorePublic,
                          onLoadMore: () =>
                              binder.fetchPublicBinder(widget.userId),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================================
// Stat Widget
// =====================================================================

class _StatItem extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: AppTheme.loomCyan, size: 20),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: AppTheme.fontXl,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: AppTheme.fontSm,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Decks Tab
// =====================================================================

class _DecksTab extends StatelessWidget {
  final List<PublicDeckSummary> decks;

  const _DecksTab({required this.decks});

  @override
  Widget build(BuildContext context) {
    if (decks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'Nenhum deck público',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontLg),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: decks.length,
      itemBuilder: (context, index) {
        final deck = decks[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: AppTheme.surfaceSlate,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CommunityDeckDetailScreen(deckId: deck.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Commander image
                  CachedCardImage(
                    imageUrl: deck.commanderImageUrl,
                    width: 50,
                    height: 70,
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
                            fontSize: AppTheme.fontMd,
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
                                color: AppTheme.manaViolet.withValues(
                                    alpha: 0.2),
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
                                  color: AppTheme.mythicGold.withValues(
                                      alpha: 0.8)),
                              const SizedBox(width: 2),
                              Text(
                                '${deck.synergyScore}%',
                                style: TextStyle(
                                  color: AppTheme.mythicGold.withValues(
                                      alpha: 0.8),
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
      },
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// =====================================================================
// Users List Tab (Followers / Following)
// =====================================================================

class _UsersListTab extends StatefulWidget {
  final List<PublicUser> users;
  final bool isLoading;
  final String emptyMessage;
  final bool hasMore;
  final VoidCallback? onLoadMore;

  const _UsersListTab({
    required this.users,
    required this.isLoading,
    required this.emptyMessage,
    this.hasMore = false,
    this.onLoadMore,
  });

  @override
  State<_UsersListTab> createState() => _UsersListTabState();
}

class _UsersListTabState extends State<_UsersListTab> {
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
      if (widget.hasMore && !widget.isLoading) {
        widget.onLoadMore?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.users.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.manaViolet),
      );
    }

    if (widget.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              widget.emptyMessage,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontLg),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: widget.users.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= widget.users.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.manaViolet),
            ),
          );
        }
        final user = widget.users[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: AppTheme.surfaceSlate,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 20,
              backgroundColor:
                  AppTheme.manaViolet.withValues(alpha: 0.3),
              backgroundImage: user.avatarUrl != null
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: user.avatarUrl == null
                  ? Text(
                      user.username[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.manaViolet,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            title: Text(
              user.displayName ?? user.username,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '@${user.username}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: AppTheme.fontSm,
              ),
            ),
            trailing: const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: user.id),
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
// Public Binder Tab (4ª tab)
// =====================================================================

class _PublicBinderTab extends StatefulWidget {
  final List<BinderItem> items;
  final bool isLoading;
  final bool hasMore;
  final VoidCallback? onLoadMore;

  const _PublicBinderTab({
    required this.items,
    required this.isLoading,
    this.hasMore = false,
    this.onLoadMore,
  });

  @override
  State<_PublicBinderTab> createState() => _PublicBinderTabState();
}

class _PublicBinderTabState extends State<_PublicBinderTab> {
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
      if (widget.hasMore && !widget.isLoading) {
        widget.onLoadMore?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.manaViolet),
      );
    }

    if (widget.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.collections_bookmark,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma carta disponível',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontLg),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= widget.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.manaViolet),
            ),
          );
        }
        final item = widget.items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: AppTheme.surfaceSlate,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CachedCardImage(
                  imageUrl: item.cardImageUrl,
                  width: 42,
                  height: 58,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                const SizedBox(width: 10),
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
                          _binderBadge('×${item.quantity}', AppTheme.manaViolet),
                          const SizedBox(width: 4),
                          _binderBadge(item.condition, _condColor(item.condition)),
                          if (item.isFoil) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.auto_awesome,
                                size: 12,
                                color: AppTheme.mythicGold.withValues(alpha: 0.8)),
                          ],
                          if (item.forTrade) ...[
                            const SizedBox(width: 4),
                            _binderStatusTag('Troca', AppTheme.loomCyan),
                          ],
                          if (item.forSale) ...[
                            const SizedBox(width: 4),
                            _binderStatusTag('Venda', AppTheme.mythicGold),
                          ],
                        ],
                      ),
                      if (item.price != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'R\$ ${item.price!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppTheme.mythicGold,
                              fontSize: AppTheme.fontSm,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _binderBadge(String text, Color color) {
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

  Widget _binderStatusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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

  Color _condColor(String c) {
    return AppTheme.conditionColor(c);
  }
}
