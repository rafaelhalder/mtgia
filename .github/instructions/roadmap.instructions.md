---
applyTo: '**'
---
# Roadmap Social & Trades — Contexto para Copilot

**Referência completa:** `ROADMAP_SOCIAL_TRADES.md` (1.340 linhas, ler quando for implementar uma task).

## Status de Features (atualizar conforme concluir)

### ✅ Pronto
- Decks públicos (listar, ver, copiar)
- Follow / Unfollow / Feed de seguidos
- Busca de usuários (username + display_name)
- Perfil público (3 tabs: Decks, Seguidores, Seguindo)
- Nick / Display Name editável (perfil)
- Toggle público/privado de deck (menu ⋮)
- Compartilhar deck (share nativo + export texto)
- CommunityScreen 3 tabs (Explorar / Seguindo / Usuários)

### ⏳ Épico 1 — Polir Existente (~1 dia)
- [ ] 1.1 Toggle `is_public` no dialog de criação de deck (server já aceita, só Flutter)
- [ ] 1.2 UI de avatar no perfil (TextField pra URL, `PATCH /users/me`)
- [ ] 1.3 Fix ALTER TABLE em runtime (`_middleware.dart` → flag estático `_schemaReady`)
- [ ] 1.4 Paginação em seguidores/seguindo (scroll infinito, hoje limitado a 50)

### ⏳ Épico 2 — Fichário / Binder (~3-4 dias)
- [ ] 2.1 DB: `user_binder_items` (quantity, condition NM/LP/MP/HP/DMG, is_foil, for_trade, for_sale, price, notes)
- [ ] 2.2 Server: CRUD `/binder` (GET list, POST add, PUT edit, DELETE, GET stats) — JWT obrigatório
- [ ] 2.3 Server: `GET /community/binders/:userId` (público, só for_trade/for_sale=true)
- [ ] 2.4 Server: `GET /community/marketplace` (busca global, filtros por carta/condição/tipo)
- [ ] 2.5 Flutter: `BinderProvider` (fetchMyBinder, add, update, remove, stats)
- [ ] 2.6 Flutter: Tela "Meu Fichário" (scroll infinito, filtros, busca)
- [ ] 2.7 Flutter: Modal editor de item do binder (quantity ±, condition chips, foil, trade/sale toggles, preço, notes)
- [ ] 2.8 Flutter: Aba "Fichário" no `UserProfileScreen` (4ª tab)
- [ ] 2.9 Flutter: Tela Marketplace (busca global, filtros, botão "Quero essa carta")

### ⏳ Épico 3 — Trades (~5-7 dias, depende do Épico 2)
- [ ] 3.1 DB: `trade_offers`, `trade_items`, `trade_messages`, `trade_status_history`
- [ ] 3.2 Server: `POST /trades` (criar proposta, validar ownership + disponibilidade)
- [ ] 3.3 Server: `GET /trades` (listar, filtro status/role/page)
- [ ] 3.4 Server: `GET /trades/:id` (detalhe completo + items + messages + history)
- [ ] 3.5 Server: `PUT /trades/:id/respond` (accept/decline, só receiver, só pending)
- [ ] 3.6 Server: `PUT /trades/:id/status` (shipped→delivered→completed, tracking_code)
- [ ] 3.7 Server: `POST /trades/:id/messages` + `GET` (chat no trade)
- [ ] 3.8 Server: Comprovante (MVP: URL externa, não upload binário)
- [ ] 3.9 Flutter: `TradeProvider` (fetchTrades, create, respond, updateStatus, messages)
- [ ] 3.10 Flutter: Tela criar proposta (items meus ↔ items dele, tipo, valor, mensagem)
- [ ] 3.11 Flutter: Trade inbox (tabs Recebidas/Enviadas/Finalizadas, cores por status)
- [ ] 3.12 Flutter: Trade detail (timeline + chat + ações dinâmicas por status)

**Fluxo de status:** pending → accepted → shipped → delivered → completed (ou declined/cancelled/disputed)

### ⏳ Épico 4 — Mensagens Diretas (~3-4 dias, paralelo ao 3)
- [ ] 4.1 DB: `conversations` (UNIQUE par de users) + `direct_messages` (read_at)
- [ ] 4.2 Server: GET/POST `/conversations`, GET/POST messages, PUT read
- [ ] 4.3 Flutter: Inbox de mensagens (avatar, preview, badge não-lidas)
- [ ] 4.4 Flutter: Tela chat (bolhas, scroll infinito, polling 5s)
- [ ] 4.5 Flutter: Botão "Mensagem" no perfil público

### ⏳ Épico 5 — Notificações (~2-3 dias, incremental)
- [ ] 5.1 DB: `notifications` (type, reference_id, title, body, read_at)
- [ ] 5.2 Server: GET list, GET count, PUT read, PUT read-all
- [ ] 5.3 Server: Criar notificações automaticamente nos handlers (follow, trade, message)
- [ ] 5.4 Flutter: Ícone sino + badge no AppBar
- [ ] 5.5 Flutter: Tela de notificações (tap navega pro contexto)

## Ordem de Execução
```
Épico 1 → Épico 2 → Épico 3 → Épico 4 (paralelo com 3) → Épico 5
```

## Regra de Implementação
Ao implementar qualquer task deste roadmap:
1. **Ler** a seção correspondente em `ROADMAP_SOCIAL_TRADES.md` para SQL exato, formato de resposta e wireframe
2. **Implementar** seguindo os padrões do `guia.instructions.md`
3. **Documentar** no `server/manual-de-instrucao.md`
4. **Marcar** `[x]` neste arquivo E no `ROADMAP_SOCIAL_TRADES.md`

## Providers Existentes (registrar novos no MultiProvider em main.dart)
1. AuthProvider
2. DeckProvider
3. CardProvider
4. MarketProvider
5. CommunityProvider
6. SocialProvider
7. BinderProvider ← NOVO (Épico 2)
8. TradeProvider ← NOVO (Épico 3)

## Palette ManaLoom (usar em todas as telas novas)
- backgroundAbyss: `#0A0E14`
- surfaceSlate: `#1E293B` / surfaceSlate2: `#0F172A`
- manaViolet: `#8B5CF6`
- loomCyan: `#06B6D4`
- mythicGold: `#F59E0B`
- textPrimary: `#F1F5F9` / textSecondary: `#94A3B8`
- outlineMuted: `#334155`

## Navegação (5 tabs, ShellRoute GoRouter)
Início | Decks | Comunidade | Market | Perfil

## Tabelas DB Novas (schemas completos no ROADMAP_SOCIAL_TRADES.md)
- `user_binder_items` — Épico 2
- `trade_offers` — Épico 3
- `trade_items` — Épico 3
- `trade_messages` — Épico 3
- `trade_status_history` — Épico 3
- `conversations` — Épico 4
- `direct_messages` — Épico 4
- `notifications` — Épico 5
