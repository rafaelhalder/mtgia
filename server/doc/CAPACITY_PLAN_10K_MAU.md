# Capacity Plan — 10k MAU

## Objetivo
Preparar backend para 10k usuários ativos mensais com foco no fluxo core (`criar -> analisar -> otimizar`).

## Suposições operacionais
- 10k MAU
- 20% DAU (~2k)
- Pico concorrente: 120-180 req/min em horários de maior uso
- Endpoints mais quentes: `/cards`, `/sets`, `/decks/:id`, `/ai/optimize`

## Estratégia aplicada
1. Índices críticos adicionais
   - `cards(lower(set_code))`
   - `cards(lower(name), lower(set_code))`
   - `sets(release_date desc)`
   - `card_legalities(format, status)`
2. Cache curto nos endpoints quentes públicos
   - `/cards`: TTL 45s
   - `/sets`: TTL 60s
3. Guard rails de custo IA
   - Limites por plano no middleware de IA

## Teste de carga mínimo
Script: `server/bin/load_test_core_flow.dart`

Exemplo:

```bash
cd server
dart run bin/load_test_core_flow.dart --base-url=http://localhost:8080 --duration-sec=120 --concurrency=30
```

Métricas alvo iniciais:
- `p95 /cards` < 500ms
- `p95 /sets` < 300ms
- Erros < 1% em endpoints core

## Próximos passos de escala
- Mover cache em memória para Redis em ambiente multi-instância
- Dashboard de capacidade semanal com p95/p99 por endpoint
- Rotina de vacuum/analyze para tabelas de maior churn (`ai_logs`, `rate_limit_events`)
