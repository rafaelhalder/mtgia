#!/usr/bin/env python3
import json

with open('test/artifacts/ai_optimize/source_deck_optimize_latest.json') as f:
    data = json.load(f)

body = data.get('optimize_response', data.get('body', data))
ad = body.get('additions_detailed', [])
post = body.get('post_analysis', {})
deck_a = body.get('deck_analysis', {})

total_entries = len(ad)
total_qty = sum(e.get('quantity', 1) for e in ad)
basics = [e for e in ad if e.get('is_basic_land')]
non_basics = [e for e in ad if not e.get('is_basic_land')]
basic_qty = sum(e.get('quantity', 1) for e in basics)
non_basic_qty = sum(e.get('quantity', 1) for e in non_basics)

td = post.get('type_distribution', {})

print('=== ADDITIONS SUMMARY ===')
print(f'Total entries: {total_entries}')
print(f'Total qty: {total_qty}')
print(f'Basic entries: {len(basics)}, total qty: {basic_qty}')
for b in basics:
    print(f'  {b["name"]}: qty={b.get("quantity", 1)}')
print(f'Non-basic entries: {len(non_basics)}, total qty: {non_basic_qty}')

# Count non-basic lands
land_names = []
for nb in non_basics:
    name = nb.get('name', '')
    # Check known land names
    if any(kw in name.lower() for kw in ['land', 'forest', 'plains', 'island', 'swamp', 'mountain',
        'pool', 'catacomb', 'strand', 'delta', 'rainforest', 'hollow', 'tower', 'bastion',
        'palace', 'canyon', 'stage', 'orchard', 'promenade', 'vesuva', 'pit', 'river',
        'isle', 'tainted']):
        land_names.append(name)
    elif 'command tower' in name.lower():
        land_names.append(name)

print(f'\nNon-basic lands detected in additions: {len(land_names)}')
for ln in land_names:
    print(f'  {ln}')

print()
print('=== POST ANALYSIS ===')
print(f'total_cards: {post.get("total_cards")}')
print(f'type_distribution: {json.dumps(td, indent=2)}')
print(f'mana_base_assessment: {post.get("mana_base_assessment")}')
print(f'mana_curve_assessment: {post.get("mana_curve_assessment")}')
print(f'average_cmc: {post.get("average_cmc")}')
print(f'detected_archetype: {post.get("detected_archetype")}')

print()
print('=== PRE ANALYSIS (deck_analysis) ===')
print(f'mana_base_assessment: {deck_a.get("mana_base_assessment")}')

# Check iterations
print(f'\nIterations: {body.get("iterations")}')
print(f'Target additions: {body.get("target_additions")}')

# Warnings
warnings = body.get('warnings', {})
if warnings:
    print(f'\nWarnings: {json.dumps(warnings, indent=2)}')
