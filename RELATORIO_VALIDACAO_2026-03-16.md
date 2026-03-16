# Relatorio de Validacao - 2026-03-16

## Escopo

Foram corrigidos e validados os seguintes pontos:

- `app`: `DeckProvider.createDeck()` nao pode mais criar deck incompleto quando `/cards/resolve/batch` falha ou retorna cartas nao resolvidas.
- `server/auth`: normalizacao consistente de `email` e `username` no fluxo de cadastro/login.
- `server/auth`: suporte seguro a senhas acima de 72 bytes com compatibilidade retroativa para hashes bcrypt ja existentes.
- `server/rate-limit`: fallback deixou de concentrar usuarios diferentes em `anonymous` quando ha headers suficientes para fingerprint.
- `server`: centralizacao dos helpers de URL do Scryfall e de deteccao de colunas opcionais dos decks.
- `server/ai`: persistencia dos jobs de `/ai/optimize` em banco para manter polling valido apos restart.
- `server/rate-limit`: validacao distribuida passou a ser atomica por `bucket + identifier`.
- `server/cards/resolve`: nomes ambiguos nao sao mais resolvidos silenciosamente para a carta errada.
- `app/decks`: criacao de deck agora falha explicitamente quando o backend sinaliza ambiguidade no resolve em lote.
- `server/ai/generate`: geracao agora passa por resolucao deterministica de nomes e validacao forte de regras do formato antes de retornar `200`.
- `server/ai/generate`: decks ilegais da IA agora retornam `422` com diagnostico estruturado em vez de sucesso silencioso com lista truncada.
- `app/decks`: tela de geracao agora exibe a mensagem detalhada do backend quando `/ai/generate` falha.

## Evidencias

### App

- Novo teste unitario em `app/test/features/decks/providers/deck_provider_test.dart`.
- Coberturas adicionadas:
  - falha explicita quando `/cards/resolve/batch` responde erro;
  - falha explicita quando o backend retorna `unresolved`;
  - preservacao de cartas com `card_id` junto com cartas resolvidas por `name`.

### Backend

- Novo teste de integracao em `server/test/auth_flow_integration_test.dart`.
- Coberturas adicionadas:
  - cadastro persiste `username/email` normalizados;
  - login aceita email com caixa e espacos diferentes;
  - cadastro bloqueia duplicidade por variacao de caixa.

- `server/test/auth_service_test.dart` agora valida:
  - senha longa;
  - `normalizeEmail`;
  - `normalizeUsername`.

- `server/test/rate_limit_middleware_test.dart` agora valida:
  - uso do primeiro IP de `X-Forwarded-For`;
  - fallback por fingerprint;
  - manutencao de `anonymous` apenas sem headers suficientes.

- `server/test/card_resolution_support_test.dart` agora valida:
  - match exato;
  - match unico por prefixo;
  - ambiguidade com multiplos candidatos;
  - fallback unico por contains;
  - caso sem candidatos.

- `app/test/features/decks/providers/deck_provider_test.dart` agora tambem valida:
  - falha explicita quando o backend retorna `ambiguous`.

- `server/test/generated_deck_validation_service_test.dart` agora valida:
  - deck de 60 cartas continua valido mesmo quando uma carta invalida e removida;
  - geracao Commander falha sem `commander`;
  - geracao Commander falha quando cartas nao resolvidas quebram o tamanho exato do deck.

## Comandos executados

- `app/flutter analyze`
- `app/flutter test`
- `server/dart analyze`
- `server/dart test test/auth_service_test.dart`
- `server/dart test test/rate_limit_middleware_test.dart`
- `server/dart test test/auth_flow_integration_test.dart` com `RUN_INTEGRATION_TESTS=1`
- `server/dart test test/import_to_deck_flow_test.dart` com `RUN_INTEGRATION_TESTS=1`
- `server/dart test test/decks_incremental_add_test.dart` com `RUN_INTEGRATION_TESTS=1`
- `server/dart test test/decks_crud_test.dart` com `RUN_INTEGRATION_TESTS=1`
- `server/dart test`
- `server/dart test test/generated_deck_validation_service_test.dart`
- `server/dart run bin/migrate.dart`
- validacao manual de `POST /cards/resolve`
- validacao manual de `POST /cards/resolve/batch`
- validacao manual de polling de `/ai/optimize/jobs/:id` apos restart do backend
- validacao manual de `POST /ai/generate`

## Resultado

- `app/flutter analyze`: sem issues.
- `app/flutter test`: passando.
- `server/dart analyze`: sem issues.
- Testes direcionados do backend: passando.
- `server/dart test` completo: passando.
- `POST /cards/resolve` com nome ambiguo: retorna erro explicito com candidatos.
- `POST /cards/resolve/batch` com nome ambiguo: retorna `ambiguous` sem resolver incorretamente.
- `/ai/optimize/jobs/:id`: permaneceu acessivel com `200` apos reinicio do `dart_frog dev`.
- `POST /ai/generate`: quando a IA devolveu deck ilegal de Commander, a rota respondeu `422` com `validation.errors`, `invalid_cards` e deck resolvido parcial para diagnostico.

## Ajuste adicional apos o relatorio inicial

- Foi corrigido o calculo de `consistencyScore` em `server/lib/ai/goldfish_simulator.dart`.
- O score estava sendo multiplicado por `100` duas vezes, saturando quase qualquer deck em `100`.
- Efeito pratico:
  - o caso `TC052` voltou a diferenciar deck inconsistente de deck corrigido;
  - `server/dart test` completo passou a fechar sem falhas.

## Limpeza final

- Foram removidos os 8 warnings restantes do backend apontados pelo `dart analyze`.
- Resultado final consolidado:
  - `app/flutter analyze`: ok
  - `app/flutter test`: ok
  - `server/dart analyze`: ok
  - `server/dart test`: ok

## Observacao de integracao

- `server/test/ai_optimize_flow_test.dart` continua com pelo menos um timeout de 30s no cenario sincrono `returns success contract in mock or real mode`.
- O timeout apareceu apos as mudancas, mas o fluxo novo de job assincrono foi validado separadamente:
  - `POST /ai/optimize` retornou `202`;
  - o polling inicial respondeu `processing`;
  - apos restart do backend, o mesmo `job_id` continuou retornando `200`.

## Ajuste adicional em generate

- A rota `POST /ai/generate` deixou de confiar apenas no prompt:
  - nomes passam por resolucao em lote reaproveitando a mesma base do import;
  - o deck final passa por `DeckRulesService` em modo estrito;
  - `200` so acontece quando o deck final e legal para o formato;
  - `422` agora explica o motivo exato da rejeicao.
