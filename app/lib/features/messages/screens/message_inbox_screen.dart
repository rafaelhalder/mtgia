import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/message_provider.dart';
import 'chat_screen.dart';

/// Tela Inbox de mensagens diretas — lista de conversas
class MessageInboxScreen extends StatefulWidget {
  const MessageInboxScreen({super.key});

  @override
  State<MessageInboxScreen> createState() => _MessageInboxScreenState();
}

class _MessageInboxScreenState extends State<MessageInboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageProvider>().fetchConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundAbyss,
        title: const Text(
          'Mensagens',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Consumer<MessageProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.conversations.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.manaViolet),
            );
          }

          if (provider.conversations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 64,
                        color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    const Text(
                      'Nenhuma conversa',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontLg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Envie mensagem para alguém pelo perfil!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontMd,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppTheme.manaViolet,
            onRefresh: () => provider.fetchConversations(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: provider.conversations.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppTheme.outlineMuted,
                indent: 72,
              ),
              itemBuilder: (context, index) {
                final conv = provider.conversations[index];
                return _ConversationTile(
                  conversation: conv,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          conversationId: conv.id,
                          otherUser: conv.otherUser,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = conversation.otherUser;
    final hasUnread = conversation.unreadCount > 0;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.manaViolet.withValues(alpha: 0.3),
        backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
            ? NetworkImage(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null || user.avatarUrl!.isEmpty
            ? Text(
                user.label.isNotEmpty ? user.label[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppTheme.manaViolet,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTheme.fontLg,
                ),
              )
            : null,
      ),
      title: Text(
        user.label,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
          fontSize: AppTheme.fontMd,
        ),
      ),
      subtitle: conversation.lastMessage != null
          ? Text(
              conversation.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: AppTheme.fontSm,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            Text(
              _formatTime(conversation.lastMessageAt!),
              style: TextStyle(
                color: hasUnread ? AppTheme.manaViolet : AppTheme.textSecondary,
                fontSize: AppTheme.fontXs,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.manaViolet,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTheme.fontXs,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'agora';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}
