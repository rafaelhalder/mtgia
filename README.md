# ManaLoom — AI-Powered MTG Deck Builder

Deck builder de Magic focado em resultado: montar, validar, analisar e otimizar decks com apoio de IA.

## Proposta de Valor

O ManaLoom reduz o tempo entre ideia e deck competitivo com um fluxo único:

1. criar ou importar deck,
2. validar legalidade por formato,
3. analisar consistência/sinergia,
4. otimizar com sugestões acionáveis.

## Para quem é

- Jogadores competitivos que querem otimizar listas com rapidez.
- Jogadores casuais que precisam de assistência para fechar estratégia.
- Colecionadores e usuários que querem usar fichário/market/trades no mesmo app.

## Diferenciais atuais

- Geração de decks por descrição textual.
- Otimização assistida por IA com recomendações de add/remove.
- Validação de formato e legalidade integrada ao fluxo.
- Base social/comunidade, fichário, marketplace e trades no mesmo produto.

## Stack

- Frontend: Flutter + Provider + GoRouter
- Backend: Dart Frog + PostgreSQL
- IA: OpenAI (com fallback controlado em desenvolvimento)

## Estrutura do repositório

- app/: aplicativo Flutter
- server/: API Dart Frog + banco + scripts
- archive_docs/: documentos arquivados para reduzir ruído operacional

## Quick Start

### Backend

1. entrar em server
2. instalar dependências com dart pub get
3. configurar .env a partir de .env.example
4. criar banco e aplicar schema/migrations
5. iniciar API com dart_frog dev

### Frontend

1. entrar em app
2. instalar dependências com flutter pub get
3. rodar com flutter run

## Documentação ativa

- Roadmap oficial do produto: [ROADMAP.md](ROADMAP.md)
- Manual técnico contínuo: [server/manual-de-instrucao.md](server/manual-de-instrucao.md)
- Instruções de testes backend: [server/test/README.md](server/test/README.md)

## Direção de produto (90 dias)

O foco atual é transformar o ManaLoom em produto competitivo:

- Core impecável (criar -> analisar -> otimizar).
- IA com impacto mensurável e custo controlado.
- Base pronta para escala e monetização freemium/pro.

Detalhes completos em [ROADMAP.md](ROADMAP.md).

## Status

Projeto em fase de MVP avançado para evolução acelerada rumo a produto.
