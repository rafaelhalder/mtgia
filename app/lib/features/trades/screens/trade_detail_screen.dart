import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cached_card_image.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/trade_provider.dart';

/// Tela de detalhe de um trade — Timeline + Items + Chat + Ações
class TradeDetailScreen extends StatefulWidget {
  final String tradeId;
  const TradeDetailScreen({super.key, required this.tradeId});

  @override
  State<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

class _TradeDetailScreenState extends State<TradeDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TradeProvider>().fetchTradeDetail(widget.tradeId);
      // Polling de mensagens a cada 10s
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          context.read<TradeProvider>().fetchMessages(widget.tradeId);
        }
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    context.read<TradeProvider>().clearSelectedTrade();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do Trade')),
      body: Consumer<TradeProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.selectedTrade == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.selectedTrade == null) {
            return Center(
              child: Text(
                provider.errorMessage ?? 'Trade não encontrado',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          final trade = provider.selectedTrade!;
          final currentUserId = context.read<AuthProvider>().user?.id;
          final isSender = trade.sender.id == currentUserId;
          final isReceiver = trade.receiver.id == currentUserId;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusHeader(trade),
                    const SizedBox(height: 16),
                    _buildParticipants(trade, isSender),
                    const SizedBox(height: 16),
                    _buildItems('Itens oferecidos', trade.myItems, Icons.upload),
                    const SizedBox(height: 12),
                    _buildItems('Itens pedidos', trade.theirItems, Icons.download),
                    if (trade.paymentAmount != null) ...[
                      const SizedBox(height: 12),
                      _buildPayment(trade),
                    ],
                    if (trade.trackingCode != null) ...[
                      const SizedBox(height: 12),
                      _buildTracking(trade),
                    ],
                    const SizedBox(height: 16),
                    _buildTimeline(trade.statusHistory),
                    const SizedBox(height: 16),
                    _buildActions(trade, isSender, isReceiver, provider),
                    const SizedBox(height: 16),
                    _buildChat(provider),
                  ],
                ),
              ),
              // Input de mensagem
              if (!['declined', 'cancelled'].contains(trade.status))
                _buildMessageInput(provider),
            ],
          );
        },
      ),
    );
  }

  // ─── Status Header ──────────────────────────────────────────
  Widget _buildStatusHeader(TradeOffer trade) {
    final color = TradeStatusHelper.color(trade.status);
    final icon = TradeStatusHelper.icon(trade.status);
    final label = TradeStatusHelper.label(trade.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: AppTheme.fontXxl,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _typeLabel(trade.type),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
                ),
              ],
            ),
          ),
          if (trade.message != null)
            Tooltip(
              message: trade.message!,
              child: const Icon(
                Icons.info_outline,
                color: AppTheme.textSecondary,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  // ─── Participantes ──────────────────────────────────────────
  Widget _buildParticipants(TradeOffer trade, bool isSender) {
    return Row(
      children: [
        _userChip(trade.sender.label, isSender ? 'Você' : 'Remetente'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.swap_horiz, color: AppTheme.textSecondary),
        ),
        _userChip(trade.receiver.label, !isSender ? 'Você' : 'Destinatário'),
      ],
    );
  }

  Widget _userChip(String name, String role) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceSlate,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.outlineMuted,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: AppTheme.fontMd),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: AppTheme.fontMd),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              role,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Items ──────────────────────────────────────────────────
  Widget _buildItems(String title, List<TradeItem> items, IconData icon) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.loomCyan),
              const SizedBox(width: 6),
              Text(
                '$title (${items.length})',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Divider(color: AppTheme.outlineMuted),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CachedCardImage(
                      imageUrl: item.card.imageUrl,
                      width: 28,
                      height: 40,
                      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.card.name,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: AppTheme.fontMd,
                            ),
                          ),
                          Text(
                            '${item.condition ?? "?"} • x${item.quantity}${item.isFoil == true ? ' ⭐' : ''}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: AppTheme.fontSm,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.agreedPrice != null)
                      Text(
                        'R\$${item.agreedPrice!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppTheme.mythicGold,
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── Pagamento ──────────────────────────────────────────────
  Widget _buildPayment(TradeOffer trade) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.mythicGold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.mythicGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_money, color: AppTheme.mythicGold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'R\$${trade.paymentAmount!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppTheme.mythicGold,
                    fontSize: AppTheme.fontXl,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (trade.paymentMethod != null)
                  Text(
                    'via ${trade.paymentMethod}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Rastreio ───────────────────────────────────────────────
  Widget _buildTracking(TradeOffer trade) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping, color: AppTheme.manaViolet, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Código de rastreio',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontSm),
                ),
                SelectableText(
                  trade.trackingCode!,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trade.deliveryMethod != null)
            Chip(
              label: Text(
                trade.deliveryMethod!,
                style: const TextStyle(fontSize: AppTheme.fontSm),
              ),
              backgroundColor: AppTheme.outlineMuted,
            ),
        ],
      ),
    );
  }

  // ─── Timeline ───────────────────────────────────────────────
  Widget _buildTimeline(List<TradeStatusEntry> history) {
    if (history.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 6),
              Text(
                'Histórico',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Divider(color: AppTheme.outlineMuted),
          ...history.asMap().entries.map((entry) {
            final idx = entry.key;
            final h = entry.value;
            final color = TradeStatusHelper.color(h.newStatus);
            final isLast = idx == history.length - 1;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline line + dot
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: AppTheme.outlineMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TradeStatusHelper.label(h.newStatus),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontSize: AppTheme.fontMd,
                            ),
                          ),
                          if (h.notes != null)
                            Text(
                              h.notes!,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                              fontSize: AppTheme.fontSm,
                            ),
                          ),
                          Text(
                            _formatDate(h.createdAt),
                            style: const TextStyle(
                              color: AppTheme.textHint,
                              fontSize: AppTheme.fontSm,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Ações Dinâmicas ────────────────────────────────────────
  Widget _buildActions(
    TradeOffer trade,
    bool isSender,
    bool isReceiver,
    TradeProvider provider,
  ) {
    final actions = <Widget>[];

    switch (trade.status) {
      case 'pending':
        if (isReceiver) {
          actions.addAll([
            _actionButton(
              label: 'Aceitar',
              icon: Icons.check,
              color: AppTheme.success,
              onTap: () => _respondTrade(provider, trade.id, 'accept'),
            ),
            const SizedBox(width: 8),
            _actionButton(
              label: 'Recusar',
              icon: Icons.close,
              color: AppTheme.error,
              onTap: () => _respondTrade(provider, trade.id, 'decline'),
            ),
          ]);
        }
        if (isSender) {
          actions.add(_actionButton(
            label: 'Cancelar',
            icon: Icons.block,
            color: AppTheme.disabled,
            onTap: () => _updateStatus(provider, trade.id, 'cancelled'),
          ));
        }
        break;

      case 'accepted':
        if (isSender) {
          actions.add(_actionButton(
            label: 'Marcar como Enviado',
            icon: Icons.local_shipping,
            color: AppTheme.manaViolet,
            onTap: () => _showShipDialog(provider, trade.id),
          ));
        }
        actions.add(_actionButton(
          label: 'Cancelar',
          icon: Icons.block,
          color: AppTheme.disabled,
          onTap: () => _updateStatus(provider, trade.id, 'cancelled'),
        ));
        break;

      case 'shipped':
        if (isReceiver) {
          actions.add(_actionButton(
            label: 'Confirmar Entrega',
            icon: Icons.inventory_2,
            color: AppTheme.success,
            onTap: () => _updateStatus(provider, trade.id, 'delivered'),
          ));
        }
        actions.add(_actionButton(
          label: 'Disputar',
          icon: Icons.warning_amber,
          color: AppTheme.error,
          onTap: () => _updateStatus(provider, trade.id, 'disputed'),
        ));
        break;

      case 'delivered':
        actions.addAll([
          _actionButton(
            label: 'Finalizar',
            icon: Icons.check_circle,
            color: AppTheme.success,
            onTap: () => _updateStatus(provider, trade.id, 'completed'),
          ),
          const SizedBox(width: 8),
          _actionButton(
            label: 'Disputar',
            icon: Icons.warning_amber,
            color: AppTheme.error,
            onTap: () => _updateStatus(provider, trade.id, 'disputed'),
          ),
        ]);
        break;
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Row(children: actions);
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: AppTheme.fontMd)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }

  void _respondTrade(TradeProvider provider, String id, String action) async {
    final success = await provider.respondToTrade(id, action);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'accept' ? 'Trade aceito!' : 'Trade recusado.'),
          backgroundColor: action == 'accept'
              ? AppTheme.success
              : AppTheme.error,
        ),
      );
    }
  }

  void _updateStatus(TradeProvider provider, String id, String status) async {
    final success = await provider.updateTradeStatus(id, status);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status atualizado: ${TradeStatusHelper.label(status)}'),
        ),
      );
    }
  }

  void _showShipDialog(TradeProvider provider, String tradeId) {
    final trackingController = TextEditingController();
    String method = 'correios';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceSlate,
        title: const Text('Informar envio', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: trackingController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Código de rastreio (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: method,
              decoration: const InputDecoration(labelText: 'Método de envio'),
              dropdownColor: AppTheme.surfaceSlate,
              items: const [
                DropdownMenuItem(value: 'correios', child: Text('Correios')),
                DropdownMenuItem(value: 'motoboy', child: Text('Motoboy')),
                DropdownMenuItem(value: 'pessoalmente', child: Text('Pessoalmente')),
                DropdownMenuItem(value: 'outro', child: Text('Outro')),
              ],
              onChanged: (v) => method = v ?? method,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.updateTradeStatus(
                tradeId,
                'shipped',
                trackingCode: trackingController.text.isNotEmpty
                    ? trackingController.text
                    : null,
                deliveryMethod: method,
              );
            },
            child: const Text('Confirmar Envio'),
          ),
        ],
      ),
    );
  }

  // ─── Chat ───────────────────────────────────────────────────
  Widget _buildChat(TradeProvider provider) {
    final messages = provider.chatMessages;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Chat (${messages.length})',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (messages.isNotEmpty) ...[
            const Divider(color: AppTheme.outlineMuted),
            ...messages.map((msg) {
              final currentUserId =
                  context.read<AuthProvider>().user?.id;
              final isMe = msg.senderId == currentUserId;

              return Align(
                alignment:
                    isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.65,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppTheme.manaViolet.withValues(alpha: 0.2)
                        : AppTheme.outlineMuted,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!isMe)
                        Text(
                          msg.senderUsername ?? '',
                          style: TextStyle(
                            color: AppTheme.loomCyan,
                            fontSize: AppTheme.fontSm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (msg.message != null)
                        Text(
                          msg.message!,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: AppTheme.fontMd,
                          ),
                        ),
                      if (msg.attachmentUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '📎 ${msg.attachmentType ?? "anexo"}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: AppTheme.fontSm,
                            ),
                          ),
                        ),
                      Text(
                        _formatTime(msg.createdAt),
                        style: const TextStyle(
                          color: AppTheme.textHint,
                          fontSize: AppTheme.fontXs,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhuma mensagem ainda',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: AppTheme.fontMd),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Input de Mensagem ──────────────────────────────────────
  Widget _buildMessageInput(TradeProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.surfaceSlate,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Escrever mensagem...',
                  hintStyle: const TextStyle(color: AppTheme.textHint),
                  filled: true,
                  fillColor: AppTheme.surfaceSlate2,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () async {
                final text = _messageController.text.trim();
                if (text.isEmpty) return;
                _messageController.clear();
                await provider.sendMessage(widget.tradeId, text);
              },
              icon: const Icon(Icons.send, color: AppTheme.manaViolet),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────
  String _typeLabel(String type) {
    switch (type) {
      case 'trade':
        return 'Troca de cartas';
      case 'sale':
        return 'Compra/Venda';
      case 'mixed':
        return 'Troca + Pagamento';
      default:
        return type;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${_formatTime(dt)}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
