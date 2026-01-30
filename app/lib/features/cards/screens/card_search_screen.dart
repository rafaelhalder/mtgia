import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/card_provider.dart';
import '../../decks/providers/deck_provider.dart';
import '../../decks/models/deck_card_item.dart';
import '../../decks/models/deck_details.dart';

class CardSearchScreen extends StatefulWidget {
  final String deckId;

  const CardSearchScreen({super.key, required this.deckId});

  @override
  State<CardSearchScreen> createState() => _CardSearchScreenState();
}

class _CardSearchScreenState extends State<CardSearchScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final deckProvider = context.read<DeckProvider>();
      if (deckProvider.selectedDeck?.id != widget.deckId) {
        await deckProvider.fetchDeckDetails(widget.deckId);
      }
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Debounce simples poderia ser adicionado aqui
    if (query.length > 2) {
      context.read<CardProvider>().searchCards(query);
    }
  }

  void _addCardToDeck(DeckCardItem card) {
    final deck = context.read<DeckProvider>().selectedDeck;
    final format = deck?.format.toLowerCase();
    final isCommanderFormat = format == 'commander' || format == 'brawl';

    final commanderIdentity = _computeCommanderIdentity(deck);
    final mustPickCommanderFirst = isCommanderFormat && (deck?.commander.isEmpty ?? true);
    final isCommanderEligible = _isCommanderEligible(card);

    final isAllowedByCommander = !isCommanderFormat ||
        commanderIdentity == null ||
        _isSubset(card.colorIdentity, commanderIdentity);

    final canOpenAddDialog =
        !mustPickCommanderFirst ? isAllowedByCommander : isCommanderEligible;

    // Mostra dialog para escolher quantidade
    showDialog(
      context: context,
      builder: (context) => _AddCardDialog(
        card: card,
        deckFormat: format,
        hasCommanderSelected: (deck?.commander.isNotEmpty ?? false),
        forceCommander: mustPickCommanderFirst,
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
                content: Text(provider.errorMessage ?? 'Erro ao adicionar carta'),
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
    final mustPickCommanderFirst = isCommanderFormat && (deck?.commander.isEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar cartas...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
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
                  Text('Digite o nome de uma carta para buscar'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.searchResults.length,
            itemBuilder: (context, index) {
              final card = provider.searchResults[index];
              final isCommanderEligible = _isCommanderEligible(card);
              final allowedByIdentity =
                  !isCommanderFormat || commanderIdentity == null || _isSubset(card.colorIdentity, commanderIdentity);
              final canAdd =
                  mustPickCommanderFirst ? isCommanderEligible : allowedByIdentity;
              return ListTile(
                leading: card.imageUrl != null
                    ? Image.network(card.imageUrl!, width: 40)
                    : const Icon(Icons.image_not_supported),
                title: Text(card.name),
                subtitle: Text([
                  card.typeLine,
                  if ((card.setName ?? '').trim().isNotEmpty) card.setName!,
                  if ((card.setReleaseDate ?? '').trim().isNotEmpty) card.setReleaseDate!,
                  if (mustPickCommanderFirst && !isCommanderEligible) 'Selecione um comandante primeiro',
                  if (!mustPickCommanderFirst && isCommanderFormat && commanderIdentity != null && !allowedByIdentity)
                    'Fora da identidade do comandante',
                ].join(' • ')),
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
    final isBasicLand = widget.card.typeLine.toLowerCase().contains('basic land');
    final canIncreaseQuantity = !isCommanderFormat || isBasicLand;
    final isCommanderEligible = _isCommanderEligible(widget.card);

    return AlertDialog(
      title: Text('Adicionar ${widget.card.name}'),
      content: Column(
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
                    onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  ),
                  Text('$_quantity', style: const TextStyle(fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: canIncreaseQuantity ? () => setState(() => _quantity++) : null,
                  ),
                ],
              ),
            ],
          ),
          if (isCommanderFormat && isCommanderEligible && !widget.hasCommanderSelected && !widget.forceCommander)
            CheckboxListTile(
              title: const Text('É Comandante?'),
              value: _isCommander,
              onChanged: (val) => setState(() {
                _isCommander = val ?? false;
                if (_isCommander) _quantity = 1;
              }),
            ),
          if (widget.forceCommander)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Esse deck precisa de um comandante. Esta carta será definida como comandante.'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: widget.canAddByCommanderIdentity
              ? () => widget.onConfirm(_quantity, widget.forceCommander ? true : _isCommander)
              : null,
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
  final identity = commander.colorIdentity.isNotEmpty ? commander.colorIdentity : commander.colors;
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
  return typeLine.contains('legendary creature') || oracle.contains('can be your commander');
}
