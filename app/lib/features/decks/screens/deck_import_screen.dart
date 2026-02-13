import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/deck_provider.dart';

class DeckImportScreen extends StatefulWidget {
  const DeckImportScreen({super.key});

  @override
  State<DeckImportScreen> createState() => _DeckImportScreenState();
}

class _DeckImportScreenState extends State<DeckImportScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _listController = TextEditingController();
  final _commanderController = TextEditingController();
  
  String _selectedFormat = 'commander';
  bool _isImporting = false;
  List<String> _notFoundLines = [];
  List<String> _warnings = [];
  int _cardsImported = 0;
  String? _error;

  final _formats = [
    'commander',
    'standard',
    'modern',
    'pioneer',
    'legacy',
    'vintage',
    'pauper',
    'brawl',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _listController.dispose();
    _commanderController.dispose();
    super.dispose();
  }

  bool get _isCommanderFormat => 
      _selectedFormat == 'commander' || _selectedFormat == 'brawl';

  Future<void> _importDeck() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o nome do deck')),
      );
      return;
    }

    if (_listController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cole a lista de cartas')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _error = null;
      _notFoundLines = [];
      _warnings = [];
    });

    final provider = context.read<DeckProvider>();
    final result = await provider.importDeckFromList(
      name: _nameController.text,
      format: _selectedFormat,
      list: _listController.text,
      description: _descriptionController.text.isNotEmpty 
          ? _descriptionController.text 
          : null,
      commander: _commanderController.text.isNotEmpty 
          ? _commanderController.text 
          : null,
    );

    if (!mounted) return;

    setState(() {
      _isImporting = false;
      _notFoundLines = List<String>.from(result['not_found_lines'] ?? []);
      _warnings = List<String>.from(result['warnings'] ?? []);
      _cardsImported = result['cards_imported'] ?? 0;
    });

    if (result['success'] == true) {
      final deck = result['deck'];
      
      // Se houve cartas não encontradas, mostra resultado com opção de editar
      if (_notFoundLines.isNotEmpty) {
        _showResultDialog(
          success: true,
          deckId: deck?['id'],
          cardsImported: _cardsImported,
          notFound: _notFoundLines,
          warnings: _warnings,
        );
      } else {
        // Tudo ok, vai direto pro deck
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deck importado com $_cardsImported cartas!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        if (deck?['id'] != null) {
          context.go('/decks/${deck['id']}');
        } else {
          context.go('/decks');
        }
      }
    } else {
      setState(() {
        _error = result['error'];
      });
      
      // Se houve erro mas tem cartas não encontradas, mostra pra ajudar
      if (_notFoundLines.isNotEmpty) {
        _showResultDialog(
          success: false,
          notFound: _notFoundLines,
          error: _error,
        );
      }
    }
  }

  void _showResultDialog({
    required bool success,
    String? deckId,
    int cardsImported = 0,
    List<String> notFound = const [],
    List<String> warnings = const [],
    String? error,
  }) {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.warning,
                  color: success ? theme.colorScheme.primary : AppTheme.warning,
                ),
                const SizedBox(width: 8),
                Text(success ? 'Importação Concluída' : 'Atenção'),
              ],
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (success) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$cardsImported cartas reconhecidas',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              'Pronto para análise de sinergia',
                              style: TextStyle(
                                fontSize: AppTheme.fontSm,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: TextStyle(color: AppTheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              if (warnings.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Text(
                      'Avisos:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text('• $w', style: TextStyle(fontSize: AppTheme.fontMd, color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
                )),
                const SizedBox(height: 16),
              ],
              
              if (notFound.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.search_off, size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 6),
                    Text(
                      '${notFound.length} cartas não identificadas:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: notFound.map((line) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.help_outline, size: 14, color: theme.colorScheme.error.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppTheme.fontSm,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.tips_and_updates, size: 14, color: theme.colorScheme.secondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tente usar o nome em inglês ou verifique a ortografia',
                        style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!success)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Revisar Lista'),
            ),
          if (success) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/decks');
              },
              child: const Text('Ver Decks'),
            ),
            if (deckId != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/decks/$deckId');
                },
                child: const Text('Abrir Deck'),
              ),
          ],
        ],
      ),
    );
  }

  void _pasteExample() {
    _listController.text = '''1 Sol Ring
1 Arcane Signet
1 Command Tower
1 Lightning Greaves
4 Island
4 Mountain
1 Counterspell''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar Lista'),
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
            // Header com IA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.secondary.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.content_paste, color: theme.colorScheme.primary, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Importar Lista',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTheme.fontLg,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cole sua lista de qualquer fonte:\n'
                    '• Moxfield, Archidekt, EDHRec\n'
                    '• MTGA/MTGO\n'
                    '• Texto simples',
                    style: TextStyle(
                      fontSize: AppTheme.fontMd,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            // Nome do Deck
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nome do Deck',
                hintText: 'Ex: Goblins Aggro',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.edit),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
            ),
            
            const SizedBox(height: 16),

            // Formato
            DropdownButtonFormField<String>(
              initialValue: _selectedFormat,
              decoration: const InputDecoration(
                labelText: 'Formato *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _formats.map((f) => DropdownMenuItem(
                value: f,
                child: Text(f[0].toUpperCase() + f.substring(1)),
              )).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedFormat = value);
                }
              },
            ),
            
            const SizedBox(height: 16),

            // Comandante (só para Commander/Brawl)
            if (_isCommanderFormat) ...[
              TextField(
                controller: _commanderController,
                decoration: const InputDecoration(
                  labelText: 'Comandante (opcional)',
                  hintText: 'Ex: Urza, Lord High Artificer',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.star),
                  helperText: 'Ou marque na lista com [Commander]',
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Descrição
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                hintText: 'Ex: Deck focado em artefatos...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
            
            const SizedBox(height: 16),

            // Lista de Cartas
            Row(
              children: [
                Icon(Icons.list_alt, size: 20, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Lista de Cartas',
                    style: TextStyle(
                      fontSize: AppTheme.fontLg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pasteExample,
                  icon: Icon(Icons.help_outline, size: 18, color: theme.colorScheme.tertiary),
                  label: Text('Exemplo', style: TextStyle(color: theme.colorScheme.tertiary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _listController,
              decoration: InputDecoration(
                hintText: 'Cole aqui sua lista de cartas...\n\nFormato: 1 Sol Ring ou 1x Sol Ring (set)',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: theme.colorScheme.surface,
              ),
              maxLines: 15,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppTheme.fontMd,
                color: theme.colorScheme.onSurface,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Contador de linhas com feedback inteligente
            Builder(
              builder: (context) {
                final detectedCount = _listController.text
                    .split('\n')
                    .where((l) => l.trim().isNotEmpty)
                    .length;
                final hasCards = detectedCount > 0;
                return Row(
                  children: [
                    Icon(
                      hasCards
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: hasCards
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$detectedCount cartas detectadas',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: AppTheme.fontSm,
                      ),
                    ),
                  ],
                );
              },
            ),

            // Erro
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: AppTheme.error.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: AppTheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Botão Importar
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isImporting ? null : _importDeck,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isImporting 
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          const Text('Importando...', style: TextStyle(fontSize: AppTheme.fontLg)),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload),
                          const SizedBox(width: 8),
                          const Text(
                            'Criar Deck',
                            style: TextStyle(fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Texto auxiliar
            Text(
              'Cartas serão validadas automaticamente',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
