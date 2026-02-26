# 🗺️ ROADMAP — Social, Fichário & Trades

**Projeto:** ManaLoom — AI-Powered MTG Deck Builder  
**Documento:** Guia passo-a-passo de implementação  
**Criado em:** 09 de Fevereiro de 2026  
**Regra:** Este é o documento ÚNICO de referência para todo o fluxo social/trades. Toda task deve ser marcada aqui conforme concluída.

---

## 📐 Visão Geral da Arquitetura

```
┌──────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                              │
│                                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐│
│  │  Início  │ │  Decks   │ │Comunidade│ │ Market   │ │ Perfil ││
│  └──────────┘ └──────────┘ └────┬─────┘ └──────────┘ └───┬────┘│
│                                 │                         │      │
│                    ┌────────────┼──────────┐              │      │
│                    ▼            ▼          ▼              ▼      │
│              ┌──────────┐ ┌────────┐ ┌────────┐   ┌──────────┐  │
│              │Explorar  │ │Seguindo│ │Usuários│   │Meu Perfil│  │
│              │(decks)   │ │(feed)  │ │(busca) │   │+ Fichário│  │
│              └──────────┘ └────────┘ └───┬────┘   └──────────┘  │
│                                          │                       │
│                                          ▼                       │
│                                   ┌────────────┐                 │
│                                   │Perfil User │                 │
│                                   │ Decks      │                 │
│                                   │ Fichário   │◄─── NOVO       │
│                                   │ Seguidores │                 │
│                                   └─────┬──────┘                 │
│                                         │                        │
│                              ┌──────────┼──────────┐             │
│                              ▼          ▼          ▼             │
│                        ┌──────────┐ ┌────────┐ ┌──────────┐     │
│                        │ Proposta │ │  Chat  │ │ Inbox    │     │
│                        │ de Trade │ │ Trade  │ │ Trades   │     │
│                        └──────────┘ └────────┘ └──────────┘     │
│                              ◄──── TUDO NOVO ────►               │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                       DART FROG SERVER                           │
│                                                                  │
│  Existente:                    Novo:                             │
│  ├── /auth/*                   ├── /binder/*           ◄ CRUD   │
│  ├── /decks/*                  ├── /community/binders/* ◄ Público│
│  ├── /cards/*                  ├── /trades/*            ◄ Negoc. │
│  ├── /community/decks/*        ├── /conversations/*     ◄ Chat  │
│  ├── /community/users/*        └── /notifications/*     ◄ Avisos│
│  ├── /users/*/follow/*                                           │
│  ├── /ai/*                                                       │
│  ├── /market/*                                                   │
│  └── /import/*                                                   │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                       POSTGRESQL                                 │
│                                                                  │
│  Existente:                    Novo:                             │
│  users, cards, sets,           user_binder_items,                │
│  card_legalities, rules,       trade_offers,                     │
│  decks, deck_cards,            trade_items,                      │
│  deck_matchups,                trade_messages,                   │
│  battle_simulations,           trade_status_history,             │
│  meta_decks, format_staples,   conversations,                   │
│  sync_log, sync_state,         direct_messages,                  │
│  archetype_counters,           notifications                     │
│  deck_weakness_reports,                                          │
│  ai_logs, user_follows                                           │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📊 Status Atual (Auditoria)

### ✅ Já Implementado e Funcionando

| Feature | Server | Flutter | DB |
|---------|--------|---------|-----|
| Listar/buscar decks públicos | ✅ | ✅ (aba Explorar) | ✅ |
| Ver detalhes de deck público | ✅ | ✅ | ✅ |
| Copiar deck público | ✅ | ✅ | ✅ |
| Follow / Unfollow | ✅ | ✅ | ✅ `user_follows` |
| Feed de seguidos | ✅ | ✅ (aba Seguindo) | ✅ |
| Busca de usuários | ✅ | ✅ (aba Usuários) | ✅ |
| Perfil público (decks + seguidores) | ✅ | ✅ | ✅ |
| Nick / Display Name editável | ✅ | ✅ (Perfil) | ✅ `display_name` |
| Toggle público/privado de deck | ✅ | ✅ (menu ⋮) | ✅ `is_public` |
| Compartilhar deck (share nativo) | ✅ | ✅ | — |
| Exportar deck como texto | ✅ | ✅ | — |

### ❌ Não Existe (Greenfield)

| Feature | Server | Flutter | DB |
|---------|--------|---------|-----|
| Fichário (binder/coleção) | ❌ | ❌ | ❌ |
| Busca de cartas pra troca/venda | ❌ | ❌ | ❌ |
| Propostas de trade | ❌ | ❌ | ❌ |
| Chat dentro do trade | ❌ | ❌ | ❌ |
| Status de entrega / comprovantes | ❌ | ❌ | ❌ |
| Histórico de trades | ❌ | ❌ | ❌ |
| Mensagens diretas | ❌ | ❌ | ❌ |
| Notificações | ❌ | ❌ | ❌ |

### ⚠️ Ajustes Pendentes no Existente

| Item | Detalhe |
|------|---------|
| Toggle público na criação de deck | Hoje só dá pra mudar no menu ⋮ depois de criado |
| UI de avatar no perfil | Server aceita `avatar_url`, mas não tem UI pra mudar |
| ALTER TABLE em runtime | `_middleware.dart` faz ALTER em cada request (mover pra migration) |
| Paginação em seguidores/seguindo | Limitado a 50 sem "load more" |

---

## 🔢 Ordem de Execução

```
ÉPICO 1          ÉPICO 2          ÉPICO 3          ÉPICO 4         ÉPICO 5
Polir            Fichário         Trades           Chat            Notificações
Existente        (Binder)         (Negociação)     Direto          
~1 dia           ~3-4 dias        ~5-7 dias        ~3-4 dias       ~2-3 dias
                      │                │                │               │
                      ▼                ▼                ▼               ▼
                 Épico 3 depende  Épico 4 pode      Épico 5 pode ser
                 do Épico 2       rodar em paralelo adicionado
                 (trades usam     com Épico 3       incrementalmente
                 itens do binder)
```

---

---

# ÉPICO 1 — Validar & Polir o Existente

> **Objetivo:** Garantir que tudo que já foi feito funciona end-to-end antes de construir em cima.  
> **Estimativa:** ~1 dia

---

## Task 1.1 — Toggle público/privado na criação de deck

**Problema:** Hoje o usuário cria o deck (sempre privado) e só depois consegue tornar público pelo menu ⋮. Deveria poder escolher na criação.

**O que fazer:**

### Server (nenhuma mudança)
O endpoint `POST /decks` já aceita `is_public` no body. Nada a fazer.

### Flutter
**Arquivo:** `app/lib/features/decks/screens/deck_list_screen.dart`

No dialog de criação de deck (onde tem campos `name` e `format`), adicionar:
```dart
// Estado local no dialog
bool _isPublic = false;

// Widget dentro do dialog, após o campo de formato:
SwitchListTile(
  title: const Text('Deck público'),
  subtitle: const Text('Visível na comunidade'),
  value: _isPublic,
  onChanged: (v) => setState(() => _isPublic = v),
  activeColor: AppTheme.loomCyan,
)
```

Ao chamar `DeckProvider.createDeck(...)`, enviar `isPublic: _isPublic`.

**Arquivo:** `app/lib/features/decks/providers/deck_provider.dart`

Verificar se `createDeck()` já envia `is_public` no body. Se não, adicionar o parâmetro.

### Validação
- [ ] Criar deck com toggle público ON → verificar que aparece na comunidade
- [ ] Criar deck com toggle OFF → verificar que NÃO aparece
- [ ] Mudar toggle depois no menu ⋮ → verificar que funciona

---

## Task 1.2 — UI de avatar no perfil

**Problema:** O server aceita `avatar_url` via `PATCH /users/me`, mas o perfil só mostra o avatar, não permite alterá-lo.

**O que fazer:**

### Flutter
**Arquivo:** `app/lib/features/profile/profile_screen.dart`

Abaixo do `CircleAvatar`, adicionar botão de editar:
```dart
TextButton.icon(
  icon: Icon(Icons.camera_alt, size: 16),
  label: Text('Alterar foto'),
  onPressed: _pickAvatar,
)
```

Opção A (simples — URL manual): Dialog com TextField para colar URL de imagem.  
Opção B (ideal — upload): Usar `image_picker` para selecionar foto → fazer upload para storage (Supabase/S3) → salvar URL.

**Para o MVP:** implementar Opção A (URL manual) e evoluir depois.

### Validação
- [ ] Colar URL de avatar → salvar → ver avatar atualizado
- [ ] Avatar aparece no perfil público quando outro user acessa

---

## Task 1.3 — Remover ALTER TABLE em runtime

**Problema:** `server/routes/_middleware.dart` executa `ALTER TABLE` e `CREATE TABLE IF NOT EXISTS` em CADA request. Isso deveria rodar apenas uma vez (startup ou migration).

**O que fazer:**

### Server
**Arquivo:** `server/routes/_middleware.dart`

Mover a lógica de `_ensureRuntimeSchema()` para um script de migration dedicado (ex: `bin/migrate.dart`) ou garantir que execute apenas UMA VEZ (usar um flag estático `bool _schemaReady = false`).

```dart
static bool _schemaReady = false;

Future<void> _ensureRuntimeSchema(Pool pool) async {
  if (_schemaReady) return;
  // ... ALTER TABLE statements ...
  _schemaReady = true;
}
```

### Validação
- [ ] Server inicia sem erros
- [ ] Schema é criado/atualizado apenas uma vez
- [ ] Requests subsequentes não executam DDL

---

## Task 1.4 — Paginação em seguidores/seguindo

**Problema:** `SocialProvider` carrega seguidores/seguindo com `limit=50` fixo sem "load more".

**O que fazer:**

### Flutter
**Arquivo:** `app/lib/features/social/providers/social_provider.dart`

Adicionar lógica de paginação similar a `fetchFollowingFeed()`:
- Variáveis `_followersPage`, `_hasMoreFollowers`
- No `fetchFollowers()`: incrementar página e append à lista
- No `fetchFollowing()`: mesma coisa

**Arquivo:** `app/lib/features/social/screens/user_profile_screen.dart`

Na `_UsersListTab`, adicionar `ScrollController` com listener de scroll infinito.

### Validação
- [ ] Seguir mais de 50 users → verificar que carrega mais ao scrollar
- [ ] Pull to refresh funciona

---

---

# ÉPICO 2 — Fichário (Binder / Coleção)

> **Objetivo:** Cada jogador tem um fichário digital com as cartas que possui. Pode marcar cartas como disponíveis para troca e/ou venda, definir condição e preço.  
> **Estimativa:** ~3-4 dias  
> **Dependência:** Nenhuma (pode começar direto)

---

## Task 2.1 — Banco de dados: tabela `user_binder_items`

**O que criar:**

```sql
-- ============================================================
-- BINDER: Fichário pessoal de cartas
-- ============================================================
CREATE TABLE IF NOT EXISTS user_binder_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id UUID NOT NULL REFERENCES cards(id) ON DELETE CASCADE,

    -- Quantidade e condição
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    condition TEXT NOT NULL DEFAULT 'NM'
        CHECK (condition IN ('NM', 'LP', 'MP', 'HP', 'DMG')),
    is_foil BOOLEAN DEFAULT FALSE,

    -- Disponibilidade
    for_trade BOOLEAN DEFAULT FALSE,   -- Disponível para troca
    for_sale BOOLEAN DEFAULT FALSE,    -- Disponível para venda
    price DECIMAL(10,2),               -- Preço pedido (null = só troca)
    currency TEXT DEFAULT 'BRL',       -- BRL ou USD

    -- Extras
    notes TEXT,                        -- "Aceito trocar por fetchlands"
    language TEXT DEFAULT 'en',        -- Idioma da carta física

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Evita duplicata exata (mesma carta, mesma condição, mesmo foil)
    UNIQUE(user_id, card_id, condition, is_foil)
);

CREATE INDEX IF NOT EXISTS idx_binder_user ON user_binder_items (user_id);
CREATE INDEX IF NOT EXISTS idx_binder_card ON user_binder_items (card_id);
CREATE INDEX IF NOT EXISTS idx_binder_for_trade ON user_binder_items (for_trade) WHERE for_trade = TRUE;
CREATE INDEX IF NOT EXISTS idx_binder_for_sale ON user_binder_items (for_sale) WHERE for_sale = TRUE;
```

**Onde:** Adicionar ao final de `server/database_setup.sql` e criar migration `bin/migrate_binder.dart`.

### Validação
- [ ] Rodar `database_setup.sql` sem erros
- [ ] Rodar migration em banco existente sem conflitos
- [ ] Verificar constraints: quantity > 0, condition válido

---

## Task 2.2 — Server: CRUD do Binder (rotas autenticadas)

**Endpoints a criar:**

| Método | Rota | Body / Query | Resposta |
|--------|------|-------------|----------|
| `GET` | `/binder` | `?page=1&limit=20&condition=NM&for_trade=true&for_sale=true` | Lista paginada dos itens do binder do user autenticado |
| `POST` | `/binder` | `{ card_id, quantity, condition, is_foil, for_trade, for_sale, price?, notes?, language? }` | Item criado (201) |
| `PUT` | `/binder/:id` | `{ quantity?, condition?, for_trade?, for_sale?, price?, notes? }` | Item atualizado |
| `DELETE` | `/binder/:id` | — | 204 No Content |
| `GET` | `/binder/stats` | — | `{ total_items, for_trade_count, for_sale_count, estimated_value }` |

**Estrutura de arquivos:**
```
server/routes/binder/
├── _middleware.dart       → authMiddleware()
├── index.dart             → GET (listar) + POST (adicionar)
├── stats/
│   └── index.dart         → GET /binder/stats
└── [id]/
    └── index.dart         → PUT (editar) + DELETE (remover)
```

**Regras de negócio:**
- `POST /binder`: verificar que `card_id` existe na tabela `cards`. Se já existe item com mesma `(card_id, condition, is_foil)`, retornar 409 Conflict com sugestão de usar PUT.
- `PUT /binder/:id`: verificar ownership (o item pertence ao user autenticado).
- `DELETE /binder/:id`: verificar ownership. Se o item está em algum trade ativo, retornar 409.
- `GET /binder`: sempre filtrar por `user_id` do JWT. Retornar JOIN com `cards` para incluir `name`, `image_url`, `set_code`.

**Formato de resposta:**
```json
{
  "data": [
    {
      "id": "uuid",
      "card": {
        "id": "uuid",
        "name": "Sol Ring",
        "image_url": "https://...",
        "set_code": "c21",
        "mana_cost": "{1}"
      },
      "quantity": 2,
      "condition": "NM",
      "is_foil": false,
      "for_trade": true,
      "for_sale": false,
      "price": null,
      "notes": "Aceito Mana Crypt",
      "language": "en"
    }
  ],
  "page": 1,
  "limit": 20,
  "total": 47
}
```

### Validação
- [ ] POST → adicionar carta ao binder → GET retorna ela
- [ ] POST duplicado → 409 Conflict
- [ ] PUT → alterar `for_trade` → GET reflete mudança
- [ ] DELETE → item some da lista
- [ ] GET com filtros → retorna só os filtrados
- [ ] Tentar acessar item de outro user → 403

---

## Task 2.3 — Server: Binder público de um usuário

**Endpoint:**

| Método | Rota | Query | Resposta |
|--------|------|-------|----------|
| `GET` | `/community/binders/:userId` | `?page=1&limit=20&for_trade=true&for_sale=true` | Cartas disponíveis do user (só as marcadas `for_trade` ou `for_sale`) |

**Arquivo:** `server/routes/community/binders/[userId].dart`

**Sem auth obrigatório** (é público). Mas se o caller estiver autenticado, incluir campo `is_own_binder: true/false` (útil pra esconder botão "Quero essa carta" no próprio binder).

**Regras:**
- Só retornar itens com `for_trade = TRUE` ou `for_sale = TRUE`.
- JOIN com `cards` para retornar nome, imagem, set.
- JOIN com `users` para retornar `username`, `display_name`, `avatar_url` do dono.

### Validação
- [ ] Acessar binder público de user que tem cartas marcadas → retorna lista
- [ ] User sem cartas marcadas → retorna lista vazia
- [ ] Cartas NÃO marcadas (for_trade=false, for_sale=false) → NÃO aparecem

---

## Task 2.4 — Server: Busca global no marketplace de cartas

**Endpoint:**

| Método | Rota | Query | Resposta |
|--------|------|-------|----------|
| `GET` | `/community/marketplace` | `?card_name=Sol Ring&condition=NM&for_trade=true&for_sale=true&page=1&limit=20` | Todos os itens de binder disponíveis de TODOS os users |

**Arquivo:** `server/routes/community/marketplace/index.dart`

**Sem auth obrigatório.**

**Query:**
```sql
SELECT bi.*, c.name, c.image_url, c.set_code, c.mana_cost,
       u.id as owner_id, u.username, u.display_name, u.avatar_url
FROM user_binder_items bi
JOIN cards c ON c.id = bi.card_id
JOIN users u ON u.id = bi.user_id
WHERE (bi.for_trade = TRUE OR bi.for_sale = TRUE)
  AND ($card_name IS NULL OR LOWER(c.name) LIKE LOWER('%' || $card_name || '%'))
  AND ($condition IS NULL OR bi.condition = $condition)
ORDER BY c.name, bi.price ASC NULLS LAST
LIMIT $limit OFFSET $offset
```

**Formato de resposta:**
```json
{
  "data": [
    {
      "binder_item_id": "uuid",
      "card": { "id": "uuid", "name": "Sol Ring", "image_url": "...", "set_code": "c21" },
      "owner": { "id": "uuid", "username": "mage42", "display_name": "Rafael", "avatar_url": null },
      "quantity": 2,
      "condition": "NM",
      "is_foil": false,
      "for_trade": true,
      "for_sale": true,
      "price": 15.50,
      "currency": "BRL",
      "notes": "Aceito Mana Crypt"
    }
  ],
  "page": 1,
  "limit": 20,
  "total": 134
}
```

### Validação
- [ ] Buscar "Sol Ring" → retorna todos os binder items disponíveis de todos os users
- [ ] Filtrar por `for_trade=true` → só trocas
- [ ] Filtrar por `condition=NM` → só NM
- [ ] Resultado inclui dados do owner (avatar, nick)

---

## Task 2.5 — Flutter: Provider do Binder

**Arquivo a criar:** `app/lib/features/binder/providers/binder_provider.dart`

**Modelo:** `BinderItem`
```dart
class BinderItem {
  final String id;
  final String cardId;
  final String cardName;
  final String? cardImageUrl;
  final String? setCode;
  final String? manaCost;
  final int quantity;
  final String condition; // NM, LP, MP, HP, DMG
  final bool isFoil;
  final bool forTrade;
  final bool forSale;
  final double? price;
  final String currency;
  final String? notes;
  final String language;
}
```

**Métodos do provider:**
- `fetchMyBinder({page, condition, forTrade, forSale, reset})` — lista paginada
- `addToBinder(cardId, quantity, condition, isFoil, forTrade, forSale, price, notes)` — POST
- `updateBinderItem(id, {quantity, condition, forTrade, forSale, price, notes})` — PUT
- `removeFromBinder(id)` — DELETE
- `fetchBinderStats()` — GET /binder/stats

**Registrar em `main.dart`** no `MultiProvider`.

### Validação
- [ ] Provider compila sem erros
- [ ] Registrado no MultiProvider

---

## Task 2.6 — Flutter: Tela "Meu Fichário"

**Arquivo a criar:** `app/lib/features/binder/screens/binder_screen.dart`

**Acesso:** A partir da tela de Perfil (botão "📒 Meu Fichário") OU como sub-rota `/profile/binder`.

**Layout:**
```
┌─────────────────────────────────────┐
│ ◄  Meu Fichário         [+ Adicionar]│
├─────────────────────────────────────┤
│ 🔍 Buscar nas minhas cartas...      │
├─────────────────────────────────────┤
│ [Todas] [Pra Troca] [Pra Venda]    │  ← FilterChips
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ 🃏 Sol Ring (C21)       NM  x2  │ │
│ │ 🔄 Disponível p/ troca         │ │
│ │ Aceito Mana Crypt              │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ 🃏 Mana Crypt (2XM)    LP  x1  │ │
│ │ 💰 R$ 450,00 (venda)           │ │
│ └─────────────────────────────────┘ │
│ ...                                 │
└─────────────────────────────────────┘
```

**Funcionalidades:**
- Lista com scroll infinito (paginado via `BinderProvider`)
- Filtros: Todas / Pra Troca / Pra Venda
- Busca local por nome
- Tap em item → abre modal de edição (Task 2.7)
- Botão "+" → abre busca de cartas (reutilizar `CardSearchScreen` com `mode=binder`)
- Swipe left pra deletar (com confirmação)

### Validação
- [ ] Tela carrega lista do binder
- [ ] Filtros funcionam
- [ ] Scroll infinito carrega mais
- [ ] Botão "+" abre busca de cartas

---

## Task 2.7 — Flutter: Modal de editar item do binder

**Arquivo a criar:** `app/lib/features/binder/widgets/binder_item_editor.dart`

**Layout (BottomSheet):**
```
┌─────────────────────────────────────┐
│ Sol Ring (C21)                       │
│ ┌───────────────────────────────┐   │
│ │ Quantidade:  [-]  2  [+]     │   │
│ └───────────────────────────────┘   │
│ ┌───────────────────────────────┐   │
│ │ Condição: [NM] LP  MP  HP DMG│   │
│ └───────────────────────────────┘   │
│ ☐ Foil                              │
│ ─────────────────────────────────   │
│ ☑ Disponível para troca             │
│ ☑ Disponível para venda             │
│ ┌───────────────────────────────┐   │
│ │ Preço: R$ [________]         │   │
│ └───────────────────────────────┘   │
│ ┌───────────────────────────────┐   │
│ │ Observações: [______________]│   │
│ │ ex: "Aceito fetchlands"      │   │
│ └───────────────────────────────┘   │
│                                     │
│ [      💾 Salvar       ]            │
│ [  🗑️ Remover do fichário  ]        │
└─────────────────────────────────────┘
```

### Validação
- [ ] Editar quantidade → salvar → reflete na lista
- [ ] Marcar pra troca/venda → salvar → ícones aparecem
- [ ] Definir preço → salvar → mostra na lista
- [ ] Remover item → confirmação → some da lista

---

## Task 2.8 — Flutter: Aba "Fichário" no perfil público

**Arquivo a alterar:** `app/lib/features/social/screens/user_profile_screen.dart`

Adicionar 4ª tab no `TabBar`: **Fichário**.

Essa tab chama `GET /community/binders/:userId` e mostra as cartas disponíveis para troca/venda do user visitado.

Cada card mostra:
- Imagem da carta
- Condição + Foil badge
- Ícones: 🔄 (troca) / 💰 (venda + preço)
- Botão **"Quero essa carta"** → navega pra tela de proposta de trade (Épico 3)

### Validação
- [ ] Visitar perfil de outro user → ver aba Fichário
- [ ] Cartas não marcadas como disponíveis NÃO aparecem
- [ ] Botão "Quero essa carta" navega pra proposta (ou exibe placeholder se Épico 3 não estiver pronto)

---

## Task 2.9 — Flutter: Marketplace (busca global de cartas)

**Opção de acesso:** Nova tela acessível pela aba Market (adicionar sub-tab ou botão) OU pela CommunityScreen.

**Arquivo a criar:** `app/lib/features/binder/screens/marketplace_screen.dart`

**Layout:**
```
┌─────────────────────────────────────┐
│ ◄  Marketplace                      │
├─────────────────────────────────────┤
│ 🔍 Buscar carta para comprar/trocar │
├─────────────────────────────────────┤
│ [Troca] [Venda] [NM] [LP] [MP]...  │
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ 🃏 Sol Ring (C21)       NM  x2  │ │
│ │ 👤 mage42 (Rafael)             │ │
│ │ 🔄 Troca  |  💰 R$ 15,50       │ │
│ │ [Quero essa carta]             │ │
│ └─────────────────────────────────┘ │
│ ...                                 │
└─────────────────────────────────────┘
```

### Validação
- [ ] Buscar "Sol Ring" → ver todos os sellers/traders
- [ ] Filtrar por condição, tipo (troca/venda)
- [ ] Tap no owner → abre perfil público
- [ ] "Quero essa carta" → abre proposta de trade

---

---

# ÉPICO 3 — Sistema de Trades (Negociação)

> **Objetivo:** Fluxo completo de proposta → negociação → acordo → entrega → conclusão.  
> **Estimativa:** ~5-7 dias  
> **Dependência:** Épico 2 (Fichário) — trades referenciam itens do binder

---

## Fluxo de Estados do Trade

```
                    ┌──────────┐
                    │ PENDING  │  ← Proposta enviada
                    └────┬─────┘
                         │
                    ┌────┴─────┐
                    │          │
               ┌────▼───┐ ┌───▼─────┐
               │ACCEPTED│ │DECLINED │  ← Destinatário decide
               └────┬───┘ └─────────┘
                    │
              ┌─────┴──────┐
              │            │
         ┌────▼───┐  ┌─────▼────┐
         │SHIPPED │  │CANCELLED │  ← Remetente envia ou cancela
         └────┬───┘  └──────────┘
              │
         ┌────▼────┐
         │DELIVERED│  ← Destinatário confirma recebimento
         └────┬────┘
              │
         ┌────▼─────┐
         │COMPLETED │  ← Ambos confirmaram
         └──────────┘
```

**Tipos de negociação:**
- `trade` — troca pura (carta por carta)
- `sale` — compra (dinheiro por carta)
- `mixed` — troca + compensação em dinheiro

---

## Task 3.1 — Banco de dados: tabelas de trades

```sql
-- ============================================================
-- TRADES: Sistema de negociação
-- ============================================================

-- Proposta de trade
CREATE TABLE IF NOT EXISTS trade_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','accepted','declined','shipped','delivered','completed','cancelled','disputed')),
    type TEXT NOT NULL DEFAULT 'trade'
        CHECK (type IN ('trade', 'sale', 'mixed')),
    delivery_method TEXT     -- 'mail', 'in_person', null se não definido ainda
        CHECK (delivery_method IS NULL OR delivery_method IN ('mail', 'in_person')),
    payment_method TEXT      -- 'pix', 'cash', 'transfer', null se só troca
        CHECK (payment_method IS NULL OR payment_method IN ('pix', 'cash', 'transfer', 'other')),
    payment_amount DECIMAL(10,2),  -- Valor a pagar (null se troca pura)
    payment_currency TEXT DEFAULT 'BRL',
    tracking_code TEXT,      -- Código de rastreio (correios)
    message TEXT,            -- Mensagem inicial da proposta
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_no_self_trade CHECK (sender_id != receiver_id)
);

CREATE INDEX IF NOT EXISTS idx_trade_sender ON trade_offers (sender_id);
CREATE INDEX IF NOT EXISTS idx_trade_receiver ON trade_offers (receiver_id);
CREATE INDEX IF NOT EXISTS idx_trade_status ON trade_offers (status);

-- Itens envolvidos no trade (de ambos os lados)
CREATE TABLE IF NOT EXISTS trade_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_offer_id UUID NOT NULL REFERENCES trade_offers(id) ON DELETE CASCADE,
    binder_item_id UUID NOT NULL REFERENCES user_binder_items(id) ON DELETE RESTRICT,
    owner_id UUID NOT NULL REFERENCES users(id),    -- Quem é o dono do item
    direction TEXT NOT NULL CHECK (direction IN ('offering', 'requesting')),
        -- 'offering' = o dono está dando essa carta
        -- 'requesting' = o outro lado está pedindo essa carta
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    agreed_price DECIMAL(10,2)   -- Preço acordado (para 'sale' ou 'mixed')
);

CREATE INDEX IF NOT EXISTS idx_trade_items_offer ON trade_items (trade_offer_id);

-- Mensagens dentro do trade (chat da negociação)
CREATE TABLE IF NOT EXISTS trade_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_offer_id UUID NOT NULL REFERENCES trade_offers(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    message TEXT,                    -- Texto da mensagem
    attachment_url TEXT,             -- URL do comprovante/foto
    attachment_type TEXT             -- 'receipt', 'tracking', 'photo', 'other'
        CHECK (attachment_type IS NULL OR attachment_type IN ('receipt','tracking','photo','other')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_trade_messages_offer ON trade_messages (trade_offer_id);

-- Histórico de mudanças de status (auditoria)
CREATE TABLE IF NOT EXISTS trade_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_offer_id UUID NOT NULL REFERENCES trade_offers(id) ON DELETE CASCADE,
    old_status TEXT,
    new_status TEXT NOT NULL,
    changed_by UUID NOT NULL REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_trade_history_offer ON trade_status_history (trade_offer_id);
```

### Validação
- [ ] Schema roda sem erros
- [ ] FK para `user_binder_items` funciona
- [ ] Constraints (status, type, delivery_method) rejeitam valores inválidos

---

## Task 3.2 — Server: Criar proposta de trade

**Endpoint:** `POST /trades`

**Body:**
```json
{
  "receiver_id": "uuid",
  "type": "trade",
  "message": "Oi, gostaria de trocar meu Sol Ring pelo seu Mana Crypt!",
  "my_items": [
    { "binder_item_id": "uuid", "quantity": 1 }
  ],
  "requested_items": [
    { "binder_item_id": "uuid", "quantity": 1 }
  ]
}
```

**Regras:**
1. `my_items`: verificar que cada `binder_item_id` pertence ao `sender_id` e tem `for_trade=true` ou `for_sale=true`.
2. `requested_items`: verificar que cada `binder_item_id` pertence ao `receiver_id` e está disponível.
3. Inserir `trade_offers` + `trade_items` em transação.
4. Registrar em `trade_status_history` (status: `pending`).

**Retorno:** 201 com o trade criado (id, status, items).

### Validação
- [ ] Criar proposta válida → 201
- [ ] Proposta pra si mesmo → 400
- [ ] Item que não é do sender → 403
- [ ] Item não disponível pra troca → 400

---

## Task 3.3 — Server: Listar meus trades

**Endpoint:** `GET /trades`

**Query params:** `?status=pending&role=sender|receiver|all&page=1&limit=20`

**Retorno:** Lista de trades com items resumidos + username/nick do outro lado.

### Validação
- [ ] Listar como sender → só trades que enviei
- [ ] Listar como receiver → só trades que recebi
- [ ] Filtrar por status → funciona

---

## Task 3.4 — Server: Detalhe do trade

**Endpoint:** `GET /trades/:id`

**Retorno:**
```json
{
  "id": "uuid",
  "status": "accepted",
  "type": "trade",
  "sender": { "id": "uuid", "username": "mage42", "display_name": "Rafael" },
  "receiver": { "id": "uuid", "username": "deckmaster", "display_name": "Ana" },
  "my_items": [...],
  "their_items": [...],
  "delivery_method": "mail",
  "tracking_code": "BR123456789",
  "payment_amount": null,
  "messages": [...],
  "status_history": [...],
  "created_at": "..."
}
```

**Regra:** Só o sender ou receiver pode ver o detalhe.

### Validação
- [ ] Sender acessa → vê todos os dados
- [ ] Receiver acessa → vê todos os dados
- [ ] Terceiro acessa → 403

---

## Task 3.5 — Server: Aceitar/Recusar trade

**Endpoint:** `PUT /trades/:id/respond`

**Body:** `{ "action": "accept" }` ou `{ "action": "decline" }`

**Regras:**
- Só o `receiver_id` pode responder.
- Só funciona se status atual = `pending`.
- Ao aceitar: status → `accepted`, gravar em `trade_status_history`.
- Ao recusar: status → `declined`, gravar em `trade_status_history`.

### Validação
- [ ] Receiver aceita → status muda pra accepted
- [ ] Receiver recusa → status muda pra declined
- [ ] Sender tenta responder → 403
- [ ] Trade não-pending → 400

---

## Task 3.6 — Server: Atualizar status de entrega

**Endpoint:** `PUT /trades/:id/status`

**Body:**
```json
{
  "status": "shipped",
  "delivery_method": "mail",
  "tracking_code": "BR123456789",
  "notes": "Enviei pelos Correios SEDEX"
}
```

**Regras de transição de estado:**
- `accepted` → `shipped` (quem envia marca como enviado)
- `shipped` → `delivered` (quem recebe confirma que chegou)
- `delivered` → `completed` (ambos confirmaram — ou auto-complete após 7 dias)
- Qualquer estado (exceto `completed`) → `cancelled` (qualquer parte cancela)
- Qualquer estado → `disputed` (abrir disputa)

### Validação
- [ ] Marcar como enviado com código de rastreio
- [ ] Confirmar recebimento
- [ ] Completar trade
- [ ] Cancelar trade
- [ ] Transição inválida → 400

---

## Task 3.7 — Server: Mensagens dentro do trade

**Endpoint:** `POST /trades/:id/messages`

**Body:**
```json
{
  "message": "Enviei hoje, segue comprovante",
  "attachment_url": "https://storage.../receipt.jpg",
  "attachment_type": "receipt"
}
```

**Regras:**
- Só sender ou receiver podem enviar.
- Trade deve estar em status ≠ `declined`, `cancelled`, `completed`.

**Endpoint para listar:** `GET /trades/:id/messages?page=1&limit=50`

### Validação
- [ ] Enviar mensagem de texto → aparece na lista
- [ ] Enviar com attachment → URL salva
- [ ] Terceiro tenta enviar → 403
- [ ] Trade completado → 400

---

## Task 3.8 — Server: Upload de comprovante

**Opção A (simples — MVP):** O Flutter faz upload para um storage externo (Supabase Storage, Imgur, Cloudinary) e envia só a URL pro server via `POST /trades/:id/messages`.

**Opção B (ideal):** `POST /trades/:id/attachments` com `multipart/form-data`, o server salva em disco ou S3.

**Para o MVP:** Usar Opção A. O server não precisa lidar com upload binário.

### Validação
- [ ] URL de comprovante é salva e retornada nos detalhes do trade

---

## Task 3.9 — Flutter: Provider de Trades

**Arquivo:** `app/lib/features/trades/providers/trade_provider.dart`

**Modelos:** `TradeOffer`, `TradeItem`, `TradeMessage`, `TradeStatusEntry`

**Métodos:**
- `fetchMyTrades({status, role, page, reset})`
- `fetchTradeDetails(tradeId)`
- `createTradeOffer(receiverId, type, message, myItems, requestedItems)`
- `respondToTrade(tradeId, action)` — accept/decline
- `updateTradeStatus(tradeId, status, deliveryMethod, trackingCode, notes)`
- `sendTradeMessage(tradeId, message, attachmentUrl, attachmentType)`
- `fetchTradeMessages(tradeId, {page})`

### Validação
- [ ] Provider compila sem erros
- [ ] Registrado no MultiProvider

---

## Task 3.10 — Flutter: Tela de criar proposta de trade

**Arquivo:** `app/lib/features/trades/screens/create_trade_screen.dart`

**Acesso:** Botão "Quero essa carta" no fichário público de outro user.

**Layout:**
```
┌─────────────────────────────────────┐
│ ◄  Nova Proposta de Trade           │
├─────────────────────────────────────┤
│ Para: @deckmaster (Ana)             │
├─────────────────────────────────────┤
│ 📥 Cartas que eu quero:             │
│ ┌───────────────────────────────┐   │
│ │ 🃏 Mana Crypt (2XM) NM x1    │   │
│ └───────────────────────────────┘   │
│ [+ Pedir outra carta]              │
├─────────────────────────────────────┤
│ 📤 Cartas que eu ofereço:           │
│ ┌───────────────────────────────┐   │
│ │ 🃏 Sol Ring (C21) NM x2       │   │
│ └───────────────────────────────┘   │
│ [+ Oferecer outra carta]           │
├─────────────────────────────────────┤
│ Tipo: (●) Troca ( ) Venda ( ) Misto│
│                                     │
│ Se misto/venda:                     │
│ Valor: R$ [________]               │
│ Pagamento: [Pix ▼]                 │
├─────────────────────────────────────┤
│ Mensagem:                           │
│ ┌───────────────────────────────┐   │
│ │ Oi, gostaria de trocar...    │   │
│ └───────────────────────────────┘   │
│                                     │
│ [     📤 Enviar Proposta     ]      │
└─────────────────────────────────────┘
```

### Validação
- [ ] Selecionar cartas de ambos os lados
- [ ] Enviar proposta → aparece no inbox do destinatário
- [ ] Validações (pelo menos 1 item de cada lado em troca, etc.)

---

## Task 3.11 — Flutter: Inbox de trades

**Arquivo:** `app/lib/features/trades/screens/trade_inbox_screen.dart`

**Acesso:** Botão no Perfil ou ícone na AppBar.

**Layout:**
```
┌─────────────────────────────────────┐
│ ◄  Minhas Negociações               │
├─────────────────────────────────────┤
│ [Recebidas] [Enviadas] [Finalizadas]│
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ 🔄 Trade com @mage42           │ │
│ │ Sol Ring ↔ Mana Crypt          │ │
│ │ Status: 🟡 Pendente            │ │
│ │ 09/02/2026                     │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ 💰 Venda para @deckmaster      │ │
│ │ Lightning Bolt x4              │ │
│ │ Status: 🟢 Enviado (rastreio)  │ │
│ │ 07/02/2026                     │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Cores de status:**
- 🟡 Pendente (amarelo/mythicGold)
- 🟢 Aceito/Enviado (verde/loomCyan)
- 🔴 Recusado/Cancelado (vermelho)
- 🔵 Concluído (manaViolet)

### Validação
- [ ] Listar trades recebidos
- [ ] Listar trades enviados
- [ ] Listar finalizados
- [ ] Tap → abre detalhe

---

## Task 3.12 — Flutter: Tela de detalhe do trade (timeline + chat)

**Arquivo:** `app/lib/features/trades/screens/trade_detail_screen.dart`

**Layout:**
```
┌─────────────────────────────────────┐
│ ◄  Trade #1234                      │
├─────────────────────────────────────┤
│ Status: 🟢 ACEITO                   │
│ Com: @deckmaster (Ana)              │
├─────────────────────────────────────┤
│ TIMELINE                            │
│ ● Proposta enviada      09/02 10:00 │
│ ● Aceito por @deckmaster 09/02 14:30│
│ ○ Aguardando envio                  │
│ ○ Entrega                           │
│ ○ Concluído                         │
├─────────────────────────────────────┤
│ ITENS                               │
│ 📤 Você oferece:                    │
│   Sol Ring (NM) x2                  │
│ 📥 Você recebe:                     │
│   Mana Crypt (LP) x1               │
├─────────────────────────────────────┤
│ CHAT                                │
│ ┌───────────────────────────────┐   │
│ │ [mage42] Vou enviar amanhã!  │   │
│ │ [deckmaster] Blz, manda PIX! │   │
│ │ [mage42] 📎 comprovante.jpg  │   │
│ └───────────────────────────────┘   │
│ ┌─────────────────────────┐ [📤]   │
│ │ Mensagem...             │ [📎]   │
│ └─────────────────────────┘         │
├─────────────────────────────────────┤
│ AÇÕES (dependem do status):         │
│ [✅ Marcar como enviado]            │
│ [📋 Adicionar rastreio]             │
│ [❌ Cancelar trade]                 │
└─────────────────────────────────────┘
```

**Botões dinâmicos por status:**
- `pending` (receiver): [Aceitar] [Recusar]
- `accepted` (sender): [Marcar enviado] [Cancelar]
- `shipped` (receiver): [Confirmar recebimento]
- `delivered`: [Concluir]

### Validação
- [ ] Timeline reflete status atual
- [ ] Chat carrega mensagens
- [ ] Enviar mensagem aparece no chat
- [ ] Botões de ação mudam com o status
- [ ] Upload de comprovante funciona

---

---

# ÉPICO 4 — Mensagens Diretas (Chat)

> **Objetivo:** Comunicação direta entre usuários fora do contexto de trades.  
> **Estimativa:** ~3-4 dias  
> **Dependência:** Nenhuma (paralelo ao Épico 3)  
> **Nota:** O chat DENTRO do trade (Task 3.7/3.12) já resolve 80% dos casos de uso. DMs são um nice-to-have.

---

## Task 4.1 — DB: tabelas de conversas

```sql
-- ============================================================
-- MESSAGING: Mensagens diretas entre usuários
-- ============================================================
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_conversation UNIQUE (
        LEAST(user_a_id, user_b_id),
        GREATEST(user_a_id, user_b_id)
    ),
    CONSTRAINT chk_no_self_chat CHECK (user_a_id != user_b_id)
);

CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    message TEXT NOT NULL,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_dm_conversation ON direct_messages (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_unread ON direct_messages (conversation_id) WHERE read_at IS NULL;
```

---

## Task 4.2 — Server: endpoints de conversas

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/conversations` | Listar minhas conversas (paginado, ordenado por `last_message_at`) |
| `POST` | `/conversations` | Iniciar conversa: `{ user_id }` → retorna conversa existente ou cria nova |
| `GET` | `/conversations/:id/messages` | Listar mensagens da conversa (paginado) |
| `POST` | `/conversations/:id/messages` | Enviar mensagem: `{ message }` |
| `PUT` | `/conversations/:id/read` | Marcar mensagens como lidas |

---

## Task 4.3 — Flutter: Tela de inbox de mensagens

**Arquivo:** `app/lib/features/messaging/screens/inbox_screen.dart`

Lista de conversas com avatar, nick, preview da última mensagem, badge de não-lidas.

---

## Task 4.4 — Flutter: Tela de chat

**Arquivo:** `app/lib/features/messaging/screens/chat_screen.dart`

Bolhas de mensagem estilo WhatsApp. Input com botão de enviar. Scroll infinito pra mensagens antigas. Auto-refresh por polling (cada 5s).

---

## Task 4.5 — Flutter: Botão "Enviar mensagem" no perfil público

No `UserProfileScreen`, adicionar botão ao lado do "Seguir":
```dart
OutlinedButton.icon(
  icon: Icon(Icons.chat_bubble_outline),
  label: Text('Mensagem'),
  onPressed: () => _openChat(userId),
)
```

---

---

# ÉPICO 5 — Notificações

> **Objetivo:** Avisar o usuário sobre eventos relevantes sem precisar ficar verificando manualmente.  
> **Estimativa:** ~2-3 dias  
> **Dependência:** Pode ser adicionado incrementalmente conforme outros épicos ficam prontos.

---

## Task 5.1 — DB: tabela de notificações

```sql
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN (
        'new_follower',
        'trade_offer_received',
        'trade_accepted',
        'trade_declined',
        'trade_shipped',
        'trade_delivered',
        'trade_completed',
        'trade_message',
        'direct_message'
    )),
    reference_id UUID,         -- ID do objeto relacionado (trade, user, etc.)
    title TEXT NOT NULL,        -- "Nova proposta de trade"
    body TEXT,                  -- "mage42 quer trocar Sol Ring por..."
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications (user_id) WHERE read_at IS NULL;
```

---

## Task 5.2 — Server: endpoints de notificações

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/notifications` | Listar notificações (paginado) com `?unread_only=true` |
| `GET` | `/notifications/count` | `{ unread: 5 }` — para badge |
| `PUT` | `/notifications/:id/read` | Marcar como lida |
| `PUT` | `/notifications/read-all` | Marcar todas como lidas |

---

## Task 5.3 — Server: criar notificações automaticamente

Adicionar chamadas em cada handler relevante:
- `POST /users/:id/follow` → notificação `new_follower` para o seguido
- `POST /trades` → notificação `trade_offer_received` para o receiver
- `PUT /trades/:id/respond` → `trade_accepted` ou `trade_declined` para o sender
- `PUT /trades/:id/status` → `trade_shipped`, `trade_delivered`, `trade_completed`
- `POST /trades/:id/messages` → `trade_message` para o outro lado
- `POST /conversations/:id/messages` → `direct_message` para o outro lado

---

## Task 5.4 — Flutter: Ícone de sino com badge

No `MainScaffold` AppBar (ou como 6ª aba), adicionar ícone de sino que mostra o count de não-lidas e navega pra tela de notificações.

---

## Task 5.5 — Flutter: Tela de notificações

Lista com ícone por tipo, título, body, tempo relativo ("há 2h"). Tap navega para o contexto (perfil do follower, detalhe do trade, chat).

---

---

# 📋 Checklist Global de Progresso

Marque `[x]` conforme cada task for concluída.

## Épico 1 — Polir Existente
- [x] 1.1 Toggle público na criação de deck
- [x] 1.2 UI de avatar no perfil
- [x] 1.3 Remover ALTER TABLE em runtime
- [x] 1.4 Paginação em seguidores/seguindo

## Épico 2 — Fichário (Binder)
- [x] 2.1 DB: tabela `user_binder_items`
- [x] 2.2 Server: CRUD do binder
- [x] 2.3 Server: Binder público
- [x] 2.4 Server: Marketplace (busca global)
- [x] 2.5 Flutter: Provider do binder
- [x] 2.6 Flutter: Tela "Meu Fichário"
- [x] 2.7 Flutter: Modal de editar item
- [x] 2.8 Flutter: Aba Fichário no perfil público
- [x] 2.9 Flutter: Tela de marketplace

## Épico 3 — Trades
- [x] 3.1 DB: tabelas de trades
- [x] 3.2 Server: Criar proposta
- [x] 3.3 Server: Listar trades
- [x] 3.4 Server: Detalhe do trade
- [x] 3.5 Server: Aceitar/Recusar
- [x] 3.6 Server: Atualizar status/entrega
- [x] 3.7 Server: Mensagens no trade
- [x] 3.8 Server: Upload de comprovante
- [x] 3.9 Flutter: Provider de trades
- [x] 3.10 Flutter: Criar proposta
- [x] 3.11 Flutter: Inbox de trades
- [x] 3.12 Flutter: Detalhe do trade (timeline + chat)

## Épico 4 — Mensagens Diretas
- [x] 4.1 DB: tabelas de conversas
- [x] 4.2 Server: endpoints de conversas
- [x] 4.3 Flutter: Inbox de mensagens
- [x] 4.4 Flutter: Tela de chat
- [x] 4.5 Flutter: Botão "Mensagem" no perfil

## Épico 5 — Notificações
- [x] 5.1 DB: tabela de notificações
- [x] 5.2 Server: endpoints de notificações
- [x] 5.3 Server: criar notificações automaticamente
- [x] 5.4 Flutter: Ícone de sino + badge
- [x] 5.5 Flutter: Tela de notificações

---

**Total: 40 tasks | 5 épicos**  
**Execução sequencial recomendada:** 1 → 2 → 3 → 4 → 5  
**Tempo estimado total:** ~15-20 dias de desenvolvimento focado
