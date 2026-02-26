# ROADMAP DE PRODUTO — ManaLoom (90 dias)

Este é o roadmap oficial e único para levar o ManaLoom de projeto funcional para **produto competitivo**.

## 1) Objetivo do ciclo

Transformar o ManaLoom no melhor fluxo para jogador de MTG que quer:
1. montar deck rápido,
2. validar legalidade sem dor,
3. otimizar com recomendações confiáveis,
4. ver impacto real das mudanças.

## 2) Norte estratégico (o que é sucesso)

### Métricas-alvo (até 90 dias)
- **TTV (time-to-value)**: usuário novo chega no primeiro deck otimizado em < 10 minutos.
- **Taxa de conclusão do fluxo principal** (`criar -> analisar -> otimizar`): > 45% dos usuários ativos.
- **Retenção D7**: > 20%.
- **Falha de API no fluxo core**: < 1%.
- **Latência p95**:
  - listagem de decks: < 400ms
  - detalhe de deck: < 500ms
  - otimização IA: < 6s (com feedback progressivo)
- **Custo de IA por usuário ativo mensal**: teto definido e monitorado.

## 3) Princípios do roadmap

1. **Core primeiro, expansão depois**: priorizar Deck Builder + IA útil antes de ampliar social/trade.
2. **Velocidade com governança**: manter entrega rápida sem criar dívida estrutural crítica.
3. **IA com ROI**: cada chamada cara de IA precisa gerar valor claro para usuário.
4. **Produto orientado a dados**: decisões guiadas por funil e retenção.

---

## 4) Plano de execução (90 dias)

## Fase 1 (Semanas 1-3) — Estabilizar Core e Arquitetura

### P0 Técnico
- Consolidar padrão backend: mover regras pesadas de `routes/` para camada de serviço.
- Padronizar migrations: eliminar qualquer DDL residual no caminho de requisição.
- Fortalecer segurança operacional:
  - rate limit com backend distribuído (ex.: Redis) para produção,
  - política de logs sem vazamento de segredos,
  - checklist de hardening por ambiente.
- Observabilidade mínima:
  - logs estruturados,
  - métricas por endpoint,
  - dashboard de erro/latência/custo IA.

### P0 Produto/UX
- Reduzir fricção no fluxo principal:
  - CTA único de entrada: “Criar e otimizar deck”.
  - estado vazio orientado por tarefa.
- Definir onboarding de 3 passos:
  1) escolher formato,
  2) importar ou gerar base,
  3) aplicar otimização guiada.

### Entregáveis da fase
- Documento de arquitetura alvo (simples e executável).
- Checklist de produção aprovado.
- Funil instrumentado do fluxo principal.

---

## Fase 2 (Semanas 4-7) — Diferenciação real de IA

### P1 IA (alto impacto)
- Recomendação explicável por carta:
  - “por que entrou/saiu”,
  - impacto estimado (curva, consistência, sinergia, legalidade).
- Score de confiança por sugestão (baixo/médio/alto).
- Memória de preferência do usuário (estilo/cores/nível de budget).
- Cache multicamada para IA:
  - resultado por assinatura de deck + prompt normalizado,
  - TTL e invalidação por mudança relevante.

### P1 Produto
- Tela de otimização com comparação “antes vs depois” clara.
- Ação rápida: aplicar pacote completo ou item a item.
- Feedback imediato de legalidade e custo estimado pós-otimização.

### Entregáveis da fase
- Versão “AI Optimization v2” no app.
- Relatório de custo IA por endpoint e economia via cache.

---

## Fase 3 (Semanas 8-12) — Tração, Monetização e Escala

### P1 Growth/Monetização
- Definir oferta **B2C freemium**:
  - Free: uso básico com limites.
  - Pro: otimizações avançadas, histórico de versões, análises premium.
- Implementar limites por plano para endpoints de IA.
- Medir conversão de valor (uso repetido da otimização + retenção D30).

### P1 Escala
- Revisão de consultas críticas com p95 alto.
- Cache para endpoints quentes (ex.: metadados, buscas recorrentes).
- Plano de capacidade para 10k MAU.

### Entregáveis da fase
- Pricing draft + experimento de paywall leve.
- Relatório de readiness para escala.

---

## 5) O que NÃO priorizar agora

Para evitar dispersão de produto, **não expandir neste ciclo**:
- novas superfícies sociais complexas,
- funcionalidades de trade mais profundas,
- features “nice-to-have” sem impacto no funil core.

Esses itens ficam em backlog até o core atingir as metas de retenção e conversão.

## 6) Backlog pós-90 dias (condicionado a metas)

- Matchup coach avançado com sideboard guidance.
- Simulação estatística mais robusta e visual.
- Recursos colaborativos para times/lojas (possível trilha SaaS).

## 7) Governança de execução

Ritual semanal:
- Segunda: priorização e metas da semana.
- Quarta: review de métricas (funil, latência, erro, custo IA).
- Sexta: demo + decisões de corte/manutenção.

Critério para entrar sprint:
- Impacta diretamente valor percebido no fluxo core, OU
- reduz risco técnico crítico de produção.

## 8) Resumo executivo

Nos próximos 90 dias, o ManaLoom deve focar em:
1. **core impecável**,
2. **IA com impacto real e explicável**,
3. **base pronta para crescer e monetizar**.

Se esse plano for seguido com disciplina, o produto sai de “projeto promissor” para “produto competitivo de verdade”.

---

## 9) Plano operacional (como executar sem se perder)

Este bloco é a regra de operação para manter andamento contínuo.

### 9.1 Estrutura de execução por sprint (2 semanas)

Cada sprint deve ter:
- **1 objetivo principal** (core, IA, escala, etc).
- **até 5 entregas** claras e testáveis.
- **1 métrica de sucesso** obrigatória.
- **0 itens “talvez”**: ou entra no sprint, ou vai para backlog.

### 9.2 Formato de backlog ativo (usar sempre)

Para cada item de sprint:
- **Título curto**
- **Impacto no produto** (qual dor resolve)
- **Área** (`app`, `server`, `db`, `ux`, `ai`)
- **Critério de aceite** (objetivo e verificável)
- **Teste obrigatório** (unitário, integração, manual guiado)
- **Status** (`todo`, `in-progress`, `review`, `done`)

### 9.3 WIP e foco

- Limite de WIP: **máximo 2 itens técnicos simultâneos**.
- Qualquer item novo só entra se outro sair.
- Se aparecer urgência, registrar impacto e remover item equivalente do sprint.

---

## 10) Sprints sugeridos (90 dias)

## Sprint 1 (Semanas 1-2) — Estabilidade do Core

### Entregas
- [ ] Refatorar endpoints críticos para camada de serviço (decks/import/ai optimize).
- [ ] Eliminar DDL residual em request path.
- [ ] Padronizar tratamento de erro backend + códigos HTTP.
- [ ] Instrumentar métricas básicas (latência p95, erro por endpoint).
- [ ] Melhorar fluxo de criação/importação com feedback claro de falhas.

### Critério de aceite
- Sem regressões no fluxo `criar -> analisar -> otimizar`.
- p95 dos endpoints core dentro de alvo inicial definido.

## Sprint 2 (Semanas 3-4) — Segurança + Observabilidade

### Entregas
- [ ] Rate limiting distribuído para produção.
- [ ] Política de logs sem segredos + revisão de variáveis sensíveis.
- [ ] Health checks e readiness consistentes.
- [ ] Dashboard mínimo (erro, latência, custo IA, throughput).
- [ ] Hardening checklist por ambiente (dev/staging/prod).

### Critério de aceite
- Nenhum endpoint core sem monitoramento.
- Checklist de segurança operacional aprovado.

## Sprint 3 (Semanas 5-6) — IA v2 (valor real)

### Entregas
- [ ] Sugestão explicável por carta (entrada/saída + impacto).
- [ ] Score de confiança por recomendação.
- [ ] Memória de preferência do usuário.
- [ ] Cache de IA por assinatura de deck + prompt.
- [ ] Comparação clara “antes vs depois” na UI.

### Critério de aceite
- Usuário entende por que cada mudança foi sugerida.
- Queda mensurável de custo por cache sem perda de qualidade percebida.

## Sprint 4 (Semanas 7-8) — UX de ativação

### Entregas
- [ ] Onboarding em 3 passos no app.
- [ ] Estado vazio guiado para primeiro resultado.
- [ ] CTA principal único para fluxo core.
- [ ] Mensagens de erro/recuperação simplificadas.
- [ ] Instrumentação de funil de ativação completa.

### Critério de aceite
- TTV < 10 minutos para primeiro deck otimizado.

## Sprint 5 (Semanas 9-10) — Monetização inicial

### Entregas
- [ ] Definição de planos Free/Pro.
- [ ] Limites por plano em endpoints de IA.
- [ ] Telemetria de uso por plano e custo por usuário.
- [ ] Experimento de paywall leve.
- [ ] Critérios de upgrade com valor percebido claro.

### Critério de aceite
- Experimento ativo com métrica de conversão definida.

## Sprint 6 (Semanas 11-12) — Escala e readiness

### Entregas
- [ ] Revisão de queries críticas e otimizações finais.
- [ ] Estratégia de cache para endpoints quentes.
- [ ] Teste de carga para cenários principais.
- [ ] Plano de capacidade para 10k MAU.
- [ ] Checklist final de Go-Live.

### Critério de aceite
- Ambiente apto para crescimento com risco operacional reduzido.

---

## 11) Regra obrigatória de testes (sempre testando tudo)

Nenhuma entrega é “done” sem passar por este gate.

### 11.1 Gate técnico por PR

Antes de concluir qualquer item:
- [ ] Testes de backend relevantes passando.
- [ ] Testes de frontend relevantes passando.
- [ ] Verificação manual do fluxo impactado (happy path + erro principal).
- [ ] Sem erro de análise/lint nos arquivos alterados.

### 11.2 Comandos mínimos de validação

Backend (`server/`):
- `dart test`

Frontend (`app/`):
- `flutter analyze`
- `flutter test`

Quando a mudança for sensível ao fluxo principal:
- validar manualmente: criar deck, abrir detalhes, analisar, otimizar, salvar.

### 11.3 Definição de pronto (DoD)

Um item só pode ser marcado como concluído se:
1. critério de aceite foi cumprido,
2. testes aplicáveis foram executados e registrados,
3. documentação do que mudou foi atualizada,
4. impacto em produto/métrica está explícito.

---

## 12) Organização do repositório (estado atual)

Para reduzir confusão operacional:
- documentos ativos na raiz: `README.md` e `ROADMAP.md`.
- checklist diário de operação: `CHECKLIST_EXECUCAO.md`.
- histórico não prioritário fica em `archive_docs/`.
- documentação técnica contínua permanece em `server/manual-de-instrucao.md`.

Se necessário reativar um documento arquivado, mover de volta com justificativa no PR.

---

## 13) Regra de priorização contínua

Perguntas obrigatórias antes de iniciar qualquer tarefa:

1. Isso melhora diretamente o fluxo core?
2. Isso reduz risco técnico crítico?
3. Isso aumenta valor percebido de forma mensurável?

Se a resposta for “não” para as 3, o item vai para backlog.

---

## 14) Protocolo de execução (modo operacional)

Este protocolo define como executar com previsibilidade e qualidade.

### 14.1 Definition of Ready (DoR)

Um item só entra em execução se tiver:
- objetivo claro em 1 frase,
- critério de aceite mensurável,
- impacto esperado em métrica (produto ou técnica),
- escopo delimitado (o que entra e o que não entra),
- plano de teste definido.

### 14.2 Ordem obrigatória de execução por item

1. Entender e delimitar escopo.
2. Implementar a menor mudança correta possível.
3. Validar localmente (qualidade + teste funcional do fluxo afetado).
4. Atualizar documentação técnica (`server/manual-de-instrucao.md`).
5. Registrar resultado no sprint (feito/bloqueado/riscos).

### 14.3 Critérios de bloqueio

Bloquear item imediatamente quando:
- faltar dependência crítica (infra, segredo, schema, contrato),
- risco de regressão sem cobertura mínima de teste,
- mudança extrapolar escopo e comprometer prazo da sprint.

Ação obrigatória ao bloquear:
- registrar causa em 1 linha,
- definir próximo passo objetivo,
- replanejar sem quebrar meta da sprint.

### 14.4 Política de rollback

Para toda entrega que altera fluxo core, definir antes:
- como desfazer (reversão de código/config),
- impacto de rollback no usuário,
- verificação pós-rollback.

### 14.5 Rituais de controle

- Daily curto: progresso, impedimento, próximo passo.
- Mid-sprint check: validar métrica parcial.
- Fechamento: demo + comparação objetivo vs realizado.

### 14.6 Fonte única de execução

- Estratégia e ordem: `ROADMAP.md`
- Histórico técnico: `server/manual-de-instrucao.md`
- Documentos não prioritários: `archive_docs/`

---

## 15) Quality Gate obrigatório (sempre antes de concluir)

Executar o gate de qualidade do projeto:

- `./scripts/quality_gate.sh quick` para validação rápida durante desenvolvimento.
- `./scripts/quality_gate.sh full` para fechamento de item/sprint.

Um item só fecha após gate verde + validação manual do fluxo impactado.
