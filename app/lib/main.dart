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
import 'features/profile/profile_screen.dart';

void main() {
  runApp(const ManaLoomApp());
}

class ManaLoomApp extends StatefulWidget {
  const ManaLoomApp({super.key});

  @override
  State<ManaLoomApp> createState() => _ManaLoomAppState();
}

class _ManaLoomAppState extends State<ManaLoomApp> {
  late final AuthProvider _authProvider;
  late final DeckProvider _deckProvider;
  late final CardProvider _cardProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _deckProvider = DeckProvider();
    _cardProvider = CardProvider();

    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _authProvider,
      redirect: (context, state) {
        final location = state.matchedLocation;

        // Sempre permite a Splash (ela decide para onde ir).
        if (location == '/') return null;

        final isAuthRoute = location == '/login' || location == '/register';
        final isProtectedRoute =
            location.startsWith('/home') || location.startsWith('/decks');

        if (isProtectedRoute && !_authProvider.isAuthenticated) {
          return '/login';
        }

        if (isAuthRoute && _authProvider.isAuthenticated) {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),

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
                        final mode = state.uri.queryParameters['mode'];
                        return CardSearchScreen(deckId: id, mode: mode);
                      },
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _deckProvider),
        ChangeNotifierProvider.value(value: _cardProvider),
      ],
      child: MaterialApp.router(
        title: 'ManaLoom - Deck Builder',
        theme: AppTheme.darkTheme,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
