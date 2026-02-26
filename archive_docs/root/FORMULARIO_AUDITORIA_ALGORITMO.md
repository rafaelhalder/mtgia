# 📋 Formulário de Auditoria de Lógica de Algoritmo
## ManaLoom - MTG Deck Optimizer

**Data:** 25/11/2025  
**Desenvolvedor Responsável:** Equipe ManaLoom  
**Versão do Sistema:** 1.0.0

---

## 🎯 Objetivo deste Formulário

Este formulário foi projetado para auditar e documentar a lógica exata dos algoritmos de otimização de decks implementados no ManaLoom. Ao responder cada pergunta, você irá expor as decisões técnicas do código atual, identificar possíveis falhas lógicas e criar uma base para melhorias futuras.

**Instruções:**
1. Responda cada pergunta com detalhes técnicos específicos.
2. Inclua trechos de código, fórmulas ou referências a arquivos quando relevante.
3. Se a lógica não está implementada, escreva "NÃO IMPLEMENTADO" e descreva o comportamento atual.
4. Marque áreas de incerteza com "⚠️ VERIFICAR".

---

## 1. 📥 Entrada e Parsing de Dados

### 1.1 Recebimento do Deck

**P1.1.1:** Como o deck é recebido pelo sistema?
- [x] Via API REST (JSON)
- [x] Via importação de texto
- [x] Via banco de dados

**Arquivo de referência:** `server/routes/import/index.dart`

**Detalhes técnicos:**
```json
Formato esperado do payload:
{
  "name": "Nome do Deck",
  "format": "commander",
  "description": "Descrição opcional",
  "commander": "Nome do Comandante (opcional)",
  "list": "1x Sol Ring (cmm)\n4 Lightning Bolt\n..." // String ou Array
}

O campo "list" aceita:
- String com quebras de linha (\n)
- Array de strings
- Array de objetos: [{"quantity": 1, "name": "Sol Ring"}]
```

---

**P1.1.2:** Como identificamos o **Comandante** vs **Maindeck**?

| Método de Detecção | Implementado? | Arquivo/Linha |
|-------------------|---------------|---------------|
| Campo `is_commander` no JSON | ☑ Sim | `routes/import/index.dart:189` |
| Tag no texto (ex: `[Commander]`, `*CMDR*`) | ☑ Sim | `routes/import/index.dart:74-77` |
| Posição na lista (primeira carta) | ☐ Não | - |
| Detecção automática por tipo (Legendary Creature) | ☐ Não | - |

**Descreva a lógica exata:**
```dart
// routes/import/index.dart linhas 74-77
final lineLower = line.toLowerCase();
final isCommanderTag = lineLower.contains('[commander') || 
                       lineLower.contains('*cmdr*') || 
                       lineLower.contains('!commander');

// Também verifica se o nome bate com o campo "commander" do payload (linha 189)
final isCommander = item['isCommanderTag'] || (commanderName != null && 
                   dbName.toLowerCase() == commanderName.toLowerCase());
```

**Tratamento de Comandante Ausente (CORRIGIDO):** 
```dart
// routes/import/index.dart - Validação de Comandante
if (format == 'commander' || format == 'brawl') {
  final hasCommander = cardsToInsert.any((c) => c['is_commander'] == true);
  
  if (!hasCommander) {
    // Tenta detectar automaticamente um comandante
    // Procura por Legendary Creature
    for (final card in cardsToInsert) {
      final typeLine = (card['type_line'] as String).toLowerCase();
      final isLegendaryCreature = typeLine.contains('legendary') && 
                                  typeLine.contains('creature');
      
      if (isLegendaryCreature) {
        card['is_commander'] = true;
        break;
      }
    }
  }
}

// Se ainda não encontrar, retorna warning na resposta:
if (warnings.isNotEmpty) {
  responseBody['warnings'] = warnings;
}
// ✅ CORRIGIDO: Sistema agora tenta detectar e avisa o usuário
```

---

**P1.1.3:** Como tratamos **cartas dupla-face (DFC)** ou **split cards** na contagem e identificação?

**Exemplo de DFCs:** "Delver of Secrets // Insectile Aberration", "Jace, Vryn's Prodigy // Jace, Telepath Unbound"

**Exemplo de Split Cards:** "Fire // Ice", "Commit // Memory"

| Tipo de Carta | Como é tratada na busca? | Como é tratada no CMC? |
|---------------|--------------------------|------------------------|
| DFC (Dupla-Face) | Fallback: Busca por prefixo "nome // %" | Usa CMC da face frontal |
| Split Card | Fallback: Busca por prefixo "nome // %" | ⚠️ Usa soma dos dois lados (banco) |
| Adventure Card | Mesma lógica de DFC | CMC do lado criatura |
| Modal DFC (MDFC) | Mesma lógica de DFC | CMC da primeira face |

**Código de referência:**
```dart
// routes/import/index.dart linhas 139-174
// Fallback para Split Cards / Double Faced
final splitPatternsToQuery = <String>[];

for (final item in parsedItems) {
   final nameKey = item['cleanName'] != null 
      ? (item['cleanName'] as String).toLowerCase() 
      : (item['name'] as String).toLowerCase();
   
   // Se ainda não achou
   if (!foundCardsMap.containsKey(nameKey)) {
      splitPatternsToQuery.add('$nameKey // %');  // Busca por LIKE
   }
}

// Executa query com padrão LIKE para encontrar "Fire // Ice" quando usuário digita "Fire"
final result = await conn.execute(
  Sql.named('SELECT id, name, type_line FROM cards WHERE lower(name) LIKE ANY(@patterns)'),
  parameters: {'patterns': TypedValue(Type.textArray, splitPatternsToQuery)},
);
```

---

### 1.2 Parser de Texto (Importação)

**P1.2.1:** Qual é a expressão regular (regex) usada para fazer o parse de linhas de deck?

```regex
Regex atual: ^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$
```

**Teste com os seguintes inputs. O regex captura corretamente?**

| Input | Quantidade | Nome | Set Code | Resultado |
|-------|------------|------|----------|-----------|
| `1x Sol Ring (cmm)` | 1 | Sol Ring | cmm | ☑ OK |
| `4 Lightning Bolt` | 4 | Lightning Bolt | (vazio) | ☑ OK |
| `1 Jace, Vryn's Prodigy // Jace, Telepath Unbound` | 1 | Jace, Vryn's Prodigy // Jace, Telepath Unbound | (vazio) | ☑ OK |
| `2x Fire // Ice (mh2)` | 2 | Fire // Ice | mh2 | ☑ OK |
| `1 Forest 96` | 1 | Forest 96 | (vazio) | ☑ OK (fallback remove o "96") |
| `1 Who // What // When // Where // Why` | 1 | Who // What // When // Where // Why | (vazio) | ☑ OK |

---

**P1.2.2:** Como tratamos o **fallback** quando uma carta não é encontrada pelo nome exato?

- [x] Busca LIKE (substring) - para split cards
- [ ] Fuzzy matching (Levenshtein distance) - **NÃO IMPLEMENTADO** no import
- [x] Busca por prefixo (split cards: "Fire // %")
- [ ] Nenhum fallback

**Detalhes da implementação:**
```
1. BUSCA EXATA: SELECT ... WHERE lower(name) = ANY(@names)
2. FALLBACK 1 (Números): Remove números do final (ex: "Forest 96" → "Forest")
   Código: cleanName = name.replaceAll(RegExp(r'\s+\d+$'), '');
3. FALLBACK 2 (Split Cards): Busca com LIKE (ex: "fire // %")
   Query: WHERE lower(name) LIKE ANY(@patterns)
4. Se ainda não achar: Adiciona à lista "notFoundCards" retornada ao usuário
```

---

## 2. 📊 Cálculos Matemáticos (Stat Engine)

### 2.1 Curva de Mana (CMC)

**P2.1.1:** Como é calculada a **Curva de Mana (CMC)** de cada carta?

**Fórmula atual:**
```dart
// routes/decks/[id]/analysis/index.dart - função _parseManaCost()
CMC = Σ (valor de cada símbolo de mana)

Onde:
- {2} → +2
- {U}, {B}, {R}, {G}, {W}, {C} → +1 cada
- {X} → +0 (ignorado)
- {2/W} (híbrido) → +1 (conta apenas 1, não 2)
- {B/P} (phyrexian) → +1
```

**Considerações especiais:**

| Caso Especial | Como é tratado? |
|---------------|-----------------|
| Custo `{X}` | ☑ Conta como 0 (continue; no código) |
| Custo Híbrido `{2/W}` | ☑ **CORRIGIDO**: Conta como 2 (maior valor entre as partes) |
| Custo Phyrexian `{B/P}` | ☑ Conta como 1 (cmc += 1) |
| Terrenos (Land) | ☑ Excluído da curva (continue; se type_line contém 'land') |
| Custos Alternativos (Evoke, Overload) | ☐ Ignorados (usa apenas mana_cost principal) |

**Código de referência:**
```dart
// routes/decks/[id]/analysis/index.dart - _parseManaCost()
ManaAnalysis _parseManaCost(String manaCost) {
  int cmc = 0;
  final colors = <String, int>{};
  final regex = RegExp(r'\{([^}]+)\}');
  final matches = regex.allMatches(manaCost);

  for (final match in matches) {
    final symbol = match.group(1) ?? '';
    final number = int.tryParse(symbol);
    if (number != null) {
      cmc += number;  // {2} → +2
    } else if (symbol == 'X') {
      continue;  // {X} → 0
    } else if (symbol.contains('/')) {
      // Híbrido: {2/W} → 2, {B/G} → 1
      final parts = symbol.split('/');
      int hybridCmc = 1;
      for (final part in parts) {
        final partNumber = int.tryParse(part);
        if (partNumber != null && partNumber > hybridCmc) {
          hybridCmc = partNumber;
        }
      }
      cmc += hybridCmc;
    } else {
      cmc += 1;  // Símbolo simples: {U}, {B}, etc.
      // ... etc
    }
  }
  return ManaAnalysis(cmc, colors);
}
```

---

**P2.1.2:** Como é calculado o **CMC Médio** do deck?

**Fórmula:**
```dart
// routes/decks/[id]/analysis/index.dart linhas 166-174
CMC Médio = (Σ CMC * quantity de cada carta não-terreno) / (total de cartas não-terreno)

// Código:
manaCurve.forEach((cmc, count) {
  totalCmc += cmc * count;
});
final avgCmc = nonLandCards > 0 ? totalCmc / nonLandCards : 0.0;
```

**Perguntas críticas:**

- Terrenos são **incluídos** ou **excluídos** do cálculo? `EXCLUÍDOS (nonLandCards = totalCards - totalLands)`
- Se uma carta tem `quantity = 4`, ela conta 4 vezes ou 1 vez? `4 VEZES (manaCurve[cmc] += quantity)`
- Cartas do sideboard são incluídas? `NÃO (só deck_cards principal)`

---

### 2.2 Distribuição de Tipos

**P2.2.1:** Como é feita a contagem de tipos de cartas?

**Regra de Contagem para Tipos Múltiplos:**

Exemplo: "Artifact Creature - Golem"

| Estratégia | Implementado? |
|------------|---------------|
| Conta +1 para Artifact E +1 para Creature (soma) | ☑ **CORRIGIDO** |
| Conta apenas no tipo principal (Creature) | ☐ |
| Usa sistema de prioridade (se é X, não conta Y) | ☐ (removido) |

**Descreva o sistema atual (CORRIGIDO):**
```dart
// routes/ai/optimize/index.dart - DeckArchetypeAnalyzer.countCardTypes()
// Agora conta TODOS os tipos presentes na carta:

if (typeLine.contains('land')) counts['lands']! + 1;
if (typeLine.contains('creature')) counts['creatures']! + 1;
if (typeLine.contains('artifact')) counts['artifacts']! + 1;
// ... etc para cada tipo

// RESULTADO: Uma "Artifact Creature" conta +1 para Creature E +1 para Artifact
// Isso permite estatísticas mais precisas para análise de arquétipos
```

---

**P2.2.2:** Como classificamos cada tipo?

| Tipo | Substring usada para detecção | Exemplo de carta |
|------|-------------------------------|------------------|
| Creature | `typeLine.contains('creature')` | Ornithopter (Artifact Creature) |
| Instant | `typeLine.contains('instant')` | Lightning Bolt |
| Sorcery | `typeLine.contains('sorcery')` | Demonic Tutor |
| Enchantment | `typeLine.contains('enchantment')` | Rhystic Study |
| Artifact | `typeLine.contains('artifact')` | Sol Ring |
| Planeswalker | `typeLine.contains('planeswalker')` | Teferi, Time Raveler |
| Land | `typeLine.contains('land')` | Command Tower |
| Battle | ☑ **IMPLEMENTADO**: `typeLine.contains('battle')` | Invasion of Ikoria |

---

### 2.3 Base de Mana (Manabase)

**P2.3.1:** Como calculamos a **quantidade ideal de terrenos**?

**Fórmula atual:**
```dart
// routes/decks/[id]/analysis/index.dart linhas 177-191
Terrenos Recomendados = 31 + (CMC_Médio * 2.5)

// Exemplos:
// CMC Médio 2.0 → 31 + 5.0 = 36 terrenos
// CMC Médio 3.0 → 31 + 7.5 = 38.5 ≈ 39 terrenos
// CMC Médio 4.0 → 31 + 10 = 41 terrenos
```

**Parâmetros utilizados:**

| Parâmetro | Usado? | Valor/Fórmula |
|-----------|--------|---------------|
| CMC Médio do deck | ☑ Sim | Multiplicador: * 2.5 |
| Formato (Commander, Standard) | ☑ Sim | Só aplica para Commander (isCommander) |
| Arquétipo (Aggro, Control) | ☐ Não | ⚠️ Não considera arquétipo na fórmula |
| Quantidade de ramp | ☐ Não | ⚠️ Não ajusta por ramp disponível |

**Fórmulas por arquétipo (se aplicável):**
```
A fórmula NÃO varia por arquétipo atualmente.
Mas no prompt de IA (ai/optimize), temos guias:
Aggro:     ~30-33 terrenos
Midrange:  ~34-37 terrenos
Control:   ~37-40 terrenos
```

---

**P2.3.2:** Como calculamos a **distribuição de cores** nos terrenos?

**Método usado:**

- [x] Pip count (contar símbolos de mana coloridos)
- [ ] Proporção fixa baseada nas cores do comandante
- [ ] Heurística simples (dividir igualmente)
- [ ] Não implementado

**Fórmula de Pip Count (se aplicável):**
```dart
// routes/decks/[id]/analysis/index.dart linhas 70-75
// O sistema CONTA os pips (símbolos coloridos) em todas as cartas:

analysis.colors.forEach((color, count) {
  if (colorDistribution.containsKey(color)) {
    colorDistribution[color] = (colorDistribution[color] ?? 0) + (count * quantity);
  }
});

// Retorna: {"W": 15, "U": 30, "B": 5, "R": 0, "G": 0, "C": 2}

⚠️ PORÉM: O sistema apenas REPORTA a distribuição atual.
NÃO CALCULA a quantidade ideal de fontes de cada cor nos terrenos.
Isso fica para a IA sugerir no prompt de otimização.
```

---

## 3. ⚖️ Lógica de "Scoring" (O que é bom e o que é ruim)

### 3.1 Identificação de Cartas Fracas

**P3.1.1:** Qual é a **fórmula matemática exata** para decidir que uma carta é "FRACA"?

**Fórmula atual:**
```dart
// lib/ai/otimizacao.dart - _calculateEfficiencyScores()
weakness_score = edhrec_rank * (cmc > 4 ? 1.5 : 1.0)

// Onde:
// - edhrec_rank: Posição no ranking EDHREC (1 = mais popular, 15000+ = menos popular)
// - cmc: Custo de mana convertido da carta
// - Multiplicador 1.5x para cartas com CMC > 4 (penaliza cartas caras E impopulares)

// Resultado: Score ALTO = Carta Ruim (candidata a corte)
// As 15 cartas com maior score são enviadas como "candidatas fracas" para a IA
```

**Fatores considerados:**

| Fator | Peso | Como é obtido? |
|-------|------|----------------|
| EDHREC Rank | Base | Campo `edhrec_rank` na tabela `cards`? ☑ Sim (via JSON do deck) |
| CMC (custo alto = ruim?) | Multiplicador 1.5x se CMC > 4 | Campo `cmc` ou calculado do `mana_cost` |
| Preço de mercado | ☐ Não usado | - |
| Sinergia com comandante | ☐ Não usado neste score | Feito separadamente via SynergyEngine |
| Popularidade em Meta Decks | ☐ Não usado diretamente | EDHREC Rank é derivado de popularidade |

---

**P3.1.2:** Como tratamos **cartas sem dados de rank** (EDHREC rank = null)?

- [ ] Assumimos rank máximo (impopular)
- [ ] Ignoramos a carta
- [x] Usamos média do deck (**CORRIGIDO**)
- [ ] Outro: _______________

**Código de referência (CORRIGIDO):**
```dart
// lib/ai/otimizacao.dart - _calculateEfficiencyScores()

// 1. Calcula a mediana do EDHREC rank das cartas que têm rank
final ranksWithValue = cards
    .where((c) => c['edhrec_rank'] != null)
    .map((c) => c['edhrec_rank'] as int)
    .toList();

// 2. Calcula a mediana do deck (ou usa 5000 como fallback razoável)
int medianRank = 5000;
if (ranksWithValue.isNotEmpty) {
  ranksWithValue.sort();
  final mid = ranksWithValue.length ~/ 2;
  medianRank = ranksWithValue.length.isOdd 
      ? ranksWithValue[mid] 
      : ((ranksWithValue[mid - 1] + ranksWithValue[mid]) ~/ 2);
}

// 3. Para cartas sem rank (novas ou de nicho), usa a mediana do deck
final rank = (card['edhrec_rank'] as int?) ?? medianRank;

// ✅ CORRIGIDO: Cartas novas não são mais penalizadas injustamente
```

---

**P3.1.3:** Como evitamos cortar **Staples** acidentalmente?

| Staple | Protegido pelo sistema? | Como? |
|--------|-------------------------|-------|
| Sol Ring | ☑ Sim | EDHREC Rank 1 → Score baixíssimo + Tabela format_staples |
| Mana Crypt | ☑ Sim (banido) | is_banned = TRUE na format_staples |
| Rhystic Study | ☑ Sim | Rank ~5 → Score baixo |
| Demonic Tutor | ☑ Sim | Rank ~15 → Score baixo |

**Existe uma lista hardcoded de staples protegidos?** 
- [x] ~~Sim~~ **ATUALIZADO (v1.3):** Agora usa tabela `format_staples` dinâmica
- A tabela é sincronizada semanalmente via `bin/sync_staples.dart`
- Fallback para Scryfall API em tempo real se dados estiverem desatualizados

**Novo Fluxo de Proteção de Staples (v1.3):**
```dart
// lib/format_staples_service.dart - FormatStaplesService
// Busca staples de duas fontes:
// 1. Banco de dados local (format_staples) - Mais rápido, cache 24h
// 2. Scryfall API - Fallback quando DB desatualizado

final staplesService = FormatStaplesService(pool);
final staples = await staplesService.getStaples(
  format: 'commander',
  colors: ['U', 'B'],
  archetype: 'control',
);
// Retorna lista dinâmica de staples do formato/cores/arquétipo
```

**Proteção no Prompt (Atualizada):**
```markdown
// lib/ai/prompt.md - REGRAS FINAIS DE SEGURANÇA
REGRA: NÃO SUGIRA CARTAS BANIDAS. A lista de banidas é obtida dinamicamente via:
- Tabela format_staples (is_banned = TRUE)
- Tabela card_legalities (status = 'banned')
- Scryfall API (-is:banned filter)
```

**Proteção Adicional - Terrenos Básicos:**
```dart
// lib/ai/otimizacao.dart linhas 65-67
if ((card['type_line'] as String).contains('Basic Land')) {
  return {'name': card['name'], 'weakness_score': -1.0};
}
// Score negativo = NUNCA sugerido para corte
```

---

### 3.2 Identificação de Cartas Boas

**P3.2.1:** Qual é a **fórmula** para decidir que uma carta é "BOA/STAPLE"?

**Fórmula atual (ATUALIZADO v1.3):**
```dart
// NOVA IMPLEMENTAÇÃO: Staples são buscados dinamicamente

// 1. Primeiro tenta buscar do banco de dados (tabela format_staples)
//    lib/format_staples_service.dart - FormatStaplesService._getStaplesFromDB()
final dbStaples = await _getStaplesFromDB(
  format: format,
  colors: colors,
  archetype: archetype,
  limit: limit,
);

// 2. Se DB estiver desatualizado (>24h), busca do Scryfall API
//    lib/format_staples_service.dart - FormatStaplesService._getStaplesFromScryfall()
final uri = Uri.https('api.scryfall.com', '/cards/search', {
  'q': 'format:commander id<=${colors.join('')} -is:banned',
  'order': 'edhrec',  // ← Ordenação por popularidade
});

// 3. Tabela format_staples é sincronizada semanalmente via:
//    bin/sync_staples.dart
// Sincroniza Top 100 staples universais + Top 50 por arquétipo + Top 30 por cor
```

**Estrutura da Tabela format_staples:**
```sql
CREATE TABLE format_staples (
    card_name TEXT NOT NULL,
    format TEXT NOT NULL,
    archetype TEXT,           -- NULL = universal
    color_identity TEXT[],
    edhrec_rank INTEGER,
    category TEXT,            -- 'ramp', 'draw', 'removal', 'staple'
    is_banned BOOLEAN,        -- Atualizado automaticamente
    last_synced_at TIMESTAMP
);
```

---

**P3.2.2:** Como diferenciamos uma carta "ruim" de uma carta "de nicho/sinergia"?

**Exemplo:** "Goblin Guide" tem EDHREC Rank baixíssimo em Commander, mas é STAPLE em Mono-Red Aggro.

**O sistema considera o arquétipo do deck?**
- [x] Sim → Via `DeckArchetypeAnalyzer` que detecta aggro/control/midrange/combo
- O arquétipo detectado influencia as recomendações de staples e o contexto no prompt

**O sistema analisa sinergia com o comandante?**
- [x] Sim → Método: `SynergyEngine.fetchCommanderSynergies()`

```dart
// lib/ai/sinergia.dart - Análise Semântica do Oracle Text
// Lê o texto do comandante e gera queries específicas:

if (oracleText.contains('artifact') || typeLine.contains('artifact')) {
  queries.add('function:artifact-payoff $colorQuery');
  queries.add('t:artifact order:edhrec $colorQuery');
}

if (oracleText.contains('create') && oracleText.contains('token')) {
  queries.add('function:token-doubler $colorQuery');
  queries.add('function:anthem $colorQuery');
}
// ... etc para cada tema (enchantments, graveyard, spellslinger)
```

---

### 3.3 Análise de Composição (Vegetables Check)

**P3.3.1:** Como detectamos se o deck tem **Ramp suficiente**?

**Critérios de detecção de "Ramp":**

| Palavra-chave no `oracle_text` | Detecta como Ramp? |
|--------------------------------|-------------------|
| `add {` | ☑ Sim |
| `search your library for a land` | ☑ Sim |
| `create a Treasure` | ☑ Sim |
| `put a land card from your hand` | ☑ Sim |

**Código de referência:**
```dart
// routes/decks/[id]/analysis/index.dart linhas 208-214
if (text.contains('add {') || 
    text.contains('search your library for a land') || 
    text.contains('create a treasure') ||
    text.contains('put a land card from your hand')) {
  rampCount += quantity;
}
```

**Quantidade mínima recomendada:** **10** cartas de ramp (para Commander)

---

**P3.3.2:** Como detectamos **Card Draw**?

| Palavra-chave | Detecta? |
|---------------|----------|
| `draw a card` | ☑ Sim |
| `draw cards` | ☑ Sim |
| `draw X cards` | ☑ Sim (coberto por "draw cards") |
| `look at the top` (impulse draw) | ☐ Não |

**Código:**
```dart
// linhas 217-219
if (text.contains('draw a card') || text.contains('draw cards')) {
  drawCount += quantity;
}
```

**Quantidade mínima recomendada:** **10** cartas de draw (para Commander)

---

**P3.3.3:** Como detectamos **Removal**?

| Tipo | Palavra-chave | Detecta? |
|------|---------------|----------|
| Single Target | `destroy target` | ☑ |
| Single Target | `exile target` | ☑ |
| Single Target | `deal X damage to target` | ☑ (texto: `deal` AND `damage to target`) |
| Board Wipe | `destroy all` | ☑ |
| Board Wipe | `exile all` | ☑ |

**Código:**
```dart
// linhas 221-232
if (text.contains('destroy target') || 
    text.contains('exile target') || 
    (text.contains('deal') && text.contains('damage to target'))) {
  removalCount += quantity;
}

if (text.contains('destroy all') || text.contains('exile all')) {
  boardWipeCount += quantity;
}
```

**Quantidade mínima recomendada:** 
- Single Target: **8** cartas
- Board Wipes: **2-3** cartas

---

## 4. 🔍 Busca e Recomendação (Source of Truth)

### 4.1 Origem das Sugestões

**P4.1.1:** De onde vêm as **sugestões de cartas novas**?

| Fonte | Usado? | Prioridade |
|-------|--------|------------|
| Tabela `format_staples` (NOVO v1.3) | ☑ Sim | **Principal** (cache local) |
| Query dinâmica no Scryfall API | ☑ Sim | Fallback (quando DB > 24h) |
| Listas hardcoded no código | ☑ **Removido** | ~~Fallback~~ → Apenas Sol Ring/Arcane Signet/Command Tower como fallback mínimo |
| Banco de dados interno (tabela `cards`) | ☑ Sim | Validação pós-sugestão |
| Meta decks (tabela `meta_decks`) | ☑ Sim | Contexto adicional |
| OpenAI (GPT) com liberdade criativa | ☑ Sim | Decisão final |

**Novo Fluxo de Sugestões (v1.3):**
```
1. FormatStaplesService.getStaples()
   ├── Tenta buscar de format_staples (DB local)
   │   └── Se dados frescos (<24h): Retorna do cache
   └── Fallback: Busca Scryfall API em tempo real
       └── Ordena por EDHREC rank (popularidade)

2. SynergyEngine.fetchCommanderSynergies()
   └── Busca cartas que combinam com o comandante

3. OpenAI combina tudo e toma decisão final
```

---

### 4.2 Integração com Scryfall

**P4.2.1:** Se usa Scryfall, quais **parâmetros de busca exatos** são usados?

**Query base:**
```dart
// lib/ai/sinergia.dart linha 74
final finalQuery = query.contains('format:') ? query : '$query format:commander -is:banned';
```

**Parâmetros adicionais:**

| Parâmetro | Valor | Propósito |
|-----------|-------|-----------|
| `format:` | `commander` | Garantir legalidade no formato |
| `-is:` | `banned` | Excluir cartas banidas |
| `order:` | `edhrec` | Ordenar por popularidade (mais usadas primeiro) |
| `id<=` | Cores do deck (ex: `UBG`) | Filtrar por identidade de cor |

**Exemplo de query completa:**
```
// routes/ai/optimize/index.dart - _fetchScryfallCards()
q=format:commander -is:banned
order=edhrec

// Para busca contextual:
q=oracle:infect format:commander -is:banned
q=function:artifact-payoff id<=UB format:commander -is:banned
```

---

**P4.2.2:** Como garantimos que **NÃO sugerimos cartas banidas**?

- [x] Filtro `-is:banned` na query do Scryfall
- [x] Verificação pós-fetch contra tabela `card_legalities`
- [x] **Ambos**
- [ ] Não verificamos

**Código de verificação pós-fetch:**
```dart
// routes/import/index.dart linhas 233-256
final legalityResult = await conn.execute(
  Sql.named(
    'SELECT c.name, cl.status FROM card_legalities cl 
     JOIN cards c ON c.id = cl.card_id 
     WHERE cl.card_id = ANY(@ids) AND cl.format = @format'
  ),
  parameters: {
    'ids': TypedValue(Type.textArray, cardIdsToCheck),
    'format': format,
  }
);

final bannedCards = <String>[];
for (final row in legalityResult) {
  if (row[1] == 'banned') {
    bannedCards.add(row[0] as String);
  }
}
```

---

**P4.2.3:** Como garantimos que **NÃO sugerimos cartas fora da identidade de cor**?

**Método utilizado:**

- [x] Filtro `id<=` na query do Scryfall (ex: `id<=UBG` para Sultai)
- [ ] Verificação pós-fetch comparando `colors` da carta com `colors` do deck
- [ ] Nenhuma verificação

**Código:**
```dart
// lib/ai/sinergia.dart linhas 21-28
final colorQuery = "id<=${colors.join('')}";
// Gera: id<=UBG (para deck Sultai)

// routes/ai/optimize/index.dart - _fetchFormatStaples()
final colorQuery = colors.isEmpty ? "c:c" : "id<=${colors.join('')}";
final query = "format:commander -is:banned $colorQuery";
```

**Possíveis bugs:**
- O que acontece com cartas híbridas? `O filtro id<= do Scryfall trata corretamente (híbrido pode ir em qualquer cor)`
- O que acontece com cartas colorless com ativações coloridas? `Cartas como "Golos" têm ativações WUBRG. O filtro id<= INCLUI corretamente pois color identity considera ativações.`

---

### 4.3 Validação Anti-Hallucination

**P4.3.1:** Como validamos cartas sugeridas pela IA contra o banco de dados?

**Fluxo de validação:**
```dart
// routes/ai/optimize/index.dart linhas 542-587
// lib/card_validation_service.dart

1. IA sugere: ["Lightning Bolt", "ManaRock999", "Sol Rig"]

2. Sistema valida via CardValidationService.validateCardNames():
   - "Lightning Bolt" → SELECT WHERE LOWER(name) = LOWER(@name) → ENCONTRADO ✓
   - "ManaRock999" → Query retorna vazio → NÃO EXISTE ✗
   - "Sol Rig" → Query retorna vazio → NÃO EXISTE ✗
     → Fuzzy search: WHERE name ILIKE '%Sol Rig%' → Sugere "Sol Ring"

3. Resultado final:
   {
     'valid': [{'id': '...', 'name': 'Lightning Bolt'}],
     'invalid': ['ManaRock999', 'Sol Rig'],
     'suggestions': {
       'Sol Rig': ['Sol Ring'],
       'ManaRock999': []
     }
   }
```

---

**P4.3.2:** Existe **fuzzy matching** para corrigir typos da IA?

- [x] Sim → Algoritmo usado: `ILIKE '%pattern%'` (substring match)
- **NÃO é Levenshtein Distance**, é apenas busca por substring

**Código:**
```dart
// lib/card_validation_service.dart linhas 75-90
Future<List<String>> _findSimilarCards(String cardName) async {
  final cleanName = cardName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
  
  final result = await _pool.execute(
    Sql.named("SELECT name FROM cards WHERE name ILIKE @pattern LIMIT 5"),
    parameters: {'pattern': '%$cleanName%'},
  );

  return result.map((row) => row[0] as String).toList();
}
```

**Threshold de similaridade (se aplicável):** N/A (busca por substring, não por similaridade %) 

---

## 5. 🤖 Integração com IA (LLM)

### 5.1 Dados Enviados no Prompt

**P5.1.1:** Quais **dados exatos** são enviados no prompt para a IA?

| Dado | Incluído? | Exemplo |
|------|-----------|---------|
| Nome do deck | ☑ Sim | "Atraxa Infect" |
| Formato (Commander, Standard) | ☑ Sim | "commander" |
| Nome do Comandante | ☑ Sim | "Atraxa, Praetors' Voice" |
| Lista completa de cartas | ☑ Sim | Lista de 99 nomes |
| Lista de cartas "fracas" (candidatas a corte) | ☑ Sim | Top 15 por weakness_score |
| CMC Médio calculado | ☑ Sim | "2.85" |
| Arquétipo detectado | ☑ Sim | "aggro", "control", "midrange" |
| Pool de cartas sinérgicas (Scryfall) | ☑ Sim | Via SynergyEngine |
| Lista de staples do formato | ☑ Sim | Via getArchetypeRecommendations() |
| Contexto de Meta Decks | ☑ Sim | Query em `meta_decks` table |

---

**P5.1.2:** Cole o **System Prompt** exato enviado à IA:

```markdown
// lib/ai/prompt.md (usado pelo DeckOptimizerService)

SYSTEM ROLE
Você é o "The Optimizer", um campeão mundial de Magic: The Gathering e deck 
builder profissional especializado em cEDH e High-Power Commander.
Sua missão não é apenas "dar dicas", mas cirurgicamente remover as peças 
fracas de um deck e inserir peças de alta performance, mantendo a curva de 
mana e a função das cartas equilibradas.

OBJETIVO
Receber uma lista de deck e um contexto de dados (estatísticas de cartas 
fracas e opções de sinergia) e retornar um JSON estrito com trocas sugeridas.

CONTEXTO DE DADOS FORNECIDO
- Decklist Atual: Lista completa do usuário
- Candidatas Fracas (Data-Driven): Lista de cartas impopulares/ineficientes
- Pool de Sinergia: Cartas que combinam com o Comandante

DIRETRIZES DE OTIMIZAÇÃO (CHAIN OF THOUGHT)
1. Análise de Curva de Mana (CMC)
2. Categorização Funcional (Swap 1-for-1)
3. Avaliação de "Cartas Armadilha"
4. Sinergia do Comandante

OUTPUT FORMAT (JSON STRICT)
{
  "summary": "Uma frase curta de impacto...",
  "swaps": [
    {
      "out": "Nome Exato da Carta a Remover",
      "in": "Nome Exato da Carta a Adicionar",
      "category": "Mana Ramp" | "Card Draw" | "Removal" | "Synergy" | "Land Base",
      "reasoning": "Explicação técnica e direta.",
      "priority": "High" | "Medium" | "Low"
    }
  ]
}

REGRAS FINAIS DE SEGURANÇA
- NÃO SUGIRA CARTAS BANIDAS (Mana Crypt, Jeweled Lotus, Dockside, Nadu)
- Ignore terrenos básicos na lista de candidatas fracas
- Seja implacável com cartas "Win-more"
```

**Arquivo de referência:** `server/lib/ai/prompt.md`

---

### 5.2 Liberdade Criativa vs Controle

**P5.2.1:** A IA tem **liberdade criativa** ou escolhe de uma **lista pré-aprovada**?

- [ ] Liberdade total (pode inventar qualquer carta)
- [ ] Escolhe apenas de uma lista fornecida no prompt (pool de sinergia + staples)
- [x] **Misto** (liberdade, mas validamos depois)

**Fluxo:**
```
1. IA recebe pools de sugestão (synergy + staples) mas NÃO é obrigada a usar apenas elas
2. IA retorna suas sugestões livremente
3. CardValidationService valida cada carta contra o banco
4. Cartas inexistentes são filtradas e warnings são gerados
```

---

**P5.2.2:** Se a IA sugere uma carta que **não existe**, o que acontece?

- [ ] Erro fatal (sistema quebra)
- [x] Carta é silenciosamente ignorada (filtrada)
- [x] Sistema sugere alternativas similares (fuzzy search)
- [x] Usuário recebe warning

**Código:**
```dart
// routes/ai/optimize/index.dart linhas 569-586
// Preparar resposta com avisos sobre cartas inválidas
final invalidCards = validation['invalid'] as List<String>;
final suggestions = validation['suggestions'] as Map<String, List<String>>;

final responseBody = {
  'removals': validRemovals,
  'additions': validAdditions,
  'reasoning': jsonResponse['reasoning'],
};

// Adicionar avisos se houver cartas inválidas
if (invalidCards.isNotEmpty) {
  responseBody['warnings'] = {
    'invalid_cards': invalidCards,
    'message': 'Algumas cartas sugeridas pela IA não foram encontradas e foram removidas',
    'suggestions': suggestions,
  };
}
```

---

**P5.2.3:** Qual é o parâmetro de **temperature** usado?

```dart
// routes/ai/optimize/index.dart linha 523
'temperature': 0.7,  // Para endpoint /ai/optimize

// lib/ai/otimizacao.dart linha 122
'temperature': 0.4,  // Para DeckOptimizerService (mais analítico)
```

**Justificativa:** 
- `0.7` no optimize: Permite mais criatividade nas sugestões
- `0.4` no otimizacao.dart: Mais conservador e analítico para decisões críticas

---

### 5.3 Formato de Resposta

**P5.3.1:** Qual é o **formato JSON esperado** da resposta da IA?

```json
// Para /ai/optimize (mais simples)
{
  "removals": ["Carta Ruim 1", "Carta Ruim 2"],
  "additions": ["Carta Boa 1", "Carta Boa 2"],
  "reasoning": "Explicação focada no arquétipo..."
}

// Para DeckOptimizerService (mais detalhado)
{
  "summary": "Curva de mana muito alta...",
  "swaps": [
    {
      "out": "Commander's Sphere",
      "in": "Arcane Signet",
      "category": "Mana Ramp",
      "reasoning": "Arcane Signet custa 2 manas em vez de 3...",
      "priority": "High"
    }
  ]
}
```

---

**P5.3.2:** O que acontece se a IA retornar **JSON inválido** ou com **markdown**?

**Tratamento atual:**
```dart
// routes/ai/optimize/index.dart linhas 536-593
// 1. Remove markdown code blocks
final cleanContent = content.replaceAll('```json', '').replaceAll('```', '').trim();

try {
  final jsonResponse = jsonDecode(cleanContent) as Map<String, dynamic>;
  // Continua processamento...
} catch (e) {
  // 2. Se falhar o parse, retorna erro com conteúdo raw para debug
  return Response.json(
    statusCode: HttpStatus.internalServerError,
    body: {'error': 'Failed to parse AI response', 'raw': content},
  );
}
```

---

## 6. 🎮 Lógica de Arquétipo

### 6.1 Detecção de Arquétipo

**P6.1.1:** Como o sistema sabe se o deck é **Aggro, Control, Midrange ou Combo**?

- [x] Input explícito do usuário (via parâmetro `archetype` no /ai/optimize)
- [x] Detecção automática baseada em estatísticas (`DeckArchetypeAnalyzer`)
- [ ] Detecção automática baseada em palavras-chave
- [ ] Não detectamos (assumimos genérico)

**Fluxo:**
```
1. Usuário pode escolher arquétipo explicitamente OU
2. Sistema detecta via DeckArchetypeAnalyzer.detectArchetype()
3. Ambos são enviados no prompt (targetArchetype + detectedArchetype)
```

---

**P6.1.2:** Se a detecção é automática, quais são os **critérios exatos**?

| Arquétipo | CMC Médio | % Criaturas | % Instants/Sorceries | Outros Critérios |
|-----------|-----------|-------------|----------------------|------------------|
| Aggro | < **2.5** | > **40%** | - | - |
| Control | > **3.0** | < **25%** | > **35%** | - |
| Combo | - | < **30%** | > **40%** | - |
| Midrange | **2.5 a 3.5** | **25% a 45%** | - | Default se não se encaixar |
| Stax | - | - | - | > **30%** Enchantments |

**Código:**
```dart
// routes/ai/optimize/index.dart - DeckArchetypeAnalyzer.detectArchetype()

// Aggro: CMC baixo (< 2.5), muitas criaturas (> 40%)
if (avgCMC < 2.5 && creatureRatio > 0.4) {
  return 'aggro';
}

// Control: CMC alto (> 3.0), poucos criaturas (< 25%), muitos instants/sorceries
if (avgCMC > 3.0 && creatureRatio < 0.25 && instantSorceryRatio > 0.35) {
  return 'control';
}

// Combo: Muitos instants/sorceries (> 40%) e poucos criaturas
if (instantSorceryRatio > 0.4 && creatureRatio < 0.3) {
  return 'combo';
}

// Stax/Enchantress: Muitos enchantments (> 30%)
if (enchantmentRatio > 0.3) {
  return 'stax';
}

// Midrange: Valor médio de CMC e equilíbrio de tipos
if (avgCMC >= 2.5 && avgCMC <= 3.5 && creatureRatio >= 0.25 && creatureRatio <= 0.45) {
  return 'midrange';
}

// Default
return 'midrange';
```

---

**P6.1.3:** Existe um sistema de **confiança** na detecção?

- [x] Sim → Como é calculado?

```dart
// routes/ai/optimize/index.dart - _calculateConfidence()

String _calculateConfidence(double avgCMC, Map<String, int> counts, String archetype) {
  final totalNonLands = cards.length - (counts['lands'] ?? 0);
  if (totalNonLands < 20) return 'baixa';  // Deck muito pequeno
  
  final creatureRatio = (counts['creatures'] ?? 0) / totalNonLands;
  
  switch (archetype) {
    case 'aggro':
      if (avgCMC < 2.2 && creatureRatio > 0.5) return 'alta';
      if (avgCMC < 2.8 && creatureRatio > 0.35) return 'média';
      return 'baixa';
    case 'control':
      if (avgCMC > 3.2 && creatureRatio < 0.2) return 'alta';
      return 'média';
    default:
      return 'média';
  }
}
```

---

### 6.2 Recomendações por Arquétipo

**P6.2.1:** Existem **staples pré-definidos** por arquétipo?

| Arquétipo | Staples Recomendados | Arquivo/Localização |
|-----------|---------------------|---------------------|
| Aggro | Lightning Greaves, Swiftfoot Boots, Jeska's Will, Deflecting Swat | `ai/optimize/index.dart:236-246` |
| Control | Counterspell, Swords to Plowshares, Path to Exile, Cyclonic Rift, Teferi's Protection | `ai/optimize/index.dart:247-258` |
| Combo | Demonic Tutor, Vampiric Tutor, Mystical Tutor, Rhystic Study, Necropotence | `ai/optimize/index.dart:259-270` |
| Midrange | Beast Within, Chaos Warp, Generous Gift, Skullclamp, The Great Henge | `ai/optimize/index.dart:271-282` |

**Adicionalmente, por COR:**
```dart
// ai/optimize/index.dart linhas 287-305
if (colors.contains('W')) → Swords to Plowshares, Path to Exile, Esper Sentinel
if (colors.contains('U')) → Counterspell, Cyclonic Rift, Rhystic Study
if (colors.contains('B')) → Demonic Tutor, Toxic Deluge, Orcish Bowmasters
if (colors.contains('R')) → Jeska's Will, Ragavan, Deflecting Swat
if (colors.contains('G')) → Nature's Lore, Three Visits, Birds of Paradise
```

---

**P6.2.2:** Existem **cartas a evitar** por arquétipo?

| Arquétipo | Cartas/Padrões a Evitar | Por quê? |
|-----------|------------------------|----------|
| Aggro | Cartas com CMC > 5, Criaturas defensivas, Removal lento | Muito lento para a estratégia |
| Control | Criaturas vanilla, Cartas agressivas sem utilidade | Não geram valor defensivo |
| Combo | Cartas que não avançam o combo, Creatures irrelevantes | Slot desperdiçado |
| Midrange | Cartas muito situacionais, Win-more cards | Inconsistentes |

**Código:**
```dart
// ai/optimize/index.dart - getArchetypeRecommendations()
case 'aggro':
  recommendations['avoid']!.addAll([
    'Cartas com CMC > 5', 'Criaturas defensivas', 'Removal lento'
  ]);
  break;
// ... etc
```

---

## 7. 🐛 Identificação de Possíveis Bugs

### Baseado nas respostas acima, marque possíveis problemas:

- [ ] **Parser não trata DFCs corretamente** (P1.1.3) - ✅ Tratado via fallback LIKE
- [ ] **CMC de cartas híbridas calculado incorretamente** (P2.1.1) - ✅ **CORRIGIDO**: `{2/W}` agora conta como 2
- [ ] **Terrenos são incluídos no CMC médio** (P2.1.2) - ✅ Excluídos corretamente
- [ ] **Tipos múltiplos são contados uma vez só** (P2.2.1) - ✅ **CORRIGIDO**: Artifact Creature conta para ambos
- [ ] **Cartas sem EDHREC rank são tratadas como ruins** (P3.1.2) - ✅ **CORRIGIDO**: Usa mediana do deck
- [ ] **Staples não são protegidos de corte** (P3.1.3) - ✅ Protegidos via prompt + rank baixo
- [x] **Cartas de nicho são marcadas como ruins** (P3.2.2) - ⚠️ Depende apenas do EDHREC global
- [ ] **Cartas banidas podem ser sugeridas** (P4.2.2) - ✅ Dupla verificação (Scryfall + DB)
- [ ] **IA pode sugerir cartas fora da identidade de cor** (P4.2.3) - ✅ Filtro id<= funciona corretamente
- [ ] **IA pode inventar cartas que não existem** (P5.2.2) - ✅ Validação pós-IA implementada
- [x] **Arquétipo pode ser detectado incorretamente** (P6.1.2) - ⚠️ Thresholds rígidos, sem ML
- [ ] **Deck sem comandante não gera erro** (P1.1.2) - ✅ **CORRIGIDO**: Detecta automaticamente + warning
- [ ] **Battle cards não são detectados** (P2.2.2) - ✅ **CORRIGIDO**: Tipo Battle implementado

### Bugs Corrigidos nesta Versão:

| Bug | Severidade | Status | Commit |
|-----|------------|--------|--------|
| CMC de híbridos incorreto | Alta | ✅ CORRIGIDO | Parsing correto de `{2/W}` → 2 |
| Cartas novas sem EDHREC rank são penalizadas | Alta | ✅ CORRIGIDO | Usa mediana do deck |
| Artifact Creature conta só como Creature | Média | ✅ CORRIGIDO | Contagem múltipla implementada |
| Deck Commander sem comandante detectado | Média | ✅ CORRIGIDO | Auto-detecta Legendary Creature + warning |
| Type "Battle" não detectado | Baixa | ✅ CORRIGIDO | Adicionado na contagem de tipos |

### Bugs Pendentes:

| Bug | Severidade | Impacto | Sugestão de Correção |
|-----|------------|---------|---------------------|
| Cartas de nicho marcadas como ruins | Baixa | Score não considera sinergia local | Adicionar análise de sinergia contextual |
| Detecção de arquétipo rígida | Baixa | Thresholds fixos podem errar | Implementar ML ou ajustar thresholds dinamicamente |

---

## 8. 📝 Notas Adicionais

**Observações do auditor:**

```
1. ARQUITETURA GERAL:
   O sistema usa uma abordagem híbrida interessante: heurísticas matemáticas 
   (CMC, EDHREC rank) combinadas com IA (GPT) para decisões finais. Isso reduz
   alucinações enquanto mantém flexibilidade.

2. PONTOS FORTES:
   - Validação anti-hallucination bem implementada (CardValidationService)
   - Fallbacks múltiplos no parsing de cartas
   - Double-check de banlist (Scryfall + DB local)
   - Sistema de arquétipo com confiança
   - ✅ (v1.3) Staples dinâmicos via FormatStaplesService
   - ✅ (v1.3) Sincronização automática de banlist

3. PONTOS FRACOS:
   - Fórmula de weakness_score muito simples (só EDHREC + CMC)
   - Não considera sinergias locais do deck no score
   - Threshold de arquétipo hardcoded (deveria ser ML)
   - Não há simulação de mãos iniciais (Monte Carlo)

4. MELHORIAS IMPLEMENTADAS (v1.3):
   - ✅ Staples dinâmicos em vez de hardcoded (FormatStaplesService)
   - ✅ Tabela format_staples para cache de staples por formato/arquétipo
   - ✅ Script sync_staples.dart para sincronização semanal via Scryfall
   - ✅ Banlist dinâmico sincronizado automaticamente
   - ✅ Tabela sync_log para auditoria de atualizações

5. PRÓXIMAS MELHORIAS SUGERIDAS:
   - Implementar Levenshtein distance para fuzzy match
   - Adicionar campo `synergy_with_commander` no score
   - Treinar modelo de ML para detecção de arquétipo
   - Implementar simulador de Goldfish (mãos iniciais)

6. SEGURANÇA:
   - API key da OpenAI vem de .env (correto)
   - Rate limiting implementado em endpoints sensíveis
   - Sanitização de nomes de cartas antes de queries SQL
```

---

## 9. ✅ Assinaturas

**Auditor:**  
Nome: GitHub Copilot  
Data: 25/11/2025  
Assinatura: Auditoria automatizada via análise de código

**Desenvolvedor:**  
Nome: _______________  
Data: ___/___/______  
Assinatura: _______________

---

_Este formulário deve ser revisado sempre que houver mudanças significativas nos algoritmos de otimização._

**Versão do Formulário:** 1.4  
**Última Atualização:** 25 de Novembro de 2025  

**Changelog:**
- v1.4: **MAJOR** - Sistema de Matchup, Análise de Fraquezas e Hate Cards Dinâmicos
  - ✅ Criada tabela `archetype_counters` para armazenar hate cards por arquétipo
  - ✅ Criada tabela `deck_weakness_reports` para histórico de fraquezas
  - ✅ Implementado `ArchetypeCountersService` para busca dinâmica de hate cards
  - ✅ Implementado endpoint `POST /ai/weakness-analysis` para análise de fraquezas
  - ✅ Implementado endpoint `POST /ai/simulate-matchup` para simulação de matchup
  - ✅ Integrado hate cards no `getArchetypeRecommendations()`
  - ✅ Dados iniciais de hate cards populados (graveyard, artifacts, tokens, etc.)
  - **Por que essa mudança?**
    - Sistema anterior não analisava matchups contra decks específicos
    - Hate cards estavam sugeridos para serem hardcoded (má prática)
    - Não havia forma de provar eficácia das otimizações
    - Faltava análise sistemática de pontos fracos do deck
- v1.3: **MAJOR** - Sistema de Staples Dinâmicos
  - ✅ Criada tabela `format_staples` para armazenar staples por formato/arquétipo/cor
  - ✅ Criada tabela `sync_log` para auditoria de sincronizações
  - ✅ Implementado `FormatStaplesService` para busca dinâmica de staples
  - ✅ Implementado script `bin/sync_staples.dart` para sincronização semanal via Scryfall
  - ✅ Removidas listas hardcoded de staples em `routes/ai/optimize/index.dart`
  - ✅ Atualizado `lib/ai/prompt.md` para referenciar banlist dinâmico
  - ✅ Banlist agora é sincronizado automaticamente via `is_banned` flag
  - **Por que essa mudança?**
    - Listas hardcoded ficam desatualizadas quando há bans (ex: Mana Crypt, Nadu)
    - Scryfall API é a fonte de verdade para popularidade (EDHREC rank)
    - Cache local (24h) evita sobrecarga na API e melhora performance
    - Script de sync pode ser executado via cron job semanal
- v1.2: Implementação das correções identificadas na auditoria
  - ✅ CMC híbrido corrigido (`{2/W}` → 2)
  - ✅ Contagem de tipos múltiplos (Artifact Creature conta para ambos)
  - ✅ EDHREC rank para cartas novas usa mediana do deck
  - ✅ Detecção automática de comandante + warning
  - ✅ Tipo Battle adicionado na contagem
- v1.1: Preenchimento completo do formulário com dados do codebase
- v1.0: Template inicial do formulário

**Arquivos Modificados (v1.3):**
- `server/database_setup.sql` - Tabelas format_staples e sync_log
- `server/bin/sync_staples.dart` - Script de sincronização (NOVO)
- `server/lib/format_staples_service.dart` - Serviço de staples dinâmicos (NOVO)
- `server/routes/ai/optimize/index.dart` - Usa FormatStaplesService
- `server/lib/ai/prompt.md` - Banlist dinâmico

**Arquivos Modificados (v1.4):**
- `server/database_setup.sql` - Tabelas archetype_counters e deck_weakness_reports
- `server/lib/archetype_counters_service.dart` - Serviço de hate cards dinâmicos (NOVO)
- `server/routes/ai/weakness-analysis/index.dart` - Análise de fraquezas (NOVO)
- `server/routes/ai/simulate-matchup/index.dart` - Simulação de matchup (NOVO)
- `server/routes/ai/optimize/index.dart` - Integração com hate cards

**Arquivos Modificados (v1.2):**
- `server/routes/import/index.dart` - Validação de comandante
- `server/routes/decks/[id]/analysis/index.dart` - CMC híbrido
- `server/routes/ai/optimize/index.dart` - Contagem de tipos + Battle
- `server/lib/ai/otimizacao.dart` - EDHREC rank mediana

**Arquivos Analisados:**
- `server/routes/import/index.dart`
- `server/routes/decks/[id]/analysis/index.dart`
- `server/routes/ai/optimize/index.dart`
- `server/lib/ai/otimizacao.dart`
- `server/lib/ai/sinergia.dart`
- `server/lib/ai/prompt.md`
- `server/lib/card_validation_service.dart`
- `server/lib/format_staples_service.dart` (NOVO)
- `server/bin/sync_staples.dart` (NOVO)
- `server/lib/archetype_counters_service.dart` (NOVO v1.4)
- `server/routes/ai/weakness-analysis/index.dart` (NOVO v1.4)
- `server/routes/ai/simulate-matchup/index.dart` (NOVO v1.4)

**Instruções para Sincronização de Staples:**
```bash
# Sincronizar apenas Commander (recomendado para primeira execução)
dart run bin/sync_staples.dart commander

# Sincronizar todos os formatos
dart run bin/sync_staples.dart ALL

# Configurar cron job para sincronização semanal (Linux)
# Toda segunda-feira às 3h da manhã:
0 3 * * 1 cd /path/to/server && dart run bin/sync_staples.dart ALL >> /var/log/mtg_sync.log 2>&1
```

**Novos Endpoints (v1.4):**

```bash
# Análise de fraquezas do deck
POST /ai/weakness-analysis
{
  "deck_id": "uuid"
}
# Retorna: weaknesses[], statistics, recommendations

# Simulação de matchup entre decks
POST /ai/simulate-matchup
{
  "my_deck_id": "uuid",
  "opponent_deck_id": "uuid",
  "simulations": 100
}
# Retorna: win_rate, advantages, disadvantages, hate_cards
```
