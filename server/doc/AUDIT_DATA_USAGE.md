# Auditoria: Dados Subutilizados no Banco

**Data:** 2025-03-13
**Autor:** Copilot (análise automatizada)

## Resumo Executivo

Identificamos **5 oportunidades principais** de melhoria, onde dados existentes no banco não estão sendo aproveitados pelo código de otimização.

---

## 🔴 CRÍTICO: MLKnowledgeService não integrado

### Situação
O arquivo `server/lib/ml_knowledge_service.dart` contém uma classe completa `MLKnowledgeService` que:
- Busca padrões de arquétipos (`archetype_patterns`)
- Busca sinergias relevantes (`synergy_packages`)
- Busca insights de cartas (`card_meta_insights`)
- Retorna recomendações baseadas em dados históricos

### Problema
Esta classe **NÃO está sendo usada** no `routes/ai/optimize/index.dart`.

### Impacto
- Não aproveita dados de 1,842 card insights
- Não considera padrões de arquétipos conhecidos
- Não usa sinergias identificadas automaticamente

### Ação Recomendada
Integrar `MLKnowledgeService` no `DeckOptimizerService` similar à integração de `FormatStaplesService`.

---

## 🟠 ALTO: archetype_counters (hate cards)

### Dados Disponíveis
```
10 registros com:
- archetype: 'graveyard', 'artifacts', 'tokens', etc
- hate_cards: ['Rest in Peace', "Grafdigger's Cage", ...]
- effectiveness_score: 1-10
- notes: 'Essencial contra Muldrotha, Meren, Karador'
```

### Situação Atual
- Usado apenas em `/ai/weakness-analysis` e `/ai/simulate-matchup`
- **NÃO usado** no optimize para sugerir sideboard ou respostas

### Impacto
Ao otimizar um deck aggro, poderia sugerir incluir hate cards contra counters comuns.

### Ação Recomendada
No modo "optimize", se detectar que deck tem poucas respostas a arquétipos específicos, consultar `archetype_counters` e sugerir cartas de hate.

---

## 🟡 MÉDIO: card_meta_insights.top_pairs

### Dados Disponíveis
```
1,842 cartas com:
- top_pairs: [{"card": "Sol Ring", "count": 35}, ...]
- Mostra quais cartas frequentemente aparecem juntas
```

### Situação Atual
- `usage_count` é usado para ORDER BY nas queries de filler ✅
- `learned_role` é consultado ✅
- **`top_pairs` NÃO é usado** para sugerir sinergias

### Impacto
Ao adicionar "Force of Will", poderia sugerir também "Force of Negation" (aparecem juntos 38x).

### Ação Recomendada
No modo "complete", ao adicionar uma carta, verificar `top_pairs` e priorizar cartas que frequentemente aparecem juntas.

---

## 🟡 MÉDIO: archetype_patterns (incompleto)

### Dados Disponíveis
```
29 registros com:
- archetype: 'value', 'control', etc
- ideal_land_count: NULL (!)
- ideal_avg_cmc: NULL (!)
- core_cards, flex_options: arrays vazios
```

### Problema
Os campos mais úteis estão **vazios**! O script `extract_meta_insights.dart` não está populando corretamente.

### Ação Recomendada
1. Corrigir o script de extração para popular `ideal_land_count` e `ideal_avg_cmc`
2. Depois, integrar no `DeckArchetypeAnalyzer` para usar como referência

---

## 🟢 BAIXO: rules (3,120 regras)

### Dados Disponíveis
```
754 Keyword Abilities
289 Keyword Actions
127 General
49 Commander
...
```

### Situação Atual
Não usado em nenhum endpoint.

### Oportunidade
- Enriquecer `/ai/explain` com regras oficiais
- Validar mecânicas no deck builder
- Educativo para usuários

### Ação Recomendada
Criar endpoint `/rules/search?keyword=flying` ou integrar no explain para citar regras relevantes.

---

## Tabelas OK (já utilizadas corretamente)

| Tabela | Status | Uso |
|--------|--------|-----|
| `format_staples` | ✅ OK | Agora integrado via FormatStaplesService |
| `card_legalities` | ✅ OK | Validação de formato |
| `card_meta_insights.usage_count` | ✅ OK | ORDER BY nas filler queries |
| `card_meta_insights.learned_role` | ✅ OK | Contexto para LLM |

---

## Prioridade de Implementação

1. **[CRÍTICO]** Integrar `MLKnowledgeService` no optimize (~4h)
2. **[ALTO]** Usar `archetype_counters` para sugestões de hate (~2h)
3. **[MÉDIO]** Usar `top_pairs` para sinergias (~2h)
4. **[MÉDIO]** Corrigir extração de `archetype_patterns` (~4h)
5. **[BAIXO]** Integrar rules no explain (~2h)

---

## Arquivos a Modificar

| Arquivo | Mudança |
|---------|---------|
| `routes/ai/optimize/index.dart` | Importar e usar MLKnowledgeService |
| `lib/ml_knowledge_service.dart` | Já existe, só integrar |
| `bin/extract_meta_insights.dart` | Corrigir extração de archetype_patterns |

---

## Estimativa Total: ~14h de trabalho
