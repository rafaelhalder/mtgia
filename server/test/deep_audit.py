#!/usr/bin/env python3
"""Deep audit: analyze all test results + raw response for every issue."""
import json, sys

# Load the 7-deck test results
with open("test/artifacts/ai_optimize/full_flow_test_results.json") as f:
    test_data = json.load(f)

# Load the quality gate artifact (1-card deck, most complex)
with open("test/artifacts/ai_optimize/source_deck_optimize_latest.json") as f:
    qg_data = json.load(f)

# Also load the raw Krenko response if available
try:
    with open("test/artifacts/ai_optimize/raw_complete_response.json") as f:
        krenko_raw = json.load(f)
except:
    krenko_raw = None

print("=" * 80)
print("DEEP AUDIT — ALL ISSUES ACROSS ALL DECK SCENARIOS")
print("=" * 80)

issues = []

# ──────────────────────────────────────────
# 1. Analyze the quality gate artifact (1-card Atraxa deck)
# ──────────────────────────────────────────
print("\n[1] Quality Gate Artifact (1-card deck → 100)")
qg_result = qg_data.get("result", qg_data)
if "result" in qg_data:
    qg_result = qg_data["result"]
else:
    qg_result = qg_data

# Check if it has the expected structure
for key in ["mode", "additions", "additions_detailed", "post_analysis", "deck_analysis", "warnings"]:
    val = qg_result.get(key)
    if val is None:
        print(f"  MISSING key: {key}")
    else:
        t = type(val).__name__
        if isinstance(val, list):
            print(f"  {key}: list[{len(val)}]")
        elif isinstance(val, dict):
            print(f"  {key}: dict keys={list(val.keys())[:8]}")
        else:
            print(f"  {key}: {t} = {str(val)[:80]}")

# Analyze additions
ad = qg_result.get("additions_detailed", [])
total_qty = sum(a.get("quantity", 1) for a in ad)
basics = [a for a in ad if a.get("is_basic_land")]
non_basics = [a for a in ad if not a.get("is_basic_land")]
basic_qty = sum(b.get("quantity", 1) for b in basics)

print(f"\n  Additions: {len(ad)} entries, {total_qty} total qty")
print(f"  Basics: {len(basics)} entries, {basic_qty} qty")
print(f"  Non-basics: {len(non_basics)} entries")
print(f"  Target additions: {qg_result.get('target_additions')}")
print(f"  Iterations: {qg_result.get('iterations')}")

# Post analysis
pa = qg_result.get("post_analysis", {})
td = pa.get("type_distribution", {})
total_cards = pa.get("total_cards", 0)
lands = td.get("lands", 0)
creatures = td.get("creatures", 0)
print(f"\n  Post-analysis total: {total_cards}")
print(f"  Type dist: {td}")
print(f"  CMC: {pa.get('average_cmc')}")
print(f"  Mana curve: {pa.get('mana_curve_assessment')}")
print(f"  Mana base: {pa.get('mana_base_assessment')}")

# Deck analysis (BEFORE)
da = qg_result.get("deck_analysis", {})
print(f"\n  Deck analysis (BEFORE):")
print(f"  Total: {da.get('total_cards')}")
print(f"  Types: {da.get('type_distribution')}")
print(f"  CMC: {da.get('average_cmc')}")
print(f"  Mana base: {da.get('mana_base_assessment')}")

# Warnings
warns = qg_result.get("warnings", {})
if isinstance(warns, dict):
    for k, v in warns.items():
        if k == "invalid_cards":
            cards_list = v if isinstance(v, list) else v.get("invalid_cards", []) if isinstance(v, dict) else []
            print(f"\n  WARNING invalid_cards: {len(cards_list)} cards")
            for c in cards_list[:10]:
                print(f"    - {c}")
        elif k == "blocked_by_bracket":
            blocked = v.get("blocked_additions", []) if isinstance(v, dict) else []
            print(f"\n  WARNING blocked_by_bracket: {len(blocked)} cards")
            for b in blocked[:5]:
                print(f"    - {b}")
        elif k == "filtered_by_color_identity":
            removed = v.get("removed_additions", []) if isinstance(v, dict) else []
            print(f"\n  WARNING filtered_by_color_identity: {len(removed) if isinstance(removed, list) else '?'}")
            if isinstance(removed, list):
                for r in removed[:5]:
                    print(f"    - {r}")

# ──────────────────────────────────────────
# 2. Analyze Krenko raw response (25-card deck)
# ──────────────────────────────────────────
if krenko_raw:
    print("\n\n[2] Krenko Raw Response (25-card deck → 100)")
    kr = krenko_raw.get("result", {})
    ad_k = kr.get("additions_detailed", [])
    total_k = sum(a.get("quantity", 1) for a in ad_k)
    basics_k = [a for a in ad_k if a.get("is_basic_land")]
    basic_qty_k = sum(b.get("quantity", 1) for b in basics_k)
    
    pa_k = kr.get("post_analysis", {})
    td_k = pa_k.get("type_distribution", {})
    
    print(f"  Additions: {len(ad_k)} entries, {total_k} qty")
    print(f"  Basics: {len(basics_k)} entries, {basic_qty_k} qty")
    print(f"  Post analysis total: {pa_k.get('total_cards')}")
    print(f"  Lands: {td_k.get('lands', 0)}")
    print(f"  Creatures: {td_k.get('creatures', 0)}")
    print(f"  Theme: {kr.get('theme', {}).get('theme')}")
    print(f"  Archetype detected: {pa_k.get('detected_archetype')}")
    
    # ISSUE: theme says spellslinger for a goblin deck
    theme = kr.get("theme", {}).get("theme", "")
    if "goblin" not in theme.lower() and "tribal" not in theme.lower():
        issues.append(f"ISSUE: Krenko mono-R goblin deck detected as '{theme}' instead of tribal-goblin/aggro")

# ──────────────────────────────────────────
# 3. Cross-deck analysis from test results
# ──────────────────────────────────────────
print("\n\n[3] Cross-Deck Analysis (7 decks)")

for r in test_data["results"]:
    name = r["deck_name"]
    qty = r["deck_qty"]
    s = r["summary"]
    mode = s.get("mode", "?")
    ok = s.get("ok", False)
    add_qty = s.get("additions_qty", 0)
    rem_qty = s.get("removals_qty", 0)
    final_est = s.get("expected_final", 0)
    lands_count = s.get("lands", 0)
    avg_cmc = s.get("avg_cmc", "?")
    
    print(f"\n  {name} ({qty} cards) → mode={mode}")
    print(f"    Final: {final_est}, Lands: {lands_count}, CMC: {avg_cmc}")
    
    # Check: final should be 100
    if isinstance(final_est, (int, float)) and final_est != 100:
        issues.append(f"ISSUE: {name} final={final_est} (expected 100)")
    
    # Check: lands should be 33-42 for commander
    if isinstance(lands_count, (int, float)) and lands_count > 0:
        if lands_count < 28:
            issues.append(f"CRITICAL: {name} only {lands_count} lands (min 28 for Commander)")
        elif lands_count < 33:
            issues.append(f"WARNING: {name} only {lands_count} lands (ideal 33-42)")
        elif lands_count > 42:
            issues.append(f"WARNING: {name} has {lands_count} lands (too many, max ~42)")
    
    # Check: optimize mode should not leave bad mana
    if mode == "optimize":
        mana_base = s.get("mana_base", "?")
        if isinstance(mana_base, str) and "Falta mana" in str(mana_base):
            issues.append(f"ISSUE: {name} (optimize mode) still has mana problems: {mana_base}")
        if isinstance(lands_count, (int, float)) and lands_count < 28:
            issues.append(f"CRITICAL: {name} optimize mode left deck with only {lands_count} lands")
    
    # Check: CMC for aggro should be < 3.0
    if isinstance(avg_cmc, (int, float)) and mode == "optimize":
        pass  # Could check per archetype

print("\n\n" + "=" * 80)
print("ALL ISSUES FOUND")
print("=" * 80)
for i, issue in enumerate(issues, 1):
    print(f"  {i}. {issue}")

if not issues:
    print("  No critical issues found!")
