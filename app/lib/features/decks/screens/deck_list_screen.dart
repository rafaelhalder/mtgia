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
                  title: Row(
                    children: const [
                      Icon(Icons.dashboard_customize, size: 22),
                      SizedBox(width: 8),
                      Text('Novo Deck'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do Deck',
                            hintText: 'Ex: Goblins Aggro',
                            prefixIcon: Icon(Icons.edit, size: 20),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedFormat,
                          decoration: const InputDecoration(
                            labelText: 'Formato',
                            prefixIcon: Icon(Icons.category, size: 20),
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
                            prefixIcon: Icon(Icons.description, size: 20),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.tips_and_updates, size: 14, color: Theme.of(context).colorScheme.secondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Após criar, a IA ajudará a montar e otimizar',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ],
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
                              SnackBar(
                                content: Row(
                                  children: const [
                                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                                    SizedBox(width: 8),
                                    Text('Deck criado! Pronto para análise de IA'),
                                  ],
                                ),
                                backgroundColor: Theme.of(context).colorScheme.primary,
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
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => context.go('/decks/generate'),
            tooltip: 'Gerar Deck',
          ),
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
                    Icons.psychology,
                    size: 80,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Bem-vindo ao MTG AI',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crie um deck manualmente ou deixe a IA\ngerar um baseado na sua descrição',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF94A3B8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showCreateDeckDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Criar Manual'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => context.go('/decks/generate'),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Criar com IA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                          foregroundColor: theme.colorScheme.onSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botão de Importar Lista
          FloatingActionButton.extended(
            heroTag: 'import',
            onPressed: () => context.go('/decks/import'),
            backgroundColor: theme.colorScheme.secondary,
            tooltip: 'Importar lista de outro site com reconhecimento automático',
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Importar'),
          ),
          const SizedBox(height: 12),
          // Botão principal (Novo Deck)
          FloatingActionButton.extended(
            heroTag: 'create',
            onPressed: () => _showCreateDeckDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Novo Deck'),
            backgroundColor: theme.colorScheme.primary,
          ),
        ],
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
