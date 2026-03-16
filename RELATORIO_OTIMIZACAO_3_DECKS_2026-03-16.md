# Relatorio de Otimizacao Real - 3 Decks Commander

- Gerado em: `2026-03-16T12:00:37.209441`
- API: `http://127.0.0.1:8080`
- Artefatos: `test/artifacts/optimization_validation_three_decks`
- Total: `3`
- Passaram: `1`
- Falharam: `2`

## Resultado por deck

### Auntie Ool, Cursewretch

- Source deck: `8c22deb9-80bd-489f-8e87-1344eabac698`
- Clone deck: `fb3a7353-ad05-406a-9248-e0c2d136a519`
- Archetype usado: `aggro`
- Optimize status: `200`
- Deck salvo valido: `true`
- Validation local: `43/100 - reprovado`
- Validation da rota: `39/100 - reprovado`
- CMC medio: `1.88 -> 1.75`
- Interacao: `22 -> 18`
- Consistencia: `70.0 -> 74.0`
- Artifact: `test/artifacts/optimization_validation_three_decks/auntie_ool_cursewretch.json`
- Status final: `FALHOU`

Falhas:
- Validation local nao reprovou
- Validation retornada pela rota nao reprovou

Avisos:
- O deck perdeu cartas de remoção. Pode ficar vulnerável.
- O deck perdeu cartas de ramp. Pode ficar lento no early game.
- 🚫 VALIDAÇÃO: As trocas sugeridas NÃO passaram na validação automática (score: 39/100).
- ⚠️ ATENÇÃO: O deck está ficando mais lento (CMC aumentou), o que é ruim para Aggro.
- O deck perdeu cartas de remoção. Pode ficar vulnerável.
- O deck perdeu cartas de ramp. Pode ficar lento no early game.
- 3 troca(s) questionável(is) — mudou função E ficou mais cara.

### Talrand, Sky Summoner

- Source deck: `df780797-bcc4-47cb-82d6-08d01ae3b03b`
- Clone deck: `be408e73-2801-4b1f-9c69-17c9c0877cad`
- Archetype usado: `midrange`
- Optimize status: `200`
- Deck salvo valido: `true`
- Validation local: `52/100 - aprovado_com_ressalvas`
- Validation da rota: `58/100 - aprovado_com_ressalvas`
- CMC medio: `3.0 -> 1.5`
- Interacao: `0 -> 0`
- Consistencia: `10.0 -> 14.0`
- Artifact: `test/artifacts/optimization_validation_three_decks/talrand_sky_summoner.json`
- Status final: `PASSOU`

Avisos:
- ⚠️ 1 (100%) das cartas sugeridas NÃO aparecem nos dados EDHREC de Talrand, Sky Summoner. Isso pode indicar baixa sinergia: Evolving Wilds

### Jin-Gitaxias // The Great Synthesis

- Source deck: `f2a2a34a-4561-4a77-886d-7067b672ac85`
- Clone deck: `6d3adc16-8c69-437b-a800-abf9c591f2b4`
- Archetype usado: `midrange`
- Optimize status: `200`
- Deck salvo valido: `true`
- Validation local: `41/100 - reprovado`
- Validation da rota: `25/100 - reprovado`
- CMC medio: `1.57 -> 1.48`
- Interacao: `25 -> 23`
- Consistencia: `93.0 -> 92.0`
- Artifact: `test/artifacts/optimization_validation_three_decks/jin_gitaxias_the_great_synthesis.json`
- Status final: `FALHOU`

Falhas:
- Validation local nao reprovou
- Validation retornada pela rota nao reprovou
- Consistencia nao piorou
- Midrange preserva ramp/removal

Avisos:
- O deck perdeu cartas de remoção. Pode ficar vulnerável.
- O deck perdeu cartas de ramp. Pode ficar lento no early game.
- 🚫 VALIDAÇÃO: As trocas sugeridas NÃO passaram na validação automática (score: 25/100).
- O deck perdeu cartas de remoção. Pode ficar vulnerável.
- O deck perdeu cartas de ramp. Pode ficar lento no early game.
- 4 troca(s) questionável(is) — mudou função E ficou mais cara.

