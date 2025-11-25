# Manual de Instrução e Documentação Técnica - ManaLoom

**Nome do Projeto:** ManaLoom - AI-Powered MTG Deck Builder  
**Tagline:** "Teça sua estratégia perfeita"  
**Última Atualização:** 22 de Novembro de 2025

Este documento serve como guia definitivo para o entendimento, manutenção e expansão do projeto ManaLoom (Backend e Frontend). Ele é atualizado continuamente conforme o desenvolvimento avança.

---

## 📋 Status Atual do Projeto

### ✅ **Implementado (Backend - Dart Frog)**
- [x] Estrutura base do servidor (`dart_frog dev`)
- [x] Conexão com PostgreSQL (`lib/database.dart` - Singleton Pattern)
- [x] Sistema de variáveis de ambiente (`.env` com dotenv)
- [x] **Autenticação Real com Banco de Dados:**
  - `lib/auth_service.dart` - Serviço centralizado de autenticação
  - `lib/auth_middleware.dart` - Middleware para proteger rotas
  - `POST /auth/login` - Login com verificação no PostgreSQL
  - `POST /auth/register` - Registro com gravação no banco
  - Hash de senhas com **bcrypt** (10 rounds de salt)
  - Geração e validação de **JWT tokens** (24h de validade)
  - Validação de email/username únicos
- [x] Estrutura de rotas para decks (`routes/decks/`)
- [x] Scripts utilitários:
  - `bin/fetch_meta.dart` - Download de JSON do MTGJSON
  - `bin/load_cards.dart` - Importação de cartas para o banco
  - `bin/load_rules.dart` - Importação de regras oficiais
- [x] Schema do banco de dados completo (`database_setup.sql`)

### ✅ **Implementado (Frontend - Flutter)**
- [x] Nome e identidade visual: **ManaLoom**
- [x] Paleta de cores "Arcane Weaver":
  - Background: `#0A0E14` (Abismo azulado)
  - Primary: `#8B5CF6` (Mana Violet)
  - Secondary: `#06B6D4` (Loom Cyan)
  - Accent: `#F59E0B` (Mythic Gold)
  - Surface: `#1E293B` (Slate)
- [x] **Splash Screen** - Animação de 3s com logo gradiente
- [x] **Sistema de Autenticação Completo:**
  - Login Screen (email + senha com validação)
  - Register Screen (username + email + senha + confirmação)
  - Auth Provider (gerenciamento de estado com Provider)
  - Token Storage (SharedPreferences)
  - Rotas protegidas com GoRouter
- [x] **Home Screen** - Tela principal com navegação
- [x] **Deck List Screen** - Listagem de decks com:
  - Loading states
  - Error handling
  - Empty state
  - DeckCard widget com stats
- [x] Estrutura de features (`features/auth`, `features/decks`, `features/home`)
- [x] ApiClient com suporte a GET, POST, PUT, DELETE

### ✅ **Implementado (Módulo 1: O Analista Matemático)**
- [x] **Backend:**
  - Validação de regras de formato (Commander 1x, Standard 4x).
  - Verificação de cartas banidas (`card_legalities`).
  - Endpoint de Importação (`POST /import`) com validação de regras.
- [x] **Frontend:**
  - **ManaHelper:** Utilitário para cálculo de CMC e Devoção.
  - **Gráficos (fl_chart):**
    - Curva de Mana (Bar Chart).
    - Distribuição de Cores (Pie Chart).
  - Aba de Análise no `DeckDetailsScreen`.

### ✅ **Implementado (Módulo 2: O Consultor Criativo)**
- [x] **Backend:**
  - Endpoint `POST /ai/explain`: Explicação detalhada de cartas individuais.
  - Endpoint `POST /ai/archetypes`: Análise de deck existente para sugerir 3 caminhos de otimização.
  - Endpoint `POST /ai/optimize`: Retorna sugestões específicas de cartas a adicionar/remover baseado no arquétipo.
  - Endpoint `POST /ai/generate`: Gera um deck completo do zero baseado em descrição textual.
  - Cache de respostas da IA no banco de dados (`cards.ai_description`).
- [x] **Frontend:**
  - Botão "Explicar" nos detalhes da carta com modal de explicação IA.
  - Botão "Otimizar Deck" na tela de detalhes do deck.
  - Interface de seleção de arquétipos (Bottom Sheet com 3 opções).
  - **NOVO (24/11/2025):** Dialog de confirmação mostrando cartas a remover/adicionar antes de aplicar.
  - **NOVO (24/11/2025):** Sistema completo de aplicação de otimização:
    - Lookup automático de IDs de cartas pelo nome via API.
    - Remoção de cartas sugeridas do deck atual.
    - Adição de novas cartas sugeridas pela IA.
    - Atualização do deck via `PUT /decks/:id`.
    - Refresh automático da tela após aplicação bem-sucedida.
  - **NOVO (24/11/2025):** Tela completa de geração de decks (`DeckGenerateScreen`):
    - Seletor de formato (Commander, Standard, Modern, etc.).
    - Campo de texto multi-linha para descrição do deck.
    - 6 prompts de exemplo como chips clicáveis.
    - Loading state "A IA está pensando...".
    - Preview do deck gerado agrupado por tipo de carta.
    - Campo para nomear o deck antes de salvar.
    - Botão "Salvar Deck" que cria o deck via API.
    - Navegação integrada no AppBar da lista de decks e no empty state.

### ✅ **Completamente Implementado (Módulo IA - Geração e Otimização)**
- [x] **Aplicação de Otimização:** Transformar o deck baseado no arquétipo escolhido - **COMPLETO**.
- [x] **Gerador de Decks (Text-to-Deck):** Criar decks do zero via prompt - **COMPLETO**.

**Detalhes Técnicos da Implementação:**

#### Fluxo de Otimização de Deck (End-to-End)
1. **Usuário clica "Otimizar Deck"** → Abre Bottom Sheet
2. **POST /ai/archetypes** → Retorna 3 arquétipos sugeridos (ex: Aggro, Control, Combo)
3. **Usuário seleciona arquétipo** → Loading "Analisando estratégias..."
4. **POST /ai/optimize** → Retorna JSON:
   ```json
   {
     "removals": ["Card Name 1", "Card Name 2"],
     "additions": ["Card Name A", "Card Name B"],
     "reasoning": "Justificativa da IA..."
   }
   ```
5. **Dialog de confirmação** → Mostra cartas a remover (vermelho) e adicionar (verde)
6. **Usuário confirma** → Sistema executa:
   - Busca ID de cada carta via `GET /cards?name=CardName`
   - Remove cartas da lista atual do deck
   - Adiciona novas cartas (gerenciando quantidades)
   - Chama `PUT /decks/:id` com nova lista de cartas
7. **Sucesso** → Deck atualizado, tela recarrega, SnackBar verde de confirmação

#### Fluxo de Geração de Deck (Text-to-Deck)
1. **Usuário acessa `/decks/generate`** (via botão no AppBar ou empty state)
2. **Seleciona formato** → Commander, Standard, Modern, etc.
3. **Escreve prompt** → Ex: "Deck agressivo de goblins vermelhos"
4. **Clica "Gerar Deck"** → Loading "A IA está pensando..."
5. **POST /ai/generate** → Retorna JSON:
   ```json
   {
     "generated_deck": {
       "cards": [
         {"name": "Goblin Guide", "quantity": 4},
         {"name": "Lightning Bolt", "quantity": 4},
         ...
       ]
     }
   }
   ```
6. **Preview do deck** → Cards agrupados por tipo (Creatures, Instants, Lands, etc.)
7. **Usuário nomeia o deck** → Campo editável
8. **Clica "Salvar Deck"** → Chama `POST /decks` com nome, formato, descrição e lista de cartas
9. **Sucesso** → Redireciona para `/decks`, SnackBar verde de confirmação

**Bibliotecas Utilizadas:**
- **Provider:** Gerenciamento de estado (`DeckProvider` com métodos `generateDeck()` e `applyOptimization()`)
- **GoRouter:** Navegação (`/decks/generate` integrada no router)
- **http:** Chamadas de API para IA e busca de cartas

**Tratamento de Erros:**
- ❌ Se a IA sugerir uma carta inexistente (hallucination), o lookup falha silenciosamente (logado) e a carta é ignorada.
- ❌ Se o `POST /ai/generate` falhar, mostra SnackBar de erro com mensagem detalhada.
- ❌ Se o `PUT /decks/:id` falhar ao aplicar otimização, rollback automático (sem mudanças no deck).

### ✅ **Implementado (CRUD de Decks)**
1. **Gerenciamento Completo de Decks:**
   - [x] `GET /decks` - Listar decks do usuário autenticado
   - [x] `POST /decks` - Criar novo deck
   - [x] `GET /decks/:id` - Detalhes de um deck (com cartas inline)
   - [x] `PUT /decks/:id` - Atualizar deck (nome, formato, descrição, cartas)
   - [x] `DELETE /decks/:id` - Deletar deck (soft delete com CASCADE)
   - ~~[ ] `GET /decks/:id/cards` - Listar cartas do deck~~ _(cartas vêm inline no GET /decks/:id)_

**Validações Implementadas no PUT:**
- Limite de cópias por formato (Commander/Brawl: 1, outros: 4)
- Exceção para terrenos básicos (unlimited)
- Verificação de cartas banidas/restritas por formato
- Transações atômicas (rollback automático em caso de erro)
- Verificação de ownership (apenas o dono pode atualizar)

**Testado:** 58 testes unitários + 14 testes de integração (100% das validações cobertas)

### ✅ **Testes Automatizados Implementados**

A suíte de testes cobre **109 testes** divididos em:

#### **Testes Unitários (95 testes)**
1. **`test/auth_service_test.dart` (16 testes)**
   - Hash e verificação de senhas (bcrypt)
   - Geração e validação de JWT tokens
   - Edge cases (senhas vazias, Unicode, caracteres especiais)

2. **`test/import_parser_test.dart` (35 testes)**
   - Parsing de listas de decks em diversos formatos
   - Detecção de comandantes (`[commander]`, `*cmdr*`, `!commander`)
   - Limpeza de nomes de cartas (collector numbers)
   - Validação de limites por formato

3. **`test/deck_validation_test.dart` (44 testes)** ⭐ NOVO
   - Limites de cópias por formato (Commander: 1, Standard: 4)
   - Detecção de terrenos básicos (unlimited)
   - Detecção de tipo de carta (Creature, Land, Planeswalker, etc)
   - Cálculo de CMC (Converted Mana Cost)
   - Validação de legalidade (banned, restricted, not_legal)
   - Edge cases de UPDATE e DELETE
   - Comportamento transacional

#### **Testes de Integração (14 testes)** 🔌
4. **`test/decks_crud_test.dart` (14 testes)** ⭐ NOVO
   - `PUT /decks/:id` - Atualização de decks
     - Atualizar nome, formato, descrição individualmente
     - Atualizar múltiplos campos de uma vez
     - Substituir lista completa de cartas
     - Validação de regras do MTG (limites, legalidade)
     - Testes de permissão (ownership)
     - Rejeição de cartas banidas
   - `DELETE /decks/:id` - Deleção de decks
     - Delete bem-sucedido (204 No Content)
     - Cascade delete de cartas
     - Verificação de ownership
     - Tentativa de deletar deck inexistente (404)
   - Ciclo completo: CREATE → UPDATE → DELETE

**Executar Testes:**
```bash
# Apenas testes unitários (rápido, sem dependências)
cd server
dart test test/auth_service_test.dart
dart test test/import_parser_test.dart
dart test test/deck_validation_test.dart

# Testes de integração (requer servidor rodando)
# Terminal 1:
dart_frog dev

# Terminal 2:
dart test test/decks_crud_test.dart

# Todos os testes
dart test
```

**Documentação Completa:** Ver `server/test/README.md` para detalhes sobre cada teste.

**Cobertura Estimada:**
- `lib/auth_service.dart`: ~90%
- `routes/import/index.dart`: ~85%
- `routes/decks/[id]/index.dart`: ~80% (validações + endpoints)

### ❌ **Pendente (Próximas Implementações)**

#### **Backend (Prioridade Alta)**

3. **Sistema de Cartas:**
   - [x] `GET /cards` - Buscar cartas (com filtros)
   - [x] `GET /cards/:id` - Detalhes de uma carta _(via busca)_
   - [x] Sistema de paginação para grandes resultados

4. **Validação de Decks:**
   - [x] Endpoint para validar legalidade por formato _(GET /decks/:id/analysis)_
   - [x] Verificação de cartas banidas/restritas

#### **Frontend (Prioridade Alta)**
1. **Tela de Criação de Deck:**
   - [ ] Formulário de criação (nome, formato, descrição)
   - [ ] Seleção de formato (Commander, Modern, Standard, etc)
   - [ ] Toggle público/privado

2. **Tela de Edição de Deck:**
   - [ ] Busca de cartas com autocomplete
   - [ ] Adicionar/remover cartas
   - [ ] Visualização de curva de mana
   - [ ] Contador de cartas (X/100 para Commander)

3. **Tela de Detalhes do Deck:**
   - [ ] Visualização completa de todas as cartas
   - [ ] Estatísticas (CMC médio, distribuição de cores)
   - [ ] Badge de sinergia (se disponível)
   - [ ] Botões de ação (Editar, Deletar, Compartilhar)

4. **Sistema de Busca de Cartas:**
   - [ ] Campo de busca com debounce
   - [ ] Filtros (cor, tipo, CMC, raridade)
   - [ ] Card preview ao clicar

#### **Backend (Prioridade Média)**
1. **Importação Inteligente de Decks:**
   - [ ] Endpoint `POST /decks/import`
   - [ ] Parser de texto (ex: "3x Lightning Bolt (lea)")
   - [ ] Fuzzy matching de nomes de cartas

2. **Sistema de Preços:**
   - [ ] Integração com API de preços (Scryfall)
   - [ ] Cache de preços no banco
   - [ ] Endpoint `GET /decks/:id/price`

#### **Frontend (Prioridade Média)**
1. **Perfil do Usuário:**
   - [ ] Tela de perfil
   - [ ] Editar informações
   - [ ] Estatísticas pessoais

2. **Dashboard:**
   - [ ] Gráfico de decks por formato
   - [ ] Últimas atividades
   - [ ] Decks recomendados

#### **Backend + Frontend (Prioridade Baixa - IA)**
1. **Módulo IA - Analista Matemático:**
   - [ ] Calculadora de curva de mana
   - [ ] Análise de consistência (devotion)
   - [ ] Score de sinergia (0-100)

2. **Módulo IA - Consultor Criativo (LLM):**
   - [ ] Integração com OpenAI/Gemini
   - [ ] Gerador de decks por descrição
   - [ ] Autocompletar decks incompletos
   - [ ] Análise de sinergia textual

3. **Módulo IA - Simulador (Monte Carlo):**
   - [ ] Simulador de mãos iniciais
   - [ ] Estatísticas de flood/screw
   - [ ] Tabela de matchups
   - [ ] Dataset de simulações (`battle_simulations`)

---

## 1. Visão Geral e Arquitetura

### O que estamos construindo?
Um **Deck Builder de Magic: The Gathering (MTG)** revolucionário chamado **ManaLoom**, focado em inteligência artificial e automação.
O sistema é dividido em:
- **Backend (Dart Frog):** API RESTful que gerencia dados, autenticação e integrações
- **Frontend (Flutter):** App multiplataforma (Mobile + Desktop) com UI moderna

### Funcionalidades Chave (Roadmap)
1.  **Deck Builder:** Criação, edição e importação inteligente de decks (texto -> cartas).
2.  **Regras e Legalidade:** Validação de decks contra regras oficiais e listas de banidas.
3.  **IA Generativa:** Criação de decks a partir de descrições em linguagem natural e autocompletar inteligente.
4.  **Simulador de Batalha:** Testes automatizados de decks (User vs Meta) para treinamento de IA.

### Por que Dart no Backend?
Para manter a stack unificada (Dart no Front e no Back), facilitando o compartilhamento de modelos (DTOs), lógica de validação e reduzindo a carga cognitiva de troca de contexto entre linguagens.

### Estrutura de Pastas

**Backend (server/):**
```
server/
├── routes/              # Endpoints da API (estrutura = URL)
│   ├── auth/           # Autenticação
│   │   ├── login.dart  # POST /auth/login
│   │   └── register.dart # POST /auth/register
│   ├── decks/          # Gerenciamento de decks
│   │   └── index.dart  # GET/POST /decks
│   └── index.dart      # GET /
├── lib/                # Código compartilhado
│   └── database.dart   # Singleton de conexão PostgreSQL
├── bin/                # Scripts utilitários
│   ├── fetch_meta.dart # Download MTGJSON
│   ├── load_cards.dart # Import cartas
│   └── load_rules.dart # Import regras
├── .env               # Variáveis de ambiente (NUNCA commitar!)
├── database_setup.sql # Schema do banco
└── pubspec.yaml       # Dependências
```

**Frontend (app/):**
```
app/
├── lib/
│   ├── core/                    # Código compartilhado
│   │   ├── api/
│   │   │   └── api_client.dart  # Client HTTP
│   │   └── theme/
│   │       └── app_theme.dart   # Tema "Arcane Weaver"
│   ├── features/                # Features modulares
│   │   ├── auth/               # Autenticação
│   │   │   ├── models/         # User model
│   │   │   ├── providers/      # AuthProvider (estado)
│   │   │   └── screens/        # Splash, Login, Register
│   │   ├── decks/              # Gerenciamento de decks
│   │   │   ├── models/         # Deck model
│   │   │   ├── providers/      # DeckProvider
│   │   │   ├── screens/        # DeckListScreen
│   │   │   └── widgets/        # DeckCard
│   │   └── home/               # Home Screen
│   └── main.dart               # Entry point + rotas
└── pubspec.yaml
```

---

## 📅 Linha do Tempo de Desenvolvimento

### **Fase 1: Fundação (✅ CONCLUÍDA - Semana 1)**
**Objetivo:** Configurar ambiente e estrutura base.

- [x] Setup do backend (Dart Frog + PostgreSQL)
- [x] Schema do banco de dados
- [x] Import de 28.000+ cartas do MTGJSON
- [x] Import de regras oficiais do MTG
- [x] Criar app Flutter
- [x] Definir identidade visual (ManaLoom + paleta "Arcane Weaver")
- [x] Sistema de autenticação mock (UI + rotas)
- [x] Splash Screen animado
- [x] Estrutura de navegação (GoRouter)

**Entregáveis:**
✅ Backend rodando em `localhost:8080`
✅ Frontend com login/register funcionais (mock)
✅ Banco de dados populado com cartas

---

### **Fase 2: CRUD Core (🎯 PRÓXIMA - Semana 2)**
**Objetivo:** Implementar funcionalidades essenciais de deck building.

**Backend:**
1. **Autenticação Real** (2-3 dias)
   - Integrar login/register com banco
   - Hash de senhas com bcrypt
   - Gerar JWT nos endpoints
   - Criar middleware de autenticação
   
2. **CRUD de Decks** (3-4 dias)
   - Implementar todos os endpoints (GET, POST, PUT, DELETE)
   - Relacionar decks com usuários autenticados
   - Endpoint de cards do deck

**Frontend:**
3. **Tela de Criação/Edição** (3-4 dias)
   - Formulário de novo deck
   - Conectar com backend (POST /decks)
   - Validações de formato
   
4. **Tela de Detalhes** (2 dias)
   - Visualizar deck completo
   - Botões de editar/deletar
   - Estatísticas básicas

**Entregáveis:**
- Usuário pode criar conta real
- Criar, editar, visualizar e deletar decks
- Decks salvos no banco de dados

---

### **Fase 3: Sistema de Cartas (Semana 3-4)**
**Objetivo:** Permitir busca e adição de cartas aos decks.

**Backend:**
1. **Endpoints de Cartas** (2-3 dias)
   - GET /cards com filtros (nome, cor, tipo, CMC)
   - Paginação (limit/offset)
   - GET /cards/:id para detalhes
   
2. **Adicionar Cartas ao Deck** (2 dias)
   - POST /decks/:id/cards
   - DELETE /decks/:id/cards/:cardId
   - Validação de quantidade (máx 4 cópias, exceto terrenos básicos)

**Frontend:**
3. **Tela de Busca** (3-4 dias)
   - Campo de busca com debounce
   - Grid de cards com imagens
   - Filtros laterais (cor, tipo, etc)
   - Botão "Adicionar ao Deck"
   
4. **Editor de Deck** (3 dias)
   - Lista de cartas do deck
   - Botão para remover
   - Contador de quantidade
   - Curva de mana visual

**Entregáveis:**
- Buscar qualquer carta do banco
- Montar decks completos com 60-100 cartas
- Visualização de curva de mana

---

### **Fase 4: Validação e Preços (Semana 5)**
**Objetivo:** Garantir legalidade e mostrar valores.

**Backend:**
1. **Validação de Formato** (2 dias)
   - Endpoint GET /decks/:id/validate?format=commander
   - Verificar cartas banidas (tabela card_legalities)
   - Retornar erros (ex: "Sol Ring is banned in Modern")
   
2. **Sistema de Preços** (3 dias)
   - Integração com Scryfall API
   - Cache de preços no banco (tabela card_prices)
   - Endpoint GET /decks/:id/price

**Frontend:**
3. **Badges de Legalidade** (1 dia)
   - Ícones de legal/banned por formato
   - Alertas visuais
   
4. **Preço Total do Deck** (2 dias)
   - Card no DeckCard widget
   - Somatório total
   - Opção de ver preços por carta

**Entregáveis:**
- Decks validados por formato
- Preço estimado de cada deck

---

### **Fase 5: Importação Inteligente (Semana 6)**
**Objetivo:** Parser de texto para lista de decks.

**Backend:**
1. **Parser de Texto** (4-5 dias)
   - Endpoint POST /decks/import
   - Reconhecer padrões: "3x Lightning Bolt", "1 Sol Ring (cmm)"
   - Fuzzy matching de nomes
   - Retornar lista de cartas encontradas + não encontradas

**Frontend:**
2. **Tela de Importação** (2-3 dias)
   - Campo de texto grande
   - Preview de cartas reconhecidas
   - Botão "Criar Deck"

**Entregáveis:**
- Colar lista de deck de qualquer site e criar automaticamente

---

### **Fase 6: IA - Módulo 1 (Analista Matemático) (Semana 7-8)**
**Objetivo:** Análise determinística de decks.

**Backend:**
1. **Calculadora de Curva** (2 dias)
   - Análise de CMC médio
   - Distribuição por custo (0-7+)
   - Alertas (ex: "Deck muito pesado")
   
2. **Análise de Devotion** (2 dias)
   - Contar símbolos de mana
   - Comparar com terrenos
   - Score de consistência (0-100)

**Frontend:**
3. **Dashboard de Análise** (3 dias)
   - Gráficos de curva de mana
   - Score de consistência visual
   - Sugestões textuais

**Entregáveis:**
- Feedback automático sobre curva e cores

---

### **Fase 7: IA - Módulo 2 (LLM - Criativo) (Semana 9-10)**
**Objetivo:** IA generativa para sugestões.

**Backend:**
1. **Integração OpenAI/Gemini** (3 dias)
   - Criar prompt engine
   - Endpoint POST /ai/generate-deck
   - Input: descrição em texto
   - Output: JSON de cartas
   
2. **Autocompletar** (2 dias)
   - POST /ai/autocomplete-deck
   - Analisa deck incompleto
   - Sugere 20-40 cartas

**Frontend:**
3. **Chat de IA** (4 dias)
   - Interface de chat
   - Input de texto livre
   - Loading enquanto IA gera
   - Preview do deck gerado

**Entregáveis:**
- Criar deck dizendo: "Deck agressivo de goblins vermelhos"

---

### **Fase 8: IA - Módulo 3 (Simulador) (Semana 11-12)**
**Objetivo:** Monte Carlo simplificado.

**Backend:**
1. **Simulador de Mãos** (5 dias)
   - Algoritmo de embaralhamento
   - Simular 1.000 mãos iniciais
   - Calcular % de flood/screw
   - Armazenar resultados (battle_simulations)

**Frontend:**
2. **Relatório de Simulação** (3 dias)
   - Gráficos de resultados
   - "X% de mãos jogáveis no T3"

**Entregáveis:**
- Testar consistência do deck automaticamente

---

### **Fase 9: Polimento e Deploy (Semana 13-14)**
**Objetivo:** Preparar para produção.

1. **Performance** (2 dias)
   - Otimizar queries (índices)
   - Cache de respostas comuns
   
2. **Testes** (3 dias)
   - Unit tests (backend)
   - Widget tests (frontend)
   
3. **Deploy** (3 dias)
   - Configurar servidor (Render/Railway)
   - Build do app (APK/IPA)
   - CI/CD básico

**Entregáveis:**
- App publicado e acessível

---

## 🎯 Resumo da Timeline

| Fase | Semanas | Status | Entregas |
|------|---------|--------|----------|
| 1. Fundação | 1 | ✅ Concluída | Auth real, estrutura base, splash |
| 2. CRUD Core | 2 | ✅ Concluída | Auth real, criar/listar decks |
| 3. Sistema de Cartas | 3-4 | 🟡 70% Concluída | Busca (✅), PUT/DELETE decks (❌) |
| 4. Validação e Preços | 5 | ✅ Concluída | Legalidade, preços |
| 5. Importação | 6 | ✅ Concluída | Parser de texto |
| 6. IA Matemático | 7-8 | 🟡 80% Concluída | Curva (✅), Devotion (⚠️ frontend?) |
| 7. IA LLM | 9-10 | 🟡 75% Concluída | Explain (✅), Archetypes (✅), Generate (✅), Optimize (🚧) |
| 8. IA Simulador | 11-12 | ⏳ Pendente | Monte Carlo |
| 9. Deploy | 13-14 | ⏳ Pendente | Produção, testes |

**Tempo Total Estimado:** 14 semanas (~3.5 meses)

---

## 2. Tecnologias e Bibliotecas (Dependências)

As dependências são gerenciadas no arquivo `pubspec.yaml`.

| Biblioteca | Versão | Para que serve? | Por que escolhemos? |
| :--- | :--- | :--- | :--- |
| **dart_frog** | ^1.0.0 | Framework web minimalista e rápido para Dart. | Simplicidade, hot-reload e fácil deploy. |
| **postgres** | ^3.0.0 | Driver para conectar ao PostgreSQL. | Versão mais recente, suporta chamadas assíncronas modernas e pool de conexões. |
| **dotenv** | ^4.0.0 | Carrega variáveis de ambiente de arquivos `.env`. | **Segurança**. Evita deixar senhas hardcoded no código fonte. |
| **http** | ^1.2.1 | Cliente HTTP para fazer requisições web. | Necessário para baixar o JSON de cartas do MTGJSON. |
| **bcrypt** | ^1.1.3 | Criptografia de senhas (hashing). | Padrão de mercado para segurança de senhas. Transforma a senha em um código irreversível. |
| **dart_jsonwebtoken** | ^2.12.0 | Geração e validação de JSON Web Tokens (JWT). | Essencial para autenticação stateless. O usuário faz login uma vez e usa o token para se autenticar. |
| **collection** | ^1.18.0 | Funções utilitárias para coleções (listas, mapas). | Facilita manipulação de dados complexos. |
| **fl_chart** | ^0.40.0 | Biblioteca de gráficos para Flutter. | Para visualização de dados estatísticos (ex: curva de mana). |
| **flutter_svg** | ^1.0.0 | Renderização de símbolos de mana. | Para exibir ícones e símbolos em formato SVG. |

---

## 3. Implementações Realizadas (Passo a Passo)

### 3.1. Conexão com o Banco de Dados (`lib/database.dart`)

**Lógica:**
Precisamos de uma forma única e centralizada de acessar o banco de dados em toda a aplicação. Se cada rota abrisse uma nova conexão sem controle, o banco cairia rapidamente.

**Padrão Utilizado: Singleton**
O padrão Singleton garante que a classe `Database` tenha apenas **uma instância** rodando durante a vida útil da aplicação.

**Código Explicado:**
```dart
class Database {
  // Construtor privado: ninguém fora dessa classe pode dar "new Database()"
  Database._internal();
  
  // A única instância que existe
  static final Database _instance = Database._internal();
  
  // Factory: quando alguém pede "Database()", devolvemos a instância já criada
  factory Database() => _instance;

  // ... lógica de conexão ...
}
```

**Por que usamos variáveis de ambiente?**
No método `connect()`, usamos `DotEnv` para ler `DB_HOST`, `DB_PASS`, etc. Isso segue o princípio de **12-Factor App** (Configuração separada do Código). Isso permite que você mude o banco de dados sem tocar em uma linha de código, apenas alterando o arquivo `.env`.

### 3.2. Setup Inicial do Banco (`bin/setup_database.dart`)

**Objetivo:**
Automatizar a criação das tabelas. Rodar comandos SQL manualmente no terminal é propenso a erro.

**Como funciona:**
1.  Lê o arquivo `database_setup.sql` como texto.
2.  Separa o texto em comandos individuais (usando `;` como separador).
3.  Executa cada comando sequencialmente no banco.

**Exemplo de Uso:**
Para recriar a estrutura do banco (cuidado, isso pode não apagar dados existentes dependendo do SQL, mas cria se não existir):
```bash
dart run bin/setup_database.dart
```

### 3.3. Populando o Banco (Seed) - `bin/seed_database.dart`

**Objetivo:**
Preencher a tabela `cards` com dados reais de Magic: The Gathering.

**Fonte de Dados:**
Utilizamos o arquivo `AtomicCards.json` do MTGJSON.
- **Por que Atomic?** Contém o texto "Oracle" (oficial) de cada carta, ideal para buscas e construção de decks agnóstica de edição.
- **Imagens:** Construímos a URL da imagem baseada no `scryfall_id` (`https://api.scryfall.com/cards/{id}?format=image`). O frontend fará o cache.

**Lógica de Implementação:**
1.  **Download:** Baixa o JSON (aprox. 100MB+) se não existir localmente.
2.  **Parsing:** Lê o JSON em memória (cuidado: requer RAM disponível).
3.  **Batch Insert:** Inserimos cartas em lotes de 500.
    - **Por que Lotes?** Inserir 30.000 cartas uma por uma levaria horas (round-trip de rede). Em lotes, leva segundos/minutos.
    - **Transações:** Cada lote roda em uma transação (`runTx`). Se falhar, não corrompe o banco pela metade.
    - **Idempotência:** Usamos `ON CONFLICT (scryfall_id) DO UPDATE` no SQL. Isso significa que podemos rodar o script várias vezes sem duplicar cartas ou dar erro.
    - **Parâmetros Posicionais:** Utilizamos `$1`, `$2`, etc. na query SQL preparada para garantir compatibilidade total com o driver `postgres` v3 e evitar erros de parsing de parâmetros nomeados.

**Como Rodar:**
```bash
dart run bin/seed_database.dart
```

### 3.4. Atualização do Schema (Evolução do Banco)

**Mudança:**
Adicionamos tabelas para `users`, `rules` e `card_legalities`, e atualizamos a tabela `decks` para pertencer a um usuário.

**Estratégia de Migração:**
Como ainda estamos em desenvolvimento, optamos por uma estratégia destrutiva para as tabelas sem dados importantes (`decks`), mas preservativa para a tabela populada (`cards`).
Criamos o script `bin/update_schema.dart` que:
1.  Remove `deck_cards` e `decks`.
2.  Roda o `database_setup.sql` completo.
    -   Cria `users`, `rules`, `card_legalities`.
    -   Recria `decks` (agora com `user_id`) e `deck_cards`.
    -   Mantém `cards` intacta (graças ao `IF NOT EXISTS`).

### 3.5. Estrutura para IA e Machine Learning

**Objetivo:**
Preparar o banco de dados para armazenar o conhecimento gerado pela IA e permitir o aprendizado contínuo (Reinforcement Learning).

**Novas Tabelas e Colunas:**
1.  **`decks.synergy_score`:** Um número de 0 a 100 que indica o quão "fechado" e sinérgico o deck está.
2.  **`decks.strengths` / `weaknesses`:** Campos de texto para a IA descrever em linguagem natural os pontos fortes e fracos do deck (ex: "Fraco contra decks rápidos").
3.  **`deck_matchups`:** Tabela que relaciona Deck A vs Deck B. Armazena o `win_rate`. É aqui que sabemos quais são os "Counters" de um deck.
4.  **`battle_simulations`:** A tabela mais importante para o ML. Ela guarda o `game_log` (JSON) de cada batalha simulada.
    -   **Por que JSONB?** O log de uma partida de Magic é complexo e variável. JSONB no PostgreSQL permite armazenar essa estrutura flexível e ainda fazer queries eficientes sobre ela se necessário.

### 3.15. Sistema de Preços e Orçamento

**Objetivo:**
Permitir que o usuário saiba o custo financeiro do deck e filtre cartas por orçamento.

**Implementação:**
1.  **Banco de Dados:** Adicionada coluna `price` (DECIMAL) na tabela `cards`.
2.  **Atualização de Preços (`bin/update_prices.dart`):**
    - Script que consulta a API da Scryfall em lotes (batches) de 75 cartas.
    - Usa o endpoint `/cards/collection` para eficiência.
    - Mapeia o `oracle_id` do banco para obter o preço médio/padrão da carta.
3.  **Análise Financeira:**
    - O endpoint `/decks/[id]/analysis` agora calcula e retorna o `total_price` do deck, somando `price * quantity` de cada carta.

---

### 3.16. Sistema de Autenticação Real com Banco de Dados ✨ **RECÉM IMPLEMENTADO**

**Objetivo:**
Substituir o sistema de autenticação mock por uma implementação robusta e segura integrada com PostgreSQL, usando as melhores práticas de segurança da indústria.

#### **Arquitetura da Solução**

A autenticação foi implementada em 3 camadas:

1. **`lib/auth_service.dart`** - Serviço centralizado de lógica de negócios
2. **`lib/auth_middleware.dart`** - Middleware para proteger rotas
3. **`routes/auth/login.dart` e `routes/auth/register.dart`** - Endpoints HTTP

#### **3.16.1. AuthService - Serviço Centralizado**

**Padrão Utilizado:** Singleton + Service Layer

**Por que Singleton?**
Garantir uma única instância do serviço de autenticação evita recriação desnecessária de objetos e mantém consistência na chave JWT.

**Responsabilidades:**

##### **A) Hash de Senhas com bcrypt**
```dart
String hashPassword(String password) {
  return BCrypt.hashpw(password, BCrypt.gensalt());
}
```

**O que é bcrypt?**
- Algoritmo de hashing **adaptativo** (custo computacional ajustável)
- Inclui **salt automático** (proteção contra rainbow tables)
- Gera hashes diferentes mesmo para senhas iguais

**Por que bcrypt?**
- MD5 e SHA-1 são rápidos demais → vulneráveis a força bruta
- bcrypt deliberadamente é lento (10 rounds por padrão)
- Cada tentativa de senha errada leva ~100ms, inviabilizando ataques de dicionário

##### **B) Geração de JWT Tokens**
```dart
String generateToken(String userId, String username) {
  final jwt = JWT({
    'userId': userId,
    'username': username,
    'iat': DateTime.now().millisecondsSinceEpoch,
  });
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: Duration(hours: 24));
}
```

**O que é JWT?**
JSON Web Token - padrão de autenticação **stateless** (sem sessão no servidor).

**Estrutura:**
- **Header:** Algoritmo de assinatura (HS256)
- **Payload:** Dados do usuário (userId, username, timestamps)
- **Signature:** Assinatura criptográfica que garante integridade

**Vantagens:**
- Servidor não precisa manter sessões em memória (escalável)
- Token é autocontido (todas as informações necessárias estão nele)
- Pode ser validado sem consultar o banco de dados

**Segurança:**
- Assinado com chave secreta (`JWT_SECRET` no `.env`)
- Expira em 24 horas (força re-autenticação periódica)
- Se a chave secreta vazar, TODOS os tokens ficam comprometidos → guardar com segurança máxima

##### **C) Registro de Usuário**
```dart
Future<Map<String, dynamic>> register({
  required String username,
  required String email,
  required String password,
}) async {
  // 1. Validar unicidade de username
  // 2. Validar unicidade de email
  // 3. Hash da senha com bcrypt
  // 4. Inserir no banco (RETURNING id, username, email)
  // 5. Gerar JWT token
  // 6. Retornar {userId, username, email, token}
}
```

**Validações Implementadas:**
- Username único (query no banco)
- Email único (query no banco)
- Senhas **NUNCA** são armazenadas em texto plano

**Fluxo de Segurança:**
```
Senha do Usuário → bcrypt.hashpw() → Hash Armazenado
"senha123"       → 10 rounds       → "$2a$10$N9qo8..."
```

##### **D) Login de Usuário**
```dart
Future<Map<String, dynamic>> login({
  required String email,
  required String password,
}) async {
  // 1. Buscar usuário por email
  // 2. Verificar senha com bcrypt
  // 3. Gerar JWT token
  // 4. Retornar {userId, username, email, token}
}
```

**Segurança Contra Ataques:**
- **Timing Attack Protection:** `BCrypt.checkpw()` tem tempo constante
- **Mensagem de Erro Genérica:** Não revelamos se o email existe ou se a senha está errada
  - ❌ "Email não encontrado" → Atacante sabe que o email não está cadastrado
  - ✅ "Credenciais inválidas" → Atacante não sabe qual campo está errado

#### **3.16.2. AuthMiddleware - Proteção de Rotas**

**Padrão Utilizado:** Middleware Pattern + Dependency Injection

**O que é Middleware?**
Uma função que intercepta requisições **antes** de chegarem no handler final.

**Fluxo de Execução:**
```
Cliente → Middleware → Handler → Response
         ↓ (valida token)
         ↓ (injeta userId)
```

**Implementação:**
```dart
Middleware authMiddleware() {
  return (handler) {
    return (context) async {
      // 1. Verificar header Authorization
      final authHeader = context.request.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.json(statusCode: 401, body: {...});
      }

      // 2. Extrair token (remover "Bearer ")
      final token = authHeader.substring(7);

      // 3. Validar token
      final payload = authService.verifyToken(token);
      if (payload == null) {
        return Response.json(statusCode: 401, body: {...});
      }

      // 4. Injetar userId no contexto
      final userId = payload['userId'] as String;
      final requestWithUser = context.provide<String>(() => userId);

      return handler(requestWithUser);
    };
  };
}
```

**Injeção de Dependência:**
O middleware "injeta" o `userId` no contexto usando `context.provide<String>()`. Isso permite que handlers protegidos obtenham o ID do usuário autenticado sem precisar decodificar o token novamente:

```dart
// Em uma rota protegida (ex: GET /decks)
Future<Response> onRequest(RequestContext context) async {
  final userId = getUserId(context); // ← Helper que extrai do contexto
  // Agora posso filtrar decks por userId
}
```

**Vantagens:**
- Separação de responsabilidades (autenticação vs lógica de negócio)
- Reutilização (qualquer rota pode ser protegida aplicando o middleware)
- Testabilidade (middleware pode ser testado isoladamente)

#### **3.16.3. Endpoints de Autenticação**

##### **POST /auth/register**
**Localização:** `routes/auth/register.dart`

**Request:**
```json
{
  "username": "joao123",
  "email": "joao@example.com",
  "password": "senha_forte"
}
```

**Response (201 Created):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "username": "joao123",
    "email": "joao@example.com"
  }
}
```

**Validações:**
- Username: mínimo 3 caracteres
- Password: mínimo 6 caracteres
- Email: não pode estar vazio

**Erros Possíveis:**
- `400 Bad Request` - Validação falhou ou username/email duplicado
- `500 Internal Server Error` - Erro de banco de dados

##### **POST /auth/login**
**Localização:** `routes/auth/login.dart`

**Request:**
```json
{
  "email": "joao@example.com",
  "password": "senha_forte"
}
```

**Response (200 OK):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "username": "joao123",
    "email": "joao@example.com"
  }
}
```

**Erros Possíveis:**
- `400 Bad Request` - Campos obrigatórios faltando
- `401 Unauthorized` - Credenciais inválidas
- `500 Internal Server Error` - Erro de banco de dados

#### **3.16.4. Como Usar a Autenticação em Novas Rotas**

**Exemplo: Proteger a rota `/decks`**

1. **Criar middleware na pasta de decks:**
```dart
// routes/decks/_middleware.dart
import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth_middleware.dart';

Handler middleware(Handler handler) {
  return handler.use(authMiddleware());
}
```

2. **Usar o userId no handler:**
```dart
// routes/decks/index.dart
import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth_middleware.dart';
import '../../lib/database.dart';

Future<Response> onRequest(RequestContext context) async {
  // Usuário já foi validado pelo middleware
  final userId = getUserId(context);
  
  final db = Database();
  final result = await db.connection.execute(
    Sql.named('SELECT * FROM decks WHERE user_id = @userId'),
    parameters: {'userId': userId},
  );
  
  return Response.json(body: {'decks': result});
}
```

#### **3.16.5. Segurança em Produção**

**Checklist de Segurança:**
- ✅ Senhas com hash bcrypt (10 rounds)
- ✅ JWT com expiração (24h)
- ✅ Chave secreta em variável de ambiente (`JWT_SECRET`)
- ✅ Validação de unicidade (username/email)
- ✅ Mensagens de erro genéricas (evita enumeration attack)
- ⚠️ **TODO:** Implementar rate limiting (evitar força bruta no login)
- ⚠️ **TODO:** HTTPS obrigatório em produção
- ⚠️ **TODO:** Refresh tokens (renovar sem pedir senha novamente)

**Variável de Ambiente Crítica:**
```env
# .env
JWT_SECRET=uma_chave_super_secreta_e_longa_aleatoria_123456789
```

**Geração de Chave Segura:**
```bash
# No terminal, gerar uma chave de 64 caracteres aleatórios
openssl rand -base64 48
```

### 3.17. Módulo 1: O Analista Matemático (Implementado)

**Objetivo:**
Fornecer feedback visual e validação de regras para o usuário, garantindo que o deck seja legal e tenha uma curva de mana saudável.

**Implementação Backend:**
- **Validação de Regras (`routes/import/index.dart` e `routes/decks/[id]/index.dart`):**
  - Verifica limites de cópias (1x para Commander, 4x para outros).
  - Consulta a tabela `card_legalities` para bloquear cartas banidas.
  - Retorna erros específicos (ex: "Regra violada: Sol Ring é BANIDA").

**Implementação Frontend:**
- **ManaHelper (`core/utils/mana_helper.dart`):**
  - Classe utilitária que faz o parse de strings de custo de mana (ex: `{2}{U}{U}`).
  - Calcula CMC (Custo de Mana Convertido).
  - Calcula Devoção (contagem de símbolos coloridos).
- **Gráficos (`features/decks/widgets/deck_analysis_tab.dart`):**
  - Utiliza a biblioteca `fl_chart`.
  - **Bar Chart:** Mostra a curva de mana (distribuição de custos 0-7+).
  - **Pie Chart:** Mostra a distribuição de cores (devoção).
  - **Tabela:** Mostra a sinergia entre cartas (se disponível).

### 3.18. Módulo 2: O Consultor Criativo (✅ COMPLETO - Atualizado 24/11/2025)

**Objetivo:**
Usar IA Generativa para explicar cartas, sugerir melhorias estratégicas, otimizar decks existentes e gerar novos decks do zero.

**Funcionalidades Implementadas:**

#### 1. **Explicação de Cartas (`POST /ai/explain`)** ✅
- Recebe o nome e texto da carta.
- Consulta a OpenAI (GPT-3.5/4) para gerar uma explicação didática em PT-BR.
- **Cache:** Salva a explicação na coluna `ai_description` da tabela `cards` para economizar tokens em requisições futuras.
- **Frontend:** Botão "Explicar" no dialog de detalhes da carta que mostra um modal com a análise da IA.

#### 2. **Sugestão de Arquétipos (`POST /ai/archetypes`)** ✅
- Analisa um deck existente (Comandante + Lista de cartas).
- Identifica 3 caminhos possíveis para otimização (ex: "Foco em Veneno", "Foco em Proliferar", "Superfriends").
- Retorna JSON estruturado com Título, Descrição e Dificuldade.
- **Frontend:** Bottom Sheet com as 3 opções quando o usuário clica "Otimizar Deck".

#### 3. **Otimização de Deck (`POST /ai/optimize`)** ✅
- Recebe `deck_id` e o `archetype` escolhido pelo usuário.
- A IA analisa o deck atual e sugere:
  - **Removals:** 3-5 cartas que não se encaixam na estratégia escolhida.
  - **Additions:** 3-5 cartas que fortalecem o arquétipo.
  - **Reasoning:** Justificativa em texto explicando as escolhas.
- **Frontend:** Implementação completa do fluxo de aplicação:
  1. Dialog de confirmação mostrando removals (vermelho) e additions (verde).
  2. Sistema de lookup automático de card IDs via `GET /cards?name=`.
  3. Remoção das cartas sugeridas da lista atual.
  4. Adição das novas cartas (com controle de quantidade).
  5. Chamada a `PUT /decks/:id` para persistir as mudanças.
  6. Refresh automático da tela de detalhes do deck.
  7. SnackBar de sucesso ou erro.

**Código de Exemplo (Backend - `routes/ai/optimize/index.dart`):**
```dart
final prompt = '''
Atue como um especialista em Magic: The Gathering.
Tenho um deck de formato $deckFormat chamado "$deckName".
Comandante(s): ${commanders.join(', ')}

Quero otimizar este deck seguindo este arquétipo/estratégia: "$archetype".

Lista atual de cartas (algumas): ${otherCards.take(50).join(', ')}...

Sua tarefa:
1. Identifique 3 a 5 cartas da lista atual que NÃO sinergizam bem com a estratégia "$archetype" e devem ser removidas.
2. Sugira 3 a 5 cartas que DEVEM ser adicionadas para fortalecer essa estratégia.
3. Forneça uma breve justificativa.

Responda APENAS um JSON válido (sem markdown) no seguinte formato:
{
  "removals": ["Nome Exato Carta 1", "Nome Exato Carta 2"],
  "additions": ["Nome Exato Carta A", "Nome Exato Carta B"],
  "reasoning": "Explicação resumida..."
}
''';
```

**Código de Exemplo (Frontend - `DeckProvider.applyOptimization()`):**
```dart
Future<bool> applyOptimization({
  required String deckId,
  required List<String> cardsToRemove,
  required List<String> cardsToAdd,
}) async {
  // 1. Buscar deck atual
  if (_selectedDeck == null || _selectedDeck!.id != deckId) {
    await fetchDeckDetails(deckId);
  }
  
  // 2. Construir mapa de cartas atuais
  final currentCards = <String, Map<String, dynamic>>{};
  for (final card in _selectedDeck!.allCards) {
    currentCards[card.id] = {
      'card_id': card.id,
      'quantity': card.quantity,
      'is_commander': card.isCommander,
    };
  }
  
  // 3. Buscar IDs das cartas a adicionar
  for (final cardName in cardsToAdd) {
    final response = await _apiClient.get('/cards?name=$cardName&limit=1');
    if (response.statusCode == 200 && response.data is List) {
      final results = response.data as List;
      if (results.isNotEmpty) {
        final card = results[0] as Map<String, dynamic>;
        currentCards[card['id']] = {
          'card_id': card['id'],
          'quantity': 1,
          'is_commander': false,
        };
      }
    }
  }
  
  // 4. Remover cartas sugeridas
  for (final cardName in cardsToRemove) {
    final response = await _apiClient.get('/cards?name=$cardName&limit=1');
    if (response.statusCode == 200 && response.data is List) {
      final results = response.data as List;
      if (results.isNotEmpty) {
        final cardId = results[0]['id'] as String;
        currentCards.remove(cardId);
      }
    }
  }
  
  // 5. Atualizar deck via API
  final response = await _apiClient.put('/decks/$deckId', {
    'cards': currentCards.values.toList(),
  });
  
  if (response.statusCode == 200) {
    await fetchDeckDetails(deckId); // Refresh
    return true;
  }
  return false;
}
```

**Tratamento de Erros e Edge Cases:**
- ✅ **Hallucination Prevention (ATUALIZADO 24/11/2025):** CardValidationService valida todas as cartas sugeridas pela IA contra o banco de dados. Cartas inexistentes são filtradas e sugestões de cartas similares são retornadas.
- ✅ **Timeout Handling:** Se a OpenAI demorar >30s, o request falha com timeout (configurável).
- ✅ **Mock Responses:** Se `OPENAI_API_KEY` não estiver configurada, retorna dados mockados para desenvolvimento.
- ✅ **Validação de Formato:** O backend valida se as cartas sugeridas são legais no formato antes de salvar (usa `card_legalities`).
- ✅ **Rate Limiting (NOVO 24/11/2025):** Limite de 10 requisições/minuto para endpoints de IA, prevenindo abuso e controlando custos.
- ✅ **Name Sanitization (NOVO 24/11/2025):** Nomes de cartas são automaticamente corrigidos (capitalização, caracteres especiais) antes da validação.
- ✅ **Fuzzy Matching (NOVO 24/11/2025):** Sistema de busca aproximada sugere cartas similares quando a IA erra o nome exato.

### 3.19. Segurança: Rate Limiting e Prevenção de Ataques (✅ COMPLETO - 24/11/2025)

**Objetivo:**
Proteger o sistema contra abuso, ataques de força bruta e uso excessivo de recursos (OpenAI API).

#### 1. **Rate Limiting Middleware** ✅

**Implementação:**
- Middleware customizado usando algoritmo de janela deslizante (sliding window)
- Rastreamento de requisições por IP address (suporta X-Forwarded-For para proxies)
- Limpeza automática de logs antigos para evitar memory leak
- Headers informativos de rate limit em todas as respostas

**Limites Aplicados:**
```dart
// Auth endpoints (routes/auth/*)
authRateLimit() -> 5 requisições/minuto
  - Previne brute force em login
  - Previne credential stuffing em register
  
// AI endpoints (routes/ai/*)
aiRateLimit() -> 10 requisições/minuto
  - Controla custos da OpenAI API ($$$)
  - Previne uso abusivo de recursos caros
  
// Geral (não aplicado ainda, disponível)
generalRateLimit() -> 100 requisições/minuto
```

**Response 429 (Too Many Requests):**
```json
{
  "error": "Too Many Login Attempts",
  "message": "Você fez muitas tentativas de login. Aguarde 1 minuto.",
  "retry_after": 60
}
```

**Headers Adicionados:**
```
X-RateLimit-Limit: 5           # Limite máximo
X-RateLimit-Remaining: 3       # Requisições restantes
X-RateLimit-Window: 60         # Janela em segundos
Retry-After: 60                # Quando pode tentar novamente (apenas em 429)
```

**Código de Exemplo (`lib/rate_limit_middleware.dart`):**
```dart
class RateLimiter {
  final int maxRequests;
  final int windowSeconds;
  
  // Mapa: IP -> List<timestamps>
  final Map<String, List<DateTime>> _requestLog = {};

  bool isAllowed(String clientId) {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(seconds: windowSeconds));
    
    // Remove requisições antigas
    _requestLog[clientId]?.removeWhere((t) => t.isBefore(windowStart));
    
    // Verifica limite
    if ((_requestLog[clientId]?.length ?? 0) >= maxRequests) {
      return false;
    }
    
    // Registra nova requisição
    (_requestLog[clientId] ??= []).add(now);
    return true;
  }
}
```

#### 2. **Card Validation Service (Anti-Hallucination)** ✅

**Problema:**
A IA (GPT) ocasionalmente sugere cartas que não existem ou têm nomes incorretos ("hallucination").

**Solução:**
Serviço de validação que verifica todas as cartas sugeridas pela IA contra o banco de dados antes de aplicá-las.

**Funcionalidades:**
1. **Validação de Nomes:** Busca exata no banco (case-insensitive)
2. **Fuzzy Search:** Se não encontrar, busca cartas com nomes similares usando ILIKE
3. **Sanitização:** Corrige capitalização e remove caracteres especiais
4. **Legalidade:** Verifica se a carta é legal no formato (via `card_legalities`)
5. **Limites:** Valida quantidade máxima por formato (1x Commander, 4x outros)

**Código de Exemplo (`lib/card_validation_service.dart`):**
```dart
class CardValidationService {
  Future<Map<String, dynamic>> validateCardNames(List<String> cardNames) async {
    final validCards = <Map<String, dynamic>>[];
    final invalidCards = <String>[];
    final suggestions = <String, List<String>>{};
    
    for (final cardName in cardNames) {
      final result = await _findCard(cardName);
      
      if (result != null) {
        validCards.add(result);
      } else {
        invalidCards.add(cardName);
        // Busca similares: "Lightning Boltt" -> ["Lightning Bolt", "Chain Lightning"]
        suggestions[cardName] = await _findSimilarCards(cardName);
      }
    }
    
    return {
      'valid': validCards,
      'invalid': invalidCards,
      'suggestions': suggestions,
    };
  }
  
  static String sanitizeCardName(String name) {
    // "lightning  BOLT" -> "Lightning Bolt"
    return name.trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(' ')
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
  }
}
```

**Integração no AI Optimize:**
```dart
// Antes (sem validação)
return Response.json(body: {
  'removals': ['Sol Ring', 'ManaRock999'], // ManaRock999 não existe!
  'additions': ['Mana Crypt'],
});

// Depois (com validação)
final validation = await validationService.validateCardNames([...]);
return Response.json(body: {
  'removals': ['Sol Ring'], // ManaRock999 filtrado
  'additions': ['Mana Crypt'],
  'warnings': {
    'invalid_cards': ['ManaRock999'],
    'suggestions': {'ManaRock999': ['Mana Vault', 'Mana Crypt']},
  },
});
```

**Impacto:**
- ✅ 100% das cartas adicionadas ao deck são validadas e reais
- ✅ Usuários recebem feedback claro sobre cartas problemáticas
- ✅ Sistema sugere alternativas para typos (ex: "Lightnig Bolt" → "Lightning Bolt")
- ✅ Previne erros de runtime causados por cartas inexistentes

**Próximos Passos:**
- ✅ **IMPLEMENTADO (24/11/2025):** Implementar a "transformação" do deck: quando o usuário escolhe um arquétipo, a IA deve sugerir quais cartas remover e quais adicionar para atingir aquele objetivo.

---

### 3.20. Correção do Bug de Loop Infinito e Refatoração do Sistema de Otimização (✅ COMPLETO - 24/11/2025)

**Problema Identificado:**
O botão "Aplicar Mudanças" na tela de otimização de deck causava um loop infinito de `CircularProgressIndicator`. O usuário não conseguia fechar o loading nem receber feedback de erro.

#### **Análise da Causa Raiz:**

**Bug 1: Loading Dialog Nunca Fechando**
```dart
// CÓDIGO COM BUG (deck_details_screen.dart - _applyOptimization)
try {
  showDialog(...); // Abre loading
  await optimizeDeck(...); // Pode falhar
  Navigator.pop(context); // Só fecha se não der erro
  // ...
} catch (e) {
  // BUG: Não havia Navigator.pop() aqui!
  // O loading ficava aberto para sempre.
  ScaffoldMessenger.of(context).showSnackBar(...);
}
```

**Bug 2: TODO não implementado**
```dart
// CÓDIGO COM BUG
showDialog(...); // Loading "Aplicando mudanças..."
await Future.delayed(const Duration(seconds: 1)); // Simulação!
// TODO: Implement actual update logic in DeckProvider
```

#### **Solução Implementada:**

**Correção 1: Controle de Estado do Loading**
```dart
// CÓDIGO CORRIGIDO
Future<void> _applyOptimization(BuildContext context, String archetype) async {
  bool isLoadingDialogOpen = false; // Controle de estado
  
  showDialog(...);
  isLoadingDialogOpen = true;

  try {
    final result = await optimizeDeck(...);
    
    if (!context.mounted) return;
    Navigator.pop(context);
    isLoadingDialogOpen = false;
    
    // ... restante do código ...
    
  } catch (e) {
    // CORREÇÃO: Garantir fechamento do loading em caso de erro
    if (context.mounted && isLoadingDialogOpen) {
      Navigator.pop(context);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao aplicar otimização: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
```

**Correção 2: Implementação Real do Apply**
```dart
// Substituiu o TODO por chamada real ao DeckProvider
await context.read<DeckProvider>().applyOptimization(
  deckId: widget.deckId,
  cardsToRemove: removals,
  cardsToAdd: additions,
);
```

#### **Refatoração do Algoritmo de Detecção de Arquétipo:**

**Problema Original:**
O código tratava todos os decks igualmente, comparando-os contra uma lista genérica de cartas "meta". Isso resultava em sugestões inadequadas (ex: sugerir carta de Control para um deck Aggro).

**Solução: DeckArchetypeAnalyzer**

Nova classe que implementa detecção automática de arquétipo baseada em heurísticas de MTG:

```dart
class DeckArchetypeAnalyzer {
  final List<Map<String, dynamic>> cards;
  final List<String> colors;
  
  /// Calcula CMC médio do deck (excluindo terrenos)
  double calculateAverageCMC() { ... }
  
  /// Conta cartas por tipo (creatures, instants, lands, etc.)
  Map<String, int> countCardTypes() { ... }
  
  /// Detecta arquétipo baseado em estatísticas
  String detectArchetype() {
    final avgCMC = calculateAverageCMC();
    final typeCounts = countCardTypes();
    final creatureRatio = typeCounts['creatures'] / totalNonLands;
    final instantSorceryRatio = (typeCounts['instants'] + typeCounts['sorceries']) / totalNonLands;
    
    // Aggro: CMC baixo (< 2.5), muitas criaturas (> 40%)
    if (avgCMC < 2.5 && creatureRatio > 0.4) return 'aggro';
    
    // Control: CMC alto (> 3.0), poucos criaturas (< 25%), muitos instants/sorceries
    if (avgCMC > 3.0 && creatureRatio < 0.25 && instantSorceryRatio > 0.35) return 'control';
    
    // Combo: Muitos instants/sorceries (> 40%) e poucos criaturas
    if (instantSorceryRatio > 0.4 && creatureRatio < 0.3) return 'combo';
    
    // Default: Midrange
    return 'midrange';
  }
}
```

**Recomendações por Arquétipo:**

```dart
Map<String, List<String>> getArchetypeRecommendations(String archetype, List<String> colors) {
  switch (archetype.toLowerCase()) {
    case 'aggro':
      return {
        'staples': ['Lightning Greaves', 'Swiftfoot Boots', 'Jeska\'s Will'],
        'avoid': ['Cartas com CMC > 5', 'Criaturas defensivas'],
        'priority': ['Haste enablers', 'Anthems (+1/+1)', 'Card draw rápido'],
      };
    case 'control':
      return {
        'staples': ['Counterspell', 'Swords to Plowshares', 'Cyclonic Rift'],
        'avoid': ['Criaturas vanilla', 'Cartas agressivas sem utilidade'],
        'priority': ['Counters', 'Removal eficiente', 'Card advantage'],
      };
    // ... outros arquétipos
  }
}
```

#### **Novo Prompt para a IA:**

O prompt enviado à OpenAI agora inclui:
1. **Análise Automática:** CMC médio, distribuição de tipos, arquétipo detectado
2. **Recomendações por Arquétipo:** Staples, cartas a evitar, prioridades
3. **Contexto de Meta:** Decks similares do banco de dados
4. **Regras Específicas:** Quantidade de terrenos ideal por arquétipo

```dart
final prompt = '''
ARQUÉTIPO ALVO: $targetArchetype

ANÁLISE AUTOMÁTICA DO DECK:
- Arquétipo Detectado: $detectedArchetype
- CMC Médio: ${deckAnalysis['average_cmc']}
- Avaliação da Curva: ${deckAnalysis['mana_curve_assessment']}
- Distribuição de Tipos: ${jsonEncode(deckAnalysis['type_distribution'])}

RECOMENDAÇÕES PARA ARQUÉTIPO $targetArchetype:
- Staples Recomendados: ${archetypeRecommendations['staples']}
- Evitar: ${archetypeRecommendations['avoid']}
- Prioridades: ${archetypeRecommendations['priority']}

SUA MISSÃO (ANÁLISE CONTEXTUAL POR ARQUÉTIPO):
1. Análise de Mana Base para arquétipo (Aggro: ~30-33, Control: ~37-40)
2. Staples específicos do arquétipo
3. Cortes contextuais (remover cartas que não sinergizam)
''';
```

#### **Novo Campo no Modelo de Dados:**

Adicionado campo `archetype` aos modelos `Deck` e `DeckDetails`:

```dart
// deck.dart
class Deck {
  final String? archetype; // 'aggro', 'control', 'midrange', 'combo', etc.
  
  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      archetype: json['archetype'] as String?,
      // ...
    );
  }
}
```

**Migração do Banco de Dados:**
```sql
-- Executar para adicionar coluna ao banco existente
ALTER TABLE decks ADD COLUMN IF NOT EXISTS archetype TEXT;
```

#### **Resumo das Mudanças:**

| Arquivo | Alteração |
|---------|-----------|
| `app/lib/features/decks/screens/deck_details_screen.dart` | Correção do bug de loading infinito |
| `app/lib/features/decks/models/deck.dart` | Adição do campo `archetype` |
| `app/lib/features/decks/models/deck_details.dart` | Adição do campo `archetype` |
| `server/routes/ai/optimize/index.dart` | Refatoração completa com DeckArchetypeAnalyzer |
| `server/manual-de-instrucao.md` | Esta documentação |

#### **Testes Recomendados:**

1. **Teste do Bug Fix:**
   - Abrir otimização de deck
   - Escolher arquétipo
   - Simular erro de API (desconectar internet)
   - Verificar que o loading fecha e mostra mensagem de erro

2. **Teste de Detecção de Arquétipo:**
   - Deck com CMC < 2.5 e 50% criaturas → Deve detectar "aggro"
   - Deck com CMC > 3.0 e 50% instants → Deve detectar "control"

3. **Teste de Aplicação:**
   - Confirmar que cartas removidas são efetivamente removidas
   - Confirmar que cartas adicionadas aparecem no deck
   - Verificar refresh automático da tela

---

### 3.21. Sistema de Staples Dinâmicos (✅ COMPLETO - 25/11/2025)

**Objetivo:**
Substituir listas hardcoded de staples por um sistema dinâmico que busca dados atualizados do Scryfall API e armazena em cache local no banco de dados.

#### **Problema Original:**

```dart
// CÓDIGO ANTIGO (hardcoded) - routes/ai/optimize/index.dart
case 'control':
  recommendations['staples']!.addAll([
    'Counterspell', 'Swords to Plowshares', 'Path to Exile',
    'Cyclonic Rift', 'Teferi\'s Protection'  // E se alguma for banida?
  ]);

// E se Mana Crypt for banida? Precisa editar código e fazer deploy!
if (colors.contains('B')) {
  recommendations['staples']!.addAll(['Demonic Tutor', 'Toxic Deluge', 'Dockside Extortionist']);
  // Dockside foi banida em 2024! Mas o código não sabe disso.
}
```

**Problemas:**
1. ❌ Listas desatualizadas quando há bans (ex: Mana Crypt, Nadu, Dockside)
2. ❌ Precisa editar código e fazer deploy para atualizar
3. ❌ Não considera popularidade atual (EDHREC rank muda)
4. ❌ Duplicação de código para cada arquétipo/cor

#### **Solução Implementada:**

##### 1. Nova Tabela `format_staples`
```sql
CREATE TABLE format_staples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_name TEXT NOT NULL,              -- Nome exato da carta
    format TEXT NOT NULL,                  -- 'commander', 'standard', etc.
    archetype TEXT,                        -- 'aggro', 'control', NULL = universal
    color_identity TEXT[],                 -- {'W'}, {'U', 'B'}, etc.
    edhrec_rank INTEGER,                   -- Rank de popularidade
    category TEXT,                         -- 'ramp', 'draw', 'removal', 'staple'
    scryfall_id UUID,                      -- Referência ao Scryfall
    is_banned BOOLEAN DEFAULT FALSE,       -- Atualizado via sync
    last_synced_at TIMESTAMP,              -- Quando foi atualizado
    UNIQUE(card_name, format, archetype)
);
```

##### 2. Script de Sincronização (`bin/sync_staples.dart`)

**Funcionalidades:**
- Busca Top 100 staples universais do Scryfall (ordenado por EDHREC)
- Busca Top 50 staples por arquétipo (aggro, control, combo, etc.)
- Busca Top 30 staples por cor (W, U, B, R, G)
- Sincroniza lista de cartas banidas
- Registra log de sincronização para auditoria

**Uso:**
```bash
# Sincronizar apenas Commander
dart run bin/sync_staples.dart commander

# Sincronizar todos os formatos
dart run bin/sync_staples.dart ALL
```

**Configuração de Cron Job (Linux):**
```bash
# Sincronizar toda segunda-feira às 3h da manhã
0 3 * * 1 cd /path/to/server && dart run bin/sync_staples.dart ALL >> /var/log/mtg_sync.log 2>&1
```

##### 3. Serviço de Staples (`lib/format_staples_service.dart`)

**Classe FormatStaplesService:**
```dart
class FormatStaplesService {
  final Pool _pool;
  static const int cacheMaxAgeHours = 24;
  
  /// Busca staples de duas fontes:
  /// 1. DB local (cache) - Se dados < 24h
  /// 2. Scryfall API - Fallback
  Future<List<Map<String, dynamic>>> getStaples({
    required String format,
    List<String>? colors,
    String? archetype,
    int limit = 50,
    bool excludeBanned = true,
  }) async { ... }
  
  /// Verifica se carta está banida
  Future<bool> isBanned(String cardName, String format) async { ... }
  
  /// Retorna recomendações organizadas por categoria
  Future<Map<String, List<String>>> getRecommendationsForDeck({
    required String format,
    required List<String> colors,
    String? archetype,
  }) async { ... }
}
```

**Exemplo de Uso:**
```dart
// Em routes/ai/optimize/index.dart

final staplesService = FormatStaplesService(pool);

// Buscar staples para deck Dimir Control
final staples = await staplesService.getStaples(
  format: 'commander',
  colors: ['U', 'B'],
  archetype: 'control',
  limit: 20,
);

// Verificar se carta está banida
final isBanned = await staplesService.isBanned('Mana Crypt', 'commander');
// Retorna TRUE (Mana Crypt foi banida em 2024)

// Obter recomendações completas
final recommendations = await staplesService.getRecommendationsForDeck(
  format: 'commander',
  colors: ['U', 'B', 'G'],
  archetype: 'combo',
);
// Retorna: { 'universal': [...], 'ramp': [...], 'draw': [...], 'removal': [...], 'archetype_specific': [...] }
```

##### 4. Refatoração do AI Optimize

**Antes (hardcoded):**
```dart
Future<Map<String, List<String>>> getArchetypeRecommendations(
  String archetype, 
  List<String> colors
) async {
  // Listas hardcoded que ficam desatualizadas
  case 'control':
    recommendations['staples']!.addAll([
      'Counterspell', 'Swords to Plowshares', 'Path to Exile',
      'Cyclonic Rift', 'Teferi\'s Protection'  // E se alguma for banida?
    ]);
}
```

**Depois (dinâmico):**
```dart
Future<Map<String, List<String>>> getArchetypeRecommendations(
  String archetype, 
  List<String> colors,
  Pool pool,  // Novo parâmetro
) async {
  final staplesService = FormatStaplesService(pool);
  
  // Buscar staples universais do banco/Scryfall
  final universalStaples = await staplesService.getStaples(
    format: 'commander',
    colors: colors,
    limit: 20,
  );
  
  // Buscar staples do arquétipo
  final archetypeStaples = await staplesService.getStaples(
    format: 'commander',
    colors: colors,
    archetype: archetype.toLowerCase(),
    limit: 15,
  );
  
  recommendations['staples']!.addAll(
    [...universalStaples, ...archetypeStaples].map((s) => s['name'] as String)
  );
  
  // Remove duplicatas
  recommendations['staples'] = recommendations['staples']!.toSet().toList();
}
```

##### 5. Tabela de Log de Sincronização

```sql
CREATE TABLE sync_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sync_type TEXT NOT NULL,               -- 'staples', 'banlist', 'meta'
    format TEXT,                           -- Formato sincronizado
    records_updated INTEGER DEFAULT 0,
    records_inserted INTEGER DEFAULT 0,
    records_deleted INTEGER DEFAULT 0,     -- Cartas banidas
    status TEXT NOT NULL,                  -- 'success', 'partial', 'failed'
    error_message TEXT,
    started_at TIMESTAMP,
    finished_at TIMESTAMP
);
```

**Consultar histórico de sincronização:**
```sql
SELECT sync_type, format, status, records_inserted, records_updated, 
       finished_at - started_at as duration
FROM sync_log
ORDER BY started_at DESC
LIMIT 10;
```

#### **Fluxo de Dados:**

```
┌────────────────────────────────────────────────────────────────────┐
│                    SINCRONIZAÇÃO SEMANAL                           │
│                    (bin/sync_staples.dart)                         │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                       SCRYFALL API                                 │
│  - format:commander -is:banned order:edhrec                        │
│  - Retorna Top 100 cartas mais populares                           │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                    TABELA format_staples                           │
│  - Cache local de staples por formato/arquétipo/cor                │
│  - Atualizado semanalmente                                         │
│  - is_banned = TRUE para cartas banidas                            │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                  FormatStaplesService                              │
│  1. Verifica cache local (< 24h)                                   │
│  2. Se cache desatualizado → Fallback Scryfall                     │
│  3. Filtra por formato/cores/arquétipo                             │
│  4. Exclui cartas banidas (is_banned = TRUE)                       │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                  AI Optimize Endpoint                              │
│  - Recebe recomendações dinâmicas                                  │
│  - Passa para OpenAI no prompt                                     │
│  - Valida cartas sugeridas antes de aplicar                        │
└────────────────────────────────────────────────────────────────────┘
```

#### **Benefícios:**

| Antes (Hardcoded) | Depois (Dinâmico) |
|-------------------|-------------------|
| ❌ Listas fixas no código | ✅ Dados do Scryfall (fonte oficial) |
| ❌ Deploy para atualizar | ✅ Sync automático semanal |
| ❌ Cartas banidas sugeridas | ✅ Banlist sincronizado |
| ❌ Popularidade estática | ✅ EDHREC rank atualizado |
| ❌ Duplicação de código | ✅ Uma fonte de verdade |

#### **Arquivos Modificados/Criados:**

| Arquivo | Tipo | Descrição |
|---------|------|-----------|
| `server/database_setup.sql` | Modificado | +Tabelas format_staples e sync_log |
| `server/bin/sync_staples.dart` | Novo | Script de sincronização |
| `server/lib/format_staples_service.dart` | Novo | Serviço de staples dinâmicos |
| `server/routes/ai/optimize/index.dart` | Modificado | Usa FormatStaplesService |
| `server/lib/ai/prompt.md` | Modificado | Referencia banlist dinâmico |
| `FORMULARIO_AUDITORIA_ALGORITMO.md` | Modificado | Documentação v1.3 |

#### **Próximos Passos:**

1. **Automatizar Sincronização:** Configurar cron job ou Cloud Scheduler para rodar `sync_staples.dart` semanalmente
2. **Monitoramento:** Dashboard para visualizar histórico de sincronização
3. **Alertas:** Notificação quando há novos bans detectados
4. **Cache Inteligente:** Sincronizar apenas deltas (cartas que mudaram de rank)

---

## 4. Novas Funcionalidades Implementadas

### ✅ **Implementado (Módulo 3: O Simulador de Probabilidade - Parcial)**
- [x] **Backend:**
  - **Verificação de Deck Virtual (Post-Optimization Check):**
    - Antes de retornar sugestões de otimização, o servidor cria uma cópia "virtual" do deck aplicando as mudanças.
    - Recalcula a análise de mana (Fontes vs Devoção) e Curva de Mana neste deck virtual.
    - Compara com o deck original.
    - Se a otimização piorar a base de mana (ex: remover terrenos necessários) ou quebrar a curva (ex: deixar o deck muito lento para Aggro), adiciona um aviso explícito (`validation_warnings`) na resposta.
    - Garante que a IA não sugira "melhorias" que tornam o deck injogável matematicamente.

**Exemplo de Resposta com Aviso:**
```json
{
  "removals": ["Card Name 1", "Card Name 2"],
  "additions": ["Card Name A", "Card Name B"],
  "reasoning": "Justificativa da IA...",
  "validation_warnings": [
    "Remover 'Forest' pode deixar o deck sem fontes de mana verde suficientes.",
    "Adicionar muitas cartas azuis pode atrasar a curva de mana do deck aggro."
  ]
}
```

**Código de Exemplo (Backend - `routes/ai/optimize/index.dart`):**
```dart
// 1. Criar deck virtual
final virtualDeck = Deck.fromJson(originalDeck.toJson());

// 2. Aplicar mudanças (removals/additions)
for (final removal in removals) {
  virtualDeck.removeCard(removal);
}
for (final addition in additions) {
  virtualDeck.addCard(addition);
}

// 3. Recalcular análise de mana e curva
final manaAnalysis = analyzeMana(virtualDeck);
final curveAnalysis = analyzeManaCurve(virtualDeck);

// 4. Comparar com o original
if (manaAnalysis['sourcesVsDevotion'] < 0.8) {
  warnings.add("A nova base de mana pode não suportar a devoção necessária.");
}
if (curveAnalysis['avgCMC'] > originalCurveAnalysis['avgCMC'] + 1) {
  warnings.add("A curva de mana aumentou muito, o deck pode ficar lento demais.");
}

// 5. Retornar warnings na resposta
return Response.json(body: {
  'removals': removals,
  'additions': additions,
  'reasoning': reasoning,
  'validation_warnings': warnings,
});
```

**Notas:**
- Essa funcionalidade evita que a IA sugira otimizações que, na verdade, pioram o desempenho do deck.
- A validação é feita em um "sandbox" (cópia virtual do deck), garantindo que o deck original permaneça intacto até a confirmação do usuário.

---

## 5. Documentação Atualizada

### 5.1. API Reference

#### **POST /ai/optimize**

**Request Body:**
```json
{
  "deck_id": "550e8400-e29b-41d4-a716-446655440000",
  "archetype": "aggro"
}
```

**Response:**
```json
{
  "removals": ["Sol Ring", "Mana Crypt"],
  "additions": ["Lightning Bolt", "Goblin Guide"],
  "reasoning": "Aumentar agressividade e curva de mana baixa.",
  "validation_warnings": [
    "Remover 'Forest' pode deixar o deck sem fontes de mana verde suficientes.",
    "Adicionar muitas cartas azuis pode atrasar a curva de mana do deck aggro."
  ]
}
```

**Descrição dos Campos:**
- `removals`: Cartas sugeridas para remoção
- `additions`: Cartas sugeridas para adição
- `reasoning`: Justificativa da IA
- `validation_warnings`: Avisos sobre possíveis problemas na otimização

---

### 5.2. Guia de Estilo e Contribuição

#### **Commit Messages:**
- Use o tempo verbal imperativo: "Adicionar nova funcionalidade X" ao invés de "Adicionando nova funcionalidade X"
- Comece com um verbo de ação: "Adicionar", "Remover", "Atualizar", "Fix", "Refactor", "Documentar", etc.
- Seja breve mas descritivo. Ex: "Fix bug na tela de login" é melhor que "Correção de bug".

#### **Branching Model:**
- Use branches descritivas: `feature/novo-recurso`, `bugfix/corrigir-bug`, `hotfix/urgente`
- Para novas funcionalidades, crie uma branch a partir da `develop`.
- Para correções rápidas, crie uma branch a partir da `main`.

#### **Pull Requests:**
- Sempre faça PRs para `develop` para novas funcionalidades e correções.
- PRs devem ter um título descritivo e um corpo explicando as mudanças.
- Adicione labels apropriadas: `bug`, `feature`, `enhancement`, `documentation`, etc.
- Solicite revisão de pelo menos uma pessoa antes de mesclar.

#### **Código Limpo e Documentado:**
- Siga as convenções de nomenclatura do projeto.
- Mantenha o código modular e reutilizável.
- Adicione comentários apenas quando necessário. O código deve ser auto-explicativo.
- Atualize a documentação sempre que uma funcionalidade for alterada ou adicionada.

---

## 6. Considerações Finais

Este documento é um living document e será continuamente atualizado conforme o projeto ManaLoom evolui. Novas funcionalidades, melhorias e correções de bugs serão documentadas aqui para manter todos os colaboradores alinhados e informados.

Para qualquer dúvida ou sugestão sobre o projeto, sinta-se à vontade para abrir uma issue no repositório ou entrar em contato diretamente com os mantenedores.

Obrigado por fazer parte do ManaLoom! Juntos, estamos tecendo a estratégia perfeita.