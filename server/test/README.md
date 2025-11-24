# Test Suite Documentation

## Overview

Este diretório contém os testes automatizados do servidor MTG Deck Builder. A suíte de testes está dividida em **testes unitários** (podem ser executados sem dependências externas) e **testes de integração** (requerem servidor e banco de dados).

## Estrutura de Testes

```
test/
├── auth_service_test.dart      # Testes unitários do AuthService
├── import_parser_test.dart      # Testes unitários do parser de importação
├── deck_validation_test.dart    # Testes unitários de validações de deck (NOVO)
└── decks_crud_test.dart         # Testes de integração PUT/DELETE (NOVO)
```

## Testes Implementados

### ✅ Testes Unitários (Não requerem servidor)

#### 1. `auth_service_test.dart` (16 testes)
**Cobertura:**
- Hash e verificação de senhas com bcrypt
- Geração e validação de tokens JWT
- Edge cases (senhas vazias, caracteres especiais, Unicode)

**Executar:**
```bash
dart test test/auth_service_test.dart
```

#### 2. `import_parser_test.dart` (35 testes)
**Cobertura:**
- Parsing de diferentes formatos de lista de deck
- Detecção de comandantes
- Limpeza de nomes de cartas
- Validação de formato
- Edge cases

**Executar:**
```bash
dart test test/import_parser_test.dart
```

#### 3. `deck_validation_test.dart` (44 testes) ⭐ NOVO
**Cobertura:**
- Limites de cópias por formato (Commander: 1, Standard: 4)
- Detecção de terrenos básicos (unlimited)
- Detecção de tipo de carta (Creature, Land, etc)
- Cálculo de CMC (Converted Mana Cost)
- Validação de legalidade (banned, restricted)
- Lógica de UPDATE e DELETE (edge cases)
- Comportamento transacional

**Executar:**
```bash
dart test test/deck_validation_test.dart
```

### 🔌 Testes de Integração (Requerem servidor e banco)

#### 4. `decks_crud_test.dart` (14 testes) ⭐ NOVO
**Cobertura:**
- `PUT /decks/:id` - Atualização de decks
  - Atualizar nome, formato, descrição
  - Atualizar múltiplos campos
  - Substituir lista de cartas
  - Validação de regras do MTG
  - Testes de permissão (ownership)
- `DELETE /decks/:id` - Deleção de decks
  - Delete bem-sucedido
  - Cascade delete de cartas
  - Verificação de ownership
- Testes de ciclo completo (CREATE → UPDATE → DELETE)

**Pré-requisitos:**
1. Servidor rodando: `dart_frog dev`
2. Banco de dados configurado no `.env`
3. Porta 8080 disponível

**Executar:**
```bash
# Terminal 1: Iniciar servidor
cd server
dart_frog dev

# Terminal 2: Executar testes de integração
dart test test/decks_crud_test.dart
```

**Nota:** Os testes de integração criam e limpam seus próprios dados de teste automaticamente.

## Executar Todos os Testes

### Apenas testes unitários (rápido, sem dependências):
```bash
dart test --exclude-tags integration
```

### Todos os testes (requer servidor rodando):
```bash
dart test
```

### Com relatório detalhado:
```bash
dart test --reporter=expanded
```

### Com cobertura de código:
```bash
dart test --coverage=./coverage
dart pub global activate coverage
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

## Estatísticas de Cobertura

| Módulo | Testes | Status | Cobertura Estimada |
|--------|--------|--------|-------------------|
| `lib/auth_service.dart` | 16 | ✅ | ~90% |
| `routes/import/index.dart` | 35 | ✅ | ~85% (parser logic) |
| `routes/decks/[id]/index.dart` (validações) | 44 | ✅ | ~75% (unit) |
| `routes/decks/[id]/index.dart` (endpoints) | 14 | 🔌 | ~80% (integration) |

**Total:** 109 testes (95 unitários + 14 integração)

## Continuous Integration (CI/CD)

Para integrar no GitHub Actions, adicione ao `.github/workflows/test.yml`:

```yaml
name: Run Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: mtgdb_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Dart
        uses: dart-lang/setup-dart@v1
      
      - name: Install dependencies
        run: |
          cd server
          dart pub get
      
      - name: Run unit tests
        run: |
          cd server
          dart test test/auth_service_test.dart
          dart test test/import_parser_test.dart
          dart test test/deck_validation_test.dart
      
      - name: Start server for integration tests
        run: |
          cd server
          dart_frog dev &
          sleep 10
      
      - name: Run integration tests
        run: |
          cd server
          dart test test/decks_crud_test.dart
```

## Próximos Passos (Roadmap de Testes)

### Prioridade Alta
- [ ] Testes de integração para `routes/auth/login.dart` e `register.dart`
- [ ] Testes de integração para `routes/decks/index.dart` (GET, POST)
- [ ] Testes para middleware de autenticação

### Prioridade Média
- [ ] Testes para análise de deck (`routes/decks/[id]/analysis/index.dart`)
- [ ] Testes para recomendações
- [ ] Testes para simulação

### Prioridade Baixa
- [ ] Testes para endpoints de IA (mocks necessários para OpenAI)
- [ ] Testes de performance (load testing)
- [ ] Testes end-to-end com Selenium/Puppeteer

## Convenções de Teste

1. **Nomenclatura:**
   - Arquivos: `<modulo>_test.dart`
   - Grupos: `group('Feature Name', () {...})`
   - Testes: `test('should do something', () {...})`

2. **Estrutura AAA:**
   ```dart
   test('should validate correctly', () {
     // Arrange (preparar dados)
     final input = 'test';
     
     // Act (executar ação)
     final result = validate(input);
     
     // Assert (verificar resultado)
     expect(result, isTrue);
   });
   ```

3. **Helpers:**
   - Use funções helper para reduzir duplicação
   - Coloque helpers no `setUp()` ou em funções privadas no início do arquivo

4. **Limpeza:**
   - Use `tearDown()` para limpar dados de teste
   - Garanta que testes são independentes (não dependem de ordem)

## Troubleshooting

### Erro: "JWT_SECRET não configurado"
**Solução:** Crie um arquivo `.env` na pasta `server/` com:
```
JWT_SECRET=test_secret_for_testing
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mtgdb_test
DB_USER=postgres
DB_PASS=postgres
```

### Erro: "Connection refused" nos testes de integração
**Solução:** Certifique-se que o servidor está rodando:
```bash
cd server
dart_frog dev
```

### Testes falhando no CI/CD
**Solução:** Verifique que:
1. O serviço PostgreSQL está configurado corretamente
2. As variáveis de ambiente estão definidas
3. O servidor tem tempo suficiente para iniciar antes dos testes

## Referências

- [Dart Test Package](https://pub.dev/packages/test)
- [Dart Frog Testing Guide](https://dartfrog.vgv.dev/docs/testing)
- [MTG Comprehensive Rules](https://magic.wizards.com/en/rules)
