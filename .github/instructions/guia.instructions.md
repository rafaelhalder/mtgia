---
applyTo: '**'
---
# Guia de Desenvolvimento e Instruções do Projeto MTG Deck Builder

Este arquivo define as regras estritas, a filosofia e o fluxo de trabalho para o desenvolvimento deste projeto.

## ⚠️ Estado Atual (importante para manutenção)
Este repositório é **full-stack**:
- `app/`: Flutter (Provider + GoRouter) consumindo API HTTP em `http://localhost:8080` (ou `10.0.2.2:8080` no Android emulator).
- `server/`: Dart Frog + PostgreSQL (JWT + validações de deck + endpoints de IA).

### Pontos críticos identificados (dev/QA)
- **POST /decks**: cartas devem ser enviadas por **ID** (`card_id`). Se o fluxo tiver só `name`, ele precisa resolver para IDs via `/cards?name=...` (ou o backend precisa aceitar `name` como fallback).
- **Deep link /decks/:id/search**: “Adicionar carta” deve funcionar mesmo se o deck ainda não foi carregado no provider (garantir `fetchDeckDetails`).
- **Rate limiting em auth**: em dev/test, limites agressivos podem bloquear QA e a suíte de testes (especialmente quando o identificador cai em `anonymous` por ausência de IP/headers).
- **IA (OpenAI)**: manter comportamento consistente entre endpoints (fallback/mock em dev quando `OPENAI_API_KEY` não estiver configurada, para não quebrar UI).
- **Atualização de cartas (novas coleções)**:
  - Script oficial: `server/bin/sync_cards.dart` (idempotente, usa checkpoint em `sync_state`).
  - Fluxo recomendado: incremental (`dart run bin/sync_cards.dart`) + cron diário.
  - Quando não existir checkpoint mas o banco já tiver cartas, usar fallback `--since-days=<N>` (default: 45) ou rodar full (`--full`).
  - `--full` processa `AtomicCards.json` (grande) — evitar rodar em loops/CI sem necessidade.

## 1. Objetivo do Projeto
Desenvolver um aplicativo de Deck Builder de Magic: The Gathering (MTG) revolucionário, focado em inteligência artificial e automação.

### Funcionalidades Principais (Core):
1.  **Deck Builder Completo:**
    *   Cadastro de usuários e decks pessoais (privados ou públicos).
    *   Cópia de decks públicos/online.
    *   **Importação Inteligente:** Capacidade de importar listas de texto (ex: "1x Sol Ring (cmm)") e reconhecer automaticamente as cartas.
2.  **Regras e Legalidade:**
    *   Tabela completa de regras do jogo para consulta.
    *   Sistema de verificação de cartas banidas por formato (Commander, Standard, etc.), atrelado à tabela de cartas.
3.  **Diferencial com IA (Machine Learning):**
    *   **Criação por Descrição:** Usuário descreve o deck (ex: "Deck agressivo de goblins vermelhos") e a IA monta.
    *   **Autocompletar:** Identificar o tema de um deck incompleto e sugerir as melhores cartas para finalizar.
    *   **Análise de Sinergia:** O sistema calcula um `synergy_score` (0-100) e identifica pontos fortes/fracos.
    *   **Aprendizado Contínuo:** A IA aprende a "malícia" do jogo através de simulações de batalha.
4.  **Simulador de Batalha (Auto-Testing):**
    *   Simular batalhas entre dois decks (ex: Deck do Usuário vs. Deck Meta) automaticamente.
    *   **Counters:** Identificar quais decks ganham de quais (Matchups) e sugerir estratégias.
    *   **Treinamento:** Usar os logs dessas simulações (`game_log`) para treinar a IA (Reinforcement Learning).
5.  **Social & Trading:**
    *   **Comunidade:** Decks públicos, busca de usuários, sistema de follow/feed.
    *   **Fichário (Binder):** Coleção pessoal de cartas com condição, marcação para troca/venda e preço.
    *   **Marketplace:** Busca global de cartas disponíveis para troca/venda entre todos os usuários.
    *   **Trades:** Propostas de negociação com fluxo de status (pending→accepted→shipped→delivered→completed), chat interno, upload de comprovantes, código de rastreio.
    *   **Mensagens:** Chat direto entre jogadores.
    *   **Notificações:** Alertas de novos seguidores, propostas de trade, mudanças de status.
    *   **📋 Roadmap detalhado:** `ROADMAP_SOCIAL_TRADES.md` (documento único de referência — consultar ANTES de implementar qualquer task desse módulo).

## 2. Estrutura de Dados (Schema Atual)
Para garantir consistência, consulte sempre as colunas existentes antes de criar queries.

### Tabela: `users`
- `id` (UUID): PK.
- `username` (TEXT): Nome de usuário único.
- `email` (TEXT): Email único.
- `password_hash` (TEXT): Hash da senha.
- `display_name` (TEXT): Nick público opcional.
- `avatar_url` (TEXT): URL do avatar.

### Tabela: `cards` (Todas as cartas do jogo)
- `id` (UUID): PK.
- `scryfall_id` (UUID): ID único oficial da carta (Oracle ID).
- `name` (TEXT): Nome da carta.
- `mana_cost` (TEXT): Custo de mana (ex: {2}{U}{U}).
- `type_line` (TEXT): Tipo da carta (ex: Creature — Human Wizard).
- `oracle_text` (TEXT): Texto de regras oficial.
- `colors` (TEXT[]): Array de cores (ex: {'W', 'U'}).
- `image_url` (TEXT): URL para imagem (Scryfall).
- `set_code` (TEXT): Sigla da edição (ex: 'lea').
- `rarity` (TEXT): Raridade.

### Tabela: `card_legalities` (Banidas/Restritas)
- `id` (UUID): PK.
- `card_id` (UUID): FK para cards.
- `format` (TEXT): Formato (commander, modern, etc).
- `status` (TEXT): 'legal', 'banned', 'restricted'.

### Tabela: `rules` (Regras do Jogo)
- `id` (UUID): PK.
- `title` (TEXT): Título da regra.
- `description` (TEXT): Texto completo.
- `category` (TEXT): Categoria da regra.

### Tabela: `decks`
- `id` (UUID): PK.
- `user_id` (UUID): FK para users.
- `name` (TEXT): Nome do deck.
- `format` (TEXT): Formato.
- `description` (TEXT): Descrição.
- `is_public` (BOOLEAN): Visibilidade.
- `synergy_score` (INTEGER): 0-100. Pontuação de consistência.
- `strengths` (TEXT): Pontos fortes (IA).
- `weaknesses` (TEXT): Pontos fracos (IA).
- `created_at` (TIMESTAMP).

### Tabela: `deck_cards` (Itens do Deck)
- `id` (UUID): PK.
- `deck_id` (UUID): FK para decks.
- `card_id` (UUID): FK para cards.
- `quantity` (INTEGER): Quantidade.
- `is_commander` (BOOLEAN): Se é comandante.

### Tabela: `deck_matchups` (Counters & Estatísticas)
- `id` (UUID): PK.
- `deck_id` (UUID): Deck analisado.
- `opponent_deck_id` (UUID): Deck oponente.
- `win_rate` (FLOAT): Taxa de vitória (0.0 a 1.0).
- `notes` (TEXT): Observações da IA.

### Tabela: `battle_simulations` (Dataset ML)
- `id` (UUID): PK.
- `deck_a_id` (UUID): Deck A.
- `deck_b_id` (UUID): Deck B.
- `winner_deck_id` (UUID): Vencedor.
- `turns_played` (INTEGER): Duração.
- `game_log` (JSONB): Log completo turno-a-turno para treino da IA.

## 3. Contratos de API (payloads reais)
**Regra:** o app deve falar com o server usando o contrato abaixo. Se for necessário suportar variantes por compatibilidade, documente e mantenha validações.

### Auth
- `POST /auth/login` → body: `{ "email": "...", "password": "..." }` → 200: `{ token, user: { id, username, email } }`
- `POST /auth/register` → body: `{ "username": "...", "email": "...", "password": "..." }` → 201: `{ token, user: { id, username, email } }`
- `GET /auth/me` → valida token e retorna `{ user: { id, username, email } }` (recomendado para boot do app).

### Decks
- `GET /decks` (JWT obrigatório) → lista decks do usuário.
- `POST /decks` (JWT obrigatório) → cria deck:
  - obrigatórios: `name`, `format`
  - opcional: `description`
  - `cards`: lista de `{ card_id, quantity, is_commander? }`
- `GET /decks/:id` (JWT obrigatório) → detalhes + cartas, com `is_commander`.
- `PUT /decks/:id` (JWT obrigatório) → atualiza campos e/ou substitui lista de `cards` (mesmo formato do `POST`).

### Cards
- `GET /cards?name=...&limit=...&page=...` → `{ data: [...], page, limit, total_returned }`

### IA
- `POST /ai/explain` (JWT obrigatório) → pode retornar fallback em dev quando sem `OPENAI_API_KEY`.
- `POST /ai/archetypes` (JWT obrigatório) → tem fallback/mock quando sem `OPENAI_API_KEY`.
- `POST /ai/optimize` (JWT obrigatório) → retorna removals/additions + análises; pode incluir warnings.
- `POST /ai/generate` (JWT obrigatório) → ideal ter fallback/mock quando sem `OPENAI_API_KEY` para não quebrar UI em dev.

## 4. Regra de Ouro: Documentação Contínua (Manual de Instrução)
**CRÍTICO:** Para CADA alteração significativa, nova funcionalidade, adição de biblioteca ou decisão arquitetural, você DEVE atualizar o arquivo `manual-de-instrucao.md` na raiz do servidor.

O `manual-de-instrucao.md` deve conter:
- **O Porquê:** A justificativa lógica por trás da decisão. Por que essa biblioteca? Por que esse padrão?
- **O Como:** Explicação técnica detalhada da implementação.
- **Bibliotecas:** Explicação do que cada dependência nova faz.
- **Padrões:** Como o Clean Code ou Clean Architecture foi aplicado naquele trecho.
- **Exemplos:** Snippets de código mostrando como o usuário pode replicar ou estender a funcionalidade seguindo o padrão.

## 5. Padrões de Código e Arquitetura
- **Clean Architecture:** Manter separação clara de responsabilidades (Data, Domain, Presentation/Routes).
- **Clean Code:** Variáveis com nomes descritivos, funções pequenas e com responsabilidade única, comentários explicativos onde a lógica for complexa.
- **Segurança:** Nunca commitar credenciais. Usar sempre variáveis de ambiente (`.env`).
- **Tratamento de Erros:** Blocos try-catch explícitos e mensagens de erro claras.

## 6. Fluxo de Trabalho
1.  **Entender:** Analisar o pedido do usuário.
2.  **Planejar:** Definir quais arquivos serão criados/alterados.
3.  **Executar:** Escrever o código seguindo os padrões acima.
4.  **Documentar:** Atualizar IMEDIATAMENTE o `manual-de-instrucao.md` com os detalhes do que foi feito.

## 7. Stack Tecnológica (Backend)
- **Framework:** Dart Frog.
- **DB Driver:** `postgres` (v3.x).
- **Env:** `dotenv`.
- **Http:** `http` (para requisições externas).

## 8. Segurança e rate limiting (dev vs produção)
- `.env` nunca deve ser commitado (use `.env.example`).
- JWT: obrigatório em rotas protegidas (`/decks`, `/ai/*`, `/import`).
- Rate limiting:
  - Auth deve ser restritivo em produção (brute force).
  - Em **development/test**, o rate limiting não pode impedir QA e suíte de testes. Preferir limites maiores em dev.

## 9. Roadmap de Implementação da IA (MVP)

Para transformar o projeto em um "Deck Builder Inteligente", seguiremos este roteiro de implementação, dividindo a IA em três módulos de complexidade crescente.

### Módulo 1: O Analista Matemático (Algoritmos Heurísticos)
*Objetivo:* Fornecer feedback imediato e determinístico sem custos de API externa.
1.  **Calculadora de Curva de Mana:** Analisar a distribuição de custos (CMC) e alertar se o deck está muito "pesado" ou "leve" para o formato.
2.  **Distribuição de Cores (Devotion):** Comparar os símbolos de mana nas cartas com os terrenos disponíveis.
    *   *Regra:* Se 50% dos símbolos são Pretos, mas apenas 20% dos terrenos geram mana Preta -> **Alerta de Consistência**.
3.  **Validação de Formato:** Usar a tabela `card_legalities` para garantir que o deck é legal.

### Módulo 2: O Consultor Criativo (LLM - OpenAI/Gemini)
*Objetivo:* Usar Inteligência Artificial Generativa para tarefas criativas e de compreensão de linguagem natural.
1.  **Gerador de Decks (Text-to-Deck):**
    *   *Input:* "Quero um deck de Commander focado em ganhar vida e drenar oponentes, cores Orzhov."
    *   *Processo:* O LLM recebe o prompt + um contexto das cartas mais populares/fortes dessas cores -> Retorna uma lista JSON de cartas.
2.  **Analista de Sinergia (Synergy Score):**
    *   *Input:* Lista completa do deck.
    *   *Processo:* O LLM analisa as interações (ex: "Esta carta cria fichas" + "Esta carta dá +1/+1 para fichas") e gera um texto explicativo (`strengths`, `weaknesses`) e uma nota (`synergy_score`).
3.  **Autocompletar Inteligente:**
    *   *Input:* Deck com 80 cartas (faltam 20).
    *   *Processo:* O LLM analisa o tema predominante e sugere as 20 melhores cartas para fechar a estratégia.

### Módulo 3: O Simulador de Probabilidade (Monte Carlo Simplificado)
*Objetivo:* Simular o desempenho do deck sem precisar implementar um motor de regras completo (que seria complexo demais).
1.  **Simulador de "Goldfish" (Jogar Sozinho):**
    *   Simular 1.000 mãos iniciais e os primeiros 5 turnos de compra.
    *   *Métrica 1 (Zica/Flood):* Qual a % de mãos com 0, 1, 6 ou 7 terrenos?
    *   *Métrica 2 (Curva):* Qual a % de chance de ter uma jogada válida no turno 1, 2, 3 e 4?
2.  **Treinamento Futuro:**
    *   Os resultados dessas simulações populam a tabela `battle_simulations`, criando um dataset para futuramente treinar uma IA que entenda "o que faz um deck ser consistente".
