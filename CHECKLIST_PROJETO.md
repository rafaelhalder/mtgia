# Checklist Geral do Projeto (Qualidade / UX / Performance / Regras)

Este documento serve como “fonte única” de tarefas para deixar o ManaLoom **pronto para usuários reais**.
Ele está organizado por áreas e inclui **critérios de aceite** para evitar regressões.

## Status Atual (resumo rápido)

- Backend: já tem sync de cartas/sets/regras + validação de Commander + endpoints incrementais.
- App: fluxo de deck funciona, com melhorias de “modo comandante” e validação manual (“Validar/Finalizar”).
- Infra: cron existente para sync de cartas; falta robustez (container name variável).

---

## 1) UX/UI (App) — Prioridade Alta

- [x] **Modo comandante na busca**: selecionar/trocar comandante via `/decks/:id/search?mode=commander`.
- [x] **Estado de loading no "Adicionar"**: desabilitar botão e mostrar progresso até confirmar.
  - Aceite: usuário vê feedback imediato; não dá "double tap".
- [x] **Otimização sem spam visual**: evitar textos "a IA está montando…" quando não necessário.
  - Aceite: UI comunica "processando" com componentes padrão (loader + status curto) e sem logs longos.
  - Implementado: Loader padrão com "Gerando sugestões..." + logs centralizados via AppLogger.
- [x] **Debounce na busca** (CardSearch): não disparar request a cada tecla.
  - Aceite: 1 request/300–500ms; melhora em redes lentas.
- [x] **Paginação/scroll infinito na busca**: hoje busca só 1 página.
  - Aceite: user consegue achar cartas comuns sem “sumir” resultados.
- [x] **Edição de deck mais clara**: mostrar `x/100` (Commander) e `x/60` (Brawl) com estados:
  - Aceite: "incompleto", "completo", "inválido" (por identidade, etc.).
  - Implementado: `DeckProgressIndicator` com barra de progresso e status visual.

## 2) Performance (App + Backend) — Prioridade Alta

- [x] **Adicionar carta sem PUT do deck inteiro** (`POST /decks/:id/cards`) para evitar `DELETE+reinsert`.
  - Aceite: tempo do botão “Adicionar” cai drasticamente (alvo < 1s em DO).
- [x] **Otimização do `GET /decks/:id`**: reduzir payload e/ou cache local.
  - Aceite: abrir detalhes rápido mesmo com 100 cartas (sem travar UI).
  - Implementado: Cache de 5 minutos no DeckProvider + invalidação automática após updates.
- [x] **Remover logs ruidosos em produção** (prints/debugPrint).
  - Aceite: logs apenas em `ENVIRONMENT=development` ou via logger configurável.

## 3) Regras (MTG) — Prioridade Alta

- [x] **Validação de Commander (MVP)**:
  - 1 comandante elegível (criatura lendária ou “can be your commander”)
  - identidade de cor (com base em `color_identity`)
  - limite máximo de cartas (não exceder 100/60)
- [x] **Validação estrita sob demanda**: `POST /decks/:id/validate` (exige 100/60 + comandante).
- [x] **Partner / Background / "Choose a Background"** (2 comandantes ou 1+background).
  - Aceite: regras do formato aplicadas e UI suportando seleção dupla.
  - Implementado: Suporte a Partner, Partner with X, Choose a Background, Friends Forever, Doctor's Companion.
- [x] **Color identity edge-cases** (hybrid, phyrexian, devoid, MDFC, etc.).
  - Aceite: testes cobrindo casos típicos e sem falsos positivos.
- [ ] **Mulligan / sideboard / companion**: decidir escopo (provavelmente fora do MVP).

## 4) IA (Configuração + Confiabilidade) — Prioridade Alta

- [x] **"IA segue regras" como política**: qualquer resultado da IA deve passar por validação do backend.
  - Aceite: `generate/optimize` chama validação e retorna erros legíveis, nunca “salva inválido”.
- [x] **Prompt com regras relevantes**: injetar regras do formato (Commander) e limitações do app.
  - Aceite: IA já sugere dentro da identidade de cor e do limite de cópias.
- [x] **Observabilidade**: salvar “prompt/resposta/tempo” (sem expor segredos) em tabela de logs.
  - Aceite: depurar recomendações fica possível.

## 5) Infra/Deploy — Prioridade Média

- [x] **Cron resiliente**: não depender do nome fixo do container.
  - Aceite: script encontra container atual (por label/serviço) e roda `sync_cards`.
  - Implementado: `cron_sync_cards.sh` com suporte a labels e logging.
- [x] **Secrets**: remover segredos do repo e rotacionar chaves expostas.
  - Aceite: `.env` só local; DO/Easypanel via variáveis; GitHub sem secrets em plaintext.
  - Verificado: `.env` não está no Git, `.env.example` bem documentado, nenhuma chave exposta no repo.
- [x] **Healthcheck + readiness**: endpoint e config no Easypanel.
  - Implementado: `/health/live` (liveness) e `/health/ready` (readiness com check de DB).

## 6) Banco / Migrações — Prioridade Média

- [x] **Padronizar migrations**: evitar "ALTER IF NOT EXISTS" espalhado em endpoints.
  - Aceite: 1 comando de migração por release + versionamento.
  - Implementado: `bin/migrate.dart` com tabela `schema_migrations` e versionamento.
- [x] **Indices críticos**:
  - `cards(name)`, `cards(color_identity GIN)`, `deck_cards(deck_id)`, `card_legalities(card_id,format)`.
  - Implementado: `migrate_add_critical_indexes.dart` com 8 índices + pg_trgm para busca fuzzy.

## 7) Testes — Prioridade Alta

- [x] `server/test/decks_incremental_add_test.dart`:
  - valida `POST /decks/:id/cards` e `POST /decks/:id/validate`
- [x] Testes de identidade de cor (vários casos) e de "trocar comandante".
  - Adicionados 13 testes cobrindo: híbrido, phyrexiano, devoid, MDFC, 5 cores, terrenos.
- [x] Testes de performance (smoke): medir tempo médio de add e detalhes do deck.
  - Implementado: `performance_smoke_test.dart` com métricas por endpoint.
- [x] App: criar pasta `app/test/` com smoke tests (mínimo) para rotas principais.

---

## ✅ Checklist Concluído!

**Resumo Final:**
- **Seção 1 (UX/UI)**: 6/6 ✅
- **Seção 2 (Performance)**: 3/3 ✅
- **Seção 3 (Regras MTG)**: 4/5 ✅ (Mulligan/sideboard fora do MVP)
- **Seção 4 (IA)**: 3/3 ✅
- **Seção 5 (Infra)**: 3/3 ✅
- **Seção 6 (Banco)**: 2/2 ✅
- **Seção 7 (Testes)**: 4/4 ✅

**Total: 25/26 tarefas concluídas** (1 fora do escopo MVP)

### Próximos Passos (Pós-MVP)

1. **Mulligan / Sideboard / Companion**: funcionalidades avançadas de gameplay.
2. **Simulador de batalha**: Monte Carlo para análise de consistência.
3. **Mais formatos**: Standard, Modern, Pioneer.
4. **App mobile**: publicação na Play Store / App Store.






