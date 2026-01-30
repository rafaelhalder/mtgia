import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../auth/providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      await auth.refreshProfile();
      final user = auth.user;
      if (!mounted || user == null) return;
      _displayNameController.text = user.displayName ?? '';
      _avatarUrlController.text = user.avatarUrl ?? '';
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateProfile(
      displayName: _displayNameController.text.trim(),
      avatarUrl: _avatarUrlController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Falha ao atualizar perfil'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: theme.colorScheme.surface,
                      backgroundImage: (user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty)
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: (user.avatarUrl == null || user.avatarUrl!.trim().isEmpty)
                          ? Text(
                              (user.displayName ?? user.username).trim().isNotEmpty
                                  ? (user.displayName ?? user.username).trim().characters.first.toUpperCase()
                                  : '?',
                              style: theme.textTheme.headlineMedium,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      user.username,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Center(
                    child: Text(
                      user.email,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome exibido',
                      hintText: 'Como você quer aparecer',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _avatarUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Avatar URL',
                      hintText: 'https://...',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Salvando...' : 'Salvar'),
                  ),
                ],
              ),
            ),
    );
  }
}

