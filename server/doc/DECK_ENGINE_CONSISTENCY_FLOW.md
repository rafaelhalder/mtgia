# Deck Engine Consistency Flow (Carro-chefe)

## 1) Objetivo

Garantir que a montagem de deck seja **consistente, reproduzível e confiável**:
- Sempre devolver um deck completo (quando houver dados mínimos válidos).
- Não depender de disponibilidade externa para finalizar a montagem.
- Manter qualidade competitiva mínima por formato/arquétipo.

---

## 2) Princípio de Arquitetura

**IA não fecha deck.**
A IA vira um componente de **ranking/explicação**.

Quem fecha deck é o **motor determinístico local** (solver), com regras fixas de:
- legalidade
- identidade de cor
- limites de cópia
- metas de composição (lands/ramp/draw/removal/wincons)
- política de power-level (bracket)

---

## 3) Papel dos dados externos (aproveitável e faz sentido)

### 3.1 O que já existe e deve continuar
- `meta_decks` (decks competitivos coletados)
- extração para tabelas de conhecimento:
  - `card_meta_insights`
  - `synergy_packages`
  - `archetype_patterns`

### 3.2 Como usar sem dependência crítica
- Dados externos entram como **sinal de priorização** (score base).
- Se fonte externa falhar, o solver continua com catálogo local + regras determinísticas.
- Nunca usar resposta externa como condição única para completar 100 cartas.

---

## 4) Novo fluxo único de montagem

## Etapa A — Normalização de entrada
Entrada mínima:
- formato
- comandante (quando Commander)
- arquétipo alvo
- preferências opcionais (bracket, keep_theme)

Saída:
- request canônica usada por todo pipeline

## Etapa B — Catálogo local elegível (hard filters)
Construir pool local com filtros obrigatórios:
1. legalidade por formato
2. identidade de cor
3. limite de cópias
4. exclusão de cartas inválidas/ruído

Saída:
- `eligible_pool` (sempre interno)

## Etapa C — Slot plan determinístico
Definir metas por formato/arquétipo:
- lands alvo
- ramp alvo
- draw alvo
- removal alvo
- interaction alvo
- engine/sinergia alvo
- finisher/wincon alvo

Saída:
- `slot_plan` (ex.: faltam 9 ramp, 6 draw, 5 removal, ...)

## Etapa D — Scoring híbrido de sinergia (local-first)
Para cada carta elegível:
- `score_role_fit` (aderência ao slot faltante)
- `score_commander_fit` (aderência mecânica ao comandante)
- `score_archetype_fit` (aderência ao arquétipo)
- `score_meta_local` (presença em `card_meta_insights` / `synergy_packages`)
- `score_curve_mana` (impacto na curva)
- `score_power_policy` (ajuste de bracket)

Fórmula inicial:
`final_score = 0.30 role_fit + 0.25 commander_fit + 0.20 archetype_fit + 0.15 meta_local + 0.10 curve_mana`

Bracket não quebra montagem; ele reduz prioridade (`power_policy`) e força substituição equivalente.

Saída:
- ranking por slot

## Etapa E — Solver de preenchimento
Preenche slots em ordem de criticidade:
1. Ramp
2. Draw
3. Removal/Interaction
4. Engine/Sinergia
5. Wincons
6. Ajuste final de lands/curva

A cada adição:
- recalcula necessidades
- valida regras hard
- evita duplicação indevida

Condição de parada:
- total de cartas atingiu alvo do formato

## Etapa F — Fallback local garantido
Se algum slot não fechar:
- usar catálogo local tier B/C por função (não por tema)
- manter hard filters
- completar deck sem depender de API externa

Se ainda impossível (caso extremo):
- retornar erro estruturado com diagnóstico exato de indisponibilidade local
- registrar telemetria de lacuna de catálogo

## Etapa G — IA (opcional) como assistente
A IA pode:
- reordenar top candidatos por contexto textual
- explicar sinergias
- sugerir alternativas

A IA não pode:
- invalidar hard rules
- bloquear fechamento do deck

---

## 5) Como a sinergia será “nossa”

## 5.1 Fonte primária
Sinergia local vem de:
- co-ocorrência em `meta_decks`
- pacotes em `synergy_packages`
- padrões de `archetype_patterns`
- feedback de aceitação/rejeição do usuário
- (futuro) logs de simulação e matchup

## 5.2 Aprendizado contínuo
Pipeline diário:
1. ingestão de novos meta_decks
2. extração incremental de insights
3. recalibração de scores por arquétipo/formato
4. publicação de versão de conhecimento (`knowledge_version`)

## 5.3 Efeito prático
Com o tempo, o sistema reduz dependência de terceiros porque:
- ranking de cartas passa a ser guiado por base local acumulada
- o catálogo interno cobre lacunas mais comuns por slot
- decisões deixam de oscilar com disponibilidade externa

---

## 6) Adaptação incremental (sem big-bang)

### Fase 1 (curta)
- Criar solver de slots com catálogo atual.
- IA apenas para ranking adicional.
- Garantia de fechamento local.

### Fase 2
- Enriquecer catálogo local por função/cor/arquétipo.
- Aplicar score híbrido completo.

### Fase 3
- Versionar conhecimento e medir regressões por comandante.
- Introduzir auto-ajuste de pesos por métricas reais.

---

## 7) SLOs de consistência (obrigatório)

Métricas de produção:
- `% deck_complete_success` (meta >= 99%)
- `% complete_sem_erro_qualidade` (meta >= 97%)
- `% fallback_local_acionado`
- `% dependência_externa_necessária` (meta decrescente)
- tempo p95 de montagem

Qualidade:
- faixa de lands por formato
- mínimo funcional por slots
- taxa de sugestões rejeitadas pelo usuário

---

## 8) Critério de aceite do carro-chefe

A montagem é considerada estável quando:
1. completa o deck de forma previsível em suites fixas de regressão;
2. mantém hard rules 100% das vezes;
3. não depende de fonte externa para fechar deck;
4. explica decisões com telemetria auditável por execução.

---

## 9) Conclusão

Sim, **é aproveitável e faz sentido** usar terceiros, mas como insumo e não como pilar crítico.

A estratégia correta para o carro-chefe é:
- **motor determinístico local para conclusão**
- **sinergia própria como ativo crescente do produto**
- **fontes externas como enriquecimento opcional**
