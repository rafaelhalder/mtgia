import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/binder_provider.dart';

/// Modal (BottomSheet) para editar/ver detalhes de um item do fichário.
/// Usado tanto para edição (modo update) quanto para adicionar ao binder.
class BinderItemEditor extends StatefulWidget {
  /// Se não-nulo, estamos editando um item existente.
  final BinderItem? item;

  /// cardId obrigatório para adição. Quando [item] != null, usa item.cardId.
  final String? cardId;
  final String? cardName;

  /// Callbacks
  final Future<bool> Function(Map<String, dynamic> data)? onSave;
  final Future<bool> Function()? onDelete;

  const BinderItemEditor({
    super.key,
    this.item,
    this.cardId,
    this.cardName,
    this.onSave,
    this.onDelete,
  });

  /// Helper estático para abrir o modal
  static Future<void> show(
    BuildContext context, {
    BinderItem? item,
    String? cardId,
    String? cardName,
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
  late TextEditingController _priceController;
  late TextEditingController _notesController;
  bool _saving = false;

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
    _priceController = TextEditingController(
      text: item?.price?.toStringAsFixed(2) ?? '',
    );
    _notesController = TextEditingController(text: item?.notes ?? '');
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

    // Se adicionando, incluir card_id
    if (widget.item == null) {
      data['card_id'] = widget.cardId;
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
            const SizedBox(height: 20),

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
