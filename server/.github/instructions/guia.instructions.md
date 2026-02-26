---
applyTo: '**'
---
# Guia de Desenvolvimento (Server) — Projeto ManaLoom

Este guia define o fluxo operacional obrigatório para mudanças no backend.

## 🔒 Modo Operacional Obrigatório (fonte única)

1. **Roadmap único:** seguir `ROADMAP.md` como ordem oficial de execução.
2. **Histórico técnico:** toda mudança relevante deve ser registrada em `server/manual-de-instrucao.md`.
3. **Documentos arquivados:** materiais não prioritários em `archive_docs/`.
4. **Quality Gate obrigatório:**
   - durante implementação: `./scripts/quality_gate.sh quick`
   - fechamento de item/sprint: `./scripts/quality_gate.sh full`
5. **DoD obrigatório:** sem aceite + testes + documentação, item não está concluído.

> Regra prática: se não melhora fluxo core, não reduz risco crítico e não aumenta valor percebido, vai para backlog.

## ⚠️ Estado Atual (server)

- Stack: Dart Frog + PostgreSQL + JWT + endpoints de IA.
- API local padrão: `http://localhost:8080`.
- IA deve manter fallback/mock em dev quando `OPENAI_API_KEY` não estiver configurada.
- Rate limiting de auth deve ser permissivo em dev/test e restritivo em produção.

## 1) Prioridade obrigatória (90 dias)

Executar nesta ordem:
1. **Core impecável:** criar/importar -> validar -> analisar -> otimizar.
2. **Segurança e observabilidade:** hardening, rate limit de produção, métricas.
3. **IA com ROI:** explicabilidade, confiança, cache, custo controlado.
4. **Monetização e escala:** somente após estabilidade do core.

Evitar neste ciclo:
- expansão de superfícies secundárias sem impacto no funil principal,
- novas frentes grandes sem valor mensurável.

## 2) Contratos e consistência

- Backend deve preservar contratos de API definidos no projeto.
- Quando houver compatibilidade temporária, documentar claramente.
- Não quebrar payloads core sem plano de migração.

## 3) Fluxo de trabalho obrigatório

1. **Entender e delimitar escopo:** objetivo, impacto e critério de aceite.
2. **Planejar execução mínima correta:** arquivos afetados e ordem.
3. **Executar com foco:** alterar só o necessário para a etapa.
4. **Validar:** rodar gate quick durante desenvolvimento.
5. **Testar fluxo impactado:** happy path + erro crítico.
6. **Fechar:** rodar gate full, documentar no manual e concluir.

## 3.1 Critérios de bloqueio

Bloquear e replanejar quando:
- faltar dependência crítica (infra, schema, segredo, contrato),
- houver risco de regressão sem cobertura mínima,
- escopo extrapolar e comprometer sprint.

Ao bloquear:
- registrar causa em 1 linha,
- definir próximo passo objetivo,
- ajustar backlog sem quebrar meta da sprint.

## 4) Quality Gate e testes

Checklist mínimo por entrega backend:
- [ ] `./scripts/quality_gate.sh quick` executado durante implementação.
- [ ] `./scripts/quality_gate.sh full` executado no fechamento.
- [ ] Sem erros de compilação/lint relevantes.
- [ ] Teste manual do fluxo impactado documentado.

Observação:
- Se a API local estiver ativa em `http://localhost:8080`, o modo `full` habilita integração backend automaticamente.

## 5) Segurança e operação

- Nunca commitar credenciais (`.env` deve ficar fora de versionamento).
- JWT obrigatório para rotas protegidas (`/decks`, `/ai/*`, `/import`, etc).
- Logs sem dados sensíveis.
- Evitar DDL em request path; usar migration/scripts idempotentes.

## 6) Padrões de código

- Separar responsabilidades (rotas enxutas + serviços/regras quando aplicável).
- Nomes descritivos e funções coesas.
- Erros com mensagens claras e status code correto.
- Preferir mudanças pequenas, seguras e fáceis de validar.

## 7) Regra de ouro de documentação

Para cada mudança significativa no backend, atualizar imediatamente:
- `server/manual-de-instrucao.md`

O registro deve incluir:
- **o porquê** da decisão,
- **o como** foi implementado,
- impacto técnico/produto,
- como validar.
