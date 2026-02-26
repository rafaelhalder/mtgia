import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/message_provider.dart';

/// Tela de chat direto com bolhas, scroll infinito e polling 5s
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final ConversationUser otherUser;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
      _markAsRead();
    });
    // Polling a cada 5 segundos para novas mensagens
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadMessages(incremental: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMessages({bool incremental = false}) {
    context.read<MessageProvider>().fetchMessages(
          widget.conversationId,
          incremental: incremental,
        );
  }

  void _markAsRead() {
    context.read<MessageProvider>().markAsRead(widget.conversationId);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final ok = await context.read<MessageProvider>().sendMessage(
      widget.conversationId,
      text,
    );
    if (ok && mounted) {
      _markAsRead();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.select<AuthProvider, String?>(
      (auth) => auth.user?.id,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceSlate2,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.manaViolet.withValues(alpha: 0.3),
              backgroundImage: widget.otherUser.avatarUrl != null &&
                      widget.otherUser.avatarUrl!.isNotEmpty
                  ? NetworkImage(widget.otherUser.avatarUrl!)
                  : null,
              child: widget.otherUser.avatarUrl == null ||
                      widget.otherUser.avatarUrl!.isEmpty
                  ? Text(
                      widget.otherUser.label.isNotEmpty
                          ? widget.otherUser.label[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppTheme.manaViolet,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSm,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.otherUser.label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: AppTheme.fontLg,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ─── Lista de mensagens ────────────────────────
          Expanded(
            child: Consumer<MessageProvider>(
              builder: (context, provider, _) {
                if (provider.isLoadingMessages && provider.messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.manaViolet),
                  );
                }

                if (provider.messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhuma mensagem ainda.\nDigite algo para iniciar a conversa!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontMd,
                      ),
                    ),
                  );
                }

                // Mensagens vêm em DESC (mais recente primeiro)
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // mais recente embaixo
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: provider.messages.length,
                  itemBuilder: (context, index) {
                    final msg = provider.messages[index];
                    final isMe = msg.senderId == currentUserId;
                    return _MessageBubble(message: msg, isMe: isMe);
                  },
                );
              },
            ),
          ),

          // ─── Input de mensagem ────────────────────────
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 8,
              bottom: 8 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceSlate2,
              border: Border(
                top: BorderSide(color: AppTheme.outlineMuted, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 4,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Mensagem...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.backgroundAbyss,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<MessageProvider>(
                  builder: (context, provider, _) {
                    return IconButton(
                      onPressed: provider.isSending ? null : _sendMessage,
                      icon: provider.isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.manaViolet,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: AppTheme.manaViolet,
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bolha de mensagem
class _MessageBubble extends StatelessWidget {
  final DirectMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 3,
          bottom: 3,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? AppTheme.manaViolet.withValues(alpha: 0.85)
              : AppTheme.surfaceSlate,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.message,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppTheme.fontMd,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: AppTheme.fontXs,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
