# Checklist Final de Go-Live

## Core e UX
- [ ] Fluxo `criar -> analisar -> otimizar` validado ponta a ponta
- [ ] Onboarding de 3 passos validado em sessão limpa
- [ ] Estado vazio guiado com CTA principal testado

## Segurança e operação
- [ ] `ENVIRONMENT=production` aplicado
- [ ] `JWT_SECRET` forte e rotacionável
- [ ] Rate limiting distribuído ativo
- [ ] Política de logs sem segredos confirmada

## IA e custo
- [ ] Limites por plano Free/Pro ativos
- [ ] Retorno de paywall (`402`) validado
- [ ] Telemetria de uso/custo por usuário validada (`/users/me/plan`)

## Dados e sincronização
- [ ] `sync_cards.dart` incremental diário ativo
- [ ] `sync_rules.dart` rotina periódica ativa
- [ ] `sync_prices.dart` rotina periódica ativa
- [ ] `sync_state` e `sync_log` com últimas execuções OK

## Performance e escala
- [ ] Índices críticos aplicados (migrações até 012)
- [ ] Cache de endpoints quentes validado (`/cards`, `/sets`)
- [ ] Teste de carga básico executado (`bin/load_test_core_flow.dart`)
- [ ] `CAPACITY_PLAN_10K_MAU.md` revisado

## Qualidade
- [ ] `./scripts/quality_gate.ps1 quick` verde
- [ ] `./scripts/quality_gate.ps1 full` verde
- [ ] Sem erros de analyze/lint relevantes
