# CHECKLIST DE EXECUÇÃO DIÁRIA — ManaLoom

Use este checklist todos os dias para executar com qualidade e sem perder contexto.

## 1) Início do dia (5 minutos)

- [ ] Ler o objetivo ativo no `ROADMAP.md` (sprint atual).
- [ ] Confirmar 1 item principal do dia (máx. 1 foco).
- [ ] Confirmar critério de aceite do item.
- [ ] Confirmar plano de teste do item.

## 2) Antes de codar

- [ ] Escopo fechado: o que entra e o que não entra.
- [ ] Arquivos afetados mapeados.
- [ ] Dependências críticas verificadas (API, DB, env, contrato).

Se faltar dependência crítica: **bloquear e replanejar**.

## 3) Durante implementação

- [ ] Executar apenas o menor incremento correto.
- [ ] Evitar refactors fora do escopo.
- [ ] Manter contrato de API estável.
- [ ] Rodar validação contínua: `./scripts/quality_gate.sh quick`.

## 4) Antes de concluir item

- [ ] Rodar: `./scripts/quality_gate.sh full`.
- [ ] Validar manualmente o fluxo impactado (happy path + erro principal).
- [ ] Confirmar que não houve regressão no fluxo core (`criar -> analisar -> otimizar`).
- [ ] Atualizar `server/manual-de-instrucao.md` com o que mudou.

## 5) Definição de pronto (DoD)

Marcar como concluído apenas se todos forem verdadeiros:
- [ ] Critério de aceite cumprido.
- [ ] Testes executados e resultado registrado.
- [ ] Documentação técnica atualizada.
- [ ] Impacto em produto/métrica explicitado.

## 6) Encerramento do dia

- [ ] Registrar progresso real (feito / pendente / bloqueio).
- [ ] Registrar próximo passo objetivo para o dia seguinte.
- [ ] Se houver bloqueio, registrar causa em 1 linha + ação proposta.

## 7) Regra de foco

Antes de iniciar qualquer nova tarefa, responder:

1. Isso melhora o fluxo core?
2. Isso reduz risco técnico crítico?
3. Isso aumenta valor percebido de forma mensurável?

Se as 3 respostas forem “não”, a tarefa vai para backlog.

## 8) Comandos rápidos

- Validação rápida: `./scripts/quality_gate.sh quick`
- Validação completa: `./scripts/quality_gate.sh full`
- API local (backend): `cd server && dart_frog dev`

---

Referências ativas:
- Estratégia e ordem: `ROADMAP.md`
- Histórico técnico: `server/manual-de-instrucao.md`
- Documentos não prioritários: `archive_docs/`
