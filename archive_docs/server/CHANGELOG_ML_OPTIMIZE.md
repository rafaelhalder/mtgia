# Changelog: Sistema ML + Otimização de Decks

## Resumo das Mudanças (De/Para)

### 1. Estrutura de Dados ML (Novas Tabelas)

| Antes | Agora |
|-------|-------|
| Sem tabelas de conhecimento ML | `card_meta_insights` - 878 cards analisados |
| Sem sinergias mapeadas | `synergy_packages` - 500 combos documentados |
| Arquétipos hardcoded | `archetype_patterns` - 6 padrões aprendidos |
| Sem feedback loop | `ml_prompt_feedback` - log de otimizações |
| Sem meta decks | `meta_decks` + `meta_deck_cards` - dados do MTGTop8 |
| Sem estado do modelo | `ml_learning_state` - versão e config ativa |

### 2. Endpoint `/ai/optimize` 

| Antes | Agora |
|-------|-------|
| Apenas IA genérica OpenAI | Monte Carlo + Critic AI + EDHREC + ML |
| Sem análise de arquétipo | `DeckArchetypeAnalyzer` detecta aggro/control/combo/midrange/stax |
| Sem análise de tema | `ThemeProfile` detecta tribal/voltron/tokens/reanimator/etc |
| `commanders.first` crashava | `commanders.firstOrNull ?? ""` (safe) |
| `symbols.values.reduce` crashava | `symbols.values.fold` (safe para vazio) |
| Sem simulações | `monteCarlo` com 1000 mãos iniciais |
| Sem validação pós-otimização | `critic_ai_analysis` valida sugestões |
| Resposta simples | Resposta completa com análises |

#### Estrutura de Resposta Antiga vs Nova

**Antes:**
```json
{
  "removals": ["Card A"],
  "additions": ["Card B"],
  "reasoning": "..."
}
```

**Agora:**
```json
{
  "mode": "optimize",
  "removals": ["Card A"],
  "additions": ["Card B"],
  "removals_detailed": [{"card_id": "uuid", "quantity": 1, "name": "Card A"}],
  "additions_detailed": [{"card_id": "uuid", "quantity": 1, "name": "Card B"}],
  "reasoning": "...",
  "deck_analysis": {
    "detected_archetype": "aggro",
    "average_cmc": "2.35",
    "type_distribution": {"creatures": 30, "instants": 10, ...},
    "total_cards": 100,
    "mana_curve_assessment": "Curva adequada para aggro",
    "mana_base_assessment": "Base de mana equilibrada",
    "archetype_confidence": "high"
  },
  "post_analysis": {...},  // Análise após otimização
  "theme": {
    "theme": "tribal:goblins",
    "score": 0.75,
    "core_cards": ["Goblin Warchief", "Krenko"]
  },
  "constraints": {"keep_theme": true},
  "bracket": 2,
  "monteCarlo": {
    "simulations": 1000,
    "opening_hands": {...},
    "mana_flood_rate": 0.12,
    "mana_screw_rate": 0.08,
    "playable_turn_1": 0.65
  },
  "critic_ai_analysis": {
    "overall_score": 85,
    "strengths": ["Curva agressiva", "Sinergia tribal forte"],
    "weaknesses": ["Pouca remoção", "Vulnerável a boardwipes"]
  },
  "validation_warnings": [],
  "warnings": {}
}
```

### 3. Novo Endpoint `/ai/ml-status`

| Campo | Descrição |
|-------|-----------|
| `status` | "active", "empty", "not_initialized", "error" |
| `model_version` | Versão do modelo (ex: "v1.0-imitation-learning") |
| `stats.card_insights` | Quantidade de cards analisados |
| `stats.synergy_packages` | Quantidade de combos documentados |
| `stats.archetype_patterns` | Quantidade de padrões de arquétipo |
| `stats.feedback_records` | Quantidade de feedbacks coletados |
| `stats.meta_decks_loaded` | Quantidade de meta decks no sistema |
| `performance.total_optimizations` | Total de otimizações realizadas |
| `performance.avg_effectiveness_score` | Score médio de efetividade |

### 4. Inferência de Arquétipo

| Antes | Agora |
|-------|-------|
| Meta decks sem arquétipo | Inferência automática por keywords |
| Apenas 2 arquétipos vazios | 6 arquétipos populados: aggro, combo, combo-control, control, tribal, value |

#### Lógica de Inferência (`_inferArchetypeFromCards`):
```dart
// Palavras-chave por arquétipo
control: counterspell, removal, board wipe, draw card
aggro: haste, first strike, +1/+1, attack
combo: infinite, tutor, storm, untap
ramp: add mana, search land, mana dork
tribal: lords, tribal synergy, creature type matters
```

### 5. Tratamento de Erros

| Antes | Agora |
|-------|-------|
| `.first` em listas vazias → `StateError` | `.firstOrNull ?? fallback` |
| `.reduce` em listas vazias → `StateError` | `.fold(0, (a,b) => a+b)` |
| Deck sem comandante → crash | Retorna erro 400 claro |
| Sem API key → crash | Retorna mock response |

### 6. Scripts de Extração ML

| Script | Função |
|--------|--------|
| `bin/migrate_ml_knowledge.dart` | Cria tabelas de ML |
| `bin/extract_meta_insights.dart` | Extrai padrões de meta decks |
| `bin/extract_meta_insights.dart --full` | Extração completa forçada |

---

## Estado Atual (Fevereiro 2025)

- **card_insights**: 878 cartas analisadas
- **synergy_packages**: 500 combos mapeados  
- **archetype_patterns**: 6 arquétipos (aggro, combo, combo-control, control, tribal, value)
- **Endpoint `/ai/optimize`**: Funcional com Monte Carlo + Critic AI
- **Endpoint `/ai/ml-status`**: Retorna estatísticas do modelo

## Próximos Passos

1. [ ] Coletar feedback de otimizações para refinar modelo
2. [ ] Adicionar mais arquétipos (voltron, stax, aristocrats)
3. [ ] Implementar detecção de combos específicos
4. [ ] Dashboard de ML no Flutter
