# Manual de Instrução e Documentação Técnica - MTG Deck Builder (Backend)

Este documento serve como guia definitivo para o entendimento, manutenção e expansão do backend do projeto MTG Deck Builder. Ele é atualizado continuamente conforme o desenvolvimento avança.

---

## 1. Visão Geral e Arquitetura

### O que estamos construindo?
Um **Deck Builder de Magic: The Gathering (MTG)** revolucionário, focado em inteligência artificial e automação.
O backend em Dart (Dart Frog) serve como o cérebro da aplicação, gerenciando dados, regras e integrações com IA.

### Funcionalidades Chave (Roadmap)
1.  **Deck Builder:** Criação, edição e importação inteligente de decks (texto -> cartas).
2.  **Regras e Legalidade:** Validação de decks contra regras oficiais e listas de banidas.
3.  **IA Generativa:** Criação de decks a partir de descrições em linguagem natural e autocompletar inteligente.
4.  **Simulador de Batalha:** Testes automatizados de decks (User vs Meta) para treinamento de IA.

### Por que Dart no Backend?
Para manter a stack unificada (Dart no Front e no Back), facilitando o compartilhamento de modelos (DTOs), lógica de validação e reduzindo a carga cognitiva de troca de contexto entre linguagens.

### Estrutura de Pastas (Convenção Dart Frog)
- `routes/`: Define os endpoints da API. A estrutura de pastas aqui reflete a URL (ex: `routes/index.dart` -> `/`).
- `lib/`: Código compartilhado, lógica de negócios, conexão com banco de dados.
- `bin/`: Scripts utilitários (setup de banco, seeds, tarefas agendadas).
- `public/`: Arquivos estáticos (se necessário).

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
