# 📋 ManaLoom — Tasks de Finalização

> Gerado em: 11/02/2026  
> Atualizado: 11/02/2026  
> Base: Audit completo de 50+ endpoints (todos ✅ 200), 10 providers, 22+ telas, 21 rotas, 25 testes E2E

---

## ✅ CONCLUÍDAS

### ~~TASK-01: Badge de mensagens não-lidas no AppBar~~
**Status:** ✅ COMPLETO  
**Arquivos modificados:**
- `app/lib/features/messages/providers/message_provider.dart` — `startPolling()`, `stopPolling()`, `fetchUnreadCount()`
- `app/lib/core/widgets/main_scaffold.dart` — `Selector<MessageProvider, int>` + Badge
- `app/lib/main.dart` — Start/stop polling on auth change

---

### ~~TASK-02: Fallback no endpoint `/decks/:id/recommendations`~~
**Status:** ✅ COMPLETO (já estava implementado)  
O endpoint já tinha fallback inteligente de 513 linhas que:
- Analisa deck real do banco (não mock genérico)
- Detecta gaps funcionais (ramp, draw, removal, wipes, protection)
- Busca cartas reais do DB nas cores do deck

---

### ~~TASK-03: Paginação scroll infinito no Trade Inbox~~
**Status:** ✅ COMPLETO  
**Arquivos modificados:**
- `app/lib/features/trades/providers/trade_provider.dart` — `fetchMoreTrades()` com append
- `app/lib/features/trades/screens/trade_inbox_screen.dart` — `_onScroll()` chama `fetchMoreTrades` por tab

---

### ~~TASK-04: Auto-refresh no Message Inbox~~
**Status:** ✅ COMPLETO (coberto por TASK-01)  
O polling de 30s do MessageProvider atualiza o badge e as conversations automaticamente.

---

### ~~TASK-05: Push Notifications (Firebase Cloud Messaging)~~
**Status:** ✅ CÓDIGO COMPLETO (aguarda configuração Firebase)  
**Arquivos criados/modificados:**
- `server/routes/_middleware.dart` — ALTER TABLE users ADD fcm_token
- `server/routes/users/me/fcm-token/index.dart` — PUT/DELETE FCM token
- `server/lib/push_notification_service.dart` — Envia push via FCM HTTP API
- `server/lib/notification_service.dart` — Integrado com push
- `app/pubspec.yaml` — firebase_core + firebase_messaging
- `app/lib/core/services/push_notification_service.dart` — Init, permission, token
- `app/lib/main.dart` — Init Firebase, register/unregister on auth

**Para ativar:**
1. Criar projeto Firebase Console
2. Baixar `google-services.json` → `app/android/app/`
3. Baixar `GoogleService-Info.plist` → `app/ios/Runner/`
4. Configurar `FCM_SERVER_KEY` no server `.env`

---

### ~~TASK-06: Melhorar Scanner OCR (accuracy)~~
**Status:** ✅ JÁ ESTAVA COMPLETO  
Scanner já tem 1.196 linhas com:
- 5 estratégias de crop
- Fuzzy matching Levenshtein
- Variações de erro OCR
- Multi-step search

---

### ~~TASK-07: Pipeline de ML Training~~
**Status:** ✅ COMPLETO  
**Arquivos criados:**
- `server/bin/ml_extract_features.dart` — Extrai features de decks + simulações → CSV
- `server/bin/ml_train_model.py` — Treina RandomForest/GradientBoosting/XGBoost

**Uso:**
```bash
# Extrair features
cd server && dart run bin/ml_extract_features.dart

# Treinar modelo
python3 server/bin/ml_train_model.py
```

---

### ~~TASK-08: Simulação turno-a-turno real~~
**Status:** ✅ COMPLETO  
**Arquivos criados/modificados:**
- `server/lib/ai/battle_simulator.dart` — Motor de simulação 700+ linhas
  - Fases do turno (untap, upkeep, draw, main, combat, end)
  - Sistema de combate com P/T, first strike, deathtouch, trample, lifelink
  - IA decisória: quando atacar, bloquear, jogar removal, wipes
  - Game log detalhado para ML training
- `server/routes/ai/simulate/index.dart` — Novo type "battle"

**Uso:**
```bash
curl -X POST https://api/ai/simulate \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"deck_id": "...", "opponent_deck_id": "...", "type": "battle"}'
```

---

## ✅ Features Completas (referência)

| # | Feature | Server | Flutter | Testes |
|---|---------|:------:|:-------:|:------:|
| 1 | Auth (register/login/me/JWT) | ✅ | ✅ | ✅ |
| 2 | Decks CRUD + validação formato | ✅ | ✅ | ✅ |
| 3 | Cards (busca, printings, sync Scryfall) | ✅ | ✅ | ✅ |
| 4 | Seletor de Edição (multi-edition) | ✅ | ✅ | ✅ |
| 5 | Notificações (polling 30s, badge, navegação) | ✅ | ✅ | ✅ |
| 6 | Binder/Fichário (CRUD, Have/Want, conditions) | ✅ | ✅ | ✅ |
| 7 | Trades (criar/aceitar/recusar/shipped/chat) | ✅ | ✅ | ✅ |
| 8 | Mensagens DM (inbox, chat, bolhas, badge) | ✅ | ✅ | ✅ |
| 9 | Comunidade (decks públicos, follow, feed) | ✅ | ✅ | ✅ |
| 10 | Marketplace (busca global trade/sale) | ✅ | ✅ | ✅ |
| 11 | IA: Gerar Deck (prompt→deck) | ✅ | ✅ | ✅ |
| 12 | IA: Otimizar Deck | ✅ | ✅ | ✅ |
| 13 | IA: Explicar Carta | ✅ | ✅ | ✅ |
| 14 | IA: Archetypes | ✅ | ✅ | ✅ |
| 15 | IA: Sinergia (score, strengths, weaknesses) | ✅ | ✅ | ✅ |
| 16 | IA: Recomendações inteligentes | ✅ | ✅ | ✅ |
| 17 | Importação texto→deck | ✅ | ✅ | ✅ |
| 18 | Scanner OCR (câmera + fuzzy match) | — | ✅ | — |
| 19 | Simulador Goldfish (Monte Carlo 1000) | ✅ | ✅ | ✅ |
| 20 | Simulador Matchup (archetype counters) | ✅ | ✅ | ✅ |
| 21 | **Simulador Battle (turno-a-turno)** | ✅ | — | — |
| 22 | Market Movers (preços, tendências) | ✅ | ✅ | ✅ |
| 23 | Perfil (avatar, display name) | ✅ | ✅ | ✅ |
| 24 | Sets / Rules | ✅ | ✅ | ✅ |
| 25 | Sync Preços (MTGJSON cron) | ✅ | — | — |
| 26 | Sync Cartas (incremental/full) | ✅ | — | — |
| 27 | **Push Notifications (FCM)** | ✅ | ✅ | — |
| 28 | **ML Feature Extraction** | ✅ | — | — |
| 29 | **ML Training Pipeline (Python)** | ✅ | — | — |

**Infraestrutura:**
- 🖥️ Produção: Docker Swarm on EasyPanel (`evolution-cartinhas.8ktevp.easypanel.host`)
- 📊 ~55 endpoints ativos | 75 route files
- 🧪 25 testes E2E (14 general + 11 trade)
- 📱 10 Providers | 21 Rotas GoRouter | 5 tabs bottom nav
- 🔔 Push: FCM ready (aguarda google-services.json)
- 🤖 ML: Feature extraction + Python training pipeline

---

## 📅 Próximos Passos (Roadmap Futuro)

1. **Configurar Firebase** — Criar projeto, baixar configs, testar push
2. **Gerar dados de treino** — Rodar simulações em lote para popular battle_simulations
3. **Treinar modelo ML** — Usar pipeline Python para prever consistência
4. **Endpoint `/ai/predict-winrate`** — Expor modelo treinado via API
5. **UI Simulador Battle** — Tela Flutter para ver replay turno-a-turno
