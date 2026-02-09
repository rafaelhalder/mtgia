import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/social_provider.dart';
import 'user_profile_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<SocialProvider>().searchUsers(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Buscar Usuários'),
        backgroundColor: AppTheme.surfaceSlate2,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(12),
            color: AppTheme.surfaceSlate2,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar por nome de usuário...',
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.loomCyan),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear,
                      color: AppTheme.textSecondary, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    context.read<SocialProvider>().clearSearch();
                  },
                ),
                filled: true,
                fillColor: AppTheme.surfaceSlate,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          // Results
          Expanded(
            child: Consumer<SocialProvider>(
              builder: (context, provider, _) {
                if (provider.isSearching) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.manaViolet),
                  );
                }

                if (provider.searchError != null) {
                  return Center(
                    child: Text(
                      provider.searchError!,
                      style:
                          const TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }

                if (_searchController.text.trim().isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search,
                            size: 64,
                            color: AppTheme.textSecondary.withValues(
                                alpha: 0.4)),
                        const SizedBox(height: 16),
                        const Text(
                          'Digite para buscar usuários',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (provider.searchResults.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            size: 48,
                            color: AppTheme.textSecondary.withValues(
                                alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text(
                          'Nenhum usuário encontrado',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: provider.searchResults.length,
                  itemBuilder: (context, index) {
                    final user = provider.searchResults[index];
                    return _UserSearchCard(
                      user: user,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                UserProfileScreen(userId: user.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserSearchCard extends StatelessWidget {
  final PublicUser user;
  final VoidCallback onTap;

  const _UserSearchCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.surfaceSlate,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.outlineMuted, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    AppTheme.manaViolet.withValues(alpha: 0.3),
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        user.username[0].toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.manaViolet,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? user.username,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (user.displayName != null)
                      Text(
                        '@${user.username}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.style,
                            size: 13, color: AppTheme.loomCyan.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          '${user.publicDeckCount} decks',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.people,
                            size: 13,
                            color: AppTheme.manaViolet.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          '${user.followerCount} seguidores',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
