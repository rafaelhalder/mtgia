# Testes do App Flutter - MTG Deck Builder

Esta pasta contém os testes unitários e de widget do aplicativo Flutter.

## Estrutura

```
test/
├── smoke_test.dart          # Testes básicos de renderização
├── core/
│   └── utils/
│       └── logger_test.dart # Testes do logger centralizado
└── features/
    └── decks/
        └── models/
            └── deck_test.dart # Testes do modelo Deck
```

## Executando os testes

```bash
# Rodar todos os testes
flutter test

# Rodar um teste específico
flutter test test/smoke_test.dart

# Rodar com cobertura
flutter test --coverage
```

## Convenções

- Arquivos de teste devem terminar com `_test.dart`
- Cada feature deve ter sua pasta correspondente em `test/features/`
- Use `group()` para agrupar testes relacionados
- Use nomes descritivos nos testes
