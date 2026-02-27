import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/models/user.dart';
import '../auth/providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  final _cityController = TextEditingController();
  final _tradeNotesController = TextEditingController();
  String? _selectedState;
  bool _isSaving = false;

  static const _brazilStates = [
    'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO',
    'MA', 'MG', 'MS', 'MT', 'PA', 'PB', 'PE', 'PI', 'PR',
    'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO',
  ];

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
      _cityController.text = user.locationCity ?? '';
      _tradeNotesController.text = user.tradeNotes ?? '';
      setState(() {
        _selectedState = user.locationState;
      });
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    _cityController.dispose();
    _tradeNotesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final auth = context.read<AuthProvider>();
    final avatarText = _avatarUrlController.text.trim();
    final cityText = _cityController.text.trim();
    final tradeNotesText = _tradeNotesController.text.trim();
    final ok = await auth.updateProfile(
      displayName: _displayNameController.text.trim(),
      avatarUrl: avatarText.isEmpty ? null : avatarText,
      locationState: _selectedState,
      locationCity: cityText.isEmpty ? null : cityText,
      tradeNotes: tradeNotesText.isEmpty ? null : tradeNotesText,
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

  void _showAvatarDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: _avatarUrlController.text);
        return AlertDialog(
          title: const Text('Alterar foto de perfil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cole a URL de uma imagem (ex: link do Imgur, Gravatar, etc.)',
                style: TextStyle(fontSize: AppTheme.fontMd, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'URL da imagem',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            if (_avatarUrlController.text.isNotEmpty)
              TextButton(
                onPressed: () {
                  _avatarUrlController.clear();
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('Remover foto', style: TextStyle(color: AppTheme.error)),
              ),
            ElevatedButton(
              onPressed: () {
                _avatarUrlController.text = controller.text.trim();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.select<AuthProvider, User?>((p) => p.user);

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
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                          backgroundImage: (user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty)
                              ? CachedNetworkImageProvider(user.avatarUrl!)
                              : null,
                          child: (user.avatarUrl == null || user.avatarUrl!.trim().isEmpty)
                              ? Text(
                                  (user.displayName ?? user.username).trim().isNotEmpty
                                      ? (user.displayName ?? user.username).trim().characters.first.toUpperCase()
                                      : '?',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                            ),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _showAvatarDialog(context),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Configurações',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nick / Apelido',
                      hintText: 'Ex: Planeswalker42',
                      prefixIcon: Icon(Icons.face),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Seu nick público — é como os outros jogadores vão te encontrar na busca e ver nos seus decks. Se não preencher, será usado o nome de usuário (@${user.username}).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontSm,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Localização
                  Text(
                    'Localização',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Informe sua localização para facilitar trocas presenciais com outros jogadores.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: AppTheme.fontSm,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Estado dropdown
                      SizedBox(
                        width: 116,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedState,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                          ),
                          dropdownColor: AppTheme.surfaceSlate,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('--'),
                            ),
                            ..._brazilStates.map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s),
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedState = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Cidade
                      Expanded(
                        child: TextField(
                          controller: _cityController,
                          decoration: const InputDecoration(
                            labelText: 'Cidade',
                            hintText: 'Ex: São Paulo',
                            prefixIcon: Icon(Icons.location_city, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Observação de troca
                  TextField(
                    controller: _tradeNotesController,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Observação para trocas',
                      hintText: 'Ex: Consigo entregar em mãos em SP, ou deixo na loja X em Curitiba...',
                      prefixIcon: Icon(Icons.info_outline, size: 20),
                      alignLabelWithHint: true,
                    ),
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
                  const SizedBox(height: 32),
                  const Divider(color: AppTheme.outlineMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Coleção',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/collection?tab=0'),
                          icon: const Icon(Icons.collections_bookmark),
                          label: const Text('Meu Fichário'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/collection?tab=1'),
                          icon: const Icon(Icons.store),
                          label: const Text('Marketplace'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

