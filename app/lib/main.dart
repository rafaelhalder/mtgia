import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/api/api_client.dart';
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
import 'features/decks/screens/deck_import_screen.dart';

import 'features/cards/providers/card_provider.dart';
import 'features/cards/screens/card_search_screen.dart';
import 'features/market/providers/market_provider.dart';
import 'features/market/screens/market_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/scanner/screens/card_scanner_screen.dart';
import 'features/community/providers/community_provider.dart';
import 'features/community/screens/community_screen.dart';
import 'features/social/providers/social_provider.dart';
import 'features/social/screens/user_profile_screen.dart';
import 'features/social/screens/user_search_screen.dart';

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
  late final MarketProvider _marketProvider;
  late final CommunityProvider _communityProvider;
  late final SocialProvider _socialProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _deckProvider = DeckProvider();
    _cardProvider = CardProvider();
    _marketProvider = MarketProvider();
    _communityProvider = CommunityProvider();
    _socialProvider = SocialProvider();

    // Log da URL da API no boot
    ApiClient.debugLogBaseUrl();

    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: _authProvider,
      redirect: (context, state) {
        final location = state.matchedLocation;
        final status = _authProvider.status;

        debugPrint('[🧭 Router] redirect: location=$location | status=$status');

        // Sempre permite a Splash (ela decide para onde ir).
        if (location == '/') return null;

        // Não redirecionar enquanto o auth está carregando ou inicializando
        // — evita loop de redirect durante login/register/splash.
        if (status == AuthStatus.loading || status == AuthStatus.initial) {
          debugPrint('[🧭 Router] → null (status=$status, aguardando)');
          return null;
        }

        final isAuthRoute = location == '/login' || location == '/register';
        final isProtectedRoute =
            location.startsWith('/home') ||
            location.startsWith('/decks') ||
            location.startsWith('/market') ||
            location.startsWith('/profile') ||
            location.startsWith('/community');

        if (isProtectedRoute && !_authProvider.isAuthenticated) {
          debugPrint('[🧭 Router] → /login (rota protegida sem auth)');
          return '/login';
        }

        if (isAuthRoute && _authProvider.isAuthenticated) {
          debugPrint('[🧭 Router] → /home (já autenticado)');
          return '/home';
        }

        debugPrint('[🧭 Router] → null (sem redirect)');
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
                  path: 'import',
                  builder: (context, state) => const DeckImportScreen(),
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
                    GoRoute(
                      path: 'scan',
                      builder: (context, state) {
                        final id = state.pathParameters['id']!;
                        return CardScannerScreen(deckId: id);
                      },
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: '/market',
              builder: (context, state) => const MarketScreen(),
            ),
            GoRoute(
              path: '/community',
              builder: (context, state) => const CommunityScreen(),
              routes: [
                GoRoute(
                  path: 'search-users',
                  builder: (context, state) => const UserSearchScreen(),
                ),
                GoRoute(
                  path: 'user/:userId',
                  builder: (context, state) {
                    final userId = state.pathParameters['userId']!;
                    return UserProfileScreen(userId: userId);
                  },
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
        ChangeNotifierProvider.value(value: _marketProvider),
        ChangeNotifierProvider.value(value: _communityProvider),
        ChangeNotifierProvider.value(value: _socialProvider),
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
