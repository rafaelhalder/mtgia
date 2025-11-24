# 🌟 ManaLoom - AI-Powered MTG Deck Builder

> **"Weave your perfect strategy"** - Um Deck Builder de Magic: The Gathering revolucionário com inteligência artificial.

[![Flutter](https://img.shields.io/badge/Flutter-3.7.2+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)](https://dart.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-316192?logo=postgresql)](https://postgresql.org)
[![License](https://img.shields.io/badge/License-Private-red)](LICENSE)

---

## 📖 Visão Global

**ManaLoom** é um aplicativo completo de Deck Builder para Magic: The Gathering que utiliza inteligência artificial para:

- 🎯 **Criar decks automaticamente** a partir de descrições em linguagem natural
- 🔍 **Analisar e otimizar** decks existentes com sugestões de melhorias
- 📊 **Calcular sinergia e consistência** usando algoritmos matemáticos e LLMs
- ⚡ **Simular partidas** para identificar pontos fortes e fracos
- 🎨 **Validar legalidade** de cartas por formato (Commander, Standard, Modern, etc.)

### Para Quem é Este Projeto?

- **Jogadores competitivos** que querem otimizar seus decks
- **Jogadores casuais** que precisam de ajuda para construir decks temáticos
- **Colecionadores** que querem gerenciar suas coleções
- **Desenvolvedores** interessados em IA aplicada a jogos de cartas

---

## 🏗️ Arquitetura do Projeto

Este é um projeto **full-stack** dividido em duas partes principais:

```
mtgia/
├── app/           # 📱 Frontend Flutter (Mobile & Desktop)
├── server/        # 🖥️ Backend Dart Frog (API RESTful)
└── docs/          # 📚 Documentação adicional
```

### Diagrama de Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                     FLUTTER APP (Frontend)                       │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────────┐ │
│  │   Auth    │  │   Decks   │  │   Cards   │  │   AI Tools   │ │
│  │  Screens  │  │  Screens  │  │  Search   │  │   Screens    │ │
│  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └──────┬───────┘ │
│        │              │              │                │          │
│  ┌─────┴──────────────┴──────────────┴────────────────┴───────┐ │
│  │              Provider (State Management)                    │ │
│  └─────┬──────────────────────────────────────────────────┬───┘ │
│        │                                                   │     │
│  ┌─────┴─────┐                                      ┌─────┴───┐ │
│  │ ApiClient │                                      │ Storage │ │
│  └─────┬─────┘                                      └─────────┘ │
└────────┼────────────────────────────────────────────────────────┘
         │ HTTP (REST API)
         │
┌────────┼────────────────────────────────────────────────────────┐
│        │           DART FROG SERVER (Backend)                   │
│  ┌─────┴─────┐                                                  │
│  │  Routes/  │  (/auth, /decks, /cards, /ai, /rules)            │
│  │Controllers│                                                   │
│  └─────┬─────┘                                                  │
│        │                                                         │
│  ┌─────┴──────────────────────────────────────┐                │
│  │     Middleware (Auth, CORS, Logging)        │                │
│  └─────┬──────────────────────────────────────┘                │
│        │                                                         │
│  ┌─────┴─────┐  ┌──────────────┐  ┌─────────────────┐         │
│  │  Services │  │   Database   │  │  OpenAI Client  │         │
│  │ (Business │  │  (Singleton) │  │   (AI Logic)    │         │
│  │   Logic)  │  └──────┬───────┘  └─────────────────┘         │
│  └───────────┘         │                                        │
└────────────────────────┼────────────────────────────────────────┘
                         │
                ┌────────┴────────┐
                │   PostgreSQL    │
                │    Database     │
                └─────────────────┘
```

### Padrão Arquitetural: Clean Architecture + Feature-First

#### Backend (server/)
- **Camada de Apresentação:** `routes/` - Endpoints HTTP organizados por recurso
- **Camada de Aplicação:** `lib/*_service.dart` - Lógica de negócio (AuthService, etc.)
- **Camada de Infraestrutura:** `lib/database.dart` - Acesso a dados (PostgreSQL)
- **Middleware:** `lib/auth_middleware.dart` - Cross-cutting concerns (autenticação, logs)

#### Frontend (app/)
- **Feature-First:** Cada feature (auth, decks, cards) é independente e autocontida
- **Presentation:** Screens e widgets
- **State Management:** Provider pattern para gerenciar estado
- **Data:** Repositórios e APIs isoladas em `core/api/`

---

## 🛠️ Stack Tecnológico & Justificativas

### Backend

| Tecnologia | Versão | Por Que Escolhemos? |
|-----------|--------|---------------------|
| **Dart Frog** | 1.0+ | Framework web moderno para Dart. **Escolhido para manter stack unificada** (Dart no front e back), facilitando compartilhamento de código (modelos, validações) e reduzindo carga cognitiva de troca de contexto. Alternativas consideradas: Shelf (mais boilerplate), Serverpod (muito pesado). |
| **PostgreSQL** | 15+ | Banco relacional robusto. **Escolhido porque MTG tem dados estruturados** (cartas, decks, relações M:N). Suporte nativo a JSON (para logs de IA), arrays (cores de cartas) e índices complexos. |
| **BCrypt** | 1.1.3 | Hash de senhas com salt. **Escolhido por ser industry standard** para segurança. 10 rounds de salt balanceiam segurança e performance. |
| **JWT** | 2.12.0 | Tokens stateless para autenticação. **Escolhido para escalar horizontalmente** sem sessões no servidor. Tokens expiram em 24h por segurança. |
| **dotenv** | 4.0.0 | Gerenciamento de variáveis de ambiente. **Escolhido para separar config de código** (12-factor app). Nunca commitamos credenciais. |
| **http** | 1.2.1 | Cliente HTTP para APIs externas. **Usado para integração com Scryfall** (imagens de cartas) e OpenAI (IA generativa). |

### Frontend

| Tecnologia | Versão | Por Que Escolhemos? |
|-----------|--------|---------------------|
| **Flutter** | 3.7.2+ | Framework UI multiplataforma. **Escolhido para criar apps nativos** (iOS, Android, Desktop, Web) com single codebase. Performance nativa, hot reload rápido. |
| **Provider** | 6.1.5+ | State management simples. **Escolhido por ser oficial do Flutter team** e suficiente para app de médio porte. Alternativas: Riverpod (mais complexo), Bloc (mais boilerplate). |
| **GoRouter** | 17.0.0 | Navegação declarativa. **Escolhido para rotas type-safe** e deep linking. Suporta rotas protegidas (auth guard). |
| **Google Fonts** | 6.3.2 | Fontes customizadas. **Usado para identidade visual "Arcane Weaver"** (Poppins para títulos, Inter para corpo). |
| **Cached Network Image** | 3.4.1 | Cache de imagens. **Crítico para performance**: cartas MTG têm ~50KB cada, app pode ter centenas na tela. Cache evita re-downloads. |
| **fl_chart** | 1.1.1 | Gráficos interativos. **Usado para Curva de Mana e Distribuição de Cores**. Alternativa: charts_flutter (descontinuado). |

### Integrações Externas

- **MTGJSON** (https://mtgjson.com): Banco de dados completo de ~25.000 cartas MTG (gratuito, JSON)
- **Scryfall API** (https://scryfall.com/docs/api): Imagens de alta qualidade e preços de mercado
- **OpenAI GPT-4** (Opcional): Análise de sinergia e geração de decks criativos

---

## 🗂️ Estrutura de Pastas Detalhada

### Backend (`server/`)

```
server/
├── routes/                      # 📍 Rotas HTTP (estrutura = endpoints)
│   ├── index.dart              # GET / (welcome)
│   ├── auth/                   # 🔐 Autenticação
│   │   ├── login.dart          # POST /auth/login
│   │   └── register.dart       # POST /auth/register
│   ├── decks/                  # 🃏 Gerenciamento de decks
│   │   ├── index.dart          # GET/POST /decks (listar/criar)
│   │   ├── _middleware.dart    # Middleware de autenticação
│   │   └── [id]/               # Rotas dinâmicas por ID
│   │       ├── index.dart      # GET/PUT/DELETE /decks/:id
│   │       ├── analysis/       # GET /decks/:id/analysis (curva de mana)
│   │       ├── recommendations/# GET /decks/:id/recommendations (IA)
│   │       └── simulate/       # POST /decks/:id/simulate (batalha)
│   ├── cards/                  # 🔍 Busca de cartas
│   │   └── index.dart          # GET /cards?name=...&colors=...
│   ├── rules/                  # 📖 Regras do jogo
│   │   └── index.dart          # GET /rules
│   ├── ai/                     # 🤖 Endpoints de IA
│   │   ├── explain/            # POST /ai/explain (explicar carta)
│   │   ├── archetypes/         # POST /ai/archetypes (sugerir estratégias)
│   │   ├── optimize/           # POST /ai/optimize (melhorar deck)
│   │   └── generate/           # POST /ai/generate (criar deck do zero)
│   └── import/                 # 📥 Importar decks de texto
│       └── index.dart          # POST /import
│
├── lib/                        # 📚 Código compartilhado
│   ├── database.dart           # Singleton de conexão PostgreSQL
│   ├── auth_service.dart       # Lógica de autenticação (hash, JWT)
│   └── auth_middleware.dart    # Middleware para proteger rotas
│
├── bin/                        # 🛠️ Scripts utilitários
│   ├── setup_database.dart     # Cria schema inicial
│   ├── seed_database.dart      # Popula cartas do MTGJSON
│   ├── seed_rules.dart         # Popula regras do jogo
│   ├── migrate_*.dart          # Migrações de schema
│   └── demo_*.dart             # Scripts de demonstração
│
├── test/                       # ✅ Testes automatizados
│   ├── auth_service_test.dart  # 16 testes (hash, JWT)
│   ├── import_parser_test.dart # 35 testes (parser de decks)
│   ├── deck_validation_test.dart # 44 testes (regras de formato)
│   └── decks_crud_test.dart    # 14 testes de integração
│
├── .env                        # ⚙️ Variáveis de ambiente (NUNCA COMMITAR!)
├── .env.example                # Template de configuração
├── database_setup.sql          # Schema inicial do banco
├── pubspec.yaml                # Dependências Dart
└── manual-de-instrucao.md      # Documentação técnica detalhada
```

### Frontend (`app/`)

```
app/
├── lib/
│   ├── main.dart                    # 🚀 Entry point
│   │
│   ├── core/                        # 🧩 Código compartilhado
│   │   ├── api/
│   │   │   └── api_client.dart      # Cliente HTTP com auth headers
│   │   ├── theme/
│   │   │   └── app_theme.dart       # Tema "Arcane Weaver"
│   │   ├── utils/
│   │   │   └── mana_helper.dart     # Helpers para CMC, cores
│   │   └── widgets/
│   │       ├── loading_overlay.dart # Overlay de loading
│   │       └── error_dialog.dart    # Dialogs de erro
│   │
│   └── features/                    # 🎯 Features modulares
│       ├── auth/                    # 🔐 Autenticação
│       │   ├── models/
│       │   │   └── user_model.dart
│       │   ├── providers/
│       │   │   └── auth_provider.dart # Estado de autenticação
│       │   └── screens/
│       │       ├── splash_screen.dart # Animação inicial (3s)
│       │       ├── login_screen.dart
│       │       └── register_screen.dart
│       │
│       ├── home/                    # 🏠 Tela principal
│       │   └── screens/
│       │       └── home_screen.dart
│       │
│       ├── decks/                   # 🃏 Gerenciamento de decks
│       │   ├── models/
│       │   │   ├── deck_model.dart
│       │   │   └── deck_card_model.dart
│       │   ├── providers/
│       │   │   └── deck_provider.dart
│       │   ├── widgets/
│       │   │   ├── deck_card_widget.dart # Card de deck na lista
│       │   │   ├── mana_curve_chart.dart # Gráfico de curva
│       │   │   └── color_pie_chart.dart  # Gráfico de cores
│       │   └── screens/
│       │       ├── deck_list_screen.dart   # Lista de decks
│       │       ├── deck_details_screen.dart # Detalhes + análise
│       │       └── deck_builder_screen.dart # Criar/editar deck
│       │
│       └── cards/                   # 🔍 Busca de cartas
│           ├── models/
│           │   └── card_model.dart
│           └── screens/
│               ├── card_search_screen.dart
│               └── card_details_screen.dart
│
├── assets/                          # 📦 Assets estáticos
│   └── symbols/                     # Símbolos de mana SVG
│
├── pubspec.yaml                     # Dependências Flutter
└── README.md                        # Documentação (básica)
```

---

## 🔄 Fluxo de Dados (Como Funciona?)

### Exemplo: Usuário Cria um Deck

```
1. USER ACTION (Frontend)
   ↓
   DeckBuilderScreen (UI)
   User preenche formulário (nome, formato, cartas)
   ↓
   Pressiona botão "Salvar Deck"
   
2. STATE MANAGEMENT
   ↓
   DeckProvider.createDeck()
   Valida dados localmente (nome não vazio, etc)
   ↓
   setState(isLoading: true)
   
3. API CALL
   ↓
   ApiClient.post('/decks', body: {...})
   Headers: { Authorization: Bearer <token> }
   ↓
   HTTP POST → http://localhost:8080/decks
   
4. BACKEND PROCESSING
   ↓
   routes/decks/index.dart (Controller)
   ↓
   auth_middleware.dart (valida JWT)
   ↓
   Extrai userId do token
   ↓
   Valida regras de formato:
   - Commander: 1 cópia (exceto terrenos básicos)
   - Standard: 4 cópias
   ↓
   Verifica cartas banidas (card_legalities)
   ↓
   Database.connection.execute()
   INSERT INTO decks (...) RETURNING id
   INSERT INTO deck_cards (...) para cada carta
   ↓
   Commit transaction
   
5. RESPONSE
   ↓
   Response.json(statusCode: 200, body: {deck: {...}})
   ↓
   HTTP 200 OK
   ↓
   ApiClient retorna Map<String, dynamic>
   
6. STATE UPDATE
   ↓
   DeckProvider.createDeck() recebe resposta
   ↓
   Converte JSON → DeckModel
   ↓
   setState(decks: [...newDecks, deck])
   setState(isLoading: false)
   
7. UI UPDATE
   ↓
   Flutter rebuild widgets que usam DeckProvider
   ↓
   DeckListScreen mostra novo deck
   ↓
   Navigator.pop() volta para lista
```

### Exemplo: IA Explica uma Carta

```
USER: Clica em "Explicar" na carta "Lightning Bolt"
   ↓
Frontend: POST /ai/explain { cardName: "Lightning Bolt" }
   ↓
Backend: routes/ai/explain/index.dart
   ↓
Verifica cache: SELECT ai_description FROM cards WHERE name = 'Lightning Bolt'
   ↓
Se cache existe → retorna imediatamente
   ↓
Se não existe:
   ↓
   OpenAI API: POST https://api.openai.com/v1/chat/completions
   Prompt: "Explique a carta Lightning Bolt em termos de estratégia..."
   ↓
   GPT-4 responde com análise detalhada
   ↓
   Salva no cache: UPDATE cards SET ai_description = '...'
   ↓
   Retorna resposta
   ↓
Frontend: Mostra explicação em dialog
```

---

## ⚙️ Setup e Desenvolvimento

### Pré-requisitos

- **Flutter SDK:** 3.7.2+ ([Download](https://flutter.dev/docs/get-started/install))
- **Dart SDK:** 3.0+ (incluído no Flutter)
- **PostgreSQL:** 15+ ([Download](https://www.postgresql.org/download/))
- **Git:** Para clonar o repositório
- **Editor:** VS Code ou Android Studio (recomendado)

### Instalação Rápida (5 minutos)

#### 1. Clonar o Repositório
```bash
git clone https://github.com/softwarePredador/mtgia.git
cd mtgia
```

#### 2. Configurar Backend

```bash
cd server

# Instalar dependências
dart pub get

# Criar arquivo .env (copiar do template)
cp .env.example .env

# Editar .env com suas credenciais
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=mtgdb
# DB_USER=postgres
# DB_PASS=sua_senha
# JWT_SECRET=gere_com_openssl_rand_base64_48
# OPENAI_API_KEY=sk-... (opcional)

# Criar database no PostgreSQL
createdb mtgdb

# Rodar schema inicial
psql -d mtgdb -f database_setup.sql

# Popular cartas do MTGJSON (demora ~5 min)
dart run bin/seed_database.dart

# Popular regras do jogo
dart run bin/seed_rules.dart

# Iniciar servidor
dart_frog dev
# Servidor rodando em http://localhost:8080
```

#### 3. Configurar Frontend

```bash
cd ../app

# Instalar dependências
flutter pub get

# Rodar app (escolha uma plataforma)
flutter run                    # Android/iOS emulator
flutter run -d windows         # Desktop Windows
flutter run -d macos           # Desktop macOS
flutter run -d chrome          # Web
```

### Variáveis de Ambiente (Backend)

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `DB_HOST` | Host do PostgreSQL | `localhost` ou `143.198.230.247` |
| `DB_PORT` | Porta do PostgreSQL | `5432` |
| `DB_NAME` | Nome do database | `mtgdb` |
| `DB_USER` | Usuário do PostgreSQL | `postgres` |
| `DB_PASS` | Senha do PostgreSQL | `sua_senha_segura` |
| `JWT_SECRET` | Chave para assinar tokens JWT | Gere com `openssl rand -base64 48` |
| `OPENAI_API_KEY` | Chave da OpenAI (opcional) | `sk-proj-...` |
| `ENVIRONMENT` | Ambiente (dev/prod) | `development` |

---

## 🧪 Testes

### Backend

```bash
cd server

# Rodar todos os testes
dart test

# Rodar apenas testes unitários (rápido, sem dependências)
dart test test/auth_service_test.dart      # 16 testes
dart test test/import_parser_test.dart     # 35 testes
dart test test/deck_validation_test.dart   # 44 testes

# Rodar testes de integração (requer servidor rodando)
# Terminal 1:
dart_frog dev
# Terminal 2:
dart test test/decks_crud_test.dart        # 14 testes

# Ver cobertura (requer coverage package)
dart pub global activate coverage
dart test --coverage=coverage
genhtml -o coverage/html coverage/lcov.info
```

**Cobertura Atual:** ~80% (95 testes unitários passando)

### Frontend

```bash
cd app

# Rodar testes (quando implementados)
flutter test

# Testes de widget
flutter test test/widgets/

# Testes de integração
flutter drive --target=test_driver/app.dart
```

---

## 📚 Documentação Adicional

- **[ROADMAP.md](ROADMAP.md)** - Status atual, o que falta e próximas etapas
- **[server/manual-de-instrucao.md](server/manual-de-instrucao.md)** - Documentação técnica detalhada do backend
- **[server/test/README.md](server/test/README.md)** - Guia completo de testes
- **[AUDIT_REPORT.md](AUDIT_REPORT.md)** - Relatório de auditoria de código (24/11/2025)

---

## 🚀 Comandos Úteis

### Backend (Dart Frog)

```bash
# Desenvolvimento (hot reload)
dart_frog dev

# Build para produção
dart_frog build

# Rodar build
dart run build/bin/server.dart

# Executar scripts utilitários
dart run bin/seed_database.dart      # Popular cartas
dart run bin/update_prices.dart      # Atualizar preços
dart run bin/demo_auth.dart          # Testar autenticação
```

### Frontend (Flutter)

```bash
# Desenvolvimento
flutter run

# Build para release
flutter build apk              # Android
flutter build ipa              # iOS
flutter build windows          # Windows Desktop
flutter build web              # Web

# Análise estática
flutter analyze

# Formatar código
flutter format lib/
```

---

## 🛡️ Segurança

### Checklist de Segurança Implementado

- ✅ Senhas hasheadas com BCrypt (10 rounds de salt)
- ✅ JWT tokens com expiração (24h)
- ✅ Middleware de autenticação em rotas protegidas
- ✅ Validação de ownership (user só acessa seus próprios decks)
- ✅ Input validation em todos os endpoints POST/PUT
- ✅ SQL injection prevention (prepared statements)
- ✅ Variáveis de ambiente (.env não commitado)
- ✅ CORS configurado (production)

### Próximos Passos de Segurança

- ⏳ Rate limiting (prevenir brute force)
- ⏳ Refresh tokens (melhor UX)
- ⏳ HTTPS obrigatório em produção
- ⏳ Auditoria de dependências (Snyk)

---

## 🤝 Contribuindo

Este é um projeto privado, mas seguimos boas práticas:

1. **Branch Strategy:** `main` (produção) + feature branches
2. **Commit Convention:** [Conventional Commits](https://www.conventionalcommits.org/)
   - `feat:` nova funcionalidade
   - `fix:` correção de bug
   - `docs:` documentação
   - `test:` adição de testes
3. **Code Review:** Toda mudança passa por review
4. **Testes:** Cobertura mínima de 80% em código crítico

---

## 📝 License

Copyright © 2025 - ManaLoom. Todos os direitos reservados.

---

## 🙏 Créditos

- **MTGJSON** - Banco de dados de cartas
- **Scryfall** - Imagens e preços
- **OpenAI** - GPT-4 para análise de IA
- **Flutter Community** - Packages incríveis

---

**Desenvolvido com 💜 por um apaixonado por Magic: The Gathering**
