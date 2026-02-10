import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../../cards/providers/card_provider.dart';
import '../providers/binder_provider.dart';

/// Modal (BottomSheet) para editar/ver detalhes de um item do fichário.
/// Usado tanto para edição (modo update) quanto para adicionar ao binder.
/// Ao adicionar, busca todas as edições da carta para o usuário escolher.
class BinderItemEditor extends StatefulWidget {
  /// Se não-nulo, estamos editando um item existente.
  final BinderItem? item;

  /// cardId obrigatório para adição. Quando [item] != null, usa item.cardId.
  final String? cardId;
  final String? cardName;
  final String? cardImageUrl;

  /// Tipo de lista inicial: 'have' ou 'want' (apenas para adição)
  final String initialListType;

  /// Callbacks
  final Future<bool> Function(Map<String, dynamic> data)? onSave;
  final Future<bool> Function()? onDelete;

  const BinderItemEditor({
    super.key,
    this.item,
    this.cardId,
    this.cardName,
    this.cardImageUrl,
    this.initialListType = 'have',
    this.onSave,
    this.onDelete,
  });

  /// Helper estático para abrir o modal
  static Future<void> show(
    BuildContext context, {
    BinderItem? item,
    String? cardId,
    String? cardName,
    String? cardImageUrl,
    String initialListType = 'have',
    Future<bool> Function(Map<String, dynamic> data)? onSave,
    Future<bool> Function()? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceSlate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (_) => BinderItemEditor(
        item: item,
        cardId: cardId,
        cardName: cardName,
        cardImageUrl: cardImageUrl,
        initialListType: initialListType,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<BinderItemEditor> createState() => _BinderItemEditorState();
}

class _BinderItemEditorState extends State<BinderItemEditor> {
  late int _quantity;
  late String _condition;
  late bool _isFoil;
  late bool _forTrade;
  late bool _forSale;
  late String _listType;
  late TextEditingController _priceController;
  late TextEditingController _notesController;
  bool _saving = false;

  /// Edições disponíveis da carta (só para adição)
  List<Map<String, dynamic>> _printings = [];
  bool _loadingPrintings = false;
  int _selectedPrintingIndex = 0;

  static const conditions = ['NM', 'LP', 'MP', 'HP', 'DMG'];
  static const conditionLabels = {
    'NM': 'Near Mint',
    'LP': 'Lightly Played',
    'MP': 'Moderately Played',
    'HP': 'Heavily Played',
    'DMG': 'Damaged',
  };

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _quantity = item?.quantity ?? 1;
    _condition = item?.condition ?? 'NM';
    _isFoil = item?.isFoil ?? false;
    _forTrade = item?.forTrade ?? false;
    _forSale = item?.forSale ?? false;
    _listType = item?.listType ?? widget.initialListType;
    _priceController = TextEditingController(
      text: item?.price?.toStringAsFixed(2) ?? '',
    );
    _notesController = TextEditingController(text: item?.notes ?? '');

    // Buscar edições se estiver adicionando (não editando)
    if (widget.item == null && widget.cardName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchPrintings();
      });
    }
  }

  Future<void> _fetchPrintings() async {
    setState(() => _loadingPrintings = true);
    try {
      final provider = context.read<CardProvider>();
      var results = await provider.fetchPrintingsByName(widget.cardName!);

      // Se só encontrou 0-1 edição, importa do Scryfall e busca de novo
      if (results.length <= 1) {
        debugPrint('[BinderItemEditor] Poucas edições (${results.length}), resolvendo via Scryfall...');
        results = await provider.resolveAndFetchPrintings(widget.cardName!);
        debugPrint('[BinderItemEditor] Após resolve: ${results.length} edições');
      }

      if (!mounted) return;
      setState(() {
        _printings = results;
        // Selecionar a edição que corresponde ao cardId passado
        if (widget.cardId != null) {
          final idx = _printings.indexWhere(
            (p) => p['id']?.toString() == widget.cardId,
          );
          if (idx >= 0) _selectedPrintingIndex = idx;
        }
      });
    } catch (e) {
      debugPrint('[BinderItemEditor] Erro ao buscar edições: $e');
    } finally {
      if (mounted) setState(() => _loadingPrintings = false);
    }
  }

  /// Retorna o card_id efetivo (da edição selecionada ou o original)
  String? get _effectiveCardId {
    if (_printings.isNotEmpty && _selectedPrintingIndex < _printings.length) {
      return _printings[_selectedPrintingIndex]['id']?.toString();
    }
    return widget.cardId;
  }

  /// Retorna a image_url da edição selecionada (fallback: imagem original)
  String? get _selectedImageUrl {
    if (_printings.isNotEmpty && _selectedPrintingIndex < _printings.length) {
      return _printings[_selectedPrintingIndex]['image_url'] as String?;
    }
    return widget.cardImageUrl;
  }

  /// Retorna o preço de mercado da edição selecionada
  double? get _selectedMarketPrice {
    if (_printings.isNotEmpty && _selectedPrintingIndex < _printings.length) {
      final p = _printings[_selectedPrintingIndex]['price'];
      if (p is num) return p.toDouble();
    }
    return null;
  }

  @override
  void dispose() {
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final data = <String, dynamic>{
      'quantity': _quantity,
      'condition': _condition,
      'is_foil': _isFoil,
      'for_trade': _forTrade,
      'for_sale': _forSale,
      'list_type': _listType,
      'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    };

    // Parse price
    final priceText = _priceController.text.trim();
    if (priceText.isNotEmpty) {
      final parsed = double.tryParse(priceText.replaceAll(',', '.'));
      data['price'] = parsed;
    } else {
      data['price'] = null;
    }

    // Se adicionando, incluir card_id (da edição selecionada)
    if (widget.item == null) {
      data['card_id'] = _effectiveCardId;
    }

    final ok = await widget.onSave?.call(data) ?? false;
    if (!mounted) return;

    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao salvar')),
      );
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceSlate,
        title: const Text('Remover do Fichário?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remover "${widget.item?.cardName}" do seu fichário?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    final ok = await widget.onDelete?.call() ?? false;
    if (!mounted) return;

    if (ok) {
      Navigator.pop(context);
    } else {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final name = widget.item?.cardName ?? widget.cardName ?? 'Carta';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outlineMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Título
            Text(
              isEditing ? 'Editar — $name' : 'Adicionar — $name',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),

            // ===== Arte da carta + Seletor de edição =====
            if (!isEditing) ...[
              // Imagem da carta selecionada
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: CachedCardImage(
                    imageUrl: _selectedImageUrl,
                    width: 180,
                    height: 252,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Preço de mercado
              if (_selectedMarketPrice != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.mythicGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.mythicGold.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Preço de mercado: US\$ ${_selectedMarketPrice!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.mythicGold,
                        fontSize: AppTheme.fontSm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Seletor de edições (horizontal scroll)
              if (_loadingPrintings)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.manaViolet),
                    ),
                  ),
                )
              else if (_printings.isNotEmpty) ...[
                Row(
                  children: [
                    const Text('Edição',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: AppTheme.fontMd)),
                    const Spacer(),
                    Text(
                      '${_printings.length} ${_printings.length == 1 ? 'disponível' : 'disponíveis'}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontSm,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _printings.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final p = _printings[index];
                      final setCode = (p['set_code'] as String? ?? '').toUpperCase();
                      final setName = p['set_name'] as String? ?? setCode;
                      final releaseDate = p['set_release_date'] as String? ?? '';
                      final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
                      final price = p['price'] is num ? (p['price'] as num).toDouble() : null;
                      final isSelected = index == _selectedPrintingIndex;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedPrintingIndex = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.manaViolet.withValues(alpha: 0.25)
                                : AppTheme.surfaceSlate2,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.manaViolet
                                  : AppTheme.outlineMuted,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.manaViolet
                                          : AppTheme.outlineMuted.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      setCode,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  if (year.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      year,
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                  if (price != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '\$${price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppTheme.mythicGold,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                setName,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Lista: Tenho / Quero
            const Text('Lista',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: AppTheme.fontMd)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _listType = 'have'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _listType == 'have'
                            ? AppTheme.loomCyan.withValues(alpha: 0.15)
                            : AppTheme.surfaceSlate2,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(AppTheme.radiusMd)),
                        border: Border.all(
                          color: _listType == 'have'
                              ? AppTheme.loomCyan
                              : AppTheme.outlineMuted,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2,
                              size: 16,
                              color: _listType == 'have'
                                  ? AppTheme.loomCyan
                                  : AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text('Tenho',
                              style: TextStyle(
                                color: _listType == 'have'
                                    ? AppTheme.loomCyan
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _listType = 'want'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _listType == 'want'
                            ? AppTheme.mythicGold.withValues(alpha: 0.15)
                            : AppTheme.surfaceSlate2,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(AppTheme.radiusMd)),
                        border: Border.all(
                          color: _listType == 'want'
                              ? AppTheme.mythicGold
                              : AppTheme.outlineMuted,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border,
                              size: 16,
                              color: _listType == 'want'
                                  ? AppTheme.mythicGold
                                  : AppTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text('Quero',
                              style: TextStyle(
                                color: _listType == 'want'
                                    ? AppTheme.mythicGold
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quantidade
            Row(
              children: [
                const Text('Quantidade',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: AppTheme.fontMd)),
                const Spacer(),
                _QuantityButton(
                  icon: Icons.remove,
                  onTap: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: AppTheme.fontXl,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _QuantityButton(
                  icon: Icons.add,
                  onTap: () => setState(() => _quantity++),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Condição (chips)
            const Text('Condição',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: conditions.map((c) {
                final selected = _condition == c;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  onSelected: (_) => setState(() => _condition = c),
                  selectedColor: AppTheme.manaViolet,
                  backgroundColor: AppTheme.surfaceSlate2,
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppTheme.textSecondary,
                    fontSize: AppTheme.fontSm,
                  ),
                  side: BorderSide(
                    color:
                        selected ? AppTheme.manaViolet : AppTheme.outlineMuted,
                  ),
                  tooltip: conditionLabels[c],
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Foil toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Foil',
                  style: TextStyle(color: AppTheme.textSecondary)),
              secondary: Icon(Icons.auto_awesome,
                  color: _isFoil ? AppTheme.mythicGold : AppTheme.outlineMuted),
              value: _isFoil,
              onChanged: (v) => setState(() => _isFoil = v),
              activeThumbColor: AppTheme.mythicGold,
            ),

            // Para Troca
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponível para troca',
                  style: TextStyle(color: AppTheme.textSecondary)),
              secondary: Icon(Icons.swap_horiz,
                  color:
                      _forTrade ? AppTheme.loomCyan : AppTheme.outlineMuted),
              value: _forTrade,
              onChanged: (v) => setState(() => _forTrade = v),
              activeThumbColor: AppTheme.loomCyan,
            ),

            // Para Venda
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponível para venda',
                  style: TextStyle(color: AppTheme.textSecondary)),
              secondary: Icon(Icons.sell,
                  color:
                      _forSale ? AppTheme.mythicGold : AppTheme.outlineMuted),
              value: _forSale,
              onChanged: (v) => setState(() => _forSale = v),
              activeThumbColor: AppTheme.mythicGold,
            ),

            // Preço
            if (_forSale) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Preço (R\$)',
                  labelStyle:
                      const TextStyle(color: AppTheme.textSecondary),
                  prefixText: 'R\$ ',
                  prefixStyle:
                      const TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    borderSide:
                        const BorderSide(color: AppTheme.outlineMuted),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    borderSide:
                        const BorderSide(color: AppTheme.manaViolet),
                  ),
                ),
              ),
            ],

            // Notas
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Notas (opcional)',
                labelStyle:
                    const TextStyle(color: AppTheme.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide:
                      const BorderSide(color: AppTheme.outlineMuted),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide:
                      const BorderSide(color: AppTheme.manaViolet),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                if (isEditing)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remover'),
                    ),
                  ),
                if (isEditing) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.manaViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isEditing ? 'Salvar' : 'Adicionar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Quantity +/- button
// =====================================================================

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QuantityButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(
            color: onTap != null ? AppTheme.manaViolet : AppTheme.outlineMuted,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? AppTheme.manaViolet : AppTheme.outlineMuted,
        ),
      ),
    );
  }
}
