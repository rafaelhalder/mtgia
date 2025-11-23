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

### 🚧 **Em Desenvolvimento**
*Nenhuma feature em andamento no momento.*

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
| 5. Importação | 6 | ⏳ Pendente | Parser de texto |
| 6. IA Matemático | 7-8 | ⏳ Pendente | Curva, consistência |
| 7. IA LLM | 9-10 | ⏳ Pendente | Gerador criativo |
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

---

## 5. Implementações da API (Rotas)

### 5.1. Rota de Busca de Cartas (`GET /cards`)

**Local:** `routes/cards/index.dart`

**Objetivo:**
Fornecer um endpoint para o frontend e a IA pesquisarem cartas no banco de dados.

**Lógica e Padrões:**
1.  **Middleware de Conexão (`routes/_middleware.dart`):**
    -   **O que faz?** Intercepta todas as requisições. Na primeira, ele abre a conexão com o banco de dados e a mantém aberta.
    -   **Por que?** Evita o custo de abrir e fechar uma conexão a cada busca de carta. É muito mais performático.
    -   **Dependency Injection:** Ele "injeta" a conexão no contexto da requisição, para que a rota final (`index.dart`) possa simplesmente "pedir" por ela usando `context.read<Connection>()`.
2.  **Query Dinâmica (`_buildQuery`):**
    -   A função constrói a query SQL dinamicamente com base nos filtros passados na URL (ex: `?name=sol`).
    -   **Segurança:** Usa parâmetros nomeados (`@name`, `@limit`) para prevenir **SQL Injection**.
3.  **Paginação:**
    -   Aceita `?page=` e `?limit=` na URL.
    -   Retorna um número limitado de resultados, essencial para a performance do app.

**Exemplo de Uso:**
- `GET /cards` -> Retorna as primeiras 50 cartas.
- `GET /cards?name=sol&page=1&limit=10` -> Retorna os 10 primeiros resultados que contenham "sol" no nome.

### 5.2. Rota de Cadastro de Usuário (`POST /users/register`)

**Local:** `routes/users/register.dart`

**Objetivo:**
Permitir que novos usuários criem uma conta no sistema.

**Lógica e Padrões:**
1.  **Validação:** Verifica se `username`, `email` e `password` foram enviados no corpo (JSON) da requisição.
2.  **Segurança (Hashing):** Usa a biblioteca `bcrypt` para criar um hash da senha. **NUNCA** salvamos a senha original.
3.  **Inserção no Banco:** Insere o novo usuário na tabela `users`.
4.  **Tratamento de Erro:** Captura o erro específico do PostgreSQL para "violação de chave única" (`23505`) e retorna uma mensagem amigável (`409 Conflict`) se o email ou username já existirem.

**Exemplo de Uso (com uma ferramenta de API):**
- **Método:** `POST`
- **URL:** `http://localhost:8080/users/register`
- **Corpo (JSON):**
  ```json
  {
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }
  ```

### 5.3. Rota de Login de Usuário (`POST /users/login`)

**Local:** `routes/users/login.dart`

**Objetivo:**
Autenticar um usuário e fornecer um token de acesso para requisições futuras.

**Lógica e Padrões:**
1.  **Busca:** Procura o usuário no banco de dados pelo `email`.
2.  **Verificação de Senha:** Usa `BCrypt.checkpw()` para comparar a senha enviada com o hash salvo no banco. Isso é seguro, pois a senha original nunca é exposta.
3.  **Geração de Token (JWT):** Se a senha estiver correta, um JSON Web Token é gerado.
    -   **Payload:** O token contém o `id` do usuário.
    -   **Segredo:** O token é assinado com uma chave secreta (`JWT_SECRET`) definida no arquivo `.env`. Isso garante que apenas o nosso servidor pode criar tokens válidos.
    -   **Expiração:** O token expira em 7 dias, forçando o usuário a fazer login novamente após esse período.
4.  **Resposta:** O servidor devolve o token para o cliente (o app Flutter). O app deve salvar esse token e enviá-lo no cabeçalho `Authorization` de todas as requisições futuras que exigem autenticação.

**Exemplo de Uso:**
- **Método:** `POST`
- **URL:** `http://localhost:8080/users/login`
- **Corpo (JSON):**
  ```json
  {
    "email": "test@example.com",
    "password": "password123"
  }
  ```
- **Resposta de Sucesso:**
  ```json
  {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
  ```

### 5.4. Rota de Criação de Decks (`POST /decks`)

**Local:** `routes/decks/index.dart`

**Objetivo:**
Permitir que um usuário autenticado crie um novo deck.

**Lógica e Padrões:**
1.  **Autenticação via Middleware:** A rota é automaticamente protegida pelo `routes/decks/_middleware.dart`. Se o usuário não enviar um token válido, a requisição nem chega aqui. O ID do usuário é lido do contexto com `context.read<String>()`.
2.  **Transação de Banco de Dados:** A criação do deck e a inserção das cartas são envolvidas em uma transação (`conn.runTx`). Isso garante que, se a inserção de uma carta falhar, a criação do deck é desfeita (rollback). Ou tudo funciona, ou nada é salvo, mantendo o banco consistente.
3.  **Validação de Entrada:** Verifica se os campos essenciais (`name`, `format`, `cards`) foram enviados.

**Exemplo de Uso:**
- **Método:** `POST`
- **URL:** `http://localhost:8080/decks`
- **Cabeçalho (Header):**
  - `Authorization`: `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` (O token obtido no login)
- **Corpo (JSON):**
  ```json
  {
    "name": "My Awesome Deck",
    "format": "Commander",
    "description": "A deck for fun.",
    "cards": [
      { "card_id": "a3b4c5d6-...", "quantity": 1 },
      { "card_id": "e7f8g9h0-...", "quantity": 1 },
      { "card_id": "i1j2k3l4-...", "quantity": 98 }
    ]
  }
  ```

### 5.5. Rota de Busca de Regras (`GET /rules`)

**Local:** `routes/rules/index.dart`

**Objetivo:**
Permitir a busca textual nas regras oficiais do Magic: The Gathering.

**Lógica e Padrões:**
1.  **Busca Textual (ILIKE):** Utiliza o operador `ILIKE` do PostgreSQL para realizar buscas case-insensitive (ignora maiúsculas/minúsculas) tanto no título (número da regra) quanto na descrição.
2.  **Paginação Simples:** Utiliza o parâmetro `limit` para restringir o número de resultados retornados, evitando sobrecarga.
3.  **Sem Autenticação:** Esta rota é pública, pois as regras do jogo são de domínio público e essenciais para qualquer usuário.

**Exemplo de Uso:**
- **Método:** `GET`
- **URL:** `http://localhost:8080/rules?q=trample&limit=5`
- **Resposta:** Retorna uma lista JSON com as regras que contêm a palavra "trample".

### 5.6. Rota de Análise Matemática (`GET /decks/<id>/analysis`)

**Local:** `routes/decks/[id]/analysis/index.dart`

**Objetivo:**
Fornecer uma análise determinística e estatística do deck (Módulo 1 da IA).

**Lógica e Padrões:**
1.  **Cálculo de Curva de Mana:** Itera sobre todas as cartas, faz o parse do custo de mana (ex: `{2}{U}`) e conta a distribuição de Custo de Mana Convertido (CMC).
2.  **Distribuição de Cores:** Conta a frequência de cada símbolo de mana (W, U, B, R, G, C) para ajudar no ajuste da base de mana.
3.  **Validação de Legalidade:** Verifica cada carta contra a tabela `card_legalities` para o formato do deck. Retorna uma lista de cartas ilegais ou banidas.

**Exemplo de Uso:**
- **Método:** `GET`
- **URL:** `http://localhost:8080/decks/UUID-DO-DECK/analysis`
- **Resposta:** JSON contendo `mana_curve`, `color_distribution` e `legality`.

### 5.7. Rota de Recomendações com IA (`POST /decks/<id>/recommendations`)

**Local:** `routes/decks/[id]/recommendations/index.dart`

**Objetivo:**
Usar Inteligência Artificial Generativa (OpenAI GPT) para atuar como um "Consultor Criativo" (Módulo 2 da IA).

**Lógica e Padrões:**
1.  **Construção de Contexto:** Busca o nome, descrição e a lista completa de cartas do deck no banco de dados.
2.  **Engenharia de Prompt:** Monta um prompt detalhado para o LLM, instruindo-o a agir como um especialista em Magic e pedindo uma saída estritamente em JSON.
3.  **Integração OpenAI:** Envia o prompt para a API `chat/completions` e processa a resposta.
4.  **Output Estruturado:** A IA retorna:
    -   `suggestions`: Lista de cartas para adicionar.
    -   `cuts`: Lista de cartas para remover.
    -   `power_level`: Nota de 1 a 10.
    -   `analysis`: Texto explicativo.

### 5.8. Rota de Importação de Decks (`POST /import`)

**Local:** `routes/import/index.dart`

**Objetivo:**
Permitir a importação rápida de decks a partir de listas de texto (comuns em sites como MTGGoldfish, TappedOut) ou arrays JSON.

**Mudança de Rota:**
Originalmente localizada em `/decks/import`, a rota foi movida para `/import` (na raiz) para evitar conflitos de roteamento com a rota dinâmica `/decks/[id]`. O Dart Frog prioriza rotas dinâmicas, o que fazia com que requisições para `/decks/import` fossem capturadas incorretamente pelo handler de ID.

**Funcionalidades:**
- **Suporte a Formatos Flexíveis:** Aceita tanto uma string única (lista de texto) quanto um array JSON de strings ou objetos.
- **Detecção de Comandante:** Identifica o comandante através de:
    - Campo JSON explícito: `"commander": "Nome da Carta"`
    - Tags no texto: `[Commander]`, `*CMDR*`, `!Commander`
- **Regex Robusto:** Utiliza uma expressão regular ajustada para capturar nomes de cartas mesmo quando seguidos por códigos de edição entre parênteses (padrão Archidekt/Moxfield).
    - Regex: `r'^(\d+)x?\s+([^(]+)\s*(?:\(([\w\d]+)\))?.*$'`
    - Captura: Quantidade, Nome (até o primeiro parêntese) e Set Code (opcional).

**Exemplo de Payload Suportado:**
```json
{
  "name": "Meu Deck",
  "format": "commander",
  "list": [
    "1x Sol Ring (cmm)",
    "1x Arcane Signet (cmm)",
    "1x Atraxa, Praetors' Voice (2xm) *F* [Commander]"
  ]
}
```

### 3.7. Otimização de Performance e Fallback (`routes/import/index.dart`)

**Problema:**
A importação inicial era lenta (N+1 queries) e falhava em encontrar cartas duplas (Split Cards) ou com nomes ligeiramente diferentes no banco (ex: "Command Tower" vs "Command Tower // Command Tower").

**Solução Implementada:**
1.  **Batch Query (Leitura em Lote):** Em vez de buscar carta por carta, o sistema coleta todos os nomes e faz uma única consulta `SELECT ... WHERE name = ANY(@names)`.
2.  **Índice de Banco:** Adicionado índice `idx_cards_lower_name` para acelerar buscas case-insensitive.
3.  **Lógica de Fallback em 3 Níveis:**
    *   *Nível 1:* Busca Exata (Case-insensitive).
    *   *Nível 2:* Limpeza de Sufixos Numéricos (ex: "Forest 96" -> "Forest").
    *   *Nível 3:* Split Cards (ex: Se busca "Command Tower" e falha, tenta encontrar "Command Tower // %").
4.  **Bulk Insert (Escrita em Lote):** A inserção na tabela `deck_cards` agora é feita em um único comando SQL (`VALUES (...), (...), ...`), reduzindo o tempo de escrita de segundos para milissegundos.

**Resultado:**
Importação de decks de Commander (100 cartas) agora é praticamente instantânea e robusta contra variações de nome.

### 3.8. Visualização de Decks (`routes/decks/[id]/index.dart`)

**Funcionalidade:**
A rota `GET /decks/[id]` foi aprimorada para entregar os dados prontos para visualização no frontend, evitando processamento pesado no cliente.

**Estrutura da Resposta:**
```json
{
  "id": "...",
  "name": "Nome do Deck",
  "stats": {
    "total_cards": 100,
    "unique_cards": 65,
    "mana_curve": { "1": 5, "2": 12, "3": 8, "4": 4, "7+": 2 },
    "color_distribution": { "W": 10, "U": 15, "B": 20, "R": 0, "G": 12 }
  },
  "commander": [ { ...carta... } ],
  "main_board": {
    "Creature": [ ... ],
    "Land": [ ... ],
    "Instant": [ ... ],
    "Artifact": [ ... ],
    "Enchantment": [ ... ],
    "Planeswalker": [ ... ]
  },
  "all_cards_flat": [ ... ]
}
```

**Lógica de Agrupamento:**
- **Comandante:** Separado automaticamente baseado na flag `is_commander`.
- **Main Board:** Agrupado por `type_line` (prioridade: Land > Creature > Planeswalker > Artifact > Enchantment > Instant > Sorcery).
- **Estatísticas:**
    - *Curva de Mana:* Calculada somando os símbolos de mana no custo (ex: `{1}{U}{U}` = 3).
    - *Distribuição de Cores:* Contagem de símbolos coloridos em todas as cartas.

### 3.9. Análise e Legalidade (`routes/decks/[id]/analysis/index.dart`)

**Objetivo:**
Validar se um deck segue as regras estritas do formato (ex: Commander) e fornecer feedback imediato ao usuário sobre problemas (cartas banidas, tamanho incorreto, cópias excessivas).

**Endpoint:** `GET /decks/[id]/analysis`

**Lógica de Validação Implementada:**
1.  **Tamanho do Deck:** Verifica se o deck tem o número mínimo/exato de cartas (ex: 100 para Commander).
2.  **Limite de Cópias (Singleton):**
    - Regra: Em Commander, apenas 1 cópia de cada carta é permitida.
    - Exceção: Terrenos Básicos (Plains, Island, Swamp, Mountain, Forest, Wastes e suas variantes nevadas) podem ter qualquer quantidade.
3.  **Cartas Banidas:**
    - Consulta a tabela `card_legalities` para verificar o status de cada carta no formato do deck.
    - Reporta erro se `status == 'banned'`.
    - Reporta erro se `status == 'restricted'` e quantidade > 1.

**Otimização de Performance (Batch Query):**
Em vez de fazer 100 consultas ao banco para verificar a legalidade de cada carta (o problema "N+1"), fazemos uma única consulta usando o operador `ANY`:
```sql
SELECT card_id, status FROM card_legalities 
WHERE format = @format AND card_id = ANY(@ids)
```
Isso reduz drasticamente o tempo de resposta da análise.

**Resposta da API:**
Retorna um objeto JSON contendo:
- `is_valid`: Booleano indicando se o deck passou em todos os testes.
- `issues`: Lista de problemas encontrados (ex: `{"type": "error", "message": "\"Sol Ring\" is BANNED in standard."}`).
- `mana_curve` e `color_distribution`: Recalculados para uso em gráficos de análise.

### 3.10. Análise de Consistência (O "Técnico Virtual")

**Objetivo:**
Ir além das regras e ajudar o usuário a ganhar jogos, apontando falhas matemáticas na construção do deck.

**Métricas Implementadas:**
1.  **Custo de Mana Médio (Avg CMC):**
    - Calcula a média de custo de todas as cartas não-terreno.
    - *Por que importa?* Define a velocidade do deck.
2.  **Recomendação de Terrenos (Land Count Verdict):**
    - Usa uma fórmula heurística baseada em Frank Karsten: `Lands = 31 + (AvgCMC * 2.5)` (ajustado para Commander).
    - *Exemplo:* Se o deck tem média 3.0, precisa de ~38 terrenos. Se tiver 30, o sistema emite um **Aviso (Warning)** sugerindo adicionar mais.
    - *Diferencial:* Não impede o uso do deck (é um warning, não erro), mas educa o usuário sobre probabilidade.
3.  **Análise de Composição (Vegetables):**
    - Verifica se o deck tem os "vegetais" necessários para funcionar (Ramp, Draw, Removal).
    - *Heurística:* Busca palavras-chave no `oracle_text` (ex: "draw a card", "add {", "destroy target").
    - *Metas (Commander):*
        - Ramp: 10+
        - Draw: 10+
        - Removal: 8+
        - Board Wipes: 2+
    - *Aviso:* "Você tem apenas 2 cartas de compra. Recomendamos pelo menos 10 para não ficar sem mão."

### 3.11. Crawler de Meta Decks (`bin/fetch_meta.dart`)

**Objetivo:**
Criar uma base de dados de decks competitivos (Meta) para servir de referência para a IA.

**Fonte de Dados:**
- **MTGTop8:** Escolhido pela consistência, organização por arquétipos e facilidade de exportação em texto.

**Funcionamento do Script:**
1.  Acessa a página do formato (ex: `mtgtop8.com/format?f=EDH`).
2.  Identifica os últimos eventos (torneios).
3.  Entra em cada evento e lista os decks do Top 8.
4.  Usa o endpoint de exportação (`mtgtop8.com/mtgo?d=ID`) para baixar a lista de cartas em texto puro.
5.  Salva na tabela `meta_decks` evitando duplicatas (`source_url` único).

**Como Executar:**
```bash
# Para buscar decks de Commander (EDH)
dart run bin/fetch_meta.dart EDH

# Para buscar decks de Standard (ST)
dart run bin/fetch_meta.dart ST

# Para buscar TODOS os formatos (ST, MO, LE, VI, EDH, PAU, PI)
dart run bin/fetch_meta.dart ALL
```

**Formatos Suportados:**
- `ST`: Standard
- `MO`: Modern
- `LE`: Legacy
- `VI`: Vintage
- `EDH`: Commander
- `PAU`: Pauper
- `PI`: Pioneer

**Infraestrutura:**
Este script foi desenhado para rodar como uma **Cron Job** (tarefa agendada) no servidor de produção (ex: Digital Ocean), mantendo o banco sempre atualizado com o que está ganhando no mundo real.

### 3.12. Comparação com o Meta (Meta Insights)

**Objetivo:**
Usar os dados coletados pelo Crawler para dar conselhos práticos ao usuário.

**Algoritmo de Similaridade:**
1.  Busca os últimos 50 decks do formato no banco `meta_decks`.
2.  Compara as cartas do usuário com cada deck do meta usando o **Índice de Jaccard** (Interseção / União).
3.  Identifica o arquétipo mais próximo (ex: "Seu deck é 45% similar ao 'Rakdos Midrange'").
4.  **Sugestão de Staples:** Lista as cartas que estão no deck do Meta mas faltam no deck do usuário.

**Resultado:**
O usuário recebe: "Seu deck parece um 'Rakdos Midrange'. A maioria desses decks usa 'Fable of the Mirror-Breaker', mas você não tem. Considere adicionar."

### 3.13. IA Generativa (Deck Builder Automático)

**Objetivo:**
Criar decks completos a partir de uma descrição em linguagem natural, usando o conhecimento do Meta para evitar alucinações.

**Endpoint:** `POST /ai/generate`

**Fluxo de Dados (RAG - Retrieval Augmented Generation):**
1.  **Input:** Usuário pede "Deck agressivo de Goblins com Krenko".
2.  **Busca de Contexto:** O sistema busca na tabela `meta_decks` por decks que contenham "Goblin" ou "Krenko".
3.  **Prompt Engineering:** Montamos um prompt para a OpenAI contendo:
    - O pedido do usuário.
    - Exemplos reais de decks do meta (se encontrados).
    - Regras estritas de formato (JSON, 100 cartas, etc).
4.  **Geração:** A LLM (GPT-4o-mini) gera a lista de cartas.
5.  **Output:** Retorna o JSON pronto para ser importado pelo frontend.

**Segurança:**
A rota é protegida por JWT (`routes/ai/_middleware.dart`), garantindo que apenas usuários logados consumam créditos da API.

### 3.14. Simulador de Probabilidade (Monte Carlo)

**Objetivo:**
Responder à pergunta "Esse deck roda na prática?" sem precisar jogar uma partida inteira.

**Endpoint:** `GET /decks/[id]/simulate`

**Metodologia:**
O sistema executa **1.000 simulações** de mãos iniciais e dos primeiros 5 turnos.
1.  **Embaralhamento:** Usa `Random()` para ordenar o deck aleatoriamente.
2.  **Mão Inicial:** Compra 7 cartas e conta os terrenos.
3.  **Curva de Mana:** Simula compras turno a turno e verifica se há mana disponível para jogar mágicas na curva (Turno 1 = Custo 1, Turno 2 = Custo 2, etc).

**Métricas Geradas:**
- **Distribuição de Terrenos:** Probabilidade de começar com 0, 1, 2... 7 terrenos.
- **Risco de Mulligan:** Se a soma de mãos ruins (0, 1, 6, 7 terrenos) for alta (>30%), emite um alerta.
- **Probabilidade "On Curve":** Chance de ter uma jogada válida em cada um dos primeiros 5 turnos.

---

## 6. Guia para Desenvolvimento Futuro

### Como adicionar uma nova funcionalidade?
1.  **Defina a Rota:** Crie um arquivo em `routes/`. Ex: `routes/cards/index.dart` para listar cartas.
2.  **Acesse o Banco:** Importe `lib/database.dart` e use `Database().connection`.
3.  **Execute a Query:** Use `await connection.execute(...)`.
4.  **Retorne a Resposta:** Retorne um objeto `Response.json(...)`.

### Padrões de Clean Code a Seguir
- **Nomes Significativos:** Evite `var x = ...`. Use `final cardsList = ...`.
- **Funções Pequenas:** Se sua rota tem 100 linhas, extraia a lógica para uma classe em `lib/`. As rotas devem ser apenas "controladores" que recebem o pedido e devolvem a resposta.
- **Tratamento de Erros:** Sempre envolva chamadas de banco ou rede em `try-catch` para não derrubar o servidor se algo der errado.

---
*Última atualização: Criação do Manual e Configuração Inicial.*
