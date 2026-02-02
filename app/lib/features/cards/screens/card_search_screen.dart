import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/card_provider.dart';
import '../../decks/providers/deck_provider.dart';
import '../../decks/models/deck_card_item.dart';
import '../../decks/models/deck_details.dart';
import 'dart:async';

class CardSearchScreen extends StatefulWidget {
  final String deckId;
  final String? mode;

  const CardSearchScreen({super.key, required this.deckId, this.mode});

  @override
  State<CardSearchScreen> createState() => _CardSearchScreenState();
}

class _CardSearchScreenState extends State<CardSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final deckProvider = context.read<DeckProvider>();
      if (deckProvider.selectedDeck?.id != widget.deckId) {
        await deckProvider.fetchDeckDetails(widget.deckId);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final provider = context.read<CardProvider>();
    if (!provider.hasMore || provider.isLoading || provider.isLoadingMore)
      return;
    final position = _scrollController.position;
    if (!position.hasPixels) return;
    if (position.pixels >= position.maxScrollExtent - 240) {
      provider.loadMore();
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.length < 3) {
      context.read<CardProvider>().clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<CardProvider>().searchCards(q);
    });
  }

  void _addCardToDeck(DeckCardItem card) async {
    final deck = context.read<DeckProvider>().selectedDeck;
    final format = deck?.format.toLowerCase();
    final isCommanderFormat = format == 'commander' || format == 'brawl';

    final commanderIdentity = _computeCommanderIdentity(deck);
    final mustPickCommanderFirst =
        isCommanderFormat && (deck?.commander.isEmpty ?? true);
    final isCommanderEligible = _isCommanderEligible(card);

    final isAllowedByCommander =
        !isCommanderFormat ||
        commanderIdentity == null ||
        _isSubset(card.colorIdentity, commanderIdentity);

    final isCommanderMode = (widget.mode ?? '').toLowerCase() == 'commander';
    final canOpenAddDialog =
        isCommanderMode
            ? isCommanderEligible
            : (!mustPickCommanderFirst
                ? isAllowedByCommander
                : isCommanderEligible);

    // Verifica se é basic land
    final isBasicLand = card.typeLine.toLowerCase().contains('basic land');

    // Em Commander/Brawl, se NÃO for basic land E não estiver em modo Commander
    // (escolhendo o comandante), adiciona direto com quantidade 1 sem modal
    if (isCommanderFormat &&
        !isBasicLand &&
        !isCommanderMode &&
        !mustPickCommanderFirst) {
      // Verifica se a carta é permitida pela identidade do comandante
      if (!canOpenAddDialog) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Esta carta não é permitida pela identidade de cor do comandante',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      final provider = context.read<DeckProvider>();
      final success = await provider.addCardToDeck(
        widget.deckId,
        card,
        1, // Commander só permite 1 cópia
        isCommander: false,
      );

      if (!context.mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${card.name} adicionada ao deck!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Erro ao adicionar carta'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Para outros casos (basic land, outros formatos, modo commander), mostra dialog
    showDialog(
      context: context,
      builder:
          (context) => _AddCardDialog(
            card: card,
            deckFormat: format,
            hasCommanderSelected: (deck?.commander.isNotEmpty ?? false),
            forceCommander: mustPickCommanderFirst || isCommanderMode,
            canAddByCommanderIdentity: canOpenAddDialog,
            onConfirm: (quantity, isCommander) async {
              final provider = context.read<DeckProvider>();
              final success = await provider.addCardToDeck(
                widget.deckId,
                card,
                quantity,
                isCommander: isCommander,
              );

              if (!context.mounted) return;
              Navigator.pop(context);

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${card.name} adicionada ao deck!')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      provider.errorMessage ?? 'Erro ao adicionar carta',
                    ),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = context.watch<DeckProvider>().selectedDeck;
    final format = deck?.format.toLowerCase();
    final isCommanderFormat = format == 'commander' || format == 'brawl';
    final commanderIdentity = _computeCommanderIdentity(deck);
    final mustPickCommanderFirst =
        isCommanderFormat && (deck?.commander.isEmpty ?? true);
    final isCommanderMode = (widget.mode ?? '').toLowerCase() == 'commander';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText:
                    isCommanderMode
                        ? 'Buscar comandante...'
                        : 'Buscar cartas...',
                border: InputBorder.none,
                hintStyle: const TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
            ),
            if (isCommanderMode)
              const Text(
                'Modo comandante',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: Consumer<CardProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(child: Text(provider.errorMessage!));
          }

          if (provider.searchResults.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Digite o nome de uma carta',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final totalItems =
              provider.searchResults.length + (provider.hasMore ? 1 : 0);

          return ListView.builder(
            controller: _scrollController,
            itemCount: totalItems,
            itemBuilder: (context, index) {
              if (index >= provider.searchResults.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final card = provider.searchResults[index];
              final isCommanderEligible = _isCommanderEligible(card);
              final allowedByIdentity =
                  !isCommanderFormat ||
                  commanderIdentity == null ||
                  _isSubset(card.colorIdentity, commanderIdentity);
              final canAdd =
                  isCommanderMode
                      ? isCommanderEligible
                      : (mustPickCommanderFirst
                          ? isCommanderEligible
                          : allowedByIdentity);
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
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
                title: Text(card.name),
                subtitle: Text(
                  [
                    card.typeLine,
                    if ((card.setName ?? '').trim().isNotEmpty) card.setName!,
                    if ((card.setReleaseDate ?? '').trim().isNotEmpty)
                      card.setReleaseDate!,
                    if (mustPickCommanderFirst && !isCommanderEligible)
                      'Selecione um comandante primeiro',
                    if (!mustPickCommanderFirst &&
                        isCommanderFormat &&
                        commanderIdentity != null &&
                        !allowedByIdentity)
                      'Fora da identidade do comandante',
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: canAdd ? () => _addCardToDeck(card) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddCardDialog extends StatefulWidget {
  final DeckCardItem card;
  final String? deckFormat;
  final bool hasCommanderSelected;
  final bool forceCommander;
  final bool canAddByCommanderIdentity;
  final Function(int quantity, bool isCommander) onConfirm;

  const _AddCardDialog({
    required this.card,
    required this.deckFormat,
    required this.hasCommanderSelected,
    required this.forceCommander,
    required this.canAddByCommanderIdentity,
    required this.onConfirm,
  });

  @override
  State<_AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends State<_AddCardDialog> {
  int _quantity = 1;
  bool _isCommander = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceCommander) {
      _isCommander = true;
      _quantity = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = widget.deckFormat?.toLowerCase();
    final isCommanderFormat = format == 'commander' || format == 'brawl';
    final isBasicLand = widget.card.typeLine.toLowerCase().contains(
      'basic land',
    );
    final canIncreaseQuantity = !isCommanderFormat || isBasicLand;
    final isCommanderEligible = _isCommanderEligible(widget.card);

    return AlertDialog(
      title: Text('Adicionar ${widget.card.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.canAddByCommanderIdentity)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Essa carta está fora da identidade de cor do comandante.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Quantidade:'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed:
                          _isSubmitting
                              ? null
                              : _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                    ),
                    Text('$_quantity', style: const TextStyle(fontSize: 18)),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed:
                          _isSubmitting
                              ? null
                              : canIncreaseQuantity
                              ? () => setState(() => _quantity++)
                              : null,
                    ),
                  ],
                ),
              ],
            ),
            if (isCommanderFormat &&
                isCommanderEligible &&
                !widget.hasCommanderSelected &&
                !widget.forceCommander)
              CheckboxListTile(
                title: const Text('É Comandante?'),
                value: _isCommander,
                onChanged:
                    _isSubmitting
                        ? null
                        : (val) => setState(() {
                          _isCommander = val ?? false;
                          if (_isCommander) _quantity = 1;
                        }),
              ),
            if (widget.forceCommander)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Esse deck precisa de um comandante. Esta carta será definida como comandante.',
                ),
              ),
            if (_isSubmitting)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _isSubmitting || !widget.canAddByCommanderIdentity
                  ? null
                  : () async {
                    setState(() => _isSubmitting = true);
                    await widget.onConfirm(
                      _quantity,
                      widget.forceCommander ? true : _isCommander,
                    );
                    if (mounted) setState(() => _isSubmitting = false);
                  },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

Set<String>? _computeCommanderIdentity(DeckDetails? deck) {
  if (deck == null) return null;
  if (deck.commander.isEmpty) return null;
  final commander = deck.commander.first;
  final identity =
      commander.colorIdentity.isNotEmpty
          ? commander.colorIdentity
          : commander.colors;
  return identity.map((e) => e.toUpperCase()).toSet();
}

bool _isSubset(List<String> cardIdentity, Set<String> commanderIdentity) {
  for (final c in cardIdentity) {
    if (!commanderIdentity.contains(c.toUpperCase())) return false;
  }
  return true;
}

bool _isCommanderEligible(DeckCardItem card) {
  final typeLine = card.typeLine.toLowerCase();
  final oracle = (card.oracleText ?? '').toLowerCase();
  return typeLine.contains('legendary creature') ||
      oracle.contains('can be your commander');
}
