import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/card_provider.dart';
import '../../decks/providers/deck_provider.dart';
import '../../decks/models/deck_card_item.dart';

class CardSearchScreen extends StatefulWidget {
  final String deckId;

  const CardSearchScreen({super.key, required this.deckId});

  @override
  State<CardSearchScreen> createState() => _CardSearchScreenState();
}

class _CardSearchScreenState extends State<CardSearchScreen> {
  final _searchController = TextEditingController();
  
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
    // Mostra dialog para escolher quantidade
    showDialog(
      context: context,
      builder: (context) => _AddCardDialog(
        card: card,
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
              return ListTile(
                leading: card.imageUrl != null
                    ? Image.network(card.imageUrl!, width: 40)
                    : const Icon(Icons.image_not_supported),
                title: Text(card.name),
                subtitle: Text(card.typeLine),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _addCardToDeck(card),
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
  final Function(int quantity, bool isCommander) onConfirm;

  const _AddCardDialog({required this.card, required this.onConfirm});

  @override
  State<_AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends State<_AddCardDialog> {
  int _quantity = 1;
  bool _isCommander = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adicionar ${widget.card.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                    onPressed: () => setState(() => _quantity++),
                  ),
                ],
              ),
            ],
          ),
          if (widget.card.typeLine.toLowerCase().contains('legendary creature') || 
              widget.card.oracleText?.toLowerCase().contains('can be your commander') == true)
            CheckboxListTile(
              title: const Text('É Comandante?'),
              value: _isCommander,
              onChanged: (val) => setState(() => _isCommander = val ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => widget.onConfirm(_quantity, _isCommander),
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
