#!/usr/bin/env python3
"""Analyze the full optimize flow test results."""
import json
import sys

RESULTS_FILE = "test/artifacts/ai_optimize/full_flow_test_results.json"

with open(RESULTS_FILE) as f:
    data = json.load(f)

print("=" * 80)
print("FULL OPTIMIZE FLOW — ANALYSIS REPORT")
print("=" * 80)

for r in data["results"]:
    name = r["deck_name"]
    qty = r["deck_qty"]
    elapsed = r["elapsed_s"]
    polls = r["polls"]
    s = r["summary"]

    print(f"\n{'─' * 70}")
    print(f"DECK: {name} ({qty} cards)")
    print(f"{'─' * 70}")
    print(f"  Mode: {s.get('mode', '?')}")
    print(f"  HTTP: {r.get('http_status', '?')}")
    print(f"  Elapsed: {elapsed}s  (polls: {polls})")
    print(f"  OK: {s.get('ok')}")
    print(f"  Additions: {s.get('additions_count', 0)} entries → {s.get('additions_qty', 0)} qty total")
    print(f"  Removals:  {s.get('removals_count', 0)} entries → {s.get('removals_qty', 0)} qty total")
    print(f"  Expected final: {s.get('expected_final')}")

    # Post-analysis
    pa_keys = ["lands", "avg_cmc", "mana_verdict", "iterations", "ai_stage", "deterministic_stage", "basics_stage"]
    pa = {k: s.get(k, "?") for k in pa_keys}
    print(f"  Post-analysis: lands={pa['lands']}  cmc={pa['avg_cmc']}  mana={pa['mana_verdict']}")
    print(f"  Stages: iter={pa['iterations']} ai={pa['ai_stage']} determ={pa['deterministic_stage']} basics={pa['basics_stage']}")

    # Warnings
    warns = s.get("warnings", [])
    if isinstance(warns, list) and warns:
        print(f"  Warnings ({len(warns)}):")
        for w in warns[:5]:
            print(f"    - {w}")
    elif isinstance(warns, dict):
        print(f"  Warnings: {json.dumps(warns, indent=4)[:200]}")

    # Error
    err = s.get("error")
    if err:
        print(f"  ERROR: {err}")

# Now let's look at RAW response structure for one async result
print("\n" + "=" * 80)
print("RAW RESPONSE STRUCTURE — First async deck")
print("=" * 80)

for r in data["results"]:
    if r.get("polls", 0) > 0:  # async
        print(f"\nDeck: {r['deck_name']}")
        raw = r.get("raw_result") or r.get("result") or r.get("response")
        if raw:
            # Show top-level keys
            if isinstance(raw, dict):
                print(f"Top-level keys: {list(raw.keys())}")
                for k, v in raw.items():
                    if isinstance(v, (str, int, float, bool)):
                        print(f"  {k}: {v}")
                    elif isinstance(v, list):
                        print(f"  {k}: list[{len(v)}]")
                        if v:
                            print(f"    first: {json.dumps(v[0], indent=2)[:200]}")
                    elif isinstance(v, dict):
                        print(f"  {k}: dict with keys {list(v.keys())[:10]}")
                        # Show sub-dict briefly
                        for sk, sv in list(v.items())[:5]:
                            if isinstance(sv, (str, int, float, bool)):
                                print(f"    {sk}: {sv}")
                            elif isinstance(sv, list):
                                print(f"    {sk}: list[{len(sv)}]")
                            elif isinstance(sv, dict):
                                print(f"    {sk}: dict{list(sv.keys())[:5]}")
            else:
                print(f"  type: {type(raw).__name__}, value: {str(raw)[:300]}")
        else:
            print("  No raw_result/result/response found")
            print(f"  Available keys in record: {list(r.keys())}")
        break  # Only first async

# Now dump all response keys for ALL results
print("\n" + "=" * 80)
print("ALL RESULT RECORD KEYS")
print("=" * 80)
for r in data["results"]:
    print(f"\n{r['deck_name']}:")
    print(f"  Record keys: {list(r.keys())}")
    # Check if there's a full_response or similar
    for k in r:
        if k not in ("deck_name", "deck_qty", "deck_id", "archetype", "elapsed_s", "polls", "summary", "http_status"):
            v = r[k]
            if isinstance(v, dict):
                print(f"  {k} (dict): keys = {list(v.keys())[:15]}")
            elif isinstance(v, list):
                print(f"  {k} (list): len = {len(v)}")
            elif isinstance(v, str) and len(v) > 100:
                print(f"  {k} (str): {v[:100]}...")
            else:
                print(f"  {k}: {v}")
