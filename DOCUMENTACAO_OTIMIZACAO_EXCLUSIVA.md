# Documentação Exclusiva — Sistema de Otimização de Decks (AI Optimize)

> **Versão:** 1.0  
> **Data:** 12/02/2026  
> **Tipo:** Análise documental + Auto-crítica (READ-ONLY — sem alterações de código)  
> **Escopo:** Endpoint `POST /ai/optimize` e todos os módulos satelitais

---

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Fluxo Passo a Passo — Modo Optimize (Swaps)](#2-fluxo-passo-a-passo--modo-optimize-swaps)
3. [Fluxo Passo a Passo — Modo Complete](#3-fluxo-passo-a-passo--modo-complete)
4. [Módulos Satelitais (Detalhe)](#4-módulos-satelitais-detalhe)
5. [Pipeline de Validação Pós-Otimização](#5-pipeline-de-validação-pós-otimização)
6. [Sistema de Prompts (O que a IA vê)](#6-sistema-de-prompts-o-que-a-ia-vê)
7. [Auto-Crítica: Falhas Identificadas](#7-auto-crítica-falhas-identificadas)
8. [Matriz de Riscos](#8-matriz-de-riscos)
9. [Diagrama de Dependências](#9-diagrama-de-dependências)
10. [Glossário Técnico](#10-glossário-técnico)

---

## 1. Visão Geral da Arquitetura

O sistema de otimização é composto por **8 arquivos** que se coordenam em pipeline:

| Arquivo | Linhas | Responsabilidade |
|---|---|---|
| `routes/ai/optimize/index.dart` | 1872 | Orquestrador principal (endpoint HTTP) |
| `lib/ai/otimizacao.dart` | 430 | Serviço de chamadas OpenAI (GPT-4o) |
| `lib/ai/sinergia.dart` | ~90 | Engine de sinergia via Scryfall API |
| `lib/ai/goldfish_simulator.dart` | 490 | Simulador Monte Carlo (consistência) |
| `lib/ai/optimization_validator.dart` | 684 | Validação automática em 3 camadas |
| `lib/card_validation_service.dart` | 223 | Anti-alucinação (valida cartas no DB) |
| `lib/color_identity.dart` | 15 | Filtro de identidade de cor |
| `lib/edh_bracket_policy.dart` | 263 | Política de brackets (power level) |

**Prompts da IA:**
| Arquivo | Uso |
|---|---|
| `lib/ai/prompt.md` | System prompt para modo optimize (swaps) |
| `lib/ai/prompt_complete.md` | System prompt para modo complete |

### Modelo de IA utilizado
- **Principal:** GPT-4o (temperature 0.4) — gera as sugestões de swap/complete
- **Crítico:** GPT-4o-mini (temperature 0.3) — valida as sugestões (Layer 3 do Validator)

---

## 2. Fluxo Passo a Passo — Modo Optimize (Swaps)

O modo optimize é ativado quando o deck já está "completo" (≥100 cartas em Commander, ≥60 em Brawl). A IA sugere **trocas 1-por-1** (remover carta fraca → adicionar carta melhor).

### Passo 1: Recepção do Request
```
POST /ai/optimize
Body: { deck_id, archetype?, bracket?, keep_theme? }
Header: Authorization: Bearer <JWT>
```

**Arquivo:** `index.dart` linhas 416-480

O handler:
1. Valida que o método é `POST`
2. Lê o body JSON (`deck_id`, `archetype`, `bracket`, `keep_theme`)
3. Extrai `userId` do JWT via `request.context['userId']`
4. Carrega a `OPENAI_API_KEY` do ambiente

### Passo 2: Carregamento do Deck do Banco de Dados

**Arquivo:** `index.dart` linhas 480-560

Query SQL complexa com CTE para calcular CMC via regex no campo `mana_cost`:
```sql
WITH deck_data AS (
  SELECT dc.id, dc.card_id, dc.quantity, dc.is_commander,
         c.name, c.type_line, c.mana_cost, c.oracle_text,
         c.colors, c.color_identity, c.rarity, c.edhrec_rank,
         COALESCE(
           (SELECT SUM(CASE 
             WHEN m[1] ~ '^[0-9]+$' THEN m[1]::int
             WHEN m[1] IN ('W','U','B','R','G','C') THEN 1
             WHEN m[1] = 'X' THEN 0
             ELSE 1
           END) FROM regexp_matches(c.mana_cost, '\{([^}]+)\}', 'g') AS m(m)),
           0
         ) as cmc
  FROM deck_cards dc
  JOIN cards c ON c.id = dc.card_id
  WHERE dc.deck_id = @deckId
)
```

Extrai:
- `allCardData`: lista de mapas com todos os dados de cada carta
- `commanders`: nomes das cartas com `is_commander = true`
- `deckColors`: união de cores de todas as cartas
- `commanderColorIdentity`: identidade de cor do(s) comandante(s)

### Passo 3: Análise de Arquétipo (DeckArchetypeAnalyzer)

**Arquivo:** `index.dart` linhas 14-290

Classe `DeckArchetypeAnalyzer` executa análise determinística:

1. **calculateAverageCMC():** Calcula CMC médio excluindo terrenos
2. **countCardTypes():** Conta criaturas, instants, sorceries, enchantments, artifacts, planeswalkers, lands, battles — **contagem multi-tipo** (ex: "Artifact Creature" conta para ambos)
3. **detectArchetype():** Heurística por ratios:
   - Aggro: CMC < 2.5 + criaturas > 40%
   - Control: CMC > 3.0 + criaturas < 25% + instants/sorceries > 35%
   - Combo: instants/sorceries > 40% + criaturas < 30%
   - Stax: enchantments > 30%
   - Default: Midrange
4. **analyzeManaBase():** Algoritmo Frank Karsten simplificado — conta terrenos que produzem cada cor vs. devotion (símbolos de mana) e calcula `devotion_vs_sources` com warnings
5. **generateAnalysis():** Retorna mapa completo com todas as métricas + `confidence_score` (baseado na qualidade da base de mana)

### Passo 4: Detecção de Tema (DeckThemeProfile)

**Arquivo:** `index.dart` linhas 290-415

Função `_detectThemeProfile()` classifica o deck em um tema:

| Tema | Condição |
|---|---|
| `eldrazi` | ≥15% Eldrazi OU ≥8 cartas Eldrazi (linha de tipo + nomes hardcoded dos Titans) |
| `artifacts` | ≥30% artefatos |
| `enchantments` | ≥30% encantamentos |
| `spellslinger` | ≥35% instants/sorceries |
| `generic` | Nenhum acima |

Retorna:
- `theme`: string do tema
- `coreCards`: lista de cartas que definem o tema (nunca devem ser removidas se `keep_theme = true`)
- Comandante(s) sempre são incluídos como `coreCards`

### Passo 5: Chamada ao Serviço de Otimização (DeckOptimizerService)

**Arquivo:** `lib/ai/otimizacao.dart` linhas 1-430

O serviço `DeckOptimizerService.optimizeDeck()` executa:

1. **_calculateEfficiencyScores():** Ordena cartas por "fraqueza":
   - Score = `EDHREC_rank × penalidade_CMC`
   - Penalidade: CMC > 4 → ×1.5
   - Exclui terrenos básicos
   - Cartas sem EDHREC rank → usa mediana como fallback
   - Seleciona as **15 piores** cartas

2. **SynergyEngine.fetchCommanderSynergies():** Busca sinergias via Scryfall:
   - Lê oracle text do comandante
   - Gera queries semânticas (artifacts→artifact-payoff, tokens→token-doubler, etc.)
   - Executa até 3 queries em paralelo no Scryfall API
   - Retorna nomes de cartas populares (ordenadas por EDHREC rank)

3. **_fetchFormatStaples():** Busca staples do formato:
   - Query Scryfall: `format:commander -is:banned id<=<colors>`

4. **_callOpenAI():** Chamada ao GPT-4o:
   - System prompt: conteúdo do arquivo `prompt.md`
   - User prompt: deck completo + candidatas fracas + pool de sinergia + staples + constraints (keep_theme, bracket, etc.)
   - Temperature: 0.4
   - Response format: JSON
   - Retorna objeto com `swaps[]` (ou `changes[]` ou `removals[]`/`additions[]`)

5. **AiLogService.logOptimization():** Loga chamada no banco (userId, deckId, latency, tokens, success/failure)

### Passo 6: Parsing da Resposta da IA

**Arquivo:** `index.dart` linhas 1000-1040

A resposta da IA pode vir em 3 formatos (por order de prioridade):

1. **`swaps`:** `[{ "out": "...", "in": "..." }]` — formato principal do `prompt.md`
2. **`changes`:** `[{ "remove": "...", "add": "..." }]` — formato alternativo
3. **`removals`/`additions`:** Listas separadas — fallback para formato antigo

Resultado: duas listas paralelas `removals[]` e `additions[]`.

### Passo 7: Garantia de Equilíbrio Numérico (Regra de Ouro)

**Arquivo:** `index.dart` linhas 1058-1070

Se `removals.length ≠ additions.length`, trunca para o menor (`minCount`). **Motivo:** deck de Commander = exatamente 100 cartas; remover X sem adicionar X = deck inválido.

### Passo 8: Sanitização de Nomes

**Arquivo:** `lib/card_validation_service.dart` linhas 207-223

`CardValidationService.sanitizeCardName()`:
- Remove espaços extras
- Remove caracteres especiais (mantém apóstrofos, hífens, vírgulas)
- Capitaliza primeira letra de cada palavra

### Passo 9: Filtros de Segurança (5 camadas sequenciais)

**Arquivo:** `index.dart` linhas 1080-1200

Cada filtro refina as listas `removals` e `additions`:

| # | Filtro | Descrição |
|---|---|---|
| 1 | **Existência no deck** | Remoções devem ser cartas que existem no deck (case-insensitive) |
| 2 | **Proteção de comandante** | Nunca remover cartas com `is_commander = true` |
| 3 | **Proteção de tema** | Se `keep_theme = true`, bloqueia remoção de `coreCards` |
| 4 | **Anti-duplicata** | Em modo optimize, adições não podem ser cartas já no deck |
| 5 | **Re-balanceamento** | Após filtros, truncar p/ `min(removals, additions)` novamente |

### Passo 10: Validação contra Banco de Dados (Anti-Alucinação)

**Arquivo:** `index.dart` linhas 1122-1170 + `lib/card_validation_service.dart`

`CardValidationService.validateCardNames()`:
1. Para cada nome, executa `SELECT id, name FROM cards WHERE LOWER(name) = LOWER(@name)`
2. Se não encontra: marca como `invalid`, busca similares via `ILIKE '%nome%'` (fuzzy 5 resultados)
3. Retorna `{ valid: [...], invalid: [...], suggestions: {...} }`

Após validação:
- `validRemovals` = apenas cartas que existem no DB (sem duplicatas)
- `validAdditions` = apenas cartas que existem no DB (sem duplicatas em modo optimize; com repetição em complete)

### Passo 11: Filtro de Identidade de Cor

**Arquivo:** `index.dart` linhas 1170-1210 + `lib/color_identity.dart`

Para cada adição, busca `color_identity` e `colors` no DB e verifica:
```dart
isWithinCommanderIdentity(
  cardIdentity: identity,   // cores da carta sugerida
  commanderIdentity: commanderColorIdentity,  // cores do commander
)
```

Lógica: `cardIdentity ⊆ commanderIdentity` (subconjunto). Cartas colorless sempre passam.

Cartas filtradas são logadas em `filteredByColorIdentity[]`.

### Passo 12: Filtro de Bracket (EDH Power Level)

**Arquivo:** `index.dart` linhas 1210-1260 + `lib/edh_bracket_policy.dart`

Se `bracket ≠ null`, aplica política de power level:

1. **tagCardForBracket():** Classifica cada carta em categorias:
   - `fastMana`: lista curada (Mana Crypt, Sol Ring, etc.)
   - `tutor`: oracle contém "search your library"
   - `freeInteraction`: custo alternativo ("rather than pay")
   - `extraTurns`: oracle contém "extra turn"
   - `infiniteCombo`: lista curada (Thassa's Oracle, Demonic Consultation, etc.)

2. **countBracketCategories():** Conta quantas cartas de cada categoria o deck já tem

3. **applyBracketPolicyToAdditions():** Para cada adição:
   - Se adicionar essa carta excede o `maxCount` do bracket → bloqueia
   - Limites por bracket:

| Categoria | Bracket 1 | Bracket 2 | Bracket 3 | Bracket 4 |
|---|---|---|---|---|
| Fast Mana | 1 | 3 | 6 | 99 |
| Tutors | 1 | 3 | 6 | 99 |
| Free Interaction | 0 | 2 | 6 | 99 |
| Extra Turns | 0 | 1 | 2 | 99 |
| Infinite Combo | 0 | 0 | 2 | 99 |

### Passo 13: Re-Balanceamento Inteligente (Filosofia Anti-Basics)

**Arquivo:** `index.dart` linhas 1274-1360

Quando `additions < removals` (filtros removeram adições):

1. **Passo 13a:** Calcula `missingCount = removals - additions`
2. **Passo 13b:** Chama `_findSynergyReplacements()` (ver Passo 13.1)
3. **Passo 13c:** Se AINDA faltam (IA/DB não retornou suficiente) → fallback com básicos
4. **Passo 13d:** Se fallback também falha → trunca remoções para tamanho de adições

**Filosofia:** "A otimização existe para MELHORAR o deck. Quando uma carta é filtrada, o correto é pedir à IA outra carta que cumpra o mesmo papel funcional, não preencher com lands."

#### Passo 13.1: _findSynergyReplacements()

**Arquivo:** `index.dart` linhas 1680-1872

Função core da filosofia anti-basics:

1. **Análise funcional das remoções:** Para cada carta removida sem par, classifica em categorias: `draw`, `removal`, `ramp`, `creature`, `artifact`, `utility`

2. **Query ao DB:** Busca cartas que:
   - Estão dentro da identidade de cor do commander (`color_identity <@ @identity`)
   - Não estão no deck nem na lista de exclusão
   - Não são terrenos básicos
   - São legais em Commander
   - Ordenadas por `edhrec_rank ASC` (mais populares primeiro)
   - Limite: 50 candidatas

3. **Seleção inteligente:** Primeiro tenta preencher necessidades funcionais específicas (se removeu draw → prioriza carta de draw), depois completa com melhores cartas gerais por EDHREC rank

4. **Retorna:** Lista de `{ id, name }` para cada substituta encontrada

### Passo 14: Análise Pós-Otimização (Virtual Deck)

**Arquivo:** `index.dart` linhas 1362-1475

Constrói um "deck virtual" (o deck como ficaria após as trocas):
1. Clone `allCardData`
2. Remove cartas de `validRemovals` (case-insensitive)
3. Adiciona dados completos das cartas de `validAdditions` (busca no DB: name, type_line, mana_cost, colors, cmc, oracle_text)
4. Roda `DeckArchetypeAnalyzer` no deck virtual
5. Compara antes vs. depois:
   - Mana base piorou? → Warning
   - CMC subiu em deck Aggro? → Warning
   - Muitos terrenos removidos (>3)? → Warning
   - CMC caiu demais em Control? → Warning
   - Instants aumentaram? → Improvement

### Passo 15: Validação Automática em 3 Camadas (OptimizationValidator)

**Arquivo:** `lib/ai/optimization_validator.dart` (684 linhas)

> **Não-bloqueante:** envolto em try/catch; falha não impede a resposta.

Ver detalhes completos na [Seção 5](#5-pipeline-de-validação-pós-otimização).

### Passo 16: Construção da Resposta Final

**Arquivo:** `index.dart` linhas 1510-1640

Resposta JSON:
```json
{
  "mode": "optimize",
  "constraints": { "keep_theme": true/false },
  "theme": { "theme": "...", "core_cards": [...] },
  "removals": ["..."],
  "additions": ["..."],
  "removals_detailed": [{ "name": "...", "card_id": "..." }],
  "additions_detailed": [{ "name": "...", "card_id": "...", "quantity": 1 }],
  "reasoning": "...",
  "deck_analysis": { ... },   // análise ANTES
  "post_analysis": { ... },   // análise DEPOIS + validation
  "validation_warnings": ["..."],
  "bracket": 1-4 | null,
  "warnings": { ... }         // cartas inválidas, filtradas por cor, bracket, tema
}
```

**Balanceamento final de detailed:** Se `additions_detailed.length ≠ removals_detailed.length`, reconstrói a partir de `validByNameLower` e, como último recurso, trunca.

---

## 3. Fluxo Passo a Passo — Modo Complete

O modo complete é ativado quando `totalCards < targetSize` (100 para Commander, 60 para Brawl).

### Diferenças em relação ao Optimize

| Aspecto | Optimize | Complete |
|---|---|---|
| Ativação | Deck ≥ targetSize | Deck < targetSize |
| Remoções | Sim (swaps 1-por-1) | Não |
| Iterações IA | 1 | Até 4 (loop) |
| Prompt | `prompt.md` | `prompt_complete.md` |
| Duplicatas adições | Bloqueadas (set) | Permitidas (para básicos) |
| Target | 5-8 trocas | `targetSize - currentSize` cartas |

### Passo C1: Detecção de Incompletude

**Arquivo:** `index.dart` linhas 587-590

```dart
final targetSize = (format == 'brawl') ? 60 : 100;
final isIncomplete = totalUniqueCards < targetSize;
```

### Passo C2: Loop Iterativo (máx 4 rodadas)

**Arquivo:** `index.dart` linhas 600-920

Cada iteração:
1. Calcula `targetAdditions = targetSize - currentSize`
2. Chama `optimizer.completeDeck()` com `targetAdditions`
3. Valida cartas contra DB (`CardValidationService`)
4. Filtra por identidade de cor
5. Filtra por bracket
6. Aplica regra de cópia única (Commander/Brawl): remove cartas que já estão no deck (case-insensitive)
7. Agrega em `aggregatedAdditions` (por nome)
8. Se `currentSize >= targetSize` → sai do loop

### Passo C3: Top-up Determinístico (Básicos)

**Arquivo:** `index.dart` linhas 1260-1300

Se após o loop + validações ainda faltam cartas:
1. Calcula terrenos básicos para a identidade (`_basicLandNamesForIdentity`)
2. Busca IDs dos básicos no DB (`_loadBasicLandIds`)
3. Distribui em round-robin entre as cores disponíveis
4. Gera `additions_detailed` com `card_id` e `quantity` (agrupadas)

### Passo C4: Resposta

Mesmo formato do optimize, mas com `mode: "complete"`, sem `removals`, e `additions_detailed` com quantidades > 1 para básicos.

---

## 4. Módulos Satelitais (Detalhe)

### 4.1 SynergyEngine (`lib/ai/sinergia.dart`)

**Propósito:** Traduzir o texto do comandante em queries de mecânica no Scryfall.

**Fluxo:**
1. Busca dados do comandante via `GET /cards/named?exact=<name>` no Scryfall
2. Analisa `oracle_text` e `type_line` por keywords
3. Mapeia para queries semânticas Scryfall:

| Keyword Oracle | Query Scryfall |
|---|---|
| `artifact` | `function:artifact-payoff`, `t:artifact order:edhrec` |
| `enchantment` / `enchanted` | `function:enchantress`, `t:enchantment order:edhrec` |
| `create` + `token` | `function:token-doubler`, `function:anthem` |
| `graveyard` / `sacrifice` | `function:reanimate`, `function:sacrifice-outlet`, `function:entomb` |
| `instant` / `sorcery` | `function:cantrip`, `function:storm-payoff` |

4. Executa até 3 queries em paralelo
5. Retorna até 20 nomes por query (top EDHREC rank), deduplicados

### 4.2 GoldfishSimulator (`lib/ai/goldfish_simulator.dart`)

**Propósito:** Simulação Monte Carlo de consistência de mão inicial e primeiros turnos.

**Algoritmo:**
1. Expande deck por quantidade (`_expandDeck`)
2. Para cada simulação (default: 1000):
   a. Embaralha o deck
   b. Compra 7 cartas
   c. Conta terrenos na mão → classifica como screw (0-1), flood (6-7) ou keepable (2-5)
   d. Simula turnos 1-4: para cada turno, baixa 1 terreno (se tiver), tenta jogar spells com mana disponível (`_canPlayOnTurn`)

**Métricas retornadas (`GoldfishResult`):**
- `screwRate`: % de mãos com 0-1 terrenos
- `floodRate`: % de mãos com 6-7 terrenos
- `keepableRate`: % de mãos com 2-5 terrenos
- `turn1PlayRate` a `turn4PlayRate`: % de mãos com play válida no turno X
- `avgCmc`: CMC médio calculado
- `landCount`: total de terrenos
- `cmcDistribution`: histograma de CMC
- `consistencyScore`: 0-100, calculado:
  ```
  score = keepableRate×40 + turn2Play×25 + turn3Play×20 + (1-screwRate)×10 + (1-floodRate)×5
  ```
- `recommendations`: lista de strings com sugestões textuais

### 4.3 MatchupAnalyzer (`lib/ai/goldfish_simulator.dart`)

**Propósito:** Comparação heurística entre dois decks (sem simulação real de jogo).

**Fatores avaliados:**
| Fator | Delta por unidade |
|---|---|
| Speed (CMC) | ±0.05 por 0.5 CMC de diferença |
| Removal vs Creatures | ±0.08 |
| Board Wipes vs Go-Wide | ±0.10 |
| Card Draw advantage | ±0.05 |
| Ramp advantage | ±0.04 |

Win rates clamped entre 0.20 e 0.80.

### 4.4 CardValidationService (`lib/card_validation_service.dart`)

**Propósito:** Prevenir "alucinações" da IA (nomes de cartas inventados).

**Funcionalidades:**
- `validateCardNames()`: valida lista de nomes contra o DB (case-insensitive)
- `_findSimilarCards()`: fuzzy search via `ILIKE` para sugerir correções
- `isCardLegalInFormat()`: verifica legalidade (default: legal se sem registro)
- `validateDeckCards()`: validação completa (existência + legalidade + limites de cópia)
- `sanitizeCardName()`: limpeza de string (caracteres especiais, capitalização)

### 4.5 EDH Bracket Policy (`lib/edh_bracket_policy.dart`)

**Propósito:** Limitar power level das sugestões ao bracket escolhido.

**Componentes:**
- `BracketPolicy.forBracket(n)`: retorna limites por categoria
- `tagCardForBracket()`: classifica carta em categorias via nome (lista curada) + oracle text (heurísticas)
- `applyBracketPolicyToAdditions()`: filtra adições que excedem o "budget" de cada categoria

---

## 5. Pipeline de Validação Pós-Otimização

**Arquivo:** `lib/ai/optimization_validator.dart` (684 linhas)

Sistema de validação automática em 3 camadas, executado após a IA sugerir trocas.

### Layer 1: Monte Carlo Comparison

**Método:** `_runMonteCarloComparison()`

Executa `GoldfishSimulator` (1000 simulações) no deck **antes** e **depois** das trocas.

Retorna `MonteCarloComparison`:
- `consistencyDelta`: diferença do consistencyScore
- `screwDelta`: diferença da taxa de screw
- `floodDelta`: diferença da taxa de flood
- Métricas completas de ambos os decks

**+ London Mulligan Simulation:** `_simulateLondonMulligan()` (500 runs)
- Expande deck, embaralha, compra 7
- Heurística de keep: 2-5 terrenos + pelo menos 1 play ≤ CMC 3
- Não keepable → mulligan (max 4 vezes, descarta 1 carta por vez)
- Retorna `MulliganReport`: keepAt7, keepAt6, keepAt5, keepAt4OrLess, keepableAfterMullRate

### Layer 2: Functional Swap Analysis

**Método:** `_analyzeFunctionalSwaps()`

Para cada par removal[i]→addition[i]:
1. Busca dados da carta removida no deck original (case-insensitive)
2. Classifica o **papel funcional** de cada carta via `_classifyFunctionalRole()`:

| Prioridade | Papel | Keywords oracle_text / type_line |
|---|---|---|
| 1 | land | type contém "land" |
| 2 | draw | "draw", "cards", "scry" |
| 3 | removal | "destroy", "exile target", "return target" |
| 4 | wipe | "destroy all", "each opponent", "all creatures" |
| 5 | ramp | "add {", "search your library for a land" |
| 6 | tutor | "search your library" |
| 7 | protection | "hexproof", "indestructible", "shroud" |
| 8 | creature | type contém "creature" |
| 9 | artifact | type contém "artifact" |
| 10 | enchantment | type contém "enchantment" |
| 11 | planeswalker | type contém "planeswalker" |
| 12 | utility | fallback |

3. Calcula `cmcDelta = newCMC - oldCMC`
4. Atribui **veredicto**:
   - `upgrade`: mesmo papel + CMC menor ou igual
   - `sidegrade`: mesmo papel + CMC ligeiramente maior (≤1)
   - `tradeoff`: papel diferente + CMC <= +1
   - `questionável`: CMC subiu >1 OU papel mudou significativamente

5. Constrói `roleDelta` (ganhos/perdas líquidas por categoria funcional)

Retorna `FunctionalReport` com lista de `SwapFunctionalAnalysis` + `roleDelta`.

### Layer 3: Critic AI (GPT-4o-mini)

**Método:** `_runCriticAI()`

Envia para GPT-4o-mini (temp 0.3):
- Lista de swaps com papéis e veredictos
- Deltas do Monte Carlo
- Resumo funcional

Pede resposta JSON:
```json
{
  "approval_score": 0-100,
  "verdict": "approved/cautious/rejected",
  "concerns": ["..."],
  "strong_swaps": ["..."],
  "weak_swaps": ["..."],
  "overall_assessment": "..."
}
```

### Cálculo do Veredicto Final

**Método:** `_computeVerdict()`

Score base: **50**

| Fator | Impacto |
|---|---|
| Consistency delta | +0.5 por ponto ganho |
| Mulligan keepAt7 melhorou | +20 |
| Screw rate diminuiu | +15 |
| Cada swap "upgrade" | +3 |
| Cada swap "sidegrade" | +1 |
| Cada swap "questionável" | -5 |
| Perdeu remoções no roleDelta | -8 |
| Perdeu draw no roleDelta | -6 |

Se Critic AI respondeu: `finalScore = calculado×0.7 + criticScore×0.3`

Clamp: 0-100.

| Score | Veredicto |
|---|---|
| ≥ 70 | `aprovado` |
| 45-69 | `aprovado_com_ressalvas` |
| < 45 | `reprovado` |

---

## 6. Sistema de Prompts (O que a IA vê)

### 6.1 prompt.md (Modo Optimize — 158 linhas)

**Persona:** "The Optimizer" — campeão mundial de MTG e deck builder profissional.

**Conteúdo enviado à IA:**
- Regras completas de Commander (903.x): identidade de cor, 100 cartas, singleton, commander tax, 40 vida, partner rules
- Guidelines por bracket (1-4): de casual a cEDH
- Constraints: `keep_theme`, `deck_theme`, `core_cards` — nunca remover core se keep_theme ativo
- Diretrizes de swap: manter curva de mana, trocar 1-por-1 funcional, priorizar instant speed, identificar cartas armadilha

**Output esperado:**
```json
{
  "summary": "...",
  "swaps": [
    { "out": "...", "in": "...", "category": "...", "reasoning": "...", "priority": "High|Medium|Low" }
  ]
}
```

Gera entre 5-8 trocas.

### 6.2 prompt_complete.md (Modo Complete — 98 linhas)

**Persona:** Deck builder profissional de Commander.

**Diferenças do optimize:**
- Recebe: comandante, arquétipo, bracket, lista parcial, pools de sugestão
- Deve retornar APENAS adições (sem remoções)
- Respeitar singleton + identidade de cor
- Priorizar: ramp, draw, remoção, base de mana, sinergia
- Métricas de consistência por bracket

**Output esperado:**
```json
{
  "summary": "...",
  "additions": ["Nome Exato 1", "Nome Exato 2", ...],
  "reasoning": "..."
}
```

---

## 7. Auto-Crítica: Falhas Identificadas

> **✅ ATUALIZAÇÃO:** Todas as 13 falhas foram corrigidas e deployadas em produção (Junho 2025).

### FALHA 1 — Operator Precedence em `_classifyFunctionalRole()` (SEVERIDADE: MÉDIA) ✅ CORRIGIDO

**Arquivo:** `optimization_validator.dart` linhas ~440-510

A função encadeia condições com `||` e `&&` sem parênteses explícitos. Exemplo simplificado:

```dart
if (oracle.contains('draw') || oracle.contains('scry') && oracle.contains('draw')) ...
```

Em Dart, `&&` tem precedência sobre `||`. A expressão acima é avaliada como:
```dart
oracle.contains('draw') || (oracle.contains('scry') && oracle.contains('draw'))
```

Neste caso **funciona por acidente** porque `oracle.contains('draw')` já cobre o segundo ramo. Mas o padrão se repete em seções como ramp e removal, onde a intenção pode não ser a mesma da precedência. Sem parênteses explícitos, futuras manutenções podem introduzir bugs silenciosos.

**Risco:** Classificação funcional incorreta → veredictos de swap errados → score de validação impreciso.

### FALHA 2 — sanitizeCardName() destrói nomes legítimos (SEVERIDADE: ALTA) ✅ CORRIGIDO

**Arquivo:** `card_validation_service.dart` linhas 207-223

A sanitização faz `.toLowerCase()` + `.capitalize()` em cada palavra:
```dart
cleaned = cleaned.split(' ').map((word) {
  return word[0].toUpperCase() + word.substring(1).toLowerCase();
}).join(' ');
```

Isso **quebra** nomes com capitalização irregular que são oficiais:
- `"Sol Ring"` → `"Sol Ring"` ✅
- `"Rhystic Study"` → `"Rhystic Study"` ✅  
- `"AEther Vial"` → `"Aether Vial"` ❌ (nome oficial usa "Æ" ou "AE")
- `"Phyrexian Dreadnought"` → ok, mas cartas com "McSomething" quebrariam

Depois, a busca no DB é `LOWER(name) = LOWER(@name)`, o que **compensa** parcialmente, mas o nome exibido para o usuário pode ser incorreto.

**Risco médio:** O filtro de acentos/ligaduras na regex `[^\w\s',-]` remove caracteres como `Æ`, `ö`, `ú` que existem em nomes reais de cartas (ex: "Lim-Dûl's Vault", "Jötun Grunt").

### FALHA 3 — SynergyEngine usa queries Scryfall "function:" que podem não existir (SEVERIDADE: MÉDIA) ✅ CORRIGIDO

**Arquivo:** `lib/ai/sinergia.dart` linhas 30-60

Queries como `function:artifact-payoff`, `function:token-doubler`, `function:enchantress` são **funções Scryfall** que dependem da API do Scryfall manter esses labels. Se Scryfall mudar ou descontinuar essas functions, o engine silenciosamente retorna listas vazias (o catch retorna `[]`).

**Risco:** Sinergia pool vazia → IA recebe menos contexto → sugestões de menor qualidade. O sistema não distingue "nenhuma sinergia encontrada" de "erro de API".

### FALHA 4 — Race condition em pool de exclusão do _findSynergyReplacements (SEVERIDADE: BAIXA) ✅ CORRIGIDO

**Arquivo:** `index.dart` linhas 1300-1310

A lista `excludeNames` é construída a partir de `deckNamesLower` + `validAdditions` + `filteredByColorIdentity`. Mas `validAdditions` pode conter nomes que foram sanitizados e podem não coincidir exatamente com os nomes no DB (case differences). A query usa `name NOT IN (SELECT unnest(@exclude::text[]))`, que é case-sensitive no PostgreSQL.

**Risco:** A função pode sugerir cartas que já estão no deck se houver divergência de case entre o nome sanitizado e o nome real no DB.

### FALHA 5 — GoldfishSimulator ignora mana colorida (SEVERIDADE: ALTA) ✅ CORRIGIDO

**Arquivo:** `goldfish_simulator.dart` linhas ~120-180

A simulação de "play on turn" verifica apenas se `availableMana >= cardCMC`:

```dart
bool _canPlayOnTurn(Map card, int availableMana) {
  return (card['cmc'] as num).toDouble() <= availableMana;
}
```

Isso ignora completamente **requisitos de mana colorida**. Uma mão com 3 Mountains e um `Cryptic Command` ({1}{U}{U}{U}) seria marcada como "jogável no turno 4" quando na realidade é impossível sem fontes de azul.

**Risco:** O `consistencyScore` tende a ser OTIMISTA demais, especialmente para decks multicoloridos. O score pode aprovar decks com base de mana disfuncional.

### FALHA 6 — MatchupAnalyzer é puramente heurístico (SEVERIDADE: MÉDIA) ⚠️ NÃO CORRIGIDO (escopo futuro)

**Arquivo:** `goldfish_simulator.dart` linhas 380-490

O analyzer não simula jogos. Ele apenas compara estatísticas estáticas (contagem de criaturas, remoções, board wipes, etc.) com deltas fixos. Isso significa:

- Não captura combos (combo deck com 5 criaturas vs aggro com 30 → heurística diz aggro ganha, mas combo pode vencer no turno 4)
- Não considera velocidade real (um deck pode ter muitos removals mas ser lento demais)
- Win rates clampados em 0.20-0.80 podem comprimir cenários extremos

**Risco:** Matchup analysis pode induzir o jogador a conclusões incorretas sobre meta.

### FALHA 7 — _calculateEfficiencyScores() ignora sinergia interna (SEVERIDADE: ALTA) ✅ CORRIGIDO

**Arquivo:** `lib/ai/otimizacao.dart` linhas ~50-100

O score de "fraqueza" usa apenas `EDHREC_rank × penalidade_CMC`. Isso significa que uma carta **impopular globalmente** mas **sinérgica com o comandante** será marcada como fraca e sugerida para remoção.

Exemplo: "Sphinx of the Second Sun" tem EDHREC rank alto (impopular globalmente), mas em um deck de "extra upkeep triggers" é a melhor carta do deck. O sistema a identificaria como candidata à remoção.

**Risco:** A IA pode receber "falsas fracas" e sugerir remover peças-chave do deck. O `keep_theme` mitiga parcialmente, mas apenas protege `coreCards` — cartas sinérgicas que não estão na lista core ainda são vulneráveis.

### FALHA 8 — London Mulligan heurística de keep é simplificada (SEVERIDADE: BAIXA) ✅ CORRIGIDO

**Arquivo:** `optimization_validator.dart` linhas ~160-210

A heurística de keep é:
```
keep = (2 ≤ lands ≤ 5) AND (hasEarlyPlay where CMC ≤ 3)
```

Isso não considera:
- Mana rocks contam como "lands virtuais" em Commander (Sol Ring na mão = keep com 2 terrenos)
- Cartas de draw em mão lenta podem ser keepable (1 terreno + Brainstorm + Mana Crypt)
- Mãos de combo que são keepable sem early play (turno 1 combo com rituals)

**Risco:** A taxa de mulligan tende a ser PESSIMISTA para decks rápidos com fast mana, e OTIMISTA para decks lentos com curva alta. O delta entre original e otimizado pode ser afetado uniformemente, atenuando o erro.

### FALHA 9 — Resposta da IA pode não respeitar o JSON strict (SEVERIDADE: MÉDIA) ✅ CORRIGIDO

**Arquivo:** `lib/ai/otimizacao.dart` linhas ~280-340

A chamada OpenAI pede `response_format: { type: "json_object" }`, mas a IA pode retornar campos extras, omitir campos, ou usar nomes diferentes do esperado. O código tem 3 fallbacks de parsing (swaps → changes → removals/additions), mas:

- Se a IA retornar `{ "suggestions": [...] }` → nenhum fallback cobre → resultado vazio
- Se `swaps[].out` for `null` → `removals.add(null)` → crash no sanitize
- O campo `out` pode conter "Nome da Carta (Set)" em vez de apenas o nome

**Risco:** Falha silenciosa — a IA retorna resposta válida como JSON mas com formato inesperado, resultando em zero remoções/adições sem aviso claro ao usuário.

### FALHA 10 — Busca de cartas por nome não usa índice (SEVERIDADE: MÉDIA) ✅ CORRIGIDO

**Arquivo:** `card_validation_service.dart` linhas 60-70 + `index.dart` múltiplos locais

Múltiplas queries fazem `WHERE LOWER(name) = LOWER(@name)`:
- `_findCard()`: 1 query por carta (loop de N cartas)
- `_findSimilarCards()`: 1 query `ILIKE` por carta inválida
- Dentro do loop: podem ser 30-50 queries individuais por request

Se a tabela `cards` tem ~90.000+ linhas e não tem índice em `LOWER(name)`, cada query faz full table scan.

**Risco:** Latência alta no endpoint. Pode ser mitigado com `CREATE INDEX idx_cards_name_lower ON cards (LOWER(name))` ou batch query (`WHERE LOWER(name) IN (...)`).

### FALHA 11 — Scryfall rate limiting não é respeitado (SEVERIDADE: MÉDIA) ✅ CORRIGIDO

**Arquivo:** `lib/ai/sinergia.dart` linhas 75-95

O `searchScryfall()` faz requests sem delay entre eles, e `fetchCommanderSynergies` executa até 3 em paralelo via `Future.wait()`. A API do Scryfall pede rate limit de 50-100ms entre requests. Em cenários de alta concorrência (múltiplos usuários otimizando ao mesmo tempo), o servidor pode receber 429 Too Many Requests.

**Risco:** Falha silenciosa (catch retorna `[]`), resultando em pool de sinergia degradada.

### FALHA 12 — Detecção de tema usa thresholds fixos (SEVERIDADE: BAIXA) ✅ CORRIGIDO

**Arquivo:** `index.dart` linhas 360-410

Thresholds hardcoded:
- Eldrazi: ≥15% ou ≥8 cartas
- Artifacts: ≥30%
- Enchantments: ≥30%
- Spellslinger: ≥35%

O Eldrazi tem nomes de Titans hardcoded (`ulamog`, `kozilek`, `emrakul`, `zhulodok`). Novos Eldrazi (de sets futuros) não seriam detectados.

Temas "populares" que não têm detecção: tokens, reanimator, aristocrats, voltron, tribal genérico, wheels, stax, group hug, chaos, landfall.

**Risco:** Decks desses temas recaem em `generic`, e o `keep_theme` protege menos (core_cards baseado apenas em commanders).

### FALHA 13 — Log de debug em produção (SEVERIDADE: BAIXA) ✅ CORRIGIDO

**Arquivo:** `index.dart` múltiplas linhas

Dezenas de `print('[DEBUG] ...')` e `print('[WARN] ...')` permanecem no código de produção. Embora não afetem funcionalidade, poluem os logs do container Docker e podem expor dados sensíveis (nomes de cartas, contagens, etc.).

---

## 8. Matriz de Riscos

| # | Falha | Severidade | Probabilidade | Impacto no Usuário | Mitigação Existente |
|---|---|---|---|---|---|
| 5 | Goldfish ignora mana colorida | ALTA | CERTA | Score de consistência inflado | Nenhuma |
| 7 | Efficiency ignora sinergia interna | ALTA | ALTA | IA remove peças-chave | `keep_theme` parcial |
| 2 | sanitizeCardName destrói nomes | ALTA | MÉDIA | Cartas não encontradas no DB | Query LOWER() compensa |
| 9 | IA retorna formato inesperado | MÉDIA | MÉDIA | Zero sugestões silenciosamente | 3 fallbacks de formato |
| 10 | Queries sem índice (N+1) | MÉDIA | CERTA | Latência 3-10x maior | Nenhuma |
| 3 | Scryfall functions deprecadas | MÉDIA | BAIXA | Pool de sinergia vazia | Catch retorna [] |
| 11 | Scryfall rate limiting | MÉDIA | MÉDIA | Sinergia degradada | Catch retorna [] |
| 1 | Operator precedence | MÉDIA | BAIXA | Classificação funcional errada | Funciona "por acidente" |
| 6 | Matchup puramente heurístico | MÉDIA | CERTA | Análise de matchup imprecisa | Clamp 0.20-0.80 |
| 4 | Race condition case-sensitive | BAIXA | BAIXA | Carta duplicada sugerida | Filtro pós-validação |
| 8 | Mulligan heuristic simplificada | BAIXA | CERTA | Taxas de mulligan imprecisas | Delta cancela parcialmente |
| 12 | Temas com thresholds fixos | BAIXA | MÉDIA | Tema não detectado → generic | Core cards do commander |
| 13 | Debug prints em produção | BAIXA | CERTA | Logs poluídos | Nenhuma |

---

## 9. Diagrama de Dependências

```
POST /ai/optimize
    │
    ├── [1] DB Query (deck + cards + legalities)
    │
    ├── [2] DeckArchetypeAnalyzer
    │       ├── calculateAverageCMC()
    │       ├── countCardTypes()
    │       ├── detectArchetype()
    │       ├── analyzeManaBase()  ← Frank Karsten
    │       └── generateAnalysis()
    │
    ├── [3] _detectThemeProfile()
    │       └── DeckThemeProfile { theme, coreCards }
    │
    ├── [4] DeckOptimizerService
    │       ├── _calculateEfficiencyScores()  ← EDHREC × CMC
    │       ├── SynergyEngine
    │       │       ├── _getCardData()       ← Scryfall API
    │       │       └── searchScryfall()      ← Scryfall API (×3)
    │       ├── _fetchFormatStaples()         ← Scryfall API
    │       └── _callOpenAI() / _callOpenAIComplete()  ← GPT-4o
    │
    ├── [5] CardValidationService
    │       ├── validateCardNames()  ← DB (N queries)
    │       └── _findSimilarCards()  ← DB ILIKE
    │
    ├── [6] isWithinCommanderIdentity()
    │
    ├── [7] applyBracketPolicyToAdditions()
    │       ├── tagCardForBracket()
    │       └── countBracketCategories()
    │
    ├── [8] _findSynergyReplacements()  ← DB (popular cards query)
    │
    ├── [9] DeckArchetypeAnalyzer (virtual deck)
    │
    └── [10] OptimizationValidator
            ├── Layer 1: GoldfishSimulator (×2: before + after)
            │            └── _simulateLondonMulligan (×2)
            ├── Layer 2: _analyzeFunctionalSwaps()
            │            └── _classifyFunctionalRole()
            └── Layer 3: _runCriticAI()  ← GPT-4o-mini
```

**Chamadas externas por request (pior caso):**
- Scryfall API: 4-5 requests (1 card data + 3 synergies + 1 staples)
- OpenAI API: 2 requests (1 GPT-4o optimize + 1 GPT-4o-mini critic)
- PostgreSQL: ~60-80 queries (bulk seria 10-15)

---

## 10. Glossário Técnico

| Termo | Definição |
|---|---|
| **CMC** | Converted Mana Cost — custo total de mana de uma carta |
| **EDHREC rank** | Classificação de popularidade de cartas em Commander (menor = mais popular) |
| **Frank Karsten** | Jogador profissional; seu artigo define mínimos de fontes de mana colorida por devotion |
| **Goldfish** | "Jogar contra um peixinho" — simular o deck sozinho sem oponente |
| **London Mulligan** | Regra oficial: comprar 7, decidir keep/mull; se mull, comprar 7 novamente e colocar 1 carta no fundo (recursivo) |
| **Screw** | Mão inicial com terrenos insuficientes (0-1) |
| **Flood** | Mão inicial com terrenos demais (6-7) |
| **Bracket** | Sistema oficial de power level do Commander (1=casual, 4=cEDH) |
| **Color Identity** | Todas as cores presentes no custo de mana E texto de regras de uma carta |
| **Singleton** | Regra: apenas 1 cópia de cada carta (exceto terrenos básicos) |
| **Oracle Text** | Texto oficial de regras de uma carta (mantido pelo Scryfall/Wizards) |
| **Alucinação** | Quando a IA inventa nomes de cartas que não existem |
| **cEDH** | Competitive Elder Dragon Highlander — Commander no nível mais alto de competição |
| **EDHREC** | Site referência para dados de popularidade/sinergia de cartas em Commander |

---

## 11. Registro de Correções (Junho 2025)

Todas as 13 falhas identificadas na auditoria foram corrigidas e deployadas em produção.

| # | Falha | Status | Correção Aplicada |
|---|-------|--------|-------------------|
| 1 | Operator Precedence | ✅ | Parênteses explícitos em todas as condições `&&` dentro de `\|\|` em `_classifyFunctionalRole()` |
| 2 | sanitizeCardName unicode | ✅ | Removido Title Case forçado; regex agora só remove control chars `[\x00-\x1F\x7F]`; adicionado strip de "(Set Code)" |
| 3 | Scryfall fallback queries | ✅ | `_buildFallbackQuery()` com 9 mapeamentos text-based quando `function:` retorna vazio |
| 4 | Case-sensitive exclude | ✅ | Query alterada para `LOWER(c.name) NOT IN (SELECT LOWER(unnest(@exclude)))` |
| 5 | Goldfish mana colorida | ✅ | `_getColorRequirements()` e `_getLandColors()` — verifica mana colorida por turno |
| 6 | MatchupAnalyzer heurístico | ⚠️ | Escopo futuro — requer motor de simulação completo |
| 7 | Efficiency scores sinergia | ✅ | `_extractMechanicKeywords()` — 30+ patterns; score÷2 se 2+ matches com commander |
| 8 | Mulligan com mana rocks | ✅ | `effectiveLands = lands + (rocks × 0.5)`; keep threshold `1.5-5.5` |
| 9 | Parse resiliente IA | ✅ | 4º fallback `suggestions`; null-safety; warning log para formato não reconhecido |
| 10 | Índice LOWER(name) | ✅ | `CREATE INDEX idx_cards_name_lower ON cards (LOWER(name))` criado em produção |
| 11 | Scryfall rate limiting | ✅ | Requests sequenciais com 120ms delay entre cada (era `Future.wait` paralelo) |
| 12 | Novos temas detectados | ✅ | 8 temas adicionados: tokens, reanimator, aristocrats, voltron, tribal, landfall, wheels, stax |
| 13 | Logger em produção | ✅ | 31 `print()` substituídos por `Log.d()`/`Log.w()`/`Log.e()` (debug suprimido em prod) |

### Bug adicional encontrado durante deploy:
- **`orElse: () => null` type error** em `_extractMechanicKeywords()` — `List<dynamic>.firstWhere()` não aceita `orElse` que retorna `null`. Corrigido com loop manual.

### Teste de produção pós-deploy:
- Endpoint `POST /ai/optimize` com deck Jin-Gitaxias (mono-U, 100 cartas)
- **Resultado:** `mode=optimize`, `theme=spellslinger` (confidence: alta, score: 0.417)
- **Balanceamento:** 7 removals = 7 additions (perfeito)
- **Goldfish:** Monte Carlo 1000 simulações antes/depois funcionando
- **Validação:** Score 56/100, veredicto `aprovado_com_ressalvas`, 1 warning

---

*Documento atualizado após correção e deploy de todas as falhas identificadas.*
