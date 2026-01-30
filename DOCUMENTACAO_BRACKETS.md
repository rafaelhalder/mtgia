# EDH Brackets (Métrica e Regras)

Este documento define a métrica usada pelo projeto para o parâmetro `bracket` (EDH power level) e garante consistência entre execuções.

## Visão geral

O bracket é aplicado em 2 camadas:

1) **IA (prompt)**: a IA recebe instruções explícitas para respeitar o bracket ao sugerir cartas.
2) **Backend (filtro determinístico)**: o servidor valida e bloqueia sugestões que excedem os limites do bracket (modo intermediário).

O bracket **não substitui** as regras duras (legalidade, identidade de cor, limite de cópias).

## Brackets

### Bracket 1 — Casual
- Objetivo: jogos mais lentos, menos consistência via tutores, sem “picos” de fast mana.
- Limites (máximo no deck):
  - fast mana: 1
  - tutores: 1
  - interação gratuita: 0
  - turnos extras: 0
  - infinite combos: 0

### Bracket 2 — Mid
- Objetivo: sinergia e staples moderadas, sem virar High/cEDH.
- Limites:
  - fast mana: 3
  - tutores: 3
  - interação gratuita: 2
  - turnos extras: 1
  - infinite combos: 0

### Bracket 3 — High
- Objetivo: decks eficientes, com interação e tutores mais presentes.
- Limites:
  - fast mana: 6
  - tutores: 6
  - interação gratuita: 6
  - turnos extras: 2
  - infinite combos: 2

### Bracket 4 — cEDH
- Objetivo: máxima eficiência.
- Limites: sem limite efetivo (o backend não bloqueia por bracket).

## Categorias (detecção)

As categorias são detectadas por heurística:

- `tutor`: `oracle_text` contém `search your library`
- `extraTurns`: `oracle_text` contém `extra turn`
- `freeInteraction`: `oracle_text` contém `rather than pay` + (exile/pay life) (heurística)
- `fastMana`: lista curada de nomes (ex.: `Sol Ring`, `Mana Crypt`, `Jeweled Lotus`, etc.)
- `infiniteCombo`: lista curada inicial (placeholder)

Implementação: `server/lib/edh_bracket_policy.dart`

## Modo intermediário (como o backend age)

- O servidor **bloqueia** adições sugeridas pela IA que excedem o “budget” restante do bracket considerando o deck atual.
- As cartas bloqueadas não somem “silenciosamente”: voltam em `warnings.blocked_by_bracket` com motivo/categorias.

Endpoint impactado:
- `POST /ai/optimize` (inclui modo `complete` quando o deck está incompleto).

