# 🗺️ ROADMAP - ManaLoom AI-Powered MTG Deck Builder

**Última Atualização:** 24 de Novembro de 2025  
**Versão Atual:** v0.8.0 (Alpha)  
**Próximo Milestone:** v1.0.0 (MVP)

---

## 📊 Visão Geral do Progresso

```
[████████████████████░░░░] 75% - Rumo ao MVP (v1.0)

✅ Concluído: 12/16 módulos principais
🚧 Em Andamento: 2/16 módulos
❌ Pendente: 2/16 módulos
```

---

## ✅ Etapa Atual - O Que Está Sendo Desenvolvido AGORA

### 🎯 Sprint Atual: Módulo IA - Otimização Completa (Fase 7)

**Período:** 20-30 de Novembro de 2025  
**Objetivo:** Finalizar integração completa com OpenAI para otimização de decks

#### Em Desenvolvimento Ativo

1. **🚧 Aplicação de Otimização no Frontend** (70% completo)
   - [x] Endpoint `/ai/archetypes` - Sugerir 3 arquétipos (✅ Backend)
   - [x] Interface de seleção de arquétipos (Bottom Sheet) (✅ Frontend)
   - [ ] Endpoint `/ai/optimize` - Transformar deck baseado no arquétipo escolhido
   - [ ] Tela de aplicação de sugestões (mostrar diff: cartas removidas vs adicionadas)
   - [ ] Animação de transição entre deck original → deck otimizado

2. **🚧 Gerador de Decks (Text-to-Deck)** (40% completo)
   - [x] Endpoint `/ai/generate` (✅ Backend funcionando)
   - [ ] Tela de geração de decks no frontend
   - [ ] Input de prompt com exemplos (ex: "Deck de elfos verdes agressivo")
   - [ ] Preview do deck gerado antes de salvar
   - [ ] Validação de legalidade automática

#### Issues Conhecidos

- ⚠️ OpenAI às vezes sugere cartas inexistentes (problema de hallucination)
  - **Solução Temporária:** Validar cartas sugeridas contra banco antes de aplicar
- ⚠️ Tempo de resposta da IA pode ser lento (5-10s)
  - **Solução:** Adicionar loading com mensagem "A IA está pensando..."

---

## 🎉 O Que Já Está Funcionando (Status: PRONTO PARA USO)

### ✅ 1. Backend - Infraestrutura Core (100%)

**Implementado:**
- ✅ Servidor Dart Frog rodando em `http://localhost:8080`
- ✅ Conexão com PostgreSQL (Singleton pattern)
- ✅ Sistema de variáveis de ambiente (`.env` + dotenv)
- ✅ Schema completo do banco de dados (`database_setup.sql`)
- ✅ Scripts de setup e seed (`bin/setup_database.dart`, `bin/seed_database.dart`)

**Endpoints Disponíveis:**
```
GET  /                    # Welcome message
POST /auth/login          # Login (retorna JWT)
POST /auth/register       # Registro de usuário
GET  /cards              # Listar cartas (paginado)
GET  /rules              # Regras do jogo
POST /import             # Importar deck de texto
```

---

### ✅ 2. Autenticação e Segurança (100%)

**Implementado:**
- ✅ Hash de senhas com BCrypt (10 rounds de salt)
- ✅ Geração e validação de JWT tokens (24h de validade)
- ✅ Middleware de autenticação (`lib/auth_middleware.dart`)
- ✅ Rotas protegidas com verificação de ownership
- ✅ Validação de email/username únicos
- ✅ Input validation em todos os endpoints POST/PUT

**Testado:**
- ✅ 16 testes unitários (`test/auth_service_test.dart`)
- ✅ Hash único mesmo com mesma senha (salt funciona)
- ✅ JWT contém `userId` e expira corretamente

**Segurança:**
- ✅ `.env` não commitado no git (`.gitignore`)
- ✅ `.env.example` documentado para setup
- ✅ Prepared statements (prevenção de SQL injection)

---

### ✅ 3. CRUD Completo de Decks (100%)

**Endpoints Funcionais:**
```
GET    /decks              # Listar decks do usuário autenticado
POST   /decks              # Criar novo deck
GET    /decks/:id          # Detalhes de um deck (com cartas inline)
PUT    /decks/:id          # Atualizar deck (nome, formato, descrição, cartas)
DELETE /decks/:id          # Deletar deck (soft delete com CASCADE)
```

**Validações Implementadas:**
- ✅ Limite de cópias por formato:
  - Commander/Brawl: 1 cópia por carta (exceto terrenos básicos)
  - Standard/Modern/Pioneer: 4 cópias por carta
  - Terrenos básicos: unlimited
- ✅ Verificação de cartas banidas/restritas por formato (`card_legalities`)
- ✅ Transações atômicas (rollback automático em caso de erro)
- ✅ Verificação de ownership (apenas o dono pode atualizar/deletar)

**Testado:**
- ✅ 44 testes unitários de validação (`test/deck_validation_test.dart`)
- ✅ 14 testes de integração (`test/decks_crud_test.dart`)
- ✅ 100% das regras de formato cobertas

**Formato do Deck Retornado:**
```json
{
  "id": "uuid",
  "name": "Atraxa Superfriends",
  "format": "commander",
  "description": "Deck focado em Planeswalkers",
  "cards": [
    {
      "id": "uuid",
      "name": "Atraxa, Praetors' Voice",
      "quantity": 1,
      "is_commander": true,
      "mana_cost": "{G}{W}{U}{B}",
      "type_line": "Legendary Creature — Phyrexian Angel"
    }
  ],
  "created_at": "2025-11-24T10:30:00Z"
}
```

---

### ✅ 4. Frontend - Identidade Visual e Navegação (100%)

**Implementado:**
- ✅ Nome do app: **ManaLoom** ("Teça sua estratégia perfeita")
- ✅ Paleta de cores "Arcane Weaver":
  - Background: `#0A0E14` (Abismo azulado)
  - Primary: `#8B5CF6` (Mana Violet)
  - Secondary: `#06B6D4` (Loom Cyan)
  - Accent: `#F59E0B` (Mythic Gold)
  - Surface: `#1E293B` (Slate)
- ✅ Splash Screen com animação (3 segundos)
- ✅ Sistema de navegação com GoRouter (rotas protegidas)
- ✅ Telas funcionais:
  - Login Screen (validação de email + senha)
  - Register Screen (username + email + senha + confirmação)
  - Home Screen (navegação principal)
  - Deck List Screen (loading, error, empty states)

**Arquitetura Frontend:**
```
lib/
├── features/
│   ├── auth/        ✅ Login, Register, AuthProvider
│   ├── decks/       ✅ List, Details, Builder
│   ├── cards/       ⏳ Search (em desenvolvimento)
│   └── home/        ✅ Dashboard
└── core/
    ├── api/         ✅ ApiClient (GET, POST, PUT, DELETE)
    ├── theme/       ✅ AppTheme (cores, tipografia)
    └── utils/       ✅ ManaHelper (CMC, cores)
```

---

### ✅ 5. Módulo IA - Analista Matemático (80%)

**Backend (Implementado):**
- ✅ Endpoint `GET /decks/:id/analysis` - Análise completa do deck:
  - CMC médio
  - Curva de mana (distribuição 0-7+ CMC)
  - Validação de legalidade (cartas banidas)
  - Preço total do deck
- ✅ Validação de regras de formato (Commander 1x, Standard 4x)
- ✅ Verificação de cartas banidas (`card_legalities`)

**Frontend (Implementado):**
- ✅ `ManaHelper` - Utilitário para cálculo de CMC e Devoção
- ✅ Gráficos com fl_chart:
  - Bar Chart para Curva de Mana
  - Pie Chart para Distribuição de Cores
- ✅ Aba de Análise no `DeckDetailsScreen`

**Pendente (20%):**
- ❌ Cálculo de Devotion no backend (símbolos de mana por cor)
  - **Nota:** Frontend calcula localmente, mas backend deveria ser fonte de verdade
- ❌ Sugestões automáticas de terrenos (baseado em devotion)

**Exemplo de Resposta:**
```json
{
  "avg_cmc": 2.8,
  "mana_curve": {
    "0": 5, "1": 12, "2": 15, "3": 10, "4": 6, "5": 2, "6+": 1
  },
  "total_price": 450.75,
  "is_legal": true,
  "banned_cards": []
}
```

---

### ✅ 6. Módulo IA - Consultor Criativo (75%)

**Backend (Implementado):**
- ✅ `POST /ai/explain` - Explicar carta individualmente
  - GPT-4 analisa estratégia, sinergia, quando usar
  - Cache de respostas no banco (`cards.ai_description`)
- ✅ `POST /ai/archetypes` - Sugerir 3 arquétipos para o deck
  - Recebe deck atual → analisa → retorna 3 caminhos de evolução
  - Ex: "Agressivo Tribal", "Controle Defensivo", "Combo Infinito"
- ✅ `POST /ai/generate` - Criar deck do zero por descrição
  - Input: "Deck de dragões vermelhos para Commander"
  - Output: 100 cartas validadas

**Frontend (Implementado):**
- ✅ Botão "Explicar" nos detalhes da carta
- ✅ Botão "Otimizar Deck" na tela de detalhes
- ✅ Bottom Sheet de seleção de arquétipos (3 opções)

**Pendente (25%):**
- 🚧 `POST /ai/optimize` - Aplicar arquétipo escolhido (em desenvolvimento)
- ❌ Tela de geração de decks no frontend (endpoint pronto, UI faltando)

**Exemplo de Prompt para GPT-4:**
```
Você é um consultor especialista em Magic: The Gathering.

Deck atual:
- Comandante: Atraxa, Praetors' Voice
- 15 Planeswalkers
- 10 cartas de proliferate
- 35 terrenos

Analise este deck e sugira 3 arquétipos diferentes para otimizá-lo:
1. Manter tema principal (Superfriends) mas melhorar consistência
2. Pivô estratégico (ex: adicionar infect para sinergia com proliferate)
3. Versão mais competitiva (cEDH-oriented)

Para cada arquétipo, sugira 10 cartas a adicionar e 10 a remover.
```

---

### ✅ 7. Importação Inteligente de Decks (100%)

**Endpoint:** `POST /import`

**Funcionalidades:**
- ✅ Parser de texto linha-a-linha:
  - Reconhece formato: `1x Sol Ring (cmm)`
  - Reconhece formato alternativo: `Sol Ring` (assume 1x)
  - Ignora linhas vazias e comentários
- ✅ Fuzzy matching de nomes de cartas (tolerante a typos)
- ✅ Validação de regras de formato durante import
- ✅ Retorna JSON com cartas reconhecidas + cartas não encontradas

**Testado:**
- ✅ 35 testes unitários (`test/import_parser_test.dart`)
- ✅ Casos edge: cartas com acentos, nomes compostos, edições antigas

**Exemplo de Input:**
```
Commander: Atraxa, Praetors' Voice
1x Doubling Season (rav)
4x Llanowar Elves
Sol Ring
// Comentário ignorado

Terrenos:
10x Forest
5x Island
```

**Exemplo de Output:**
```json
{
  "success": true,
  "cards_found": 17,
  "cards_not_found": ["Llanowar Elves"], // Typo no nome
  "cards": [
    {
      "name": "Atraxa, Praetors' Voice",
      "quantity": 1,
      "is_commander": true
    },
    {
      "name": "Doubling Season",
      "quantity": 1,
      "set_code": "rav"
    }
  ]
}
```

---

### ✅ 8. Busca Avançada de Cartas (60%)

**Implementado:**
- ✅ Endpoint `GET /cards` - Listar cartas com paginação
- ✅ Filtros básicos:
  - `?name=lightning` (busca parcial no nome)
  - `?colors=R,G` (cartas vermelhas ou verdes)
  - `?type=creature` (tipo da carta)
- ✅ Paginação: `?page=1&limit=20`

**Pendente (40%):**
- ❌ Filtros avançados:
  - CMC range (`?cmc_min=2&cmc_max=4`)
  - Raridade (`?rarity=mythic`)
  - Formato legal (`?format=commander`)
- ❌ Ordenação (`?sort=name` ou `?sort=price`)
- ❌ Frontend de busca (tela de pesquisa)

---

### ✅ 9. Regras Oficiais do Magic (100%)

**Implementado:**
- ✅ Tabela `rules` populada com regras oficiais
- ✅ Endpoint `GET /rules` - Listar todas as regras
- ✅ Categorização por tipo (combate, stack, mulligan, etc)
- ✅ Script de seed: `bin/seed_rules.dart`

**Fonte:** Comprehensive Rules (arquivo txt oficial da Wizards)

**Exemplo de Regra:**
```json
{
  "id": "uuid",
  "title": "100.1",
  "description": "Estes são os Comprehensive Rules do Magic...",
  "category": "Introdução"
}
```

---

## 🚧 O Que Falta - Funcionalidades Planejadas

### 🔄 Próximo Sprint (Dezembro 2025)

#### 1. Finalizar Módulo IA - Otimização (2 semanas)

**Backend:**
- [ ] `POST /ai/optimize` - Aplicar arquétipo escolhido
  - Receber: `deck_id` + `archetype_name`
  - Retornar: diff (cartas a adicionar/remover)
- [ ] Validação de sugestões da IA (garantir cartas existem)
- [ ] Retry logic se OpenAI falhar

**Frontend:**
- [ ] Tela de aplicação de sugestões
- [ ] Mostrar diff lado-a-lado: "Antes" vs "Depois"
- [ ] Botão "Aplicar Mudanças" (chama PUT /decks/:id)
- [ ] Animação de transição entre decks

**Esforço Estimado:** 20 horas

---

#### 2. Tela de Geração de Decks (1 semana)

**Backend:**
- ✅ Endpoint já existe (`POST /ai/generate`)

**Frontend:**
- [ ] Nova tela: "Criar Deck com IA"
- [ ] Input de prompt com sugestões de exemplo
- [ ] Seletor de formato (Commander, Standard, Modern)
- [ ] Loading com mensagem "A IA está montando seu deck..."
- [ ] Preview do deck gerado antes de salvar
- [ ] Botão "Salvar Deck" (chama POST /decks)

**Esforço Estimado:** 12 horas

---

#### 3. Busca Avançada de Cartas (1 semana)

**Backend:**
- [ ] Adicionar filtros avançados:
  ```
  GET /cards?cmc_min=2&cmc_max=4&rarity=rare&format=commander&sort=price
  ```
- [ ] Índices no banco para performance (CMC, rarity)

**Frontend:**
- [ ] Tela de busca avançada com filtros
- [ ] Chips de filtros ativos (ex: "Vermelho", "CMC 1-3")
- [ ] Grid de cartas com imagens (cached_network_image)
- [ ] Lazy loading / infinite scroll
- [ ] Botão "Adicionar ao Deck" em cada carta

**Esforço Estimado:** 16 horas

---

### 🔮 Futuras Etapas (v1.1 - Q1 2026)

#### Módulo IA - Simulador de Batalhas (Fase 8)

**Objetivo:** Simular partidas entre decks automaticamente para treinar IA

**Backend:**
- [ ] Endpoint `POST /decks/:id/simulate`
  - Recebe: `opponent_deck_id`
  - Simula 1.000 partidas automaticamente
  - Retorna: win rate, estatísticas
- [ ] Motor simplificado de jogo (apenas regras básicas):
  - Compra inicial (7 cartas, mulligan)
  - Curva de mana (jogar 1 carta por turno)
  - Combate simplificado (poder vs resistência)
- [ ] Salvar logs em `battle_simulations` (dataset para ML)
- [ ] Endpoint `GET /decks/:id/matchups` - Ver counters

**Frontend:**
- [ ] Tela de "Testar Deck"
- [ ] Seletor de deck oponente (meta decks pré-definidos)
- [ ] Gráfico de win rate ao longo de simulações
- [ ] Lista de matchups (quais decks ganham/perdem)

**Esforço Estimado:** 40 horas (complexo)

**Nota:** Este é o módulo mais ambicioso. Requer lógica complexa de jogo.

---

#### Sistema de Preços e Coleção (v1.2)

**Objetivo:** Integrar preços de mercado e tracking de coleção

**Backend:**
- [ ] Integração com Scryfall API (buscar preços)
- [ ] Coluna `price` em `cards` (DECIMAL)
- [ ] Script `bin/update_prices.dart` (rodar diariamente)
- [ ] Endpoint `GET /decks/:id/price` - Preço total do deck
- [ ] Nova tabela `user_collection` (cartas que o usuário possui)

**Frontend:**
- [ ] Mostrar preço total do deck
- [ ] Tela de "Minha Coleção"
- [ ] Marcar cartas como "Tenho" ou "Preciso Comprar"
- [ ] Filtro de busca: "Mostrar apenas cartas que tenho"

**Esforço Estimado:** 24 horas

---

#### Dashboard e Estatísticas (v1.3)

**Backend:**
- [ ] Endpoint `GET /stats` - Estatísticas do usuário
  - Total de decks
  - Formatos favoritos
  - Cartas mais usadas
  - Valor total da coleção

**Frontend:**
- [ ] Dashboard na Home Screen
- [ ] Gráficos:
  - Decks por formato (Pie Chart)
  - Evolução de decks ao longo do tempo (Line Chart)
  - Top 10 cartas mais usadas (Bar Chart)

**Esforço Estimado:** 16 horas

---

## ❌ Gaps Conhecidos e Limitações Atuais

### 🔴 Crítico (Impede Produção)

1. **Sem Rate Limiting** (Vulnerável a Brute Force)
   - **Problema:** Endpoint `/auth/login` pode ser atacado
   - **Solução:** Adicionar rate limiting (ex: 5 tentativas/minuto)
   - **Esforço:** 4 horas

2. **Sem HTTPS em Produção** (Tráfego não criptografado)
   - **Problema:** Senhas podem ser interceptadas
   - **Solução:** Configurar certificado SSL (Let's Encrypt)
   - **Esforço:** 2 horas (infra)

3. **OpenAI API Key Hardcoded** (Se commitar acidentalmente = $$$)
   - **Problema:** `.env` pode ser commitado por erro
   - **Solução:** Adicionar pre-commit hook (git-secrets)
   - **Esforço:** 1 hora

---

### 🟡 Importante (Melhora Qualidade)

1. **Sem Refresh Tokens** (UX ruim após 24h)
   - **Problema:** Usuário precisa fazer login todo dia
   - **Solução:** Implementar refresh tokens (30 dias de validade)
   - **Esforço:** 8 horas

2. **Sem Testes no Frontend** (0% cobertura)
   - **Problema:** Refatorações podem quebrar UI silenciosamente
   - **Solução:** Adicionar testes de widget (flutter_test)
   - **Esforço:** 16 horas

3. **Sem CI/CD** (Deploy manual)
   - **Problema:** Processo de deploy lento e propenso a erros
   - **Solução:** GitHub Actions (build + test + deploy)
   - **Esforço:** 8 horas

4. **Sem Logging Estruturado** (Debugging difícil)
   - **Problema:** Erros em produção são difíceis de rastrear
   - **Solução:** Adicionar logger (ex: logger package) + Sentry
   - **Esforço:** 6 horas

---

### 🟢 Nice to Have (Melhorias Futuras)

1. **Sem Docs OpenAPI/Swagger** (API não auto-documentada)
   - **Solução:** Gerar Swagger.json a partir das rotas
   - **Esforço:** 4 horas

2. **Sem Internacionalização (i18n)** (Apenas PT-BR)
   - **Solução:** Adicionar suporte a EN-US
   - **Esforço:** 12 horas

3. **Sem Modo Offline** (Requer internet sempre)
   - **Solução:** Cache local com SQLite (app/)
   - **Esforço:** 20 horas

4. **Sem Notificações Push** (Usuário não sabe de updates)
   - **Solução:** Firebase Cloud Messaging
   - **Esforço:** 8 horas

---

## 📅 Timeline para v1.0 (MVP)

**Meta:** Lançar MVP até 31 de Dezembro de 2025

### Semana 1 (25 Nov - 1 Dez): Finalizar IA - Otimização
- [ ] Implementar `POST /ai/optimize` (backend)
- [ ] Criar tela de aplicação de sugestões (frontend)
- [ ] Testes de integração

### Semana 2 (2-8 Dez): Geração de Decks + Segurança
- [ ] Criar tela de geração de decks (frontend)
- [ ] Adicionar rate limiting (backend)
- [ ] Configurar HTTPS (infra)

### Semana 3 (9-15 Dez): Busca Avançada + Polish
- [ ] Implementar filtros avançados (backend)
- [ ] Criar tela de busca (frontend)
- [ ] Melhorar UX (loading states, error handling)

### Semana 4 (16-22 Dez): Testes + Docs + Deploy
- [ ] Aumentar cobertura de testes (backend 90%, frontend 60%)
- [ ] Documentar API (Swagger)
- [ ] Setup CI/CD
- [ ] Deploy em staging

### Semana 5 (23-31 Dez): Beta Testing + Launch
- [ ] Beta testing com 5-10 usuários
- [ ] Corrigir bugs críticos
- [ ] Deploy em produção
- [ ] Lançamento público! 🎉

---

## 🎯 Definição de "Done" (Checklist MVP)

**Backend:**
- [x] Autenticação funcionando (login, register, JWT)
- [x] CRUD completo de decks
- [x] Validação de regras de formato
- [x] Busca de cartas
- [x] Importação de decks
- [x] IA: Explicar cartas (`/ai/explain`)
- [x] IA: Sugerir arquétipos (`/ai/archetypes`)
- [ ] IA: Otimizar deck (`/ai/optimize`) - 🚧 EM ANDAMENTO
- [ ] IA: Gerar deck (`/ai/generate`) - ✅ Backend pronto, frontend faltando
- [ ] Rate limiting configurado
- [ ] HTTPS em produção
- [x] Testes automatizados (80% cobertura)

**Frontend:**
- [x] Splash Screen
- [x] Login/Register
- [x] Home Screen
- [x] Lista de decks
- [x] Detalhes do deck com análise
- [x] Gráficos (Curva de Mana, Cores)
- [ ] Busca avançada de cartas
- [ ] Tela de geração de decks
- [ ] Tela de otimização de decks
- [ ] Testes de widget (60% cobertura)

**Infraestrutura:**
- [x] PostgreSQL configurado
- [x] Variáveis de ambiente (`.env`)
- [ ] HTTPS/SSL
- [ ] CI/CD (GitHub Actions)
- [ ] Monitoring (Sentry ou similar)

**Documentação:**
- [x] README.md completo
- [x] ROADMAP.md atualizado
- [x] manual-de-instrucao.md (backend)
- [ ] OpenAPI/Swagger
- [ ] Guia de contribuição

---

## 📊 Métricas de Sucesso

**Técnicas:**
- ✅ 80%+ cobertura de testes no backend (ATINGIDO: 80%)
- ⏳ 60%+ cobertura de testes no frontend (ATUAL: 0%)
- ✅ Tempo de resposta da API < 200ms (ATINGIDO: ~100ms)
- ⏳ Tempo de resposta da IA < 10s (ATUAL: ~8s)

**Qualidade de Código:**
- ✅ Zero warnings no `dart analyze` (ATINGIDO)
- ✅ Zero erros de segurança conhecidos (ATINGIDO)
- ✅ Documentação atualizada semanalmente (ATINGIDO)

**UX:**
- ⏳ Tempo de onboarding < 5 minutos (PENDENTE: testar com usuários)
- ⏳ Criar primeiro deck < 10 minutos (PENDENTE: testar com usuários)

---

## 🚀 Visão de Longo Prazo (v2.0 - 2026)

### Recursos Ambiciosos

1. **Modo Multiplayer** (Testar decks com amigos online)
2. **Marketplace** (Comprar/vender cartas integrado)
3. **Torneios Virtuais** (Competir com comunidade)
4. **IA Preditiva** (Prever meta de torneios)
5. **Realidade Aumentada** (Escanear cartas físicas com câmera)

---

**Última Revisão:** 24 de Novembro de 2025  
**Próxima Revisão:** 1 de Dezembro de 2025

---

_Desenvolvido com 💜 por um apaixonado por Magic: The Gathering_
