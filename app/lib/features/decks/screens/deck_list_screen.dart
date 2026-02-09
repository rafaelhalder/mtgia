import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/deck_provider.dart';
import '../widgets/deck_card.dart';

class DeckListScreen extends StatefulWidget {
  const DeckListScreen({super.key});

  @override
  State<DeckListScreen> createState() => _DeckListScreenState();
}

class _DeckListScreenState extends State<DeckListScreen> {
  @override
  void initState() {
    super.initState();
    // Busca os decks ao abrir a tela
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeckProvider>().fetchDecks();
    });
  }

  Future<void> _showCreateDeckDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedFormat = 'commander';
    final formats = [
      'commander',
      'standard',
      'modern',
      'pioneer',
      'legacy',
      'vintage',
      'pauper',
    ];

    return showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Novo Deck'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do Deck',
                            hintText: 'Ex: Goblins Aggro',
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedFormat,
                          decoration: const InputDecoration(
                            labelText: 'Formato',
                          ),
                          items:
                              formats
                                  .map(
                                    (f) => DropdownMenuItem(
                                      value: f,
                                      child: Text(
                                        f[0].toUpperCase() + f.substring(1),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => selectedFormat = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descrição (Opcional)',
                            hintText: 'Ex: Deck focado em tokens...',
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.isEmpty) return;

                        final success = await context
                            .read<DeckProvider>()
                            .createDeck(
                              name: nameController.text,
                              format: selectedFormat,
                              description: descriptionController.text,
                            );

                        if (context.mounted) {
                          if (success) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Deck criado com sucesso!'),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.read<DeckProvider>().errorMessage ??
                                      'Erro ao criar deck',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('Criar'),
                    ),
                  ],
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Decks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DeckProvider>().fetchDecks(),
            tooltip: 'Recarregar',
          ),
        ],
      ),
      body: Consumer<DeckProvider>(
        builder: (context, provider, child) {
          // Loading (apenas se a lista estiver vazia)
          if (provider.isLoading && provider.decks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Carregando decks...', style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          // Error
          if (provider.hasError && provider.decks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    provider.errorMessage ?? 'Erro desconhecido',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => provider.fetchDecks(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar Novamente'),
                  ),
                ],
              ),
            );
          }

          // Empty State
          if (provider.decks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.style_outlined,
                    size: 80,
                    color: theme.colorScheme.secondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Nenhum deck criado',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toque no botão abaixo para começar',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF94A3B8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // Lista de Decks
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.decks.length,
            itemBuilder: (context, index) {
              final deck = provider.decks[index];
              return DeckCard(
                deck: deck,
                onTap: () {
                  context.go('/decks/${deck.id}');
                },
                onDelete: () async {
                  final confirmed = await _showDeleteDialog(context, deck.name);
                  if (confirmed == true) {
                    await provider.deleteDeck(deck.id);
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'create':
              _showCreateDeckDialog(context);
              break;
            case 'generate':
              context.go('/decks/generate');
              break;
            case 'import':
              context.go('/decks/import');
              break;
          }
        },
        offset: const Offset(0, -160),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'create',
            child: ListTile(
              leading: Icon(Icons.add, color: theme.colorScheme.primary),
              title: const Text('Novo Deck'),
              subtitle: const Text('Criar do zero'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'generate',
            child: ListTile(
              leading: Icon(Icons.auto_awesome, color: theme.colorScheme.secondary),
              title: const Text('Gerar com IA'),
              subtitle: const Text('Descreva e a IA monta'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'import',
            child: ListTile(
              leading: Icon(Icons.content_paste, color: const Color(0xFFF59E0B)),
              title: const Text('Importar Lista'),
              subtitle: const Text('Colar de outro site'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        ],
        child: FloatingActionButton.extended(
          onPressed: null,
          icon: const Icon(Icons.add),
          label: const Text('Novo Deck'),
        ),
      ),
    );
  }

  Future<bool?> _showDeleteDialog(BuildContext context, String deckName) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Deletar Deck'),
            content: Text('Tem certeza que deseja deletar "$deckName"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Deletar'),
              ),
            ],
          ),
    );
  }
}
