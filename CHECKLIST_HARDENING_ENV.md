# Checklist de Hardening por Ambiente

Este checklist define o mínimo de segurança e operação por ambiente para o backend ManaLoom.

## Development

- [ ] `ENVIRONMENT=development`
- [ ] `JWT_SECRET` não reutilizado de produção
- [ ] `OPENAI_API_KEY` opcional (fallbacks habilitados quando ausente)
- [ ] `RATE_LIMIT_DISTRIBUTED` pode ficar `false` (ou `true` com DB local)
- [ ] Logs sem segredos (sanitização ativa)
- [ ] `./scripts/quality_gate.ps1 quick` antes de finalizar tarefa

## Staging

- [ ] `ENVIRONMENT=production` (com configs de staging)
- [ ] `JWT_SECRET` exclusivo de staging
- [ ] `OPENAI_API_KEY` com limite/cota de staging
- [ ] `RATE_LIMIT_DISTRIBUTED=true`
- [ ] Migrações atualizadas (`dart run bin/migrate.dart`)
- [ ] Readiness verde em `/health/ready`
- [ ] Dashboard operacional disponível em `/health/dashboard`
- [ ] Smoke: fluxo `criar -> analisar -> otimizar`
- [ ] `./scripts/quality_gate.ps1 full` verde

## Production

- [ ] `ENVIRONMENT=production`
- [ ] `JWT_SECRET` forte e rotacionado
- [ ] `OPENAI_API_KEY` de produção com monitoramento de custo
- [ ] `RATE_LIMIT_DISTRIBUTED=true`
- [ ] `TELEMETRY_ADMIN_*` restrito a usuários operacionais
- [ ] Retenção de telemetria ativa (`TELEMETRY_RETENTION_DAYS` + job de cleanup)
- [ ] Endpoints de saúde ativos:
  - [ ] `/health`
  - [ ] `/health/ready`
  - [ ] `/health/metrics`
  - [ ] `/health/dashboard`
- [ ] Alertas mínimos definidos:
  - [ ] erro endpoint core > limiar
  - [ ] latência p95 endpoint core > limiar
  - [ ] custo IA acima de limiar diário
- [ ] Plano de rollback documentado e testado

## Operação semanal

- [ ] Revisar dashboard (`/health/dashboard`)
- [ ] Revisar fallback de optimize (`/ai/optimize/telemetry`)
- [ ] Revisar custo IA (`ai_logs`)
- [ ] Revisar `quality_gate full` em branch principal
