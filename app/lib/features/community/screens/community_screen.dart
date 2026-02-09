import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/community_provider.dart';
import 'community_deck_detail_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommunityProvider>().fetchPublicDecks(reset: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Comunidade'),
        backgroundColor: AppTheme.surfaceSlate2,
      ),
      body: Column(
        children: [
          // Search bar + filters
          Container(
            padding: const EdgeInsets.all(12),
            color: AppTheme.surfaceSlate2,
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar decks públicos...',
                    hintStyle:
                        const TextStyle(color: AppTheme.textSecondary),
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
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
                const SizedBox(height: 8),
                // Format chips
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildFormatChip(null, 'Todos'),
                      ..._formats
                          .map((f) => _buildFormatChip(f, _capitalize(f))),
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
                    child: CircularProgressIndicator(
                        color: AppTheme.manaViolet),
                  );
                }

                if (provider.errorMessage != null &&
                    provider.decks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off,
                            size: 48, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(provider.errorMessage!,
                            style: const TextStyle(
                                color: AppTheme.textSecondary)),
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
                              color: AppTheme.textSecondary, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Compartilhe seus decks para aparecerem aqui!',
                          style: TextStyle(
                              color: AppTheme.textSecondary.withValues(
                                  alpha: 0.7),
                              fontSize: 13),
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
                          builder: (_) => CommunityDeckDetailScreen(
                              deckId: deck.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatChip(String? format, String label) {
    final isSelected = _selectedFormat == format;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label,
            style: TextStyle(
              color:
                  isSelected ? AppTheme.backgroundAbyss : AppTheme.textPrimary,
              fontSize: 12,
            )),
        selected: isSelected,
        selectedColor: AppTheme.loomCyan,
        backgroundColor: AppTheme.surfaceSlate,
        checkmarkColor: AppTheme.backgroundAbyss,
        side: BorderSide(
          color:
              isSelected ? AppTheme.loomCyan : AppTheme.outlineMuted,
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
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Commander image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: deck.commanderImageUrl != null
                    ? Image.network(
                        deck.commanderImageUrl!,
                        width: 56,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 78,
                          color: AppTheme.surfaceSlate2,
                          child: const Icon(Icons.style,
                              color: AppTheme.textSecondary),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 78,
                        color: AppTheme.surfaceSlate2,
                        child: const Icon(Icons.style,
                            color: AppTheme.textSecondary),
                      ),
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
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 14,
                            color: AppTheme.textSecondary.withValues(
                                alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(
                          deck.ownerUsername ?? 'Anônimo',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withValues(
                                alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.manaViolet.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _capitalize(deck.format),
                            style: const TextStyle(
                              color: AppTheme.manaViolet,
                              fontSize: 10,
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
                            fontSize: 12,
                          ),
                        ),
                        if (deck.synergyScore != null) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: AppTheme.mythicGold.withValues(
                                alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${deck.synergyScore}%',
                            style: TextStyle(
                              color: AppTheme.mythicGold.withValues(
                                  alpha: 0.8),
                              fontSize: 12,
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
                          fontSize: 11,
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
