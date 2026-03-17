#!/usr/bin/env python3
"""Analyze the raw complete response to understand qty vs entries."""
import json

with open("test/artifacts/ai_optimize/raw_complete_response.json") as f:
    data = json.load(f)

result = data["result"]
ad = result["additions_detailed"]

# Basic stats
total_entries = len(ad)
total_qty = sum(a["quantity"] for a in ad)
target = result["target_additions"]

print(f"Total entries (unique cards): {total_entries}")
print(f"Total qty (sum of quantities): {total_qty}")
print(f"target_additions: {target}")
print(f"Match? {total_qty == target}")

# Entries with qty > 1
multi = [a for a in ad if a.get("quantity", 1) > 1]
print(f"\nEntries with qty > 1: {len(multi)}")
for m in multi:
    print(f"  {m['name']}: qty={m['quantity']}  is_basic={m.get('is_basic_land')}")

# Basic lands
basics = [a for a in ad if a.get("is_basic_land")]
print(f"\nBasic lands entries: {len(basics)}, qty: {sum(b['quantity'] for b in basics)}")
for b in basics:
    print(f"  {b['name']}: qty={b['quantity']}")

# Post analysis
pa = result.get("post_analysis", {})
print(f"\nPost-analysis:")
for k, v in pa.items():
    print(f"  {k}: {v}")

# Deck analysis
da = result.get("deck_analysis", {})
print(f"\nDeck analysis:")
for k, v in da.items():
    if isinstance(v, str) and len(v) > 200:
        print(f"  {k}: {v[:200]}...")
    else:
        print(f"  {k}: {v}")

# Reasoning
r = result.get("reasoning", "")
print(f"\nReasoning: {r[:500]}...")

# Validation warnings
vw = result.get("validation_warnings", [])
print(f"\nValidation warnings: {len(vw)}")
for w in vw[:5]:
    print(f"  - {w}")
