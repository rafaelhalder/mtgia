import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' show Share;
import '../providers/deck_provider.dart';
import '../models/deck_card_item.dart';
import '../models/deck_details.dart';
import '../../cards/providers/card_provider.dart';
import '../widgets/deck_analysis_tab.dart';
import '../widgets/deck_progress_indicator.dart';
import '../../auth/providers/auth_provider.dart';

class DeckDetailsScreen extends StatefulWidget {
  final String deckId;

  const DeckDetailsScreen({super.key, required this.deckId});

  @override
  State<DeckDetailsScreen> createState() => _DeckDetailsScreenState();
}

class _DeckDetailsScreenState extends State<DeckDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _pricing;
  bool _isPricingLoading = false;
  final Set<String> _hiddenCardIds = <String>{};
  bool _pricingAutoLoaded = false;
  bool _validationAutoLoaded = false;
  bool _isValidating = false;
  Map<String, dynamic>? _validationResult;
  Set<String> _invalidCardNames = {};

  /// Extrai o nome da carta problemática do resultado da validação.
  /// Usa o campo estruturado 'card_name' quando disponível,
  /// senão faz fallback via regex na mensagem de erro.
  Set<String> _extractInvalidCardNames(Map<String, dynamic>? result) {
    if (result == null || result['ok'] == true) return {};
    final cardName = result['card_name'] as String?;
    if (cardName != null && cardName.isNotEmpty) return {cardName};
    // Fallback: extrair nome entre aspas da mensagem de erro
    final error = result['error'] as String?;
    if (error == null) return {};
    final matches = RegExp(r'"([^"]+)"').allMatches(error);
    return matches.map((m) => m.group(1)!).toSet();
  }

  /// Verifica se uma carta está na lista de cartas inválidas.
  bool _isCardInvalid(DeckCardItem card) {
    if (_invalidCardNames.isEmpty) return false;
    return _invalidCardNames.any(
      (name) => name.toLowerCase() == card.name.toLowerCase(),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeckProvider>().fetchDeckDetails(widget.deckId);
    });
  }

  Map<String, dynamic>? _pricingFromDeck(DeckDetails deck) {
    if (deck.pricingTotal == null) return null;
    return {
      'deck_id': deck.id,
      'currency': deck.pricingCurrency ?? 'USD',
      'estimated_total_usd': deck.pricingTotal,
      'missing_price_cards': deck.pricingMissingCards ?? 0,
      'items': const [],
      'pricing_updated_at': deck.pricingUpdatedAt?.toIso8601String(),
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do Deck'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: 'Otimizar deck',
            onPressed: () => _showOptimizationOptions(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              switch (value) {
                case 'paste':
                  _showImportListDialog(context);
                  break;
                case 'validate':
                  _validateDeck();
                  break;
                case 'toggle_public':
                  _togglePublic();
                  break;
                case 'share':
                  _shareDeck();
                  break;
                case 'export':
                  _exportDeckAsText();
                  break;
              }
            },
            itemBuilder: (context) {
              final deck = context.read<DeckProvider>().selectedDeck;
              final isPublic = deck?.isPublic ?? false;
              return [
                const PopupMenuItem(
                  value: 'paste',
                  child: ListTile(
                    leading: Icon(Icons.content_paste_go),
                    title: Text('Colar lista de cartas'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'validate',
                  child: ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text('Validar Deck'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle_public',
                  child: ListTile(
                    leading: Icon(
                      isPublic ? Icons.lock_outline : Icons.public,
                    ),
                    title: Text(
                      isPublic ? 'Tornar Privado' : 'Tornar Público',
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Compartilhar'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('Exportar como texto'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ];
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Visão Geral'),
            Tab(text: 'Cartas'),
            Tab(text: 'Análise'),
          ],
        ),
      ),
      floatingActionButton: _buildAddCardsMenu(context),
      body: Consumer<DeckProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.detailsErrorMessage != null) {
            final isUnauthorized = provider.detailsStatusCode == 401;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(provider.detailsErrorMessage!),
                  const SizedBox(height: 16),
                  if (isUnauthorized)
                    ElevatedButton(
                      onPressed: () async {
                        await context.read<AuthProvider>().logout();
                        if (!context.mounted) return;
                        context.go('/login');
                      },
                      child: const Text('Fazer login novamente'),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => provider.fetchDeckDetails(widget.deckId),
                      child: const Text('Tentar Novamente'),
                    ),
                ],
              ),
            );
          }

          final deck = provider.selectedDeck;
          if (deck == null) {
            return const Center(child: Text('Deck não encontrado'));
          }
          _pricing ??= _pricingFromDeck(deck);

          // Auto-load pricing when deck is ready
          if (!_pricingAutoLoaded && !_isPricingLoading) {
            _pricingAutoLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadPricing(force: false);
            });
          }

          // Auto-validate deck when ready
          if (!_validationAutoLoaded && !_isValidating) {
            _validationAutoLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _autoValidateDeck();
            });
          }

          final format = deck.format.toLowerCase();
          final isCommanderFormat = format == 'commander' || format == 'brawl';
          final maxCards =
              format == 'commander' ? 100 : (format == 'brawl' ? 60 : null);
          final totalCards = _totalCards(deck);

          return TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Visão Geral
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.name, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Chip(label: Text(deck.format.toUpperCase())),
                        const SizedBox(width: 8),
                        if (_isValidating)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (_validationResult != null)
                          InkWell(
                            onTap: () {
                              final ok = _validationResult!['ok'] == true;
                              if (ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ Deck válido para o formato!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                final msg = _validationResult!['error']?.toString()
                                    ?? 'Deck não está completo ou válido para o formato';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('⚠️ $msg'),
                                    backgroundColor: theme.colorScheme.error,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                                // Navega para a aba Cartas para destacar a carta problemática
                                if (_invalidCardNames.isNotEmpty) {
                                  _tabController.animateTo(1);
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _validationResult!['ok'] == true
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : theme.colorScheme.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _validationResult!['ok'] == true
                                      ? const Color(0xFF10B981)
                                      : theme.colorScheme.error,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _validationResult!['ok'] == true
                                        ? Icons.verified
                                        : Icons.warning_amber_rounded,
                                    size: 14,
                                    color: _validationResult!['ok'] == true
                                        ? const Color(0xFF10B981)
                                        : theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _validationResult!['ok'] == true
                                        ? 'Válido'
                                        : 'Inválido',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: _validationResult!['ok'] == true
                                          ? const Color(0xFF10B981)
                                          : theme.colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Visibility indicator
                    InkWell(
                      onTap: _togglePublic,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: deck.isPublic
                              ? const Color(0xFF06B6D4).withValues(alpha: 0.15)
                              : const Color(0xFF64748B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: deck.isPublic
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFF64748B),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              deck.isPublic ? Icons.public : Icons.lock_outline,
                              size: 14,
                              color: deck.isPublic
                                  ? const Color(0xFF06B6D4)
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              deck.isPublic ? 'Público' : 'Privado',
                              style: TextStyle(
                                color: deck.isPublic
                                    ? const Color(0xFF06B6D4)
                                    : const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DeckProgressIndicator(
                      deck: deck,
                      totalCards: totalCards,
                      maxCards: maxCards,
                      hasCommander: deck.commander.isNotEmpty,
                      onTap:
                          () => _tabController.animateTo(
                            1,
                          ), // Vai para tab de cartas
                    ),
                    const SizedBox(height: 12),
                    _PricingRow(
                      pricing: _pricing,
                      isLoading: _isPricingLoading,
                      onForceRefresh: () => _loadPricing(force: true),
                      onShowDetails: _showPricingDetails,
                    ),
                    if (isCommanderFormat && deck.commander.isEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.25,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.errorContainer,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Selecione um comandante para aplicar regras e filtros de identidade de cor.',
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  () => context.go(
                                    '/decks/${widget.deckId}/search',
                                  ),
                              child: const Text('Selecionar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Descrição editável
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Descrição',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              () => _showEditDescriptionDialog(
                                context,
                                deck.description,
                              ),
                          icon: Icon(
                            (deck.description == null ||
                                    deck.description!.trim().isEmpty)
                                ? Icons.add
                                : Icons.edit,
                            size: 16,
                          ),
                          label: Text(
                            (deck.description == null ||
                                    deck.description!.trim().isEmpty)
                                ? 'Adicionar'
                                : 'Editar',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (deck.description != null &&
                        deck.description!.trim().isNotEmpty)
                      InkWell(
                        onTap:
                            () => _showEditDescriptionDialog(
                              context,
                              deck.description,
                            ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            deck.description!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap:
                            () =>
                                _showEditDescriptionDialog(context, null),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.2,
                              ),
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Text(
                            'Toque para adicionar uma descrição ao deck...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (deck.commander.isNotEmpty) ...[
                      Text('Comandante', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...deck.commander.map(
                        (c) => Card(
                          shape: _isCardInvalid(c)
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: theme.colorScheme.error,
                                    width: 2,
                                  ),
                                )
                              : null,
                          color: _isCardInvalid(c)
                              ? theme.colorScheme.error.withValues(alpha: 0.08)
                              : null,
                          child: Stack(
                            children: [
                              ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 44,
                                height: 62,
                                child:
                                    c.imageUrl != null
                                        ? Image.network(
                                          c.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (_, __, ___) => Container(
                                                color: Colors.grey[800],
                                                child: const Icon(
                                                  Icons.image_not_supported,
                                                  size: 20,
                                                ),
                                              ),
                                        )
                                        : Container(
                                          color: Colors.grey[800],
                                          child: const Icon(
                                            Icons.image_not_supported,
                                            size: 20,
                                          ),
                                        ),
                              ),
                            ),
                            title: Text(c.name),
                            subtitle: Text(c.typeLine),
                            onTap: () => _showCardDetails(context, c),
                          ),
                              if (_isCardInvalid(c))
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Inválida',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed:
                              () => context.go(
                                '/decks/${widget.deckId}/search?mode=commander',
                              ),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Trocar comandante'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Estratégia',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showOptimizationOptions(context),
                          icon: const Icon(Icons.tune, size: 18),
                          label: Text(
                            (deck.archetype == null ||
                                    deck.archetype!.trim().isEmpty)
                                ? 'Definir'
                                : 'Alterar',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _showOptimizationOptions(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              (deck.archetype == null ||
                                      deck.archetype!.trim().isEmpty)
                                  ? theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5)
                                  : theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                (deck.archetype == null ||
                                        deck.archetype!.trim().isEmpty)
                                    ? theme.colorScheme.outline.withValues(
                                      alpha: 0.3,
                                    )
                                    : theme.colorScheme.primary.withValues(
                                      alpha: 0.4,
                                    ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (deck.archetype == null ||
                                      deck.archetype!.trim().isEmpty)
                                  ? Icons.help_outline
                                  : Icons.psychology,
                              color:
                                  (deck.archetype == null ||
                                          deck.archetype!.trim().isEmpty)
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (deck.archetype == null ||
                                            deck.archetype!.trim().isEmpty)
                                        ? 'Não definida'
                                        : deck.archetype!,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          (deck.archetype == null ||
                                                  deck.archetype!
                                                      .trim()
                                                      .isEmpty)
                                              ? theme.colorScheme.outline
                                              : theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    deck.bracket != null
                                        ? 'Bracket: ${deck.bracket} • ${_bracketLabel(deck.bracket!)}'
                                        : 'Bracket não definido',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: theme.colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (deck.archetype == null ||
                        deck.archetype!.trim().isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Toque para definir a estratégia do deck',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Tab 2: Cartas
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (maxCards != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DeckProgressIndicator(
                        deck: deck,
                        totalCards: totalCards,
                        maxCards: maxCards,
                        hasCommander: deck.commander.isNotEmpty,
                      ),
                    ),
                  if (_invalidCardNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: theme.colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_invalidCardNames.length} carta(s) com problema: ${_invalidCardNames.join(", ")}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ...deck.mainBoard.entries.map((entry) {
                    // Ordena cartas inválidas para o topo do grupo
                    final sortedCards = List<DeckCardItem>.from(entry.value);
                    if (_invalidCardNames.isNotEmpty) {
                      sortedCards.sort((a, b) {
                        final aInvalid = _isCardInvalid(a) ? 0 : 1;
                        final bInvalid = _isCardInvalid(b) ? 0 : 1;
                        return aInvalid.compareTo(bInvalid);
                      });
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '${entry.key} (${entry.value.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...sortedCards
                            .where((card) => !_hiddenCardIds.contains(card.id))
                            .map(
                              (card) => Dismissible(
                                key: ValueKey('deck-card-${card.id}'),
                                direction: DismissDirection.horizontal,
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text(
                                        'Editar',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Excluir',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.delete, color: Colors.white),
                                    ],
                                  ),
                                ),
                                confirmDismiss: (direction) async {
                                  if (direction ==
                                      DismissDirection.startToEnd) {
                                    await _showEditCardDialog(
                                      context,
                                      card,
                                      deckFormat: deck.format,
                                    );
                                    return false;
                                  }

                                  if (direction ==
                                      DismissDirection.endToStart) {
                                    final confirmed = await _confirmRemoveCard(
                                      context,
                                      card,
                                    );
                                    if (confirmed != true) return false;

                                    if (mounted) {
                                      setState(
                                        () => _hiddenCardIds.add(card.id),
                                      );
                                    }

                                    try {
                                      await context
                                          .read<DeckProvider>()
                                          .removeCardFromDeck(
                                            deckId: widget.deckId,
                                            cardId: card.id,
                                          );
                                      if (!mounted) return true;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Carta removida: ${card.name}',
                                          ),
                                          backgroundColor:
                                              theme.colorScheme.primary,
                                        ),
                                      );
                                      return true;
                                    } catch (e) {
                                      if (mounted) {
                                        setState(
                                          () => _hiddenCardIds.remove(card.id),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao remover: $e',
                                            ),
                                            backgroundColor:
                                                theme.colorScheme.error,
                                          ),
                                        );
                                      }
                                      return false;
                                    }
                                  }

                                  return false;
                                },
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: _isCardInvalid(card)
                                      ? RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: theme.colorScheme.error,
                                            width: 2,
                                          ),
                                        )
                                      : null,
                                  color: _isCardInvalid(card)
                                      ? theme.colorScheme.error.withValues(alpha: 0.08)
                                      : null,
                                  child: Stack(
                                    children: [
                                      ListTile(
                                    contentPadding: const EdgeInsets.all(8),
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: SizedBox(
                                        width: 40,
                                        height: 56,
                                        child:
                                            card.imageUrl != null
                                                ? Image.network(
                                                  card.imageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (_, __, ___) => Container(
                                                        color: Colors.grey[800],
                                                        child: const Icon(
                                                          Icons
                                                              .image_not_supported,
                                                          size: 20,
                                                        ),
                                                      ),
                                                )
                                                : Container(
                                                  color: Colors.grey[800],
                                                  child: const Icon(
                                                    Icons.image_not_supported,
                                                    size: 20,
                                                  ),
                                                ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                theme
                                                    .colorScheme
                                                    .primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            '${card.quantity}x',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      theme
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            card.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          card.typeLine,
                                          style: theme.textTheme.bodySmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            _ManaCostRow(cost: card.manaCost),
                                            const SizedBox(width: 8),
                                            if (card.setCode.isNotEmpty)
                                              Text(
                                                card.setCode.toUpperCase(),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          theme
                                                              .colorScheme
                                                              .outline,
                                                    ),
                                              ),
                                            if (card.condition != CardCondition.nm) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _conditionColor(card.condition)
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: _conditionColor(
                                                      card.condition,
                                                    ),
                                                    width: 0.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  card.condition.code,
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                        fontSize: 9,
                                                        color: _conditionColor(
                                                          card.condition,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    onTap:
                                        () => _showCardDetails(context, card),
                                  ),
                                      if (_isCardInvalid(card))
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.error,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.warning_amber_rounded,
                                                  size: 12,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'Inválida',
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),
                ],
              ),

              // Tab 3: Análise
              DeckAnalysisTab(deck: deck),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditDescriptionDialog(
    BuildContext context,
    String? currentDescription,
  ) async {
    final controller = TextEditingController(
      text: currentDescription?.trim() ?? '',
    );
    final theme = Theme.of(context);

    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Descrição do Deck'),
            content: TextField(
              controller: controller,
              maxLines: 5,
              autofocus: true,
              decoration: InputDecoration(
                hintText:
                    'Descreva a estratégia, tema ou objetivo do deck...\n\nEx: Deck focado em tokens e sacrifício com sinergia Orzhov.',
                hintMaxLines: 5,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Salvar'),
              ),
            ],
          ),
    );

    if (result == null || !mounted) return;

    // Update via PUT
    try {
      final provider = context.read<DeckProvider>();
      final response = await provider.updateDeckDescription(
        deckId: widget.deckId,
        description: result,
      );
      if (!mounted) return;

      if (response) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isEmpty
                  ? 'Descrição removida'
                  : 'Descrição atualizada',
            ),
            backgroundColor: theme.colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  /// Menu expansível para adicionar cartas (busca ou scanner)
  Widget _buildAddCardsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'search':
            context.go('/decks/${widget.deckId}/search');
            break;
          case 'scan':
            context.go('/decks/${widget.deckId}/scan');
            break;
        }
      },
      offset: const Offset(0, -120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'search',
          child: ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Buscar Carta'),
            subtitle: const Text('Pesquisar por nome'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'scan',
          child: ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Escanear Carta'),
            subtitle: const Text('Usar câmera (OCR)'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
      child: FloatingActionButton.extended(
        onPressed: null, // O PopupMenuButton cuida do tap
        icon: const Icon(Icons.add),
        label: const Text('Adicionar Cartas'),
      ),
    );
  }

  /// Validação silenciosa auto-triggered (sem loading dialog, sem snackbar).
  Future<void> _autoValidateDeck() async {
    if (_isValidating) return;
    setState(() => _isValidating = true);
    try {
      final res = await context.read<DeckProvider>().validateDeck(widget.deckId);
      if (!mounted) return;
      setState(() {
        _validationResult = res;
        _invalidCardNames = _extractInvalidCardNames(res);
      });
    } catch (e) {
      if (!mounted) return;
      final errorResult = {
        'ok': false,
        'error': e.toString().replaceFirst('Exception: ', ''),
      };
      setState(() {
        _validationResult = errorResult;
        _invalidCardNames = _extractInvalidCardNames(errorResult);
      });
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  // ───── Social / Sharing ─────

  Future<void> _togglePublic() async {
    final provider = context.read<DeckProvider>();
    final deck = provider.selectedDeck;
    if (deck == null) return;

    final newState = !deck.isPublic;
    final success =
        await provider.togglePublic(deck.id, isPublic: newState);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (newState
                  ? 'Deck agora é público! 🌍'
                  : 'Deck agora é privado 🔒')
              : 'Erro ao alterar visibilidade',
        ),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _shareDeck() async {
    final provider = context.read<DeckProvider>();
    final result = await provider.exportDeckAsText(widget.deckId);

    if (!mounted) return;

    if (result.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'].toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final text = result['text'] as String? ?? '';
    await Share.share(text);
  }

  Future<void> _exportDeckAsText() async {
    final provider = context.read<DeckProvider>();
    final result = await provider.exportDeckAsText(widget.deckId);

    if (!mounted) return;

    if (result.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'].toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final text = result['text'] as String? ?? '';
    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lista de cartas copiada para a área de transferência! 📋'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _validateDeck() async {
    final provider = context.read<DeckProvider>();
    final deckId = widget.deckId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await provider.validateDeck(deckId);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _validationResult = res;
        _invalidCardNames = _extractInvalidCardNames(res);
      });

      final ok = res['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '✅ Deck válido!' : 'Deck inválido'),
          backgroundColor:
              ok ? Colors.green : Theme.of(context).colorScheme.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Deck inválido'),
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    }
  }

  void _showCardDetails(BuildContext context, DeckCardItem card) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (card.imageUrl != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: AspectRatio(
                        aspectRatio: 0.714, // MTG card ratio ~ 2.5"x3.5"
                        child: Image.network(
                          card.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => Container(
                                color: Colors.grey[900],
                                child: const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 64,
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (card.manaCost != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Custo: ',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              _ManaCostRow(cost: card.manaCost),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          card.typeLine,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[400],
                          ),
                        ),
                        if ((card.setName ?? '').trim().isNotEmpty ||
                            (card.setReleaseDate ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            [
                              if ((card.setName ?? '').trim().isNotEmpty)
                                card.setName!,
                              if ((card.setReleaseDate ?? '').trim().isNotEmpty)
                                card.setReleaseDate!,
                            ].join(' • '),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[500]),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed:
                                  () => _showEditionPicker(context, card),
                              icon: const Icon(Icons.collections_bookmark),
                              label: const Text('Trocar edição'),
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _showAiExplanation(context, card),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Explicar',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (card.oracleText != null) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          _OracleText(card.oracleText!),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _showAiExplanation(
    BuildContext context,
    DeckCardItem card,
  ) async {
    // Mostra loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Chama a API
      // Precisamos do CardProvider aqui. Como DeckDetailsScreen não tem CardProvider diretamente no build,
      // vamos usar o context.read. Certifique-se que CardProvider está disponível na árvore (está no main.dart).
      // Importante: Usar o context do widget pai, não do dialog de loading.
      if (!context.mounted) return;
      final explanation = await context.read<CardProvider>().explainCard(card);

      // Fecha loading
      if (context.mounted) {
        Navigator.pop(context); // Fecha o loading
      }

      if (!context.mounted) return;

      // Mostra resultado
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Análise: ${card.name}')),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(
                  explanation ?? 'Não foi possível gerar uma explicação.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi'),
                ),
              ],
            ),
      );
    } catch (e) {
      // Garante que o loading fecha em caso de erro
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao explicar carta: $e')));
      }
    }
  }

  void _showOptimizationOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder:
                (context, scrollController) => _OptimizationSheet(
                  deckId: widget.deckId,
                  scrollController: scrollController,
                ),
          ),
    );
  }

  Future<void> _showEditionPicker(
    BuildContext context,
    DeckCardItem card,
  ) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edições disponíveis',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(card.name, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: context.read<CardProvider>().fetchPrintingsByName(
                    card.name,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Erro ao buscar edições: ${snapshot.error}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }
                    final list = snapshot.data ?? const [];
                    if (list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nenhuma edição encontrada no banco.'),
                      );
                    }

                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.6,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final it = list[index];
                          final id = (it['id'] ?? '').toString();
                          final setName =
                              (it['set_name'] ?? it['set_code'] ?? '')
                                  .toString();
                          final date =
                              (it['set_release_date'] ?? '').toString();
                          final rarity = (it['rarity'] ?? '').toString();
                          final price = it['price'];
                          final priceText =
                              (price is num)
                                  ? '\$${price.toStringAsFixed(2)}'
                                  : (price is String && price.trim().isNotEmpty)
                                  ? '\$$price'
                                  : '—';

                          final isSelected = id == card.id;

                          return ListTile(
                            leading:
                                (it['image_url'] != null)
                                    ? Image.network(
                                      it['image_url'],
                                      width: 40,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (_, __, ___) => const Icon(
                                            Icons.image_not_supported,
                                          ),
                                    )
                                    : const Icon(Icons.image_not_supported),
                            title: Text(setName),
                            subtitle: Text(
                              [
                                if (date.isNotEmpty) date,
                                if (rarity.isNotEmpty) rarity,
                              ].join(' • '),
                            ),
                            trailing: Text(
                              priceText,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            selected: isSelected,
                            onTap:
                                isSelected
                                    ? null
                                    : () async {
                                      Navigator.of(sheetContext).pop();
                                      await _replaceEdition(
                                        oldCardId: card.id,
                                        newCardId: id,
                                      );
                                    },
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _replaceEdition({
    required String oldCardId,
    required String newCardId,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await context.read<DeckProvider>().replaceCardEdition(
        deckId: widget.deckId,
        oldCardId: oldCardId,
        newCardId: newCardId,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Edição atualizada.')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<bool?> _confirmRemoveCard(BuildContext context, DeckCardItem card) {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remover carta'),
            content: Text('Remover "${card.name}" do deck?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remover'),
              ),
            ],
          ),
    );
  }

  Future<void> _showEditCardDialog(
    BuildContext context,
    DeckCardItem card, {
    required String deckFormat,
  }) async {
    final theme = Theme.of(context);
    final deckProvider = context.read<DeckProvider>();
    final qtyController = TextEditingController(text: '${card.quantity}');
    final format = deckFormat.toLowerCase();
    final consolidateSameName = format == 'commander' || format == 'brawl';

    bool isSaving = false;
    String? error;
    String selectedCardId = card.id;
    CardCondition selectedCondition = card.condition;

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                title: const Text('Editar carta'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: context
                            .read<CardProvider>()
                            .fetchPrintingsByName(card.name),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('Carregando edições...'),
                            );
                          }
                          if (snapshot.hasError) {
                            return Text(
                              'Erro ao carregar edições: ${snapshot.error}',
                              style: TextStyle(color: theme.colorScheme.error),
                            );
                          }

                          final list = snapshot.data ?? const [];
                          if (list.isEmpty) {
                            return const Text('Nenhuma edição encontrada.');
                          }

                          if (!list.any(
                            (m) => (m['id'] ?? '').toString() == selectedCardId,
                          )) {
                            selectedCardId = list.first['id'].toString();
                          }

                          return InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Edição (set)',
                              border: OutlineInputBorder(),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: selectedCardId,
                                items:
                                    list.map((it) {
                                      final id = (it['id'] ?? '').toString();
                                      final setCode =
                                          (it['set_code'] ?? '')
                                              .toString()
                                              .toUpperCase();
                                      final setName =
                                          (it['set_name'] ?? '').toString();
                                      final date =
                                          (it['set_release_date'] ?? '')
                                              .toString();
                                      final label = [
                                        if (setCode.isNotEmpty) setCode,
                                        if (setName.isNotEmpty) setName,
                                        if (date.isNotEmpty) '($date)',
                                      ].join(' • ');
                                      return DropdownMenuItem<String>(
                                        value: id,
                                        child: Text(
                                          label.isEmpty ? id : label,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                onChanged:
                                    isSaving
                                        ? null
                                        : (v) {
                                          if (v == null) return;
                                          setDialogState(
                                            () => selectedCardId = v,
                                          );
                                        },
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      // --- Condição (TCGPlayer standard) ---
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Condição',
                          border: OutlineInputBorder(),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<CardCondition>(
                            isExpanded: true,
                            value: selectedCondition,
                            items: CardCondition.values.map((c) {
                              return DropdownMenuItem<CardCondition>(
                                value: c,
                                child: Text('${c.code} — ${c.label}'),
                              );
                            }).toList(),
                            onChanged: isSaving
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setDialogState(
                                      () => selectedCondition = v,
                                    );
                                  },
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed:
                        isSaving
                            ? null
                            : () async {
                              final qty = int.tryParse(
                                qtyController.text.trim(),
                              );
                              if (qty == null || qty <= 0) {
                                setDialogState(
                                  () => error = 'Quantidade inválida',
                                );
                                return;
                              }

                              setDialogState(() {
                                isSaving = true;
                                error = null;
                              });

                              try {
                                await deckProvider.updateDeckCardEntry(
                                  deckId: widget.deckId,
                                  oldCardId: card.id,
                                  newCardId: selectedCardId,
                                  quantity: qty,
                                  cardName: card.name,
                                  consolidateSameName: consolidateSameName,
                                  condition: selectedCondition.code,
                                );
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Carta atualizada.'),
                                    backgroundColor: theme.colorScheme.primary,
                                  ),
                                );
                              } catch (e) {
                                if (!ctx.mounted) return;
                                setDialogState(() {
                                  isSaving = false;
                                  error = e.toString().replaceFirst(
                                    'Exception: ',
                                    '',
                                  );
                                });
                              }
                            },
                    child:
                        isSaving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text('Salvar'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _loadPricing({required bool force}) async {
    if (_isPricingLoading) return;
    setState(() => _isPricingLoading = true);
    try {
      final res = await context.read<DeckProvider>().fetchDeckPricing(
        widget.deckId,
        force: force,
      );
      if (!mounted) return;
      setState(() => _pricing = res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isPricingLoading = false);
    }
  }

  Future<void> _showPricingDetails() async {
    // Se não tem items, precisa carregar do endpoint
    final hasItems =
        _pricing != null && (_pricing!['items'] as List?)?.isNotEmpty == true;

    if (!hasItems) {
      // Carregar pricing completo primeiro
      await _loadPricing(force: false);
      if (!mounted) return;
    }

    final pricing = _pricing;
    if (pricing == null) return;
    final items =
        (pricing['items'] as List?)?.whereType<Map>().toList() ?? const [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custo do deck',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Total estimado: \$${(pricing['estimated_total_usd'] ?? 0)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.65,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final it = items[index].cast<String, dynamic>();
                      final name = (it['name'] ?? '').toString();
                      final qty = (it['quantity'] as int?) ?? 0;
                      final setCode = (it['set_code'] ?? '').toString();
                      final unit = it['unit_price_usd'];
                      final unitText =
                          (unit is num) ? '\$${unit.toStringAsFixed(2)}' : '—';
                      final line = it['line_total_usd'];
                      final lineText =
                          (line is num) ? '\$${line.toStringAsFixed(2)}' : '—';

                      return ListTile(
                        dense: true,
                        title: Text('$qty× $name'),
                        subtitle: Text(
                          setCode.isEmpty ? '' : setCode.toUpperCase(),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              lineText,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              unitText,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dialog para importar lista de cartas para o deck existente
  void _showImportListDialog(BuildContext context) {
    final listController = TextEditingController();
    final theme = Theme.of(context);
    final deckId = widget.deckId; // Captura antes do dialog
    final parentContext = context; // Salva contexto pai para snackbar
    bool isImporting = false;
    bool replaceAll = false;
    List<String> notFoundLines = [];
    String? error;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => PopScope(
                  canPop: !isImporting,
                  child: AlertDialog(
                    title: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Importar Lista',
                                style: TextStyle(fontSize: 18),
                              ),
                              Text(
                                'Adicionar cartas de outra fonte',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Opção de substituir tudo
                            Container(
                              decoration: BoxDecoration(
                                color:
                                    replaceAll
                                        ? Colors.orange.withOpacity(0.1)
                                        : theme.colorScheme.surface,
                                border: Border.all(
                                  color:
                                      replaceAll
                                          ? Colors.orange.withOpacity(0.5)
                                          : theme.colorScheme.outline
                                              .withOpacity(0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: CheckboxListTile(
                                value: replaceAll,
                                onChanged: (value) {
                                  setDialogState(
                                    () => replaceAll = value ?? false,
                                  );
                                },
                                title: Row(
                                  children: [
                                    Icon(
                                      replaceAll
                                          ? Icons.swap_horiz
                                          : Icons.add_circle_outline,
                                      size: 18,
                                      color:
                                          replaceAll
                                              ? Colors.orange
                                              : theme.colorScheme.secondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      replaceAll
                                          ? 'Substituir deck'
                                          : 'Adicionar cartas',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  replaceAll
                                      ? 'Remove cartas atuais e usa apenas a nova lista'
                                      : 'Mantém cartas existentes e adiciona as novas',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: replaceAll ? Colors.orange : null,
                                  ),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Campo de texto
                            TextField(
                              controller: listController,
                              decoration: InputDecoration(
                                hintText:
                                    'Cole sua lista de cartas aqui...\n\nFormato: 1 Sol Ring ou 1x Sol Ring',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.4),
                                  fontSize: 12,
                                ),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: theme.colorScheme.surface,
                              ),
                              maxLines: 10,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),

                            // Erro
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.redAccent.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Cartas não encontradas
                            if (notFoundLines.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '⚠️ ${notFoundLines.length} cartas não encontradas:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...notFoundLines
                                        .take(5)
                                        .map(
                                          (line) => Text(
                                            '• $line',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.orange.shade200,
                                            ),
                                          ),
                                        ),
                                    if (notFoundLines.length > 5)
                                      Text(
                                        '... e mais ${notFoundLines.length - 5}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.orange.shade300,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            isImporting ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton.icon(
                        onPressed:
                            isImporting
                                ? null
                                : () async {
                                  if (listController.text.trim().isEmpty) {
                                    setDialogState(
                                      () => error = 'Cole a lista de cartas',
                                    );
                                    return;
                                  }

                                  setDialogState(() {
                                    isImporting = true;
                                    error = null;
                                    notFoundLines = [];
                                  });

                                  final provider =
                                      parentContext.read<DeckProvider>();
                                  final result = await provider
                                      .importListToDeck(
                                        deckId: deckId,
                                        list: listController.text,
                                        replaceAll: replaceAll,
                                      );

                                  if (!ctx.mounted) return;

                                  setDialogState(() {
                                    isImporting = false;
                                    notFoundLines = List<String>.from(
                                      result['not_found_lines'] ?? [],
                                    );
                                  });

                                  if (result['success'] == true) {
                                    Navigator.pop(ctx);

                                    final imported =
                                        result['cards_imported'] ?? 0;
                                    ScaffoldMessenger.of(
                                      parentContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          notFoundLines.isEmpty
                                              ? '$imported cartas importadas!'
                                              : '$imported cartas importadas (${notFoundLines.length} não encontradas)',
                                        ),
                                        backgroundColor:
                                            notFoundLines.isEmpty
                                                ? Theme.of(
                                                  parentContext,
                                                ).colorScheme.primary
                                                : Colors.orange,
                                      ),
                                    );

                                    // Recarrega o deck
                                    provider.fetchDeckDetails(
                                      deckId,
                                      forceRefresh: true,
                                    );
                                  } else {
                                    setDialogState(() {
                                      error =
                                          result['error'] ?? 'Erro ao importar';
                                    });
                                  }
                                },
                        icon:
                            isImporting
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.upload),
                        label: Text(isImporting ? 'Importando...' : 'Importar'),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  final Map<String, dynamic>? pricing;
  final bool isLoading;
  final VoidCallback onForceRefresh;
  final VoidCallback? onShowDetails;

  const _PricingRow({
    required this.pricing,
    required this.isLoading,
    required this.onForceRefresh,
    this.onShowDetails,
  });

  String _formatUpdatedAt(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return 'há ${diff.inMinutes}min';
    if (diff.inDays < 1) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 7) return 'há ${diff.inDays}d';
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = pricing?['estimated_total_usd'];
    final missing = pricing?['missing_price_cards'];
    final updatedAt = pricing?['pricing_updated_at']?.toString();

    String subtitle;
    if (isLoading && total == null) {
      subtitle = 'Calculando...';
    } else if (total is num) {
      subtitle = 'Estimado: \$${total.toStringAsFixed(2)}';
      if (missing is num && missing > 0) {
        subtitle += ' • ${missing.toInt()} sem preço';
      }
      final ago = _formatUpdatedAt(updatedAt);
      if (ago.isNotEmpty) {
        subtitle += ' • $ago';
      }
    } else {
      subtitle = 'Calculando custo...';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_money),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Custo', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
                if (isLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onShowDetails != null && total is num)
            TextButton(
              onPressed: isLoading ? null : onShowDetails,
              child: const Text('Detalhes'),
            ),
          IconButton(
            tooltip: 'Atualizar preços',
            onPressed: isLoading ? null : onForceRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

/// Retorna cor indicativa da condição da carta (TCGPlayer standard).
Color _conditionColor(CardCondition c) {
  switch (c) {
    case CardCondition.nm:
      return const Color(0xFF22C55E); // green
    case CardCondition.lp:
      return const Color(0xFF06B6D4); // cyan
    case CardCondition.mp:
      return const Color(0xFFF59E0B); // amber
    case CardCondition.hp:
      return const Color(0xFFF97316); // orange
    case CardCondition.dmg:
      return const Color(0xFFEF4444); // red
  }
}

class _ManaCostRow extends StatelessWidget {
  final String? cost;
  const _ManaCostRow({this.cost});

  @override
  Widget build(BuildContext context) {
    if (cost == null || cost!.isEmpty) return const SizedBox.shrink();

    // Regex atualizado para capturar tudo dentro de {}, incluindo barras (ex: {2/W})
    final matches = RegExp(r'\{([^\}]+)\}').allMatches(cost!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children:
          matches.map((m) {
            final symbol = m.group(1)!;
            return _ManaSymbol(symbol: symbol);
          }).toList(),
    );
  }
}

int _totalCards(DeckDetails deck) {
  var total = 0;
  for (final c in deck.commander) {
    total += c.quantity;
  }
  for (final list in deck.mainBoard.values) {
    for (final c in list) {
      total += c.quantity;
    }
  }
  return total;
}

String _bracketLabel(int bracket) {
  switch (bracket) {
    case 1:
      return 'Casual';
    case 2:
      return 'Mid-power';
    case 3:
      return 'High-power';
    case 4:
      return 'cEDH';
    default:
      return 'Mid-power';
  }
}

class _ManaSymbol extends StatelessWidget {
  final String symbol;
  const _ManaSymbol({required this.symbol});

  @override
  Widget build(BuildContext context) {
    // Sanitiza o símbolo para corresponder ao nome do arquivo (ex: "2/W" -> "2-W")
    final filename = symbol.replaceAll('/', '-');

    return Container(
      margin: const EdgeInsets.only(right: 2),
      width: 18,
      height: 18,
      child: SvgPicture.asset(
        'assets/symbols/$filename.svg',
        placeholderBuilder: (context) => _FallbackManaSymbol(symbol: symbol),
      ),
    );
  }
}

class _FallbackManaSymbol extends StatelessWidget {
  final String symbol;
  const _FallbackManaSymbol({required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        symbol,
        style: const TextStyle(fontSize: 8, color: Colors.black),
      ),
    );
  }
}

class _OracleText extends StatelessWidget {
  final String text;
  const _OracleText(this.text);

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    // Regex para capturar símbolos de mana entre chaves, ex: {T}, {1}, {U/R}
    final regex = RegExp(r'\{([^\}]+)\}');

    text.splitMapJoin(
      regex,
      onMatch: (Match m) {
        final symbol = m.group(1)!;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.0),
              // Ajusta o tamanho para fluir melhor com o texto
              child: SizedBox(
                width: 16,
                height: 16,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _ManaSymbol(symbol: symbol),
                ),
              ),
            ),
          ),
        );
        return '';
      },
      onNonMatch: (String s) {
        spans.add(TextSpan(text: s));
        return '';
      },
    );

    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        children: spans,
      ),
    );
  }
}

class _OptimizationSheet extends StatefulWidget {
  final String deckId;
  final ScrollController scrollController;

  const _OptimizationSheet({
    required this.deckId,
    required this.scrollController,
  });

  @override
  State<_OptimizationSheet> createState() => _OptimizationSheetState();
}

class _OptimizationSheetState extends State<_OptimizationSheet> {
  late Future<List<Map<String, dynamic>>> _optionsFuture;
  int _selectedBracket = 2;
  bool _showAllStrategies = true;
  bool _keepTheme = true;

  String? get _currentArchetype {
    final deck = context.read<DeckProvider>().selectedDeck;
    return deck?.archetype;
  }

  Future<void> _copyOptimizeDebug({
    required String deckId,
    required String archetype,
    required int bracket,
    required Map<String, dynamic> result,
  }) async {
    final debugJson = {
      'request': {
        'deck_id': deckId,
        'archetype': archetype,
        'bracket': bracket,
        'keep_theme': _keepTheme,
      },
      'response': result,
    };
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(debugJson),
      ),
    );
  }

  Future<void> _applyOptimization(
    BuildContext context,
    String archetype,
  ) async {
    // Controle do estado do loading para garantir fechamento correto
    bool isLoadingDialogOpen = false;
    final deckProvider = context.read<DeckProvider>();

    /// Helper para fechar o dialog de loading de forma segura
    void closeLoadingDialog() {
      if (context.mounted && isLoadingDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        isLoadingDialogOpen = false;
      }
    }

    // 1. Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Gerando sugestões...'),
                  ],
                ),
              ),
            ),
          ),
    );
    isLoadingDialogOpen = true;

    try {
      // 2. Call API to get suggestions
      final result = await deckProvider.optimizeDeck(
        widget.deckId,
        archetype,
        bracket: _selectedBracket,
        keepTheme: _keepTheme,
      );

      closeLoadingDialog();

      if (!context.mounted) return;

      final removals = (result['removals'] as List).cast<String>();
      final additions = (result['additions'] as List).cast<String>();
      final reasoning = result['reasoning'] as String? ?? '';
      final warnings =
          (result['warnings'] is Map)
              ? (result['warnings'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
      final themeInfo =
          (result['theme'] is Map)
              ? (result['theme'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
      final constraints =
          (result['constraints'] is Map)
              ? (result['constraints'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
      final mode = (result['mode'] as String?) ?? 'optimize';
      final additionsDetailed =
          (result['additions_detailed'] as List?)
              ?.whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList() ??
          const <Map<String, dynamic>>[];
      final removalsDetailed =
          (result['removals_detailed'] as List?)
              ?.whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList() ??
          const <Map<String, dynamic>>[];

      if (removals.isEmpty && additions.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma mudança sugerida para aplicar.'),
          ),
        );
        return;
      }

      // 3. Show confirmation dialog with suggestions
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(
                mode == 'complete'
                    ? 'Completar deck ($archetype)'
                    : 'Sugestões para: $archetype',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (constraints['keep_theme'] == true &&
                        themeInfo['theme'] != null) ...[
                      Text(
                        'Tema preservado: ${themeInfo['theme']}',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (reasoning.isNotEmpty) ...[
                      Text(
                        reasoning,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    if (warnings.isNotEmpty) ...[
                      const Text(
                        'Avisos:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (warnings['filtered_by_color_identity'] is Map)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '• Algumas adições foram removidas por estarem fora da identidade do comandante.',
                          ),
                        ),
                      if (warnings['blocked_by_bracket'] is Map)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '• Algumas adições foram bloqueadas por exceder limites do bracket.',
                          ),
                        ),
                      if (warnings['invalid_cards'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '• Algumas cartas sugeridas não foram encontradas e foram removidas.',
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (removals.isNotEmpty) ...[
                      const Text(
                        '❌ Remover:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      ...removals.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Text('• $c'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (additions.isNotEmpty) ...[
                      const Text(
                        '✅ Adicionar:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      ...additions
                          .take(30)
                          .map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text('• $c'),
                            ),
                          ),
                      if (additions.length > 30)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 8),
                          child: Text(
                            '+ ${additions.length - 30} cartas…',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                if (kDebugMode)
                  TextButton(
                    onPressed: () async {
                      await _copyOptimizeDebug(
                        deckId: widget.deckId,
                        archetype: archetype,
                        bracket: _selectedBracket,
                        result: result,
                      );
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Debug copiado')),
                      );
                    },
                    child: const Text('Copiar debug'),
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Aplicar Mudanças'),
                ),
              ],
            ),
      );

      if (confirmed != true || !context.mounted) return;

      // 4. Apply the optimization
      // Show loading again
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (ctx) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Aplicando mudanças...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
      );
      isLoadingDialogOpen = true;

      // Aplicar as mudanças via DeckProvider (versão otimizada com IDs)
      if (mode == 'complete' && additionsDetailed.isNotEmpty) {
        // Completar deck: adicionar em lote.
        await deckProvider.addCardsBulk(
          deckId: widget.deckId,
          cards:
              additionsDetailed
                  .where((m) => m['card_id'] != null)
                  .map(
                    (m) => {
                      'card_id': m['card_id'],
                      'quantity': (m['quantity'] as int?) ?? 1,
                      'is_commander': false,
                    },
                  )
                  .toList(),
        );
      } else if (removalsDetailed.isNotEmpty || additionsDetailed.isNotEmpty) {
        // Usar versão rápida com IDs (evita N buscas HTTP)
        await deckProvider.applyOptimizationWithIds(
          deckId: widget.deckId,
          removalsDetailed: removalsDetailed,
          additionsDetailed: additionsDetailed,
        );
      } else {
        // Fallback para versão antiga (caso servidor não retorne detailed)
        await deckProvider.applyOptimization(
          deckId: widget.deckId,
          cardsToRemove: removals,
          cardsToAdd: additions,
        );
      }

      // Persistir estratégia/bracket no deck para UX.
      await deckProvider.updateDeckStrategy(
        deckId: widget.deckId,
        archetype: archetype,
        bracket: _selectedBracket,
      );
      if (!context.mounted) return;

      closeLoadingDialog();

      if (!context.mounted) return;
      Navigator.pop(context); // Close Sheet

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Otimização aplicada com sucesso!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      // Garantir que o loading seja fechado em caso de erro
      closeLoadingDialog();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aplicar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final deck = context.read<DeckProvider>().selectedDeck;
    final savedBracket = deck?.bracket;
    if (savedBracket != null) _selectedBracket = savedBracket;
    _optionsFuture = context.read<DeckProvider>().fetchOptimizationOptions(
      widget.deckId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedArchetype = _currentArchetype;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.tune, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Otimizar Deck', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Escolha uma estratégia para otimizar:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Bracket / Power level',
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedBracket,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 - Casual')),
                  DropdownMenuItem(value: 2, child: Text('2 - Mid')),
                  DropdownMenuItem(value: 3, child: Text('3 - High')),
                  DropdownMenuItem(value: 4, child: Text('4 - cEDH')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedBracket = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Manter tema do deck'),
            subtitle: const Text(
              'Otimiza sem trocar o plano principal e evita remover cartas núcleo.',
            ),
            value: _keepTheme,
            onChanged: (v) => setState(() => _keepTheme = v),
          ),
          const SizedBox(height: 8),
          if (savedArchetype != null && savedArchetype.trim().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Estratégia atual: $savedArchetype',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _showAllStrategies = !_showAllStrategies);
                    },
                    child: Text(_showAllStrategies ? 'Ocultar' : 'Trocar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _applyOptimization(context, savedArchetype),
              icon: const Icon(Icons.check),
              label: const Text('Aplicar Otimização'),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _optionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Analisando estratégias...'),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text('Erro: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _optionsFuture = context
                                  .read<DeckProvider>()
                                  .fetchOptimizationOptions(widget.deckId);
                            });
                          },
                          child: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  );
                }

                final options = snapshot.data!;
                final visibleOptions =
                    _showAllStrategies
                        ? options
                        : const <Map<String, dynamic>>[];
                return ListView.separated(
                  controller: widget.scrollController,
                  itemCount: visibleOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final option = visibleOptions[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          final title = (option['title'] ?? '').toString();
                          if (title.isEmpty) return;
                          _applyOptimization(context, title);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      option['title'] ?? 'Sem Título',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                  ),
                                  if (option['difficulty'] != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        option['difficulty'],
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                option['description'] ?? '',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Aplicar Estratégia',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
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
}
