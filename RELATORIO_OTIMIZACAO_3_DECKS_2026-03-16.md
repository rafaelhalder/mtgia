# Relatorio de Otimizacao Real - 3 Decks Commander

- Gerado em: `2026-03-16T17:22:56.249001`
- API: `http://127.0.0.1:8080`
- Artefatos: `test/artifacts/optimization_validation_three_decks`
- Total: `3`
- Otimizacoes aceitas: `0`
- Rejeicoes protegidas: `3`
- Passaram: `3`
- Falharam: `0`

## Resultado por deck

### Auntie Ool, Cursewretch

- Source deck: `8c22deb9-80bd-489f-8e87-1344eabac698`
- Clone deck: `202d0076-4a03-4aa0-917f-4a5d8982aff7`
- Tipo de resultado: `protected_rejection`
- Archetype usado: `aggro`
- Optimize status: `422`
- Deck salvo valido: `true`
- Validation local: `n/d - quality_rejected`
- Validation da rota: `n/d`
- CMC medio: `n/d`
- Interacao: `n/d`
- Consistencia: `n/d`
- Artifact: `test/artifacts/optimization_validation_three_decks/auntie_ool_cursewretch.json`
- Status final: `PASSOU`

Avisos:
- Rejeicao protegida pelo gate de qualidade: As trocas sugeridas pioravam funcao, curva ou consistencia do deck.
- Nenhuma troca segura restou apos o gate de qualidade da otimizacao.

### Talrand, Sky Summoner

- Source deck: `df780797-bcc4-47cb-82d6-08d01ae3b03b`
- Clone deck: `1256028a-a2bd-47af-98dc-d866c5130b2e`
- Tipo de resultado: `protected_rejection`
- Archetype usado: `midrange`
- Optimize status: `422`
- Deck salvo valido: `true`
- Validation local: `n/d - quality_rejected`
- Validation da rota: `n/d`
- CMC medio: `n/d`
- Interacao: `n/d`
- Consistencia: `n/d`
- Artifact: `test/artifacts/optimization_validation_three_decks/talrand_sky_summoner.json`
- Status final: `PASSOU`

Avisos:
- Rejeicao protegida pelo gate de qualidade: As trocas foram recusadas porque degradam funcoes criticas ou nao atingem qualidade minima.
- A validação final não fechou como "aprovado" (score 64/100). Optimize só retorna sucesso quando a melhoria é aprovada sem ressalvas.
- Score final abaixo do mínimo para aceitar a otimização com sucesso (64/100; mínimo 70).
- A base de mana continua com problema crítico após a otimização.
- A otimizacao sugerida nao passou no gate final de qualidade.

### Jin-Gitaxias // The Great Synthesis

- Source deck: `f2a2a34a-4561-4a77-886d-7067b672ac85`
- Clone deck: `93c4cf9f-f1c3-404e-b5fa-51345f733f49`
- Tipo de resultado: `protected_rejection`
- Archetype usado: `midrange`
- Optimize status: `422`
- Deck salvo valido: `true`
- Validation local: `n/d - quality_rejected`
- Validation da rota: `n/d`
- CMC medio: `n/d`
- Interacao: `n/d`
- Consistencia: `n/d`
- Artifact: `test/artifacts/optimization_validation_three_decks/jin_gitaxias_the_great_synthesis.json`
- Status final: `PASSOU`

Avisos:
- Rejeicao protegida pelo gate de qualidade: As trocas foram recusadas porque degradam funcoes criticas ou nao atingem qualidade minima.
- Validação automática reprovou as trocas (score 44/100).
- A validação final não fechou como "aprovado" (score 44/100). Optimize só retorna sucesso quando a melhoria é aprovada sem ressalvas.
- Score final abaixo do mínimo para aceitar a otimização com sucesso (44/100; mínimo 70).
- A segunda revisão crítica da IA rejeitou a proposta (approval_score 45/100).
- As trocas não demonstraram ganho mensurável suficiente em consistência, mana ou execução do plano.
- A otimizacao sugerida nao passou no gate final de qualidade.

