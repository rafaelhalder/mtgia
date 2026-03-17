#!/usr/bin/env python3
"""
====================================================================
  TESTE COMPLETO DO FLUXO DE OTIMIZAÇÃO DE DECKS
  Testa decks reais do banco com diferentes tamanhos e commanders.
  Mede tempo de resposta e valida qualidade do retorno.
====================================================================
"""
import requests
import json
import time
import sys
import jwt
from datetime import datetime

BASE = "http://localhost:8080"
JWT_SECRET = "your-super-secret-and-long-string-for-jwt"

# ── Decks selecionados para teste (diversidade de cenários) ──────
TEST_DECKS = [
    {
        "id": "f2a2a34a-4561-4a77-886d-7067b672ac85",
        "name": "jin (completo 100)",
        "user_id": "18df0188-9f27-4e20-84fe-a9fa2c39951c",
        "archetype": "control",
        "qty": 100,
        "expect_mode": "optimize",
        "scenario": "Deck completo - 100 cartas - deve retornar optimize simples (remoções/adições)"
    },
    {
        "id": "8c22deb9-80bd-489f-8e87-1344eabac698",
        "name": "goblins (completo 100)",
        "user_id": "18df0188-9f27-4e20-84fe-a9fa2c39951c",
        "archetype": "aggro",
        "qty": 100,
        "expect_mode": "optimize",
        "scenario": "Deck mono-R completo - mesmo owner - optimize simples"
    },
    {
        "id": "d5e25e80-5c22-42b2-8eb8-59624b1f149a",
        "name": "Meu Deck Commander (94 cards)",
        "user_id": "582db467-f18c-4dd0-a642-9e60c908fd9d",
        "archetype": "midrange",
        "qty": 94,
        "expect_mode": "complete",
        "scenario": "Deck faltando 6 cartas - complete mode async - preenchimento leve"
    },
    {
        "id": "786f4956-9bca-49e7-afa7-0c0d36548f6e",
        "name": "Debate #7 Atraxa (74 cards)",
        "user_id": "7c4df7f4-2ef7-48bb-815c-c72307fe9e63",
        "archetype": "midrange",
        "qty": 74,
        "expect_mode": "complete",
        "scenario": "Deck 4 cores (WUBG) com 74 cartas - precisa 26 - complete mode grande"
    },
    {
        "id": "872edb81-93fd-4373-aaab-5f189a4197eb",
        "name": "Debate #3 Atraxa (44 cards)",
        "user_id": "dce191a8-5db8-4caa-b63f-19412f379e17",
        "archetype": "midrange",
        "qty": 44,
        "expect_mode": "complete",
        "scenario": "Deck 4 cores com 44 cartas - precisa 56 - grande preenchimento"
    },
    {
        "id": "88887282-d112-4e3d-876c-d3faf209ab29",
        "name": "Debate #8 Krenko (25 cards)",
        "user_id": "18a56811-b72c-495f-a505-519a8fb42526",
        "archetype": "aggro",
        "qty": 25,
        "expect_mode": "complete",
        "scenario": "Deck mono-R (Krenko) - 25 cartas - precisa 75 - grande preenchimento mono-color"
    },
    {
        "id": "0b163477-2e8a-488a-8883-774fcd05281f",
        "name": "Jin/Atraxa (apenas commander)",
        "user_id": "ecfa81f6-af37-4f06-9940-ec5291cbe520",
        "archetype": "midrange",
        "qty": 1,
        "expect_mode": "complete",
        "scenario": "Deck vazio - apenas commander Atraxa - precisa criar 99 cartas do zero"
    },
]

token_cache = {}

def get_token(user_id):
    """Generate JWT directly using the secret (bypasses login)."""
    if user_id in token_cache:
        return token_cache[user_id]
    token = jwt.encode({"userId": user_id}, JWT_SECRET, algorithm="HS256")
    token_cache[user_id] = token
    return token

def poll_job(job_id, token, max_polls=120, interval=2):
    """Polls for async job completion. Returns (result_dict, elapsed_seconds, poll_count)."""
    start = time.time()
    polls = 0
    last_stage = ""
    for i in range(max_polls):
        polls += 1
        r = requests.get(
            f"{BASE}/ai/optimize/jobs/{job_id}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=30
        )
        if r.status_code != 200:
            print(f"  ⚠ Poll #{polls}: HTTP {r.status_code}")
            time.sleep(interval)
            continue
        data = r.json()
        status = data.get("status", "?")
        stage = data.get("stage", "")
        if stage != last_stage:
            elapsed = time.time() - start
            print(f"  ⟳ [{elapsed:5.1f}s] Stage: {stage}")
            last_stage = stage
        if status == "completed":
            elapsed = time.time() - start
            return data, elapsed, polls
        if status == "failed":
            elapsed = time.time() - start
            print(f"  ✗ Job falhou: {data.get('error', '?')}")
            return data, elapsed, polls
        time.sleep(interval)
    elapsed = time.time() - start
    print(f"  ✗ TIMEOUT após {max_polls} polls ({elapsed:.1f}s)")
    return None, elapsed, polls

def analyze_result(data, deck_info):
    """Analyzes the optimization result and returns a summary dict."""
    summary = {"ok": False}
    
    if data is None:
        summary["error"] = "Sem resultado (timeout ou erro)"
        return summary

    if not isinstance(data, dict):
        summary["error"] = f"Resultado não é dict: {type(data)}"
        return summary

    # Result might be nested under "result" key (async) or flat (sync)
    result = data.get("result", data) if isinstance(data, dict) else data
    if not isinstance(result, dict):
        summary["error"] = f"Result field não é dict: {type(result)}"
        return summary
    
    mode = result.get("mode", "?")
    summary["mode"] = mode
    
    # For async mode, the optimize_response may be nested
    optimize_resp = result.get("optimize_response")
    if isinstance(optimize_resp, dict):
        result = optimize_resp
        mode = result.get("mode", mode)
        summary["mode"] = mode

    additions = result.get("additions_detailed", [])
    if not additions:
        additions = result.get("additions", [])
    if not isinstance(additions, list):
        additions = []
    removals = result.get("removals_detailed", [])
    if not removals:
        removals = result.get("removals", [])
    if not isinstance(removals, list):
        removals = []
    
    summary["additions_count"] = len(additions)
    summary["removals_count"] = len(removals)
    
    additions_qty = sum(
        (a.get("quantity", 1) if isinstance(a, dict) else 1) for a in additions
    )
    removals_qty = sum(
        (r.get("quantity", 1) if isinstance(r, dict) else 1) for r in removals
    )
    summary["additions_qty"] = additions_qty
    summary["removals_qty"] = removals_qty
    
    # Expected final count
    expected_final = deck_info["qty"] + additions_qty - removals_qty
    summary["expected_final"] = expected_final
    
    # Mana analysis
    post = result.get("post_analysis", {})
    if post:
        type_dist = post.get("type_distribution", {})
        land_count = type_dist.get("lands", 0) if isinstance(type_dist, dict) else 0
        summary["lands"] = land_count
        summary["avg_cmc"] = post.get("average_cmc", "?")
        summary["total_cards_post"] = post.get("total_cards", "?")
        summary["mana_curve"] = post.get("mana_curve_assessment", "?")
        summary["mana_base"] = post.get("mana_base_assessment", "?")
        summary["type_distribution"] = type_dist
    
    # Stages used
    meta = result.get("pipeline_metadata", result.get("metadata", {}))
    if meta:
        summary["iterations"] = meta.get("iterations", "?")
        summary["ai_stage"] = meta.get("ai_stage_used", "?")
        summary["deterministic_stage"] = meta.get("deterministic_stage_used", "?")
        summary["basics_stage"] = meta.get("guaranteed_basics_stage_used", "?")
    
    # Warnings
    warnings = result.get("warnings", [])
    summary["warnings"] = warnings
    
    # Quality checks
    is_commander = deck_info.get("expect_mode") == "complete" or deck_info["qty"] < 100
    if is_commander and mode == "complete":
        # Commander deck should reach 100
        target = 100
        if expected_final == target:
            summary["qty_check"] = "✓ 100 cartas"
        elif expected_final >= 99:
            summary["qty_check"] = f"≈ {expected_final} cartas (aceitável)"
        else:
            summary["qty_check"] = f"✗ {expected_final} cartas (esperado {target})"
        
        # Lands should be 35-40 for commander
        type_dist = post.get("type_distribution", {}) if post else {}
        lands = type_dist.get("lands", 0) if isinstance(type_dist, dict) else 0
        if isinstance(lands, (int, float)):
            if 33 <= lands <= 42:
                summary["land_check"] = f"✓ {lands} lands (ideal)"
            elif 28 <= lands <= 45:
                summary["land_check"] = f"≈ {lands} lands (aceitável)"
            else:
                summary["land_check"] = f"✗ {lands} lands (fora do range)"
        
        # Mana verdict
        verdict = summary.get("mana_verdict", "")
        if "equilibrada" in str(verdict).lower():
            summary["mana_check"] = "✓ Base equilibrada"
        elif "falta" in str(verdict).lower():
            summary["mana_check"] = f"⚠ {verdict}"
        else:
            summary["mana_check"] = f"? {verdict}"
    
    summary["ok"] = True
    return summary

def print_summary(deck_info, summary, elapsed, polls):
    """Pretty-prints the test result."""
    print(f"\n{'='*70}")
    print(f"  DECK: {deck_info['name']}")
    print(f"  Cenário: {deck_info['scenario']}")
    print(f"{'='*70}")
    print(f"  Tempo total: {elapsed:.1f}s ({polls} polls)" if polls > 0 else f"  Tempo total: {elapsed:.1f}s (sync)")
    print(f"  Mode: {summary.get('mode', '?')}")
    print(f"  Adições: {summary.get('additions_count', '?')} entries ({summary.get('additions_qty', '?')} qty)")
    print(f"  Remoções: {summary.get('removals_count', '?')} entries ({summary.get('removals_qty', '?')} qty)")
    print(f"  Total final estimado: {summary.get('expected_final', '?')}")
    
    if "lands" in summary:
        print(f"  Lands: {summary['lands']}")
    if "avg_cmc" in summary:
        print(f"  CMC médio: {summary['avg_cmc']}")
    if "mana_curve" in summary:
        print(f"  Curva de mana: {summary['mana_curve']}")
    if "mana_base" in summary:
        print(f"  Base de mana: {summary['mana_base']}")
    if "total_cards_post" in summary:
        print(f"  Total (post_analysis): {summary['total_cards_post']}")
    if "type_distribution" in summary:
        td = summary["type_distribution"]
        parts = [f"{k}:{v}" for k, v in sorted(td.items()) if v > 0]
        print(f"  Distribuição: {', '.join(parts)}")
    
    if "qty_check" in summary:
        print(f"  [Qty] {summary['qty_check']}")
    if "land_check" in summary:
        print(f"  [Land] {summary['land_check']}")
    if "mana_check" in summary:
        print(f"  [Mana] {summary['mana_check']}")
    
    if summary.get("iterations"):
        print(f"  Iterações AI: {summary['iterations']}")
    stages = []
    if summary.get("ai_stage"): stages.append("AI")
    if summary.get("deterministic_stage"): stages.append("Deterministic")
    if summary.get("basics_stage"): stages.append("Basics")
    if stages:
        print(f"  Stages usados: {', '.join(stages)}")
    
    warns = summary.get("warnings", [])
    if warns:
        if isinstance(warns, dict):
            print(f"  ⚠ Warnings:")
            for k, v in warns.items():
                desc = str(v)[:150]
                print(f"    - {k}: {desc}")
        elif isinstance(warns, list):
            print(f"  ⚠ Warnings ({len(warns)}):")
            for w in warns[:5]:
                print(f"    - {w}")
    
    print()

def test_deck(deck_info):
    """Tests a single deck through optimize/complete flow. Returns (summary, elapsed, polls)."""
    print(f"\n{'─'*70}")
    print(f"▶ Testando: {deck_info['name']} ({deck_info['qty']} cartas)")
    print(f"  Cenário: {deck_info['scenario']}")
    print(f"{'─'*70}")
    
    # Auth
    token = get_token(deck_info["user_id"])
    if not token:
        return {"ok": False, "error": "Auth failed"}, 0, 0
    print(f"  ✓ Auth OK")
    
    # Fire optimize
    start = time.time()
    try:
        r = requests.post(
            f"{BASE}/ai/optimize",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json={
                "deck_id": deck_info["id"],
                "archetype": deck_info.get("archetype", "midrange"),
                "mode": "complete",
            },
            timeout=60
        )
    except Exception as e:
        elapsed = time.time() - start
        return {"ok": False, "error": f"Request failed: {e}"}, elapsed, 0
    
    elapsed = time.time() - start
    print(f"  HTTP {r.status_code} em {elapsed:.1f}s")
    
    if r.status_code == 202:
        # Async mode - poll
        data = r.json()
        job_id = data.get("job_id")
        print(f"  ↳ Job ID: {job_id}")
        result, poll_elapsed, polls = poll_job(job_id, token)
        total_elapsed = elapsed + poll_elapsed
        summary = analyze_result(result, deck_info)
        return summary, total_elapsed, polls
    
    elif r.status_code == 200:
        # Sync mode
        data = r.json()
        summary = analyze_result(data, deck_info)
        return summary, elapsed, 0
    
    else:
        body = r.text[:500]
        print(f"  ✗ Erro: {body}")
        return {"ok": False, "error": f"HTTP {r.status_code}: {body}"}, elapsed, 0


# ══════════════════════════════════════════════════════════════════
#   MAIN
# ══════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    print("=" * 70)
    print("  TESTE COMPLETO DO FLUXO DE OTIMIZAÇÃO")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Server: {BASE}")
    print(f"  Decks a testar: {len(TEST_DECKS)}")
    print("=" * 70)
    
    # Quick health check
    try:
        r = requests.get(f"{BASE}/health", timeout=5)
        print(f"  Health: {r.json().get('status', '?')}")
    except:
        print("  ✗ Server não respondeu! Aborting.")
        sys.exit(1)
    
    results = []
    total_start = time.time()
    
    for deck in TEST_DECKS:
        try:
            summary, elapsed, polls = test_deck(deck)
            results.append({
                "deck": deck,
                "summary": summary,
                "elapsed": elapsed,
                "polls": polls
            })
            print_summary(deck, summary, elapsed, polls)
        except Exception as e:
            print(f"  ✗ EXCEÇÃO: {e}")
            results.append({
                "deck": deck,
                "summary": {"ok": False, "error": str(e)},
                "elapsed": 0,
                "polls": 0
            })
    
    total_elapsed = time.time() - total_start
    
    # ── RELATÓRIO FINAL ───────────────────────────────────────────
    print("\n" + "═" * 70)
    print("  RELATÓRIO FINAL")
    print("═" * 70)
    print(f"\n{'Deck':<35} {'Mode':<10} {'Tempo':<8} {'Add':<5} {'Rem':<5} {'Final':<6} {'Lands':<6} {'Mana':<20}")
    print("─" * 100)
    
    ok_count = 0
    fail_count = 0
    for res in results:
        d = res["deck"]
        s = res["summary"]
        name = d["name"][:34]
        mode = s.get("mode", "err")
        elapsed = f"{res['elapsed']:.0f}s"
        adds = str(s.get("additions_qty", "-"))
        rems = str(s.get("removals_qty", "-"))
        final = str(s.get("expected_final", "-"))
        lands = str(s.get("lands", "-"))
        mana = str(s.get("mana_verdict", "-"))[:19]
        
        if s.get("ok"):
            ok_count += 1
            status = "✓"
        else:
            fail_count += 1
            status = "✗"
        
        print(f"{status} {name:<33} {mode:<10} {elapsed:<8} {adds:<5} {rems:<5} {final:<6} {lands:<6} {mana}")
    
    print("─" * 100)
    print(f"\n  Total: {ok_count} OK, {fail_count} FALHAS")
    print(f"  Tempo total: {total_elapsed:.0f}s")
    print(f"  Média por deck: {total_elapsed/len(TEST_DECKS):.0f}s")
    print()
    
    # Save results as JSON
    output_path = "/Users/desenvolvimentomobile/Documents/rafa/mtg/mtgia/server/test/artifacts/ai_optimize/full_flow_test_results.json"
    try:
        with open(output_path, "w") as f:
            json.dump({
                "timestamp": datetime.now().isoformat(),
                "total_elapsed_s": round(total_elapsed, 1),
                "ok_count": ok_count,
                "fail_count": fail_count,
                "results": [
                    {
                        "deck_id": r["deck"]["id"],
                        "deck_name": r["deck"]["name"],
                        "deck_qty": r["deck"]["qty"],
                        "elapsed_s": round(r["elapsed"], 1),
                        "polls": r["polls"],
                        "summary": r["summary"]
                    }
                    for r in results
                ]
            }, f, indent=2, default=str)
        print(f"  Resultados salvos em: {output_path}")
    except Exception as e:
        print(f"  ⚠ Falha ao salvar: {e}")
