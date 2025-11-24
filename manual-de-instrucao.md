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
  - Cache de respostas da IA no banco de dados (`cards.ai_description`).
- [x] **Frontend:**
  - Botão "Explicar" nos detalhes da carta.
  - Botão "Otimizar Deck" na tela de detalhes.
  - Interface de seleção de arquétipos (Bottom Sheet).

### 🚧 **Em Desenvolvimento**
- [ ] **Aplicação de Otimização:** Transformar o deck baseado no arquétipo escolhido.
- [ ] **Gerador de Decks (Text-to-Deck):** Criar decks do zero via prompt.

### ❌ **Pendente (Próximas Implementações)**

#### **Backend (Prioridade Alta)**
1. **CRUD de Decks:**
   - [ ] `GET /decks` - Listar decks do usuário autenticado
   - [ ] `POST /decks` - Criar novo deck
   - [ ] `GET /decks/:id` - Detalhes de um deck
   - [ ] `PUT /decks/:id` - Atualizar deck
   - [ ] `DELETE /decks/:id` - Deletar deck
   - [ ] `GET /decks/:id/cards` - Listar cartas do deck

3. **Sistema de Cartas:**
   - [ ] `GET /cards` - Buscar cartas (com filtros)
   - [ ] `GET /cards/:id` - Detalhes de uma carta
   - [ ] Sistema de paginação para grandes resultados

4. **Validação de Decks:**
   - [ ] Endpoint para validar legalidade por formato
   - [ ] Verificação de cartas banidas/restritas

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
| 1. Fundação | 1 | ✅ Concluída | Auth mock, estrutura base, splash |
| 2. CRUD Core | 2 | 🎯 Próxima | Auth real, criar/editar decks |
| 3. Sistema de Cartas | 3-4 | ⏳ Pendente | Busca, adicionar cartas |
| 4. Validação e Preços | 5 | ⏳ Pendente | Legalidade, preços |
| 5. Importação | 6 | ✅ Concluída | Parser de texto |
| 6. IA Matemático | 7-8 | ✅ Concluída | Curva, consistência |
| 7. IA LLM | 9-10 | 🚧 Em Andamento | Gerador criativo, Otimizador |
| 8. IA Simulador | 11-12 | ⏳ Pendente | Monte Carlo |
| 9. Deploy | 13-14 | ⏳ Pendente | Produção |

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

### 3.18. Módulo 2: O Consultor Criativo (Em Andamento)

**Objetivo:**
Usar IA Generativa para explicar cartas e sugerir melhorias estratégicas nos decks.

**Funcionalidades Implementadas:**
1.  **Explicação de Cartas (`POST /ai/explain`):**
    - Recebe o nome e texto da carta.
    - Consulta a OpenAI para gerar uma explicação didática em PT-BR.
    - **Cache:** Salva a explicação na coluna `ai_description` da tabela `cards` para economizar tokens em requisições futuras.
2.  **Sugestão de Arquétipos (`POST /ai/archetypes`):**
    - Analisa um deck existente (Comandante + Lista).
    - Identifica 3 caminhos possíveis para otimização (ex: "Foco em Veneno", "Foco em Proliferar", "Superfriends").
    - Retorna JSON estruturado com Título, Descrição e Dificuldade.

**Próximos Passos:**
- Implementar a "transformação" do deck: quando o usuário escolhe um arquétipo, a IA deve sugerir quais cartas remover e quais adicionar para atingir aquele objetivo.