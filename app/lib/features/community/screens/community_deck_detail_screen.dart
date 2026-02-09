import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../decks/providers/deck_provider.dart';
import '../../social/screens/user_profile_screen.dart';
import '../providers/community_provider.dart';

class CommunityDeckDetailScreen extends StatefulWidget {
  final String deckId;

  const CommunityDeckDetailScreen({super.key, required this.deckId});

  @override
  State<CommunityDeckDetailScreen> createState() =>
      _CommunityDeckDetailScreenState();
}

class _CommunityDeckDetailScreenState
    extends State<CommunityDeckDetailScreen> {
  Map<String, dynamic>? _deckData;
  bool _isLoading = true;
  String? _error;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    _loadDeck();
  }

  Future<void> _loadDeck() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final data = await context
        .read<CommunityProvider>()
        .fetchPublicDeckDetails(widget.deckId);

    if (mounted) {
      setState(() {
        _deckData = data;
        _isLoading = false;
        _error = data == null ? 'Não foi possível carregar o deck' : null;
      });
    }
  }

  Future<void> _copyDeck() async {
    setState(() => _isCopying = true);

    final result =
        await context.read<DeckProvider>().copyPublicDeck(widget.deckId);

    if (!mounted) return;
    setState(() => _isCopying = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Deck copiado para sua coleção! 🎉'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Erro ao copiar deck'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: Text(_deckData?['name'] ?? 'Deck Público'),
        backgroundColor: AppTheme.surfaceSlate2,
        actions: [
          if (_deckData != null)
            IconButton(
              icon: _isCopying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.loomCyan),
                    )
                  : const Icon(Icons.copy, color: AppTheme.loomCyan),
              tooltip: 'Copiar para meus decks',
              onPressed: _isCopying ? null : _copyDeck,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.manaViolet),
      );
    }

    if (_error != null) {
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
              onPressed: _loadDeck,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final deck = _deckData!;
    final commander = (deck['commander'] as List?) ?? [];
    final mainBoard =
        (deck['main_board'] as Map<String, dynamic>?) ?? {};
    final stats = (deck['stats'] as Map<String, dynamic>?) ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSlate,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.outlineMuted),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        deck['name'] ?? '',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            AppTheme.manaViolet.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _capitalize(deck['format'] ?? ''),
                        style: const TextStyle(
                          color: AppTheme.manaViolet,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: deck['owner_id'] != null
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(
                                      userId: deck['owner_id'] as String),
                                ),
                              );
                            }
                          : null,
                      child: Text(
                        deck['owner_username'] ?? 'Anônimo',
                        style: TextStyle(
                          color: AppTheme.loomCyan,
                          fontSize: 13,
                          decoration: deck['owner_id'] != null
                              ? TextDecoration.underline
                              : null,
                          decorationColor: AppTheme.loomCyan,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${stats['total_cards'] ?? 0} cartas',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (deck['description'] != null &&
                    (deck['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    deck['description'],
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (deck['synergy_score'] != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 16, color: AppTheme.mythicGold),
                      const SizedBox(width: 4),
                      Text(
                        'Sinergia: ${deck['synergy_score']}%',
                        style: const TextStyle(
                          color: AppTheme.mythicGold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Copy button prominent
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCopying ? null : _copyDeck,
              icon: _isCopying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.file_copy_outlined),
              label: Text(_isCopying
                  ? 'Copiando...'
                  : 'Copiar Deck para minha coleção'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.loomCyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Commander section
          if (commander.isNotEmpty) ...[
            const Text(
              '🏆 Comandante',
              style: TextStyle(
                color: AppTheme.mythicGold,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            ...commander.map((card) => _buildCardTile(
                card as Map<String, dynamic>)),
            const SizedBox(height: 16),
          ],

          // Main board sections
          ...mainBoard.entries.map((entry) {
            final type = entry.key;
            final cards = entry.value as List;
            final totalQty = cards.fold<int>(
                0, (sum, c) => sum + ((c as Map)['quantity'] as int));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$type ($totalQty)',
                  style: const TextStyle(
                    color: AppTheme.loomCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                ...cards.map((card) =>
                    _buildCardTile(card as Map<String, dynamic>)),
                const SizedBox(height: 12),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCardTile(Map<String, dynamic> card) {
    final qty = card['quantity'] as int? ?? 1;
    final name = card['name'] as String? ?? '';
    final typeLine = card['type_line'] as String? ?? '';
    final manaCost = card['mana_cost'] as String? ?? '';
    final imageUrl = card['image_url'] as String?;

    return Card(
      color: AppTheme.surfaceSlate2,
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        dense: true,
        leading: imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  imageUrl,
                  width: 32,
                  height: 45,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 32,
                    height: 45,
                    child: Icon(Icons.image_not_supported,
                        size: 16, color: AppTheme.textSecondary),
                  ),
                ),
              )
            : null,
        title: Text(
          '${qty}x $name',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          typeLine,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        trailing: manaCost.isNotEmpty
            ? Text(
                manaCost,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              )
            : null,
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
