import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/deck_provider.dart';

/// Tela para gerar decks usando IA a partir de uma descrição em texto
class DeckGenerateScreen extends StatefulWidget {
  const DeckGenerateScreen({super.key});

  @override
  State<DeckGenerateScreen> createState() => _DeckGenerateScreenState();
}

class _DeckGenerateScreenState extends State<DeckGenerateScreen> {
  final _promptController = TextEditingController();
  final _deckNameController = TextEditingController();
  String _selectedFormat = 'Commander';
  bool _isGenerating = false;
  Map<String, dynamic>? _generatedDeck;

  final List<String> _formats = [
    'Commander',
    'Standard',
    'Modern',
    'Pioneer',
    'Legacy',
    'Vintage',
    'Pauper',
  ];

  final List<String> _examplePrompts = [
    'Deck agressivo de goblins vermelhos para Commander',
    'Deck de controle azul e branco com contramágicas',
    'Deck de elfos verdes focado em ramp e criaturas grandes',
    'Deck aristocratas preto e branco com sacrifício',
    'Deck de dragões vermelhos com muito tesouro',
    'Deck tribal de zumbis com sinergias de cemitério',
  ];

  @override
  void dispose() {
    _promptController.dispose();
    _deckNameController.dispose();
    super.dispose();
  }

  Future<void> _generateDeck() async {
    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, descreva o deck que deseja criar')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedDeck = null;
    });

    try {
      final result = await context.read<DeckProvider>().generateDeck(
            prompt: _promptController.text.trim(),
            format: _selectedFormat,
          );

      setState(() {
        _generatedDeck = result;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar deck: $e')),
        );
      }
    }
  }

  Future<void> _saveDeck() async {
    if (_generatedDeck == null) return;

    final deckName = _deckNameController.text.trim().isEmpty
        ? 'Deck Gerado por IA'
        : _deckNameController.text.trim();

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Extract cards from generated deck
      final generatedDeckData = _generatedDeck!['generated_deck'] as Map<String, dynamic>;
      final cardsList = generatedDeckData['cards'] as List;

      // Convert to format expected by createDeck API
      final cardsToAdd = cardsList.map((card) {
        return {
          'name': card['name'],
          'quantity': card['quantity'] ?? 1,
        };
      }).toList();

      // Create deck with cards
      final success = await context.read<DeckProvider>().createDeck(
            name: deckName,
            format: _selectedFormat.toLowerCase(),
            description: _promptController.text.trim(),
            cards: cardsToAdd.cast<Map<String, dynamic>>(),
          );

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deck criado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/decks');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao salvar o deck')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar deck: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerar Deck com IA'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/decks'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Descreva o deck dos seus sonhos',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A IA irá criar um deck completo e balanceado baseado na sua descrição.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),

            // Format Selector
            Text('Formato:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedFormat,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
              items: _formats.map((format) {
                return DropdownMenuItem(
                  value: format,
                  child: Text(format),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedFormat = value;
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            // Prompt Input
            Text('Descreva seu deck:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ex: Deck agressivo de goblins vermelhos com muitas criaturas pequenas...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
            ),
            const SizedBox(height: 16),

            // Example Prompts
            Text(
              'Ou escolha um exemplo:',
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _examplePrompts.map((example) {
                return ActionChip(
                  label: Text(
                    example,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    setState(() {
                      _promptController.text = example;
                    });
                  },
                  backgroundColor: theme.colorScheme.surfaceVariant,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Generate Button
            ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateDeck,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isGenerating ? 'A IA está pensando...' : 'Gerar Deck',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: 32),

            // Generated Deck Preview
            if (_generatedDeck != null) ...[
              const Divider(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(Icons.preview, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Text(
                    'Preview do Deck Gerado',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Deck Name Input
              TextField(
                controller: _deckNameController,
                decoration: InputDecoration(
                  labelText: 'Nome do Deck',
                  hintText: 'Deck Gerado por IA',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  prefixIcon: const Icon(Icons.edit),
                ),
              ),
              const SizedBox(height: 16),

              // Card List Preview
              _buildDeckPreview(),
              const SizedBox(height: 24),

              // Save Button
              ElevatedButton.icon(
                onPressed: _saveDeck,
                icon: const Icon(Icons.save),
                label: const Text(
                  'Salvar Deck',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeckPreview() {
    if (_generatedDeck == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final generatedDeckData = _generatedDeck!['generated_deck'] as Map<String, dynamic>;
    final cardsList = generatedDeckData['cards'] as List;

    // Group cards by type for better visualization
    final Map<String, List<Map<String, dynamic>>> groupedCards = {};

    for (final card in cardsList) {
      final cardMap = card as Map<String, dynamic>;
      final name = cardMap['name'] as String;
      
      // Simple type categorization based on common patterns
      String category = 'Other';
      if (name.toLowerCase().contains('land') ||
          name.toLowerCase().contains('forest') ||
          name.toLowerCase().contains('island') ||
          name.toLowerCase().contains('mountain') ||
          name.toLowerCase().contains('plains') ||
          name.toLowerCase().contains('swamp')) {
        category = 'Lands';
      } else if (name.toLowerCase().contains('creature')) {
        category = 'Creatures';
      } else if (name.toLowerCase().contains('instant')) {
        category = 'Instants';
      } else if (name.toLowerCase().contains('sorcery')) {
        category = 'Sorceries';
      } else if (name.toLowerCase().contains('artifact')) {
        category = 'Artifacts';
      } else if (name.toLowerCase().contains('enchantment')) {
        category = 'Enchantments';
      }

      groupedCards.putIfAbsent(category, () => []);
      groupedCards[category]!.add(cardMap);
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_list_numbered, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Total: ${cardsList.length} cartas',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...groupedCards.entries.map((entry) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key} (${entry.value.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...entry.value.map((card) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 8),
                    child: Text(
                      '${card['quantity'] ?? 1}x ${card['name']}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          }),
        ],
      ),
    );
  }
}
