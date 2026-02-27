import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/activation_funnel_service.dart';
import '../../core/theme/app_theme.dart';

class OnboardingCoreFlowScreen extends StatefulWidget {
  const OnboardingCoreFlowScreen({super.key});

  @override
  State<OnboardingCoreFlowScreen> createState() => _OnboardingCoreFlowScreenState();
}

class _OnboardingCoreFlowScreenState extends State<OnboardingCoreFlowScreen> {
  final List<String> _formats = const [
    'commander',
    'standard',
    'modern',
    'pioneer',
    'legacy',
    'vintage',
    'pauper',
  ];

  String _selectedFormat = 'commander';

  @override
  void initState() {
    super.initState();
    ActivationFunnelService.instance.track(
      'core_flow_started',
      source: 'onboarding',
    );
  }

  Future<void> _trackFormatAndContinue() async {
    await ActivationFunnelService.instance.track(
      'format_selected',
      format: _selectedFormat,
      source: 'onboarding',
    );
  }

  Future<void> _chooseGenerate() async {
    await _trackFormatAndContinue();
    await ActivationFunnelService.instance.track(
      'base_choice_generate',
      format: _selectedFormat,
      source: 'onboarding',
    );
    if (!mounted) return;
    context.go('/decks/generate?format=$_selectedFormat&from=onboarding');
  }

  Future<void> _chooseImport() async {
    await _trackFormatAndContinue();
    await ActivationFunnelService.instance.track(
      'base_choice_import',
      format: _selectedFormat,
      source: 'onboarding',
    );
    if (!mounted) return;
    context.go('/decks/import?format=$_selectedFormat&from=onboarding');
  }

  Future<void> _completeGuide() async {
    await ActivationFunnelService.instance.track(
      'onboarding_completed',
      format: _selectedFormat,
      source: 'onboarding',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Abra um deck e toque em “Otimizar Deck” para concluir o fluxo.')),
    );
    context.go('/decks');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.backgroundAbyss,
      appBar: AppBar(
        title: const Text('Criar e Otimizar Deck'),
        backgroundColor: AppTheme.surfaceSlate2,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StepCard(
            step: '1',
            title: 'Escolha o formato',
            description: 'Defina o formato principal antes de criar a base.',
            child: DropdownButtonFormField<String>(
              initialValue: _selectedFormat,
              decoration: const InputDecoration(labelText: 'Formato'),
              items: _formats
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(f[0].toUpperCase() + f.substring(1)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedFormat = value);
              },
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            step: '2',
            title: 'Monte a base inicial',
            description: 'Você pode gerar com IA ou importar uma lista existente.',
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _chooseGenerate,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Gerar com IA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.manaViolet,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chooseImport,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Importar lista'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            step: '3',
            title: 'Aplique otimização guiada',
            description:
                'Depois de criar seu deck, abra os detalhes e toque em “Otimizar Deck”.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resultado esperado: comparação Antes vs Depois + sugestões com confiança.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton(
                    onPressed: _completeGuide,
                    child: const Text('Ir para meus decks'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.description,
    required this.child,
  });

  final String step;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceSlate,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.outlineMuted),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.manaViolet,
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
