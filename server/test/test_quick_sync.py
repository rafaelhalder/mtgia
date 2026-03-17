#!/usr/bin/env python3
"""
Quick test: only sync optimize decks (Jin + Goblins) to verify quantity fix.
"""
import requests
import json
import time
import jwt
from datetime import datetime

BASE = "http://localhost:8080"
JWT_SECRET = "your-super-secret-and-long-string-for-jwt"

QUICK_DECKS = [
    {
        "id": "f2a2a34a-4561-4a77-886d-7067b672ac85",
        "name": "jin (100 cards - sync optimize)",
        "user_id": "18df0188-9f27-4e20-84fe-a9fa2c39951c",
        "archetype": "control",
        "qty": 100,
    },
    {
        "id": "8c22deb9-80bd-489f-8e87-1344eabac698",
        "name": "goblins (100 cards - sync optimize)",
        "user_id": "18df0188-9f27-4e20-84fe-a9fa2c39951c",
        "archetype": "aggro",
        "qty": 100,
    },
]

def get_token(user_id):
    return jwt.encode({"userId": user_id}, JWT_SECRET, algorithm="HS256")

for deck in QUICK_DECKS:
    print(f"\n{'='*60}")
    print(f"  {deck['name']}")
    print(f"{'='*60}")
    
    token = get_token(deck["user_id"])
    start = time.time()
    
    r = requests.post(
        f"{BASE}/ai/optimize",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={
            "deck_id": deck["id"],
            "archetype": deck.get("archetype", "midrange"),
            "mode": "complete",
        },
        timeout=60
    )
    
    elapsed = time.time() - start
    print(f"  HTTP {r.status_code} em {elapsed:.1f}s")
    
    if r.status_code != 200:
        print(f"  ERROR: {r.text[:300]}")
        continue
    
    data = r.json()
    
    # Extract key metrics
    mode = data.get("mode", "?")
    additions = data.get("additions_detailed", data.get("additions", []))
    removals = data.get("removals_detailed", data.get("removals", []))
    
    add_qty = sum(a.get("quantity", 1) if isinstance(a, dict) else 1 for a in additions) if isinstance(additions, list) else 0
    rem_qty = sum(r.get("quantity", 1) if isinstance(r, dict) else 1 for r in removals) if isinstance(removals, list) else 0
    
    post = data.get("post_analysis", {})
    type_dist = post.get("type_distribution", {})
    lands = type_dist.get("lands", "?")
    total = post.get("total_cards", "?")
    avg_cmc = post.get("average_cmc", "?")
    mana_assessment = post.get("mana_base_assessment", "?")
    archetype = post.get("detected_archetype", "?")
    
    print(f"  Mode: {mode}")
    print(f"  Additions: {add_qty}, Removals: {rem_qty}")
    print(f"  post_analysis.total_cards: {total}")
    print(f"  post_analysis.lands: {lands}")
    print(f"  post_analysis.avg_cmc: {avg_cmc}")
    print(f"  post_analysis.archetype: {archetype}")
    print(f"  post_analysis.mana_base: {mana_assessment}")
    print(f"  Type distribution: {json.dumps(type_dist, indent=2)}")
    
    # Warnings
    warns = data.get("warnings", [])
    if warns:
        print(f"  Warnings: {json.dumps(warns, indent=2, default=str)[:500]}")
    
    # KEY VALIDATION
    if isinstance(lands, (int, float)):
        if lands >= 28:
            print(f"  ✅ PASS: {lands} lands (>= 28 minimum)")
        else:
            print(f"  ❌ FAIL: {lands} lands (< 28 minimum)")
    else:
        print(f"  ⚠ Cannot validate lands: {lands}")
    
    # Additions names for inspection
    if isinstance(additions, list) and len(additions) > 0:
        names = [a.get("name", a) if isinstance(a, dict) else a for a in additions]
        print(f"  Additions: {names}")
    if isinstance(removals, list) and len(removals) > 0:
        names = [r.get("name", r) if isinstance(r, dict) else r for r in removals]
        print(f"  Removals: {names}")

print(f"\n{'='*60}")
print("  DONE")
print(f"{'='*60}")
