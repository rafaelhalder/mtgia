import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/deck_provider.dart';
import '../models/deck_card_item.dart';
import '../../cards/providers/card_provider.dart';
import '../widgets/deck_analysis_tab.dart';

class DeckDetailsScreen extends StatefulWidget {
  final String deckId;

  const DeckDetailsScreen({super.key, required this.deckId});

  @override
  State<DeckDetailsScreen> createState() => _DeckDetailsScreenState();
}

class _DeckDetailsScreenState extends State<DeckDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeckProvider>().fetchDeckDetails(widget.deckId);
    });
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
            tooltip: 'Otimizar Deck com IA',
            onPressed: () => _showOptimizationOptions(context),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(provider.detailsErrorMessage!),
                  const SizedBox(height: 16),
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
                      ...deck.commander.map((c) => Card(
                        child: ListTile(
                          leading: c.imageUrl != null 
                              ? Image.network(c.imageUrl!, width: 50) 
                              : const Icon(Icons.image_not_supported),
                          title: Text(c.name),
                          subtitle: Text(c.typeLine),
                          onTap: () => _showCardDetails(context, c),
                        ),
                      )),
                    ],
                  ],
                ),
              ),

              // Tab 2: Cartas
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
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
                        ...entry.value.map((card) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(8),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 40,
                                height: 56,
                                child: card.imageUrl != null
                                    ? Image.network(card.imageUrl!, fit: BoxFit.cover)
                                    : Container(
                                        color: Colors.grey[800],
                                        child: const Icon(Icons.image_not_supported, size: 20),
                                      ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${card.quantity}x',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    card.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(card.typeLine, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                _ManaCostRow(cost: card.manaCost),
                              ],
                            ),
                            onTap: () => _showCardDetails(context, card),
                          ),
                        )),
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

  void _showCardDetails(BuildContext context, DeckCardItem card) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (card.imageUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Image.network(
                    card.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 200,
                      child: Center(child: Icon(Icons.image_not_supported, size: 64)),
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[400],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _showAiExplanation(context, card),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: Theme.of(context).colorScheme.primary),
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

  Future<void> _showAiExplanation(BuildContext context, DeckCardItem card) async {
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
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.purple),
              const SizedBox(width: 8),
              Expanded(child: Text('Análise da IA: ${card.name}')),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(explanation ?? 'Não foi possível gerar uma explicação.'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao explicar carta: $e')),
        );
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
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _OptimizationSheet(
          deckId: widget.deckId,
          scrollController: scrollController,
        ),
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
      children: matches.map((m) {
        final symbol = m.group(1)!;
        return _ManaSymbol(symbol: symbol);
      }).toList(),
    );
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

  Future<void> _applyOptimization(BuildContext context, String archetype) async {
    // 1. Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. Call API to get suggestions
      final result = await context.read<DeckProvider>().optimizeDeck(widget.deckId, archetype);
      
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading

      final removals = (result['removals'] as List).cast<String>();
      final additions = (result['additions'] as List).cast<String>();
      final reasoning = result['reasoning'] as String? ?? '';

      // 3. Show confirmation dialog with suggestions
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Sugestões para: $archetype'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reasoning),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('❌ Remover:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                ...removals.map((c) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text('• $c'),
                )),
                const SizedBox(height: 16),
                const Text('✅ Adicionar:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ...additions.map((c) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text('• $c'),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
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
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Aplicando mudanças...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      final success = await context.read<DeckProvider>().applyOptimization(
        deckId: widget.deckId,
        cardsToRemove: removals,
        cardsToAdd: additions,
      );

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading
      Navigator.pop(context); // Close Sheet

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deck otimizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao aplicar otimização')),
        );
      }

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _optionsFuture = context.read<DeckProvider>().fetchOptimizationOptions(widget.deckId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              Text(
                'Otimizar Deck',
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A IA analisou seu comandante e sugere estes caminhos:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
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
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Erro: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _optionsFuture = context.read<DeckProvider>().fetchOptimizationOptions(widget.deckId);
                            });
                          },
                          child: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  );
                }

                final options = snapshot.data!;
                return ListView.separated(
                  controller: widget.scrollController,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _applyOptimization(context, option['title']),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      option['title'] ?? 'Sem Título',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  if (option['difficulty'] != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
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
                                  Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
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
