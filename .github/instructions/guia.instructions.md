---
applyTo: '**'
---
# Guia de Desenvolvimento e Instruções do Projeto MTG Deck Builder

Este arquivo define as regras estritas, a filosofia e o fluxo de trabalho para o desenvolvimento deste projeto.

---

## 📑 Índice

1. [🚀 Quick Start](#-quick-start)
2. [📁 Estrutura de Arquivos](#-estrutura-de-arquivos)
3. [🔒 Modo Operacional](#-modo-operacional-obrigatório)
4. [⚠️ Estado Atual](#️-estado-atual-importante-para-manutenção)
5. [🎯 Objetivo do Projeto](#-objetivo-do-projeto)
6. [🗄️ Estrutura de Dados](#️-estrutura-de-dados-schema-atual)
7. [📡 Contratos de API](#-contratos-de-api-payloads-reais)
8. [💻 Stack Tecnológica](#-stack-tecnológica)
9. [🔐 Segurança](#-segurança)
10. [✅ Validação e Testes](#-validação-e-testes)
11. [🤖 DeckArchetypeAnalyzer](#-deckarchetypeanalyzer-regras-críticas)
12. [🧠 Roadmap da IA](#-roadmap-de-implementação-da-ia)
13. [📋 Padrões e Fluxo de Trabalho](#-padrões-e-fluxo-de-trabalho)
14. [🔧 Troubleshooting](#-troubleshooting)

---

## 🚀 Quick Start

### Comandos Essenciais

```bash
# ══════════════════════════════════════════════════════════════
# SERVIDOR (Backend)
# ══════════════════════════════════════════════════════════════

# Iniciar servidor em desenvolvimento (hot reload)
cd server && dart_frog dev

# Iniciar servidor em produção (mais estável)
cd server && dart run .dart_frog/server.dart

# Verificar se servidor está rodando
curl -s http://localhost:8080/health

# Matar servidor antigo se porta estiver ocupada
lsof -ti:8080 | xargs kill -9 2>/dev/null

# ══════════════════════════════════════════════════════════════
# FLUTTER (App)
# ══════════════════════════════════════════════════════════════

# Rodar no Chrome
cd app && flutter run -d chrome

# Rodar no Android emulator
cd app && flutter run -d emulator-5554

# Rodar testes unitários
cd app && flutter test

# ══════════════════════════════════════════════════════════════
# BANCO DE DADOS (PostgreSQL remoto)
# ══════════════════════════════════════════════════════════════

# Conexão direta (usar variáveis do .env)
psql postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder

# Limpar cache de otimização (OBRIGATÓRIO após alterar DeckArchetypeAnalyzer)
psql $DATABASE_URL -c "DELETE FROM ai_optimize_cache"

# Via Python (se psql não disponível)
.venv/bin/python -c "
import psycopg2
conn = psycopg2.connect('postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder')
cur = conn.cursor()
cur.execute('DELETE FROM ai_optimize_cache')
conn.commit()
print('Cache cleared')
conn.close()
"

# ══════════════════════════════════════════════════════════════
# TESTES E QUALIDADE
# ══════════════════════════════════════════════════════════════

# Quality gate (modo rápido durante dev)
./scripts/quality_gate.sh quick

# Quality gate (modo completo no fechamento)
./scripts/quality_gate.sh full

# Quality gate do carro-chefe (otimização)
./scripts/quality_gate_carro_chefe.sh

# Teste de integração dos 7 decks
.venv/bin/python server/test/test_full_optimize_flow.py

# Testes unitários do server
cd server && dart test
```

---

## 📁 Estrutura de Arquivos

### Arquivos Principais (SEMPRE ATUALIZADOS)

| Arquivo | Propósito | Atualizar quando... |
|---------|-----------|---------------------|
| `ROADMAP.md` | Priorização e ordem de execução (90 dias) | Mudar escopo ou prioridade |
| `.github/instructions/guia.instructions.md` | **ESTE ARQUIVO** — regras de desenvolvimento | Mudar schema, API, ou padrões |
| `.github/instructions/roadmap.instructions.md` | Status de features social/trades | Completar task de social/trades |
| `server/manual-de-instrucao.md` | Histórico técnico detalhado (7600+ linhas) | TODA mudança significativa |

### Estrutura do Projeto

```
mtgia/
├── .github/
│   └── instructions/
│       ├── guia.instructions.md          ← ESTE ARQUIVO (regras gerais)
│       └── roadmap.instructions.md       ← Status de social/trades
├── app/                                   ← Flutter (frontend)
│   ├── lib/
│   │   ├── main.dart                     ← Entry point + providers
│   │   ├── core/                         ← Theme, router, utils
│   │   └── features/                     ← Telas organizadas por feature
│   │       ├── auth/
│   │       ├── decks/
│   │       ├── cards/
│   │       ├── community/
│   │       ├── binder/
│   │       ├── trades/
│   │       └── messages/
│   └── test/                             ← Testes unitários Flutter
├── server/                                ← Dart Frog (backend)
│   ├── .env                              ← ⚠️ NÃO COMMITAR (no .gitignore)
│   ├── .dart_frog/server.dart            ← Entry point gerado
│   ├── manual-de-instrucao.md            ← Histórico técnico
│   ├── pubspec.yaml                      ← Dependências Dart
│   ├── routes/                           ← Endpoints da API
│   │   ├── auth/                         ← Login, register, me
│   │   ├── decks/                        ← CRUD de decks
│   │   ├── cards/                        ← Busca de cartas
│   │   ├── ai/                           ← Endpoints de IA
│   │   │   ├── optimize/index.dart       ← ⭐ ARQUIVO MAIS CRÍTICO (~5500 linhas)
│   │   │   ├── explain/
│   │   │   ├── generate/
│   │   │   └── archetypes/
│   │   ├── binder/
│   │   ├── trades/
│   │   ├── conversations/
│   │   └── community/
│   ├── lib/                              ← Código compartilhado
│   │   ├── ai/                           ← Lógica de IA
│   │   ├── db/                           ← Conexão com banco
│   │   └── middleware/                   ← JWT, rate limit
│   ├── bin/                              ← Scripts utilitários
│   │   ├── sync_cards.dart               ← Sincronizar cartas do Scryfall
│   │   └── *.dart                        ← Outros scripts
│   └── test/                             ← Testes
│       ├── test_full_optimize_flow.py    ← Teste de integração (7 decks)
│       └── artifacts/                    ← Resultados de testes
├── scripts/                               ← Scripts de qualidade
│   ├── quality_gate.sh                   ← Gate geral
│   └── quality_gate_carro_chefe.sh       ← Gate do optimize
├── archive_docs/                          ← Documentos históricos
│   └── root/
│       └── ROADMAP_SOCIAL_TRADES.md      ← Referência completa social/trades
└── ROADMAP.md                             ← Roadmap principal (90 dias)
```

### Arquivos Ignorados pelo Git (.gitignore)

```
.DS_Store               # macOS
**/AtomicCards.json     # Dados brutos (muito grande)
.dart_tool/             # Cache Dart
build/                  # Build outputs
.venv/                  # Python virtualenv
.env                    # ⚠️ CREDENCIAIS - NUNCA COMMITAR
server/cache/           # Cache local
*.log                   # Logs
```

---

## 🔒 Modo Operacional Obrigatório

### Fonte Única de Execução

1. **Roadmap único:** usar `ROADMAP.md` como fonte principal de priorização.
2. **Histórico técnico:** registrar mudanças em `server/manual-de-instrucao.md`.
3. **Documentos arquivados:** materiais não prioritários ficam em `archive_docs/`.
4. **Quality Gate obrigatório:**
    - `./scripts/quality_gate.sh quick` (durante implementação)
    - `./scripts/quality_gate.sh full` (fechamento de item/sprint)
5. **Definição de pronto (DoD):** nenhuma tarefa é concluída sem critério de aceite + testes + documentação.

> Regra: se uma mudança não melhora fluxo core, não reduz risco crítico, e não aumenta valor percebido, ela vai para backlog.

### 🎯 Exceção Temporária — Foco no Carro-Chefe (Otimização de Deck)

**Válido temporariamente enquanto o foco estiver em estabilizar o fluxo `optimize/complete`.**

Durante esta janela:
- fica **desativada a obrigatoriedade** de rodar o gate geral;
- passa a ser **obrigatório** rodar o gate exclusivo:
    - `./scripts/quality_gate_carro_chefe.sh`
    - ou com deck-alvo explícito: `SOURCE_DECK_ID=<uuid> ./scripts/quality_gate_carro_chefe.sh`

---

## ⚠️ Estado Atual (importante para manutenção)

Este repositório é **full-stack**:
- `app/`: Flutter (Provider + GoRouter) consumindo API HTTP em `http://localhost:8080` (ou `10.0.2.2:8080` no Android emulator).
- `server/`: Dart Frog + PostgreSQL (JWT + validações de deck + endpoints de IA).

### Pontos Críticos (dev/QA)

| Área | Problema | Solução |
|------|----------|---------|
| **POST /decks** | Cartas devem ser enviadas por ID (`card_id`) | Resolver para IDs via `/cards?name=...` antes |
| **Deep link /decks/:id/search** | "Adicionar carta" pode falhar se deck não carregado | Garantir `fetchDeckDetails` antes |
| **Rate limiting em auth** | Limites agressivos bloqueiam QA | Usar limites maiores em dev |
| **IA (OpenAI)** | Sem `OPENAI_API_KEY` quebra UI | Manter fallback/mock em dev |
| **Cache de Otimização** | Respostas cacheadas por 24h | Limpar cache após mudanças no código |
| **Atualização de cartas** | Novas coleções MTG | Rodar `sync_cards.dart` |

### 🧹 Cache de Otimização (`ai_optimize_cache`)

Respostas do `/ai/optimize` são cacheadas no banco por 24h. **Ao alterar código do `DeckArchetypeAnalyzer` ou lógica de análise, OBRIGATÓRIO limpar o cache:**

```sql
DELETE FROM ai_optimize_cache;
```

### 🔄 Atualização de Cartas (novas coleções)

```bash
# Script oficial (idempotente, usa checkpoint em sync_state)
cd server && dart run bin/sync_cards.dart

# Usar fallback se não existir checkpoint
dart run bin/sync_cards.dart --since-days=45

# Full sync (processa AtomicCards.json completo - LENTO)
dart run bin/sync_cards.dart --full
```

---

## 🎯 Objetivo do Projeto

Desenvolver um aplicativo de Deck Builder de Magic: The Gathering (MTG) revolucionário, focado em inteligência artificial e automação.

### Funcionalidades Core

1. **Deck Builder Completo:** Cadastro de usuários e decks (privados/públicos), cópia de decks públicos, importação inteligente de listas de texto.

2. **Regras e Legalidade:** Tabela de regras, verificação de banidas por formato.

3. **Diferencial com IA:**
   - Criação por descrição ("Deck agressivo de goblins vermelhos")
   - Autocompletar decks incompletos
   - Análise de sinergia com `synergy_score`

4. **Simulador de Batalha:** (FUTURO) Simular matchups, identificar counters, gerar dataset para treinar IA.

5. **Social & Trading:** ✅ IMPLEMENTADO - Follow, feed, binder, marketplace, trades, mensagens, notificações.

---

## 🗄️ Estrutura de Dados (Schema Atual)

Para garantir consistência, consulte sempre as colunas existentes antes de criar queries.

### Tabela: `users`
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `username` | TEXT | Nome de usuário único |
| `email` | TEXT | Email único |
| `password_hash` | TEXT | Hash da senha |
| `created_at` | TIMESTAMPTZ | Data de criação |
| `display_name` | TEXT | Nick público opcional |
| `avatar_url` | TEXT | URL do avatar |
| `updated_at` | TIMESTAMPTZ | Última atualização |
| `location_state` | VARCHAR | Estado/UF |
| `location_city` | VARCHAR | Cidade |
| `trade_notes` | TEXT | Notas do perfil de trades |
| `fcm_token` | TEXT | Token Firebase Cloud Messaging |

### Tabela: `cards` (33.7k cartas)
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `scryfall_id` | UUID | Oracle ID oficial |
| `name` | TEXT | Nome da carta |
| `mana_cost` | TEXT | Custo de mana (ex: {2}{U}{U}) |
| `type_line` | TEXT | Tipo (ex: Creature — Human Wizard) |
| `oracle_text` | TEXT | Texto de regras oficial |
| `colors` | TEXT[] | Array de cores |
| `color_identity` | TEXT[] | Identidade de cor (commander) |
| `image_url` | TEXT | URL para imagem |
| `set_code` | TEXT | Sigla da edição |
| `rarity` | TEXT | Raridade |
| `cmc` | NUMERIC | Converted Mana Cost |
| `price_usd` | NUMERIC | Preço em USD |
| `price_usd_foil` | NUMERIC | Preço foil |
| `collector_number` | TEXT | Número de colecionador |
| `foil` | BOOLEAN | Se é foil |
| `ai_description` | TEXT | Descrição gerada por IA |
| `price` | NUMERIC | (deprecated, usar price_usd) |
| `price_updated_at` | TIMESTAMPTZ | Última atualização de preço |
| `created_at` | TIMESTAMPTZ | Data de criação |

### Tabela: `card_legalities`
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `card_id` | UUID | FK para cards |
| `format` | TEXT | Formato (commander, modern, etc) |
| `status` | TEXT | 'legal', 'banned', 'restricted' |

### Tabela: `decks`
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `user_id` | UUID | FK para users |
| `name` | TEXT | Nome do deck |
| `format` | TEXT | Formato |
| `description` | TEXT | Descrição |
| `is_public` | BOOLEAN | Visibilidade |
| `synergy_score` | INTEGER | 0-100, pontuação de consistência |
| `strengths` | TEXT | Pontos fortes (IA) |
| `weaknesses` | TEXT | Pontos fracos (IA) |
| `archetype` | TEXT | Arquétipo (aggro, control, combo) |
| `bracket` | INTEGER | Bracket de poder (1-4) |
| `pricing_total` | NUMERIC | Preço total do deck |
| `pricing_currency` | TEXT | Moeda |
| `pricing_missing_cards` | INTEGER | Cartas sem preço |
| `pricing_updated_at` | TIMESTAMPTZ | Última atualização |
| `created_at` | TIMESTAMPTZ | Data de criação |
| `deleted_at` | TIMESTAMPTZ | Soft delete |

### Tabela: `deck_cards`
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `deck_id` | UUID | FK para decks |
| `card_id` | UUID | FK para cards |
| `quantity` | INTEGER | ⚠️ CRÍTICO: sempre usar em contagens |
| `is_commander` | BOOLEAN | Se é comandante |
| `condition` | TEXT | Condição (NM/LP/MP/HP/DMG) |

### Tabela: `ai_optimize_cache`
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `cache_key` | TEXT | UNIQUE. Hash (deck_id + signature + params) |
| `user_id` | UUID | FK para users |
| `deck_id` | UUID | FK para decks |
| `deck_signature` | TEXT | Hash do conteúdo do deck |
| `payload` | JSONB | Resposta completa cacheada |
| `created_at` | TIMESTAMPTZ | Data de criação |
| `expires_at` | TIMESTAMPTZ | Expira após 24h |

### Tabela: `card_meta_insights` (1,842 rows)
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID | PK |
| `card_name` | TEXT | Nome da carta |
| `usage_count` | INTEGER | Quantas vezes usada (popularidade) |
| `meta_deck_count` | INTEGER | Quantos decks de meta usam |
| `common_archetypes` | TEXT[] | Arquétipos comuns |
| `common_formats` | TEXT[] | Formatos comuns |
| `top_pairs` | JSONB | Cartas frequentemente usadas junto |
| `learned_role` | TEXT | Função (ramp, removal, etc) |
| `versatility_score` | FLOAT | Score de versatilidade |
| `last_updated_at` | TIMESTAMPTZ | Última atualização |

### Outras Tabelas (referência)
- `rules` — Regras do jogo (id, title, description, category, created_at)
- `deck_matchups` — Estatísticas de matchups
- `battle_simulations` — Dataset para ML
- `user_binder_items` — Fichário pessoal
- `trade_offers`, `trade_items`, `trade_messages`, `trade_status_history` — Sistema de trades
- `conversations`, `direct_messages` — Chat
- `notifications` — Notificações
- `user_follows` — Seguidores

### ⚠️ Limitações Conhecidas do Banco

| Limitação | Impacto | Workaround |
|-----------|---------|------------|
| `cards.edhrec_rank` não existe | — | Queries usam fallback (median 5000) |
| Duplicatas em `cards` | 33.7k cards, 33.5k nomes únicos | Usar `DISTINCT ON` |

---

## 📡 Contratos de API (payloads reais)

**Regra:** o app deve falar com o server usando o contrato abaixo.

### Auth
```javascript
POST /auth/login
  Body: { "email": "...", "password": "..." }
  Response 200: { token, user: { id, username, email } }

POST /auth/register
  Body: { "username": "...", "email": "...", "password": "..." }
  Response 201: { token, user: { id, username, email } }

GET /auth/me
  Headers: Authorization: Bearer <token>
  Response 200: { user: { id, username, email } }
```

### Decks
```javascript
GET /decks                    // Lista decks do usuário (JWT obrigatório)
POST /decks                   // Cria deck
  Body: { name, format, description?, cards: [{ card_id, quantity, is_commander? }] }
GET /decks/:id                // Detalhes + cartas
PUT /decks/:id                // Atualiza (mesmo formato do POST)
```

### Cards
```javascript
GET /cards?name=...&limit=...&page=...
  Response: { data: [...], page, limit, total_returned }
```

### IA
```javascript
POST /ai/optimize             // ⭐ Endpoint principal
  Body: { deck_id, archetype?, mode?, keep_theme?, bracket? }
  
  Mode selection:
    - deck com 100 cartas → mode: "optimize" (sync ~40s)
    - deck < 100 cartas → mode: "complete" (async job)
  
  Response: {
    mode: "optimize" | "complete",
    additions: [...],
    removals: [...],
    post_analysis: { lands, total_cards, mana_base_assessment, ... },
    cache: { hit: bool }
  }

POST /ai/explain              // Explicar deck
POST /ai/generate             // Gerar deck por descrição
POST /ai/archetypes           // Detectar arquétipos
```

---

## 💻 Stack Tecnológica

### Backend
| Componente | Tecnologia |
|------------|------------|
| Framework | Dart Frog |
| DB Driver | `postgres` (v3.x) |
| Env | `dotenv` |
| HTTP Client | `http` |
| JWT | `dart_jsonwebtoken` |

### Frontend
| Componente | Tecnologia |
|------------|------------|
| Framework | Flutter |
| State Management | Provider |
| Navigation | GoRouter |
| HTTP Client | `http` |

### Banco de Dados
```
Host: 143.198.230.247
Port: 5433
Database: halder
User: postgres
```

---

## 🔐 Segurança

### JWT Configuration
| Config | Valor |
|--------|-------|
| Secret | via `JWT_SECRET` no `.env` (default dev: `your-super-secret-and-long-string-for-jwt`) |
| Payload key | `userId` (não `user_id`) |
| Algoritmo | HS256 |
| Rotas protegidas | `/decks`, `/ai/*`, `/import`, `/binder`, `/trades`, `/conversations` |

### Rate Limiting
- **Produção:** Auth restritivo (brute force protection)
- **Dev/Test:** Limites maiores para não bloquear QA

### .env (NUNCA COMMITAR)
```bash
DATABASE_URL=postgresql://...
JWT_SECRET=your-super-secret-and-long-string-for-jwt
OPENAI_API_KEY=sk-...
```

---

## ✅ Validação e Testes

### Gate de Qualidade

```bash
# Checklist mínimo por entrega:
# [ ] Gate de qualidade executado
# [ ] Sem erros de compilação/lint
# [ ] Teste manual do fluxo impactado

# Modo rápido (durante dev)
./scripts/quality_gate.sh quick

# Modo completo (fechamento)
./scripts/quality_gate.sh full

# Foco no carro-chefe (temporário)
./scripts/quality_gate_carro_chefe.sh
```

### Teste de Integração do Optimize (7 decks)

Script: `server/test/test_full_optimize_flow.py`

| Deck | Cartas | Mode | Validação |
|------|--------|------|-----------|
| Jin (mono-U) | 100 | optimize | Lands ~38, mana equilibrada |
| Goblins (BR) | 100 | optimize | Lands ~25, aggro |
| Commander 94 | 94 | complete | Deve chegar a 100 |
| Atraxa 74 (WUBG) | 74 | complete | Deve chegar a 100 |
| Atraxa 44 (WUBG) | 44 | complete | Deve chegar a 100 |
| Krenko 25 (mono-R) | 25 | complete | Deve chegar a 100 |
| Atraxa 1 (commander only) | 1 | complete | Deve criar 99 cartas |

```bash
# IMPORTANTE: Limpar cache antes (obrigatório após mudanças no código)
psql $DATABASE_URL -c "DELETE FROM ai_optimize_cache"

# Rodar teste (server deve estar em localhost:8080)
.venv/bin/python server/test/test_full_optimize_flow.py
```

---

## 🤖 DeckArchetypeAnalyzer (Regras Críticas)

Arquivo: `server/routes/ai/optimize/index.dart` (~5500 linhas)

Esta é a classe mais crítica do sistema. Analisa decks para determinar arquétipo, curva de mana e distribuição de tipos.

### ⚠️ REGRA FUNDAMENTAL: Sempre multiplicar por `quantity`

Cada entry no deck tem um campo `quantity`. **TODAS as funções de contagem DEVEM multiplicar por qty:**

```dart
// ✅ CORRETO: multiplica por quantity
final qty = (card['quantity'] as int?) ?? 1;
counts['lands'] = counts['lands']! + qty;  // Island x30 = 30 lands

// ❌ ERRADO: ignora quantity  
counts['lands'] = counts['lands']! + 1;    // Island x30 = 1 land (BUG!)
```

### Funções que usam quantity (todas já corrigidas)

| Função | O que faz |
|--------|-----------|
| `countCardTypes()` | Conta lands, creatures, instants, etc |
| `calculateAverageCMC()` | CMC ponderado por quantidade |
| `analyzeManaBase()` | Devotion e fontes de mana |
| `detectArchetype()` | Cálculo de totalNonLands |
| `_calculateConfidence()` | Confiança do arquétipo |

### Queries de Filler (busca de cartas para completar)

As 5 queries de filler usam ordenação por **popularidade** (via `card_meta_insights.usage_count`):

```sql
-- Padrão de todas as queries de filler
SELECT DISTINCT ON (LOWER(name)) ...
FROM cards c
LEFT JOIN card_meta_insights cmi ON LOWER(c.name) = LOWER(cmi.card_name)
ORDER BY COALESCE(cmi.usage_count, 0) DESC, RANDOM()
```

**Regra:** NUNCA usar `ORDER BY c.name ASC` em queries de filler (resultaria apenas em cartas A-R).

### Após modificar DeckArchetypeAnalyzer

1. Limpar cache: `DELETE FROM ai_optimize_cache`
2. Reiniciar servidor
3. Rodar teste de integração dos 7 decks

---

## 🧠 Roadmap de Implementação da IA

### Módulo 1: Analista Matemático ✅ IMPLEMENTADO
*Algoritmos heurísticos sem custo de API*

- ✅ `calculateAverageCMC()` — CMC ponderado
- ✅ `analyzeManaBase()` — Devotion vs fontes
- ✅ Validação de formato via `card_legalities`

### Módulo 2: Consultor Criativo ✅ IMPLEMENTADO
*LLM (OpenAI GPT-4o)*

- ✅ `POST /ai/generate` — Cria deck por descrição
- ✅ `POST /ai/explain` — Analisa sinergia
- ✅ `POST /ai/optimize` (complete) — Completa decks
- ✅ `POST /ai/optimize` (optimize) — Otimiza decks completos

### Módulo 3: Simulador de Probabilidade 🔜 FUTURO
*Monte Carlo simplificado*

- Simular 1.000 mãos iniciais
- Métrica de Zica/Flood (% de mãos ruins)
- Métrica de Curva (% de jogada válida por turno)
- Popular `battle_simulations` para treinar IA

> **Status:** Módulos 1 e 2 funcionando. 7 decks testados com sucesso.

---

## 📋 Padrões e Fluxo de Trabalho

### Documentação Contínua (Regra de Ouro)

Para CADA alteração significativa, atualizar `server/manual-de-instrucao.md`:
- **O Porquê:** Justificativa da decisão
- **O Como:** Explicação técnica
- **Bibliotecas:** O que cada dependência faz
- **Padrões:** Como Clean Code foi aplicado
- **Exemplos:** Snippets de código

### Padrões de Código
- **Clean Architecture:** Separar Data, Domain, Presentation/Routes
- **Clean Code:** Nomes descritivos, funções pequenas
- **Segurança:** Nunca commitar credenciais
- **Tratamento de Erros:** try-catch explícitos

### Fluxo de Trabalho

1. **Entender:** Confirmar objetivo, impacto, critério de aceite
2. **Planejar:** Listar arquivos afetados
3. **Executar:** Implementar só o necessário
4. **Validar:** Rodar quality gate
5. **Testar:** Validar happy path + erro crítico
6. **Documentar:** Atualizar manual-de-instrucao.md
7. **Fechar:** Só com DoD atendida

### Critérios de Bloqueio

Bloquear quando:
- Faltar dependência crítica
- Houver risco de regressão sem cobertura
- Escopo extrapolar sprint

Ao bloquear:
- Registrar causa em 1 linha
- Definir próximo passo
- Ajustar backlog

---

## 🔧 Troubleshooting

### Servidor não inicia

```bash
# 1. Verificar se porta está ocupada
lsof -ti:8080

# 2. Matar processo antigo
lsof -ti:8080 | xargs kill -9

# 3. Limpar build cache
cd server && rm -rf build

# 4. Tentar com dart run (mais estável)
cd server && dart run .dart_frog/server.dart
```

### Otimização retorna dados antigos

```bash
# Cache de 24h pode ter dados obsoletos
# SEMPRE limpar após mudanças no código:
psql $DATABASE_URL -c "DELETE FROM ai_optimize_cache"
```

### Testes falhando com erro de autenticação

```bash
# Rate limit pode estar bloqueando
# Verificar tabela rate_limit_events
# Em dev, usar limites maiores
```

### Flutter não conecta no servidor

```bash
# Android emulator usa IP diferente
# Trocar localhost por 10.0.2.2

# Verificar se servidor está rodando
curl -s http://localhost:8080/health
```

### Deck com lands errados após optimize

1. Verificar se cache foi limpo
2. Verificar se `quantity` está sendo multiplicado
3. Rodar teste de integração
4. Verificar logs do servidor

### OpenAI retorna erro

```bash
# Verificar se OPENAI_API_KEY está no .env
# Verificar quota da API
# Em dev sem API key, verificar se fallback está funcionando
```

### Cartas novas não aparecem

```bash
# Sincronizar com Scryfall
cd server && dart run bin/sync_cards.dart

# Se falhar, rodar full sync
dart run bin/sync_cards.dart --full
```

---

## 📊 Prioridade (90 dias)

1. **Core impecável:** criar → importar → validar → analisar → otimizar
2. **Segurança:** hardening, rate limit, métricas
3. **IA com ROI:** explicabilidade, confiança, cache
4. **Monetização:** somente após estabilidade

**Evitar neste ciclo:**
- Expansão de features secundárias
- Novas frentes sem critério de valor
