import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../providers/trade_provider.dart';
import '../../binder/providers/binder_provider.dart';

/// Tela para criar uma proposta de trade
class CreateTradeScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;

  const CreateTradeScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
  });

  @override
  State<CreateTradeScreen> createState() => _CreateTradeScreenState();
}

class _CreateTradeScreenState extends State<CreateTradeScreen> {
  String _type = 'trade';
  final _messageController = TextEditingController();
  final _paymentController = TextEditingController();
  String? _paymentMethod;

  // Items selecionados
  final List<Map<String, dynamic>> _mySelectedItems = [];
  final List<Map<String, dynamic>> _requestedSelectedItems = [];

  // Binder items carregados
  List<BinderItem> _myBinderItems = [];
  List<BinderItem> _theirBinderItems = [];
  bool _loadingMy = true;
  bool _loadingTheir = true;

  @override
  void initState() {
    super.initState();
    _loadBinders();
  }

  Future<void> _loadBinders() async {
    final binderProvider = context.read<BinderProvider>();

    // My binder (for_trade = true)
    binderProvider.applyFilters(forTrade: true);
    await binderProvider.fetchMyBinder(reset: true);
    if (mounted) {
      setState(() {
        _myBinderItems = List.from(binderProvider.items);
        _loadingMy = false;
      });
    }

    // Their binder (from community endpoint)
    await binderProvider.fetchPublicBinder(widget.receiverId, reset: true);
    if (mounted) {
      setState(() {
        _theirBinderItems = List.from(binderProvider.publicItems);
        _loadingTheir = false;
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_type == 'trade' && (_mySelectedItems.isEmpty || _requestedSelectedItems.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Troca pura exige itens de ambos os lados')),
      );
      return;
    }
    if (_mySelectedItems.isEmpty && _requestedSelectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione pelo menos 1 item')),
      );
      return;
    }

    final provider = context.read<TradeProvider>();
    final success = await provider.createTrade(
      receiverId: widget.receiverId,
      type: _type,
      message: _messageController.text.isNotEmpty ? _messageController.text : null,
      myItems: _mySelectedItems,
      requestedItems: _requestedSelectedItems,
      paymentAmount: _paymentController.text.isNotEmpty
          ? double.tryParse(_paymentController.text)
          : null,
      paymentMethod: _paymentMethod,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proposta enviada! ✅'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Erro ao criar proposta'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trade com ${widget.receiverName}'),
        actions: [
          Consumer<TradeProvider>(
            builder: (context, provider, _) {
              return TextButton.icon(
                onPressed: provider.isLoading ? null : _submit,
                icon: provider.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Enviar'),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tipo de trade
            const Text(
              'Tipo',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: AppTheme.fontLg,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'trade', label: Text('Troca'), icon: Icon(Icons.swap_horiz)),
                ButtonSegment(value: 'sale', label: Text('Venda'), icon: Icon(Icons.attach_money)),
                ButtonSegment(value: 'mixed', label: Text('Misto'), icon: Icon(Icons.merge)),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.manaViolet.withValues(alpha: 0.2),
                selectedForegroundColor: AppTheme.manaViolet,
              ),
            ),
            const SizedBox(height: 20),

            // Meus itens
            _buildItemSection(
              title: 'Meus itens (oferecendo)',
              icon: Icons.upload,
              items: _myBinderItems,
              selectedItems: _mySelectedItems,
              isLoading: _loadingMy,
              isMine: true,
            ),
            const SizedBox(height: 20),

            // Itens deles
            _buildItemSection(
              title: 'Itens de ${widget.receiverName} (pedindo)',
              icon: Icons.download,
              items: _theirBinderItems,
              selectedItems: _requestedSelectedItems,
              isLoading: _loadingTheir,
              isMine: false,
            ),
            const SizedBox(height: 20),

            // Pagamento (se sale ou mixed)
            if (_type != 'trade') ...[
              const Text(
                'Pagamento',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: AppTheme.fontLg,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _paymentController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(labelText: 'Método'),
                      dropdownColor: AppTheme.surfaceSlate,
                      items: const [
                        DropdownMenuItem(value: 'pix', child: Text('Pix')),
                        DropdownMenuItem(value: 'transfer', child: Text('Transferência')),
                        DropdownMenuItem(value: 'cash', child: Text('Dinheiro')),
                      ],
                      onChanged: (v) => setState(() => _paymentMethod = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // Mensagem
            TextField(
              controller: _messageController,
              maxLines: 3,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Mensagem (opcional)',
                hintText: 'Ex: Tenho interesse nessas cartas...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildItemSection({
    required String title,
    required IconData icon,
    required List<BinderItem> items,
    required List<Map<String, dynamic>> selectedItems,
    required bool isLoading,
    required bool isMine,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.loomCyan),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: AppTheme.fontLg,
              ),
            ),
            const Spacer(),
            Text(
              '${selectedItems.length} selecionados',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSlate,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Center(
              child: Text(
                'Nenhum item disponível',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppTheme.surfaceSlate,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(
                color: AppTheme.outlineMuted,
                height: 1,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = selectedItems.any(
                  (s) => s['binder_item_id'] == item.id,
                );

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: CachedCardImage(
                    imageUrl: item.cardImageUrl,
                    width: 36,
                    height: 50,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  title: Text(
                    item.cardName,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: AppTheme.fontMd),
                  ),
                  subtitle: Text(
                    '${item.condition} • x${item.quantity}${item.isFoil ? ' ⭐ Foil' : ''}${item.price != null ? ' • R\$${item.price!.toStringAsFixed(2)}' : ''}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm),
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    activeColor: AppTheme.manaViolet,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          selectedItems.add({
                            'binder_item_id': item.id,
                            'quantity': 1,
                            'agreed_price': item.price,
                          });
                        } else {
                          selectedItems.removeWhere(
                            (s) => s['binder_item_id'] == item.id,
                          );
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
