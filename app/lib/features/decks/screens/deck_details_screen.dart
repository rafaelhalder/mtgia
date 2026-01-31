import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
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
          IconButton(
            icon: const Icon(Icons.verified_outlined),
            tooltip: 'Validar/Finalizar Deck',
            onPressed: _validateDeck,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.go('/decks/${widget.deckId}/search');
        },
        icon: const Icon(Icons.add),
        label: const Text('Adicionar Cartas'),
      ),
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
                    Chip(label: Text(deck.format.toUpperCase())),
                    const SizedBox(height: 12),
                    DeckProgressIndicator(
                      deck: deck,
                      totalCards: totalCards,
                      maxCards: maxCards,
                      hasCommander: deck.commander.isNotEmpty,
                      onTap: () => _tabController.animateTo(1), // Vai para tab de cartas
                    ),
                    const SizedBox(height: 12),
                    _PricingRow(
                      pricing: _pricing,
                      isLoading: _isPricingLoading,
                      onPressed: () => _loadPricing(force: true),
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
                    if (deck.description != null) ...[
                      Text('Descrição', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(deck.description!),
                      const SizedBox(height: 24),
                    ],
                    if (deck.commander.isNotEmpty) ...[
                      Text('Comandante', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...deck.commander.map(
                        (c) => Card(
                          child: ListTile(
                            leading:
                                c.imageUrl != null
                                    ? Image.network(c.imageUrl!, width: 50)
                                    : const Icon(Icons.image_not_supported),
                            title: Text(c.name),
                            subtitle: Text(c.typeLine),
                            onTap: () => _showCardDetails(context, c),
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
                    Text('Estratégia', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            (deck.archetype == null ||
                                    deck.archetype!.trim().isEmpty)
                                ? 'Não definida'
                                : deck.archetype!,
                          ),
                        ),
                        Chip(label: Text('Bracket: ${deck.bracket ?? 2}')),
                      ],
                    ),
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
                  ...deck.mainBoard.entries.map((entry) {
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
                        ...entry.value.map(
                          (card) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
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
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    card.typeLine,
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  _ManaCostRow(cost: card.manaCost),
                                ],
                              ),
                              onTap: () => _showCardDetails(context, card),
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
                      child: Image.network(
                        card.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const SizedBox(
                              height: 200,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 64,
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
                                      fit: BoxFit.cover,
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
    final hasItems = _pricing != null && 
        (_pricing!['items'] as List?)?.isNotEmpty == true;
    
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
}

class _PricingRow extends StatelessWidget {
  final Map<String, dynamic>? pricing;
  final bool isLoading;
  final VoidCallback onPressed;
  final VoidCallback onForceRefresh;
  final VoidCallback? onShowDetails;

  const _PricingRow({
    required this.pricing,
    required this.isLoading,
    required this.onPressed,
    required this.onForceRefresh,
    this.onShowDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = pricing?['estimated_total_usd'];
    final missing = pricing?['missing_price_cards'];

    String subtitle = 'Calcular custo estimado';
    if (total is num) {
      subtitle = 'Estimado: \$${total.toStringAsFixed(2)}';
      if (missing is num && missing > 0) {
        subtitle += ' • ${missing.toInt()} sem preço';
      }
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
          if (onShowDetails != null)
            TextButton(
              onPressed: isLoading ? null : onShowDetails,
              child: const Text('Detalhes'),
            ),
          TextButton(
            onPressed: isLoading ? null : onPressed,
            child: const Text('Calcular'),
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
        _selectedBracket,
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
      final mode = (result['mode'] as String?) ?? 'optimize';
      final additionsDetailed =
          (result['additions_detailed'] as List?)
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

      // Aplicar as mudanças via DeckProvider
      if (mode == 'complete' && additionsDetailed.isNotEmpty) {
        // Completar deck: adicionar em lote (mais rápido e evita N chamadas).
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
      } else {
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
        const SnackBar(
          content: Text('Mudanças aplicadas com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Garantir que o loading seja fechado em caso de erro
      closeLoadingDialog();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao aplicar otimização: $e'),
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
              Icon(Icons.auto_fix_high, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Otimizar Deck', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sugestões para o seu comandante:',
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
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Otimizar com esta estratégia'),
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
