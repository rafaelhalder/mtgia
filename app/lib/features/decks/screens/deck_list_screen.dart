import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
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
    bool isPublic = false;
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
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Deck público'),
                          subtitle: const Text('Visível na comunidade'),
                          value: isPublic,
                          onChanged: (v) => setState(() => isPublic = v),
                          contentPadding: EdgeInsets.zero,
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
                              isPublic: isPublic,
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
                                backgroundColor: AppTheme.error,
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
      body: Builder(
        builder: (context) {
          final deckIsLoading = context.select<DeckProvider, bool>((p) => p.isLoading);
          final decks = context.select<DeckProvider, List>((p) => p.decks);
          final hasError = context.select<DeckProvider, bool>((p) => p.hasError);
          final errorMessage = context.select<DeckProvider, String?>((p) => p.errorMessage);

          // Loading (apenas se a lista estiver vazia)
          if (deckIsLoading && decks.isEmpty) {
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
          if (hasError && decks.isEmpty) {
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
                    errorMessage ?? 'Erro desconhecido',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.read<DeckProvider>().fetchDecks(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar Novamente'),
                  ),
                ],
              ),
            );
          }

          // Empty State
          if (decks.isEmpty) {
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
                      color: AppTheme.textSecondary,
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
            itemCount: decks.length,
            itemBuilder: (context, index) {
              final deck = decks[index];
              return DeckCard(
                deck: deck,
                onTap: () {
                  context.go('/decks/${deck.id}');
                },
                onDelete: () async {
                  final deckProvider = context.read<DeckProvider>();
                  final confirmed = await _showDeleteDialog(context, deck.name);
                  if (confirmed == true) {
                    await deckProvider.deleteDeck(deck.id);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
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
              leading: Icon(Icons.content_paste, color: AppTheme.mythicGold),
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
