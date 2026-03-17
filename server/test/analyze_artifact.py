#!/usr/bin/env python3
import json, sys, os

# Find the file relative to script location or cwd
script_dir = os.path.dirname(os.path.abspath(__file__))
artifact_path = os.path.join(script_dir, 'artifacts/ai_optimize/source_deck_optimize_latest.json')
if not os.path.exists(artifact_path):
    artifact_path = 'test/artifacts/ai_optimize/source_deck_optimize_latest.json'

with open(artifact_path) as f:
    raw = json.load(f)

# Unwrap if wrapped in test structure
if 'optimize_response' in raw:
    d = raw['optimize_response']
else:
    d = raw

print('=== TOP LEVEL ===')
print(f'mode: {d.get("mode","?")}')
print(f'target_additions: {d.get("target_additions","?")}')
print(f'iterations: {d.get("iterations","?")}')
print(f'bracket: {d.get("bracket","?")}')

adds = d['additions_detailed']
print(f'\n=== ADDITIONS ===')
print(f'additions_detailed entries: {len(adds)}')
total_qty = sum(a['quantity'] for a in adds)
print(f'total quantity (sum of qty): {total_qty}')

basics = [a for a in adds if a.get('is_basic_land')]
non_basics = [a for a in adds if not a.get('is_basic_land')]
basic_qty = sum(a['quantity'] for a in basics)
non_basic_qty = sum(a['quantity'] for a in non_basics)
print(f'basic entries: {len(basics)}, total basic qty: {basic_qty}')
print(f'non-basic entries: {len(non_basics)}, total non-basic qty: {non_basic_qty}')

print('\nBasic land details:')
for b in basics:
    print(f'  {b["name"]}: qty={b["quantity"]}, card_id={b["card_id"]}')

print(f'\n=== DECK ANALYSIS (pre - original deck only) ===')
da = d.get('deck_analysis', {})
for k,v in da.items():
    print(f'  {k}: {v}')

print(f'\n=== POST ANALYSIS (after additions) ===')
pa = d.get('post_analysis', {})
for k,v in pa.items():
    print(f'  {k}: {v}')

print(f'\n=== KNOWN LAND CARDS IN ADDITIONS ===')
land_keywords = ['plains', 'island', 'swamp', 'forest', 'mountain', 'wastes',
    'command tower', 'exotic orchard', 'war room', 'reliquary tower',
    'path of ancestry', 'bastion', 'boseiju', 'sea of clouds',
    'flooded strand', 'polluted delta', 'misty rainforest',
    'drowned catacomb', 'sunken hollow', 'underground river',
    'creeping tar pit']
land_count = 0
land_qty = 0
for a in adds:
    nl = a['name'].lower()
    is_land = a.get('is_basic_land', False)
    for kw in land_keywords:
        if kw in nl:
            is_land = True
            break
    if is_land:
        land_count += 1
        land_qty += a['quantity']
        print(f'  {a["name"]}: qty={a["quantity"]}, basic={a.get("is_basic_land")}')

print(f'Total land entries: {land_count}, total land qty: {land_qty}')

print(f'\n=== WARNINGS ===')
w = d.get('warnings', {})
for k,v in w.items():
    if isinstance(v, dict):
        print(f'  {k}:')
        for k2,v2 in v.items():
            if isinstance(v2, list):
                print(f'    {k2}: {len(v2)} items')
                for item in v2[:5]:
                    print(f'      {item}')
            else:
                print(f'    {k2}: {v2}')
    elif isinstance(v, list):
        print(f'  {k}: {v}')
    else:
        print(f'  {k}: {v}')

# Check consistency_slo if present
if 'consistency_slo' in d:
    print(f'\n=== CONSISTENCY SLO ===')
    for k,v in d['consistency_slo'].items():
        print(f'  {k}: {v}')
