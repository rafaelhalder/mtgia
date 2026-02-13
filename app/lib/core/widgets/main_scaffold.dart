import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../../features/messages/providers/message_provider.dart';
import '../../features/notifications/providers/notification_provider.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Determina o índice atual com base na rota
    final String location = GoRouterState.of(context).uri.toString();
    int currentIndex = 0;
    if (location.startsWith('/decks')) {
      currentIndex = 1;
    } else if (location.startsWith('/collection') ||
        location.startsWith('/trades')) {
      currentIndex = 2;
    } else if (location.startsWith('/community')) {
      currentIndex = 3;
    } else if (location.startsWith('/profile')) {
      currentIndex = 4;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundAbyss,
        elevation: 0,
        toolbarHeight: 40,
        automaticallyImplyLeading: false,
        actions: [
          // Ícone de mensagens com badge de não-lidas
          Selector<MessageProvider, int>(
            selector: (_, p) => p.unreadCount,
            builder: (context, msgUnread, child) {
              return IconButton(
                icon: Badge(
                  isLabelVisible: msgUnread > 0,
                  label: Text(
                    msgUnread > 99 ? '99+' : '$msgUnread',
                    style: const TextStyle(fontSize: 9),
                  ),
                  backgroundColor: AppTheme.loomCyan,
                  child: const Icon(Icons.chat_bubble_outline,
                      color: AppTheme.textSecondary, size: 22),
                ),
                onPressed: () => context.push('/messages'),
                tooltip: 'Mensagens',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              );
            },
          ),
          // Ícone de notificações com badge
          Selector<NotificationProvider, int>(
            selector: (_, p) => p.unreadCount,
            builder: (context, unreadCount, child) {
              return IconButton(
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(fontSize: 9),
                  ),
                  backgroundColor: AppTheme.error,
                  child: const Icon(Icons.notifications_outlined,
                      color: AppTheme.textSecondary, size: 22),
                ),
                onPressed: () => context.push('/notifications'),
                tooltip: 'Notificações',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/decks');
              break;
            case 2:
              context.go('/collection');
              break;
            case 3:
              context.go('/community');
              break;
            case 4:
              context.go('/profile');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Decks',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Coleção',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Comunidade',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
