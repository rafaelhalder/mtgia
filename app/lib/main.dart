import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'features/decks/screens/deck_list_screen.dart';
import 'features/decks/providers/deck_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/providers/auth_provider.dart';

import 'core/widgets/main_scaffold.dart';

import 'features/decks/screens/deck_details_screen.dart';
import 'features/decks/screens/deck_generate_screen.dart';

import 'features/cards/providers/card_provider.dart';
import 'features/cards/screens/card_search_screen.dart';

void main() {
  runApp(const ManaLoomApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    // Splash Screen
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    
    // Auth Routes
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    
    // Protected Routes (com Bottom Navigation)
    ShellRoute(
      builder: (context, state, child) {
        return MainScaffold(child: child);
      },
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/decks',
          builder: (context, state) => const DeckListScreen(),
          routes: [
            GoRoute(
              path: 'generate',
              builder: (context, state) => const DeckGenerateScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return DeckDetailsScreen(deckId: id);
              },
              routes: [
                GoRoute(
                  path: 'search',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return CardSearchScreen(deckId: id);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

class ManaLoomApp extends StatelessWidget {
  const ManaLoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DeckProvider()),
        ChangeNotifierProvider(create: (_) => CardProvider()),
      ],
      child: MaterialApp.router(
        title: 'ManaLoom - AI Deck Builder',
        theme: AppTheme.darkTheme,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
