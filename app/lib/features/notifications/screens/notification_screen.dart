import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/notification_provider.dart';

/// Tela de notificações do app
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundAbyss,
        title: const Text(
          'Notificações',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => provider.markAllAsRead(),
                child: const Text(
                  'Ler todas',
                  style: TextStyle(
                    color: AppTheme.manaViolet,
                    fontSize: AppTheme.fontSm,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.notifications.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.manaViolet),
            );
          }

          if (provider.notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 64,
                        color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    const Text(
                      'Nenhuma notificação',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontLg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppTheme.manaViolet,
            onRefresh: () => provider.fetchNotifications(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: provider.notifications.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppTheme.outlineMuted,
                indent: 56,
              ),
              itemBuilder: (context, index) {
                final notif = provider.notifications[index];
                return _NotificationTile(
                  notification: notif,
                  onTap: () {
                    if (!notif.isRead) {
                      provider.markAsRead(notif.id);
                    }
                    _navigateToContext(context, notif);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Navega para o contexto da notificação
  void _navigateToContext(BuildContext context, AppNotification notif) {
    final refId = notif.referenceId;
    if (refId == null) return;

    switch (notif.type) {
      case 'new_follower':
        context.push('/community/user/$refId');
        break;
      case 'trade_offer_received':
      case 'trade_accepted':
      case 'trade_declined':
      case 'trade_shipped':
      case 'trade_delivered':
      case 'trade_completed':
      case 'trade_message':
        context.push('/trades/$refId');
        break;
      case 'direct_message':
        // refId = conversationId → navega direto para o inbox de mensagens
        context.push('/messages');
        break;
    }
  }
}

/// Tile de notificação individual
class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification.isRead;

    return ListTile(
      onTap: onTap,
      tileColor: isRead ? null : AppTheme.manaViolet.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: _typeColor(notification.type).withValues(alpha: 0.2),
        child: Icon(
          _typeIcon(notification.type),
          color: _typeColor(notification.type),
          size: 20,
        ),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
          fontSize: AppTheme.fontMd,
        ),
      ),
      subtitle: notification.body != null
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                notification.body!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: AppTheme.fontSm,
                ),
              ),
            )
          : null,
      trailing: Text(
        _formatRelative(notification.createdAt),
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: AppTheme.fontXs,
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'new_follower':
        return Icons.person_add;
      case 'trade_offer_received':
        return Icons.inbox;
      case 'trade_accepted':
        return Icons.check_circle;
      case 'trade_declined':
        return Icons.cancel;
      case 'trade_shipped':
        return Icons.local_shipping;
      case 'trade_delivered':
        return Icons.inventory;
      case 'trade_completed':
        return Icons.done_all;
      case 'trade_message':
        return Icons.message;
      case 'direct_message':
        return Icons.chat_bubble;
      default:
        return Icons.notifications;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'new_follower':
        return AppTheme.loomCyan;
      case 'trade_offer_received':
        return AppTheme.mythicGold;
      case 'trade_accepted':
        return Colors.green;
      case 'trade_declined':
        return AppTheme.error;
      case 'trade_shipped':
        return Colors.orange;
      case 'trade_delivered':
        return AppTheme.loomCyan;
      case 'trade_completed':
        return Colors.green;
      case 'trade_message':
        return AppTheme.manaViolet;
      case 'direct_message':
        return AppTheme.manaViolet;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _formatRelative(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'agora';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}sem';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}

