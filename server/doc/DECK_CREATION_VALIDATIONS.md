# Validações Obrigatórias na Criação/Completação de Deck

**Status:** Norma técnica do backend (fonte de verdade para validação de deck)

**Escopo:** Fluxos `POST /decks`, `PUT /decks/:id`, `POST /decks/:id/cards`, `POST /decks/:id/cards/bulk`, `POST /ai/optimize` em `mode=complete`.

---

## 1) Princípio de Produto

A criação/completação de deck deve priorizar, nesta ordem:

1. **Validade de regra** (nunca quebrar regras do formato)
2. **Qualidade mínima de composição** (não retornar deck degenerado)
3. **Consistência estratégica** (arquétipo/theme/bracket)
4. **Auditabilidade** (resultado rastreável e revisável)

> Regra crítica: **deck válido porém ruim é falha de produto**.

---

## 2) Pipeline de Validação (ordem obrigatória)

## 2.1 Validação de payload (hard fail)

- Campos obrigatórios presentes por endpoint.
- Tipos corretos (`card_id`, `quantity`, `is_commander`, etc.).
- `quantity > 0`.
- Em bulk, `is_commander=true` é inválido.

**Falha:** `400`.

## 2.2 Resolução e existência de cartas (hard fail)

- Toda carta deve existir na tabela `cards`.
- Se vier nome em fluxo compatível, deve resolver para `card_id` antes de validar.

**Falha:** `400`.

## 2.3 Legalidade por formato (hard fail)

- Verificar `card_legalities` para o formato do deck.
- `banned` e `not_legal` são bloqueantes.
- `restricted` limita a 1 cópia.

**Falha:** `400`.

## 2.4 Regras estruturais do formato (hard fail)

### Commander/Brawl
- Comandante elegível (lendária criatura ou texto que permita commander).
- Regras de Partner/Background válidas.
- Limite de cópias por carta não-básica = 1.
- Tamanho máximo: Commander 100, Brawl 60.
- Em validação estrita, tamanho exato obrigatório.

### Outros formatos
- Limite de cópias padrão por carta não-básica = 4.

**Falha:** `400`.

## 2.5 Identidade de cor do comandante (hard fail)

- Toda carta deve estar contida na identidade de cor do(s) comandante(s).
- Para colorless commander, apenas cartas colorless/incolores.

**Falha:** `400`.

## 2.6 Política de bracket/power-level (hard filter + warning)

- Aplicar filtros de bracket em cartas sugeridas (tutores, fast mana, free interaction, extra turns, etc.).
- Carta bloqueada por bracket não entra no deck final.
- Registrar itens bloqueados em `warnings.blocked_by_bracket`.

**Comportamento:** bloqueia carta, não quebra request por si só.

---

## 3) Validação de Qualidade de Composição (obrigatória no mode=complete)

> Esta seção impede retorno tecnicamente válido e estrategicamente ruim.

## 3.1 Regras mínimas de composição (hard fail no complete)

Para Commander (100 cartas):

- **Terrenos totais** devem ficar em faixa aceitável: `32..42`.
- **Cartas não-terreno** mínimas: `>= 58`.
- **Terrenos básicos** não podem dominar o deck:
  - `basic_lands <= 65%` dos terrenos totais.
- Se `target_additions >= 40`, precisa existir **mínimo de 12 adições não-básicas**.

Se alguma regra falhar, o complete deve:
1. tentar regenerar (2ª passagem);
2. se falhar novamente, retornar erro de qualidade.

**Falha final:** `422` com diagnóstico.

## 3.2 Coerência de arquétipo (soft gate + warning)

- Comparar antes/depois: curva de mana, distribuição funcional e plano do arquétipo.
- Se piorar fortemente (ex.: aggro com curva subindo muito), incluir warning explícito.

**Comportamento:** warning + telemetria.

---

## 4) Política de fallback (proibido fallback degenerado)

## 4.1 Proibição

- É **proibido** fallback que complete majoritariamente com básicos por ausência de candidatas.
- Exemplo proibido: `70+` básicos em complete sem justificativa estratégica.

## 4.2 Fallback permitido

Em falta de sugestões da IA/pool sinérgico:

1. usar pool determinístico de staples não-básicas permitidas por formato/identidade/bracket;
2. completar mana base somente após atingir mínimo de não-terrenos;
3. respeitar limites de cópia e legalidade.

Se ainda assim não atingir qualidade mínima: `422`.

---

## 5) Observabilidade e auditoria (obrigatório)

Cada execução de `optimize complete` deve registrar:

- request normalizado (deck/archetype/bracket/keep_theme)
- summary de validações aplicadas
- composição final (lands, basics, non-lands)
- warnings
- resultado de persistência (`bulk_status`)

Artefato recomendado para QA:
- `server/test/artifacts/ai_optimize/<scenario>_latest.json`
- `server/test/artifacts/ai_optimize/<scenario>_<timestamp>.json`

---

## 6) Critério de aceite (DoD do carro-chefe)

Uma entrega de otimização só é considerada pronta quando:

- passa regras duras de formato/legalidade/identidade;
- passa regras mínimas de composição do complete;
- não retorna fallback degenerado;
- salva com sucesso no fluxo real (`/decks/:id/cards/bulk`);
- deixa artefato de validação revisável;
- está coberta por teste de integração de regressão.

---

## 7) Nota sobre a falha observada

O comportamento “fallback para muitos terrenos básicos” foi identificado como **anti-objetivo de produto**. Esta especificação formaliza que esse resultado é inválido em termos de qualidade, mesmo quando o deck passa nas regras estruturais.
