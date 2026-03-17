#!/usr/bin/env python3
"""Verify exactly how allCardData is structured for Jin's deck."""
import psycopg2

conn = psycopg2.connect('postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder')
cur = conn.cursor()

# Jin deck: simulate what the Dart code does
# One row per deck_cards entry
cur.execute("""
    SELECT c.name, dc.is_commander, dc.quantity, c.type_line, c.mana_cost
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = 'f2a2a34a-4561-4a77-886d-7067b672ac85'
    ORDER BY c.type_line, c.name
""")
rows = cur.fetchall()
total_qty = 0
land_entries = 0
land_qty = 0
all_entries = 0
for r in rows:
    name, is_cmdr, qty, type_line, mana = r
    total_qty += qty
    all_entries += 1
    is_land = 'land' in (type_line or '').lower()
    if is_land:
        land_entries += 1
        land_qty += qty
    if qty > 1:
        print(f'  QTY={qty}: {name} [{type_line}]{"  *** LAND" if is_land else ""}')

print(f'\nJin deck: {all_entries} DB entries, {total_qty} total qty')
print(f'  Lands: {land_entries} entries (unique), {land_qty} total qty')
print(f'  Non-lands: {all_entries - land_entries} entries, {total_qty - land_qty} total qty')
print(f'\n  DeckArchetypeAnalyzer sees: {land_entries} lands (should be {land_qty})')
print(f'  Error factor: {land_qty / land_entries:.1f}x undercount!')

# Same for Goblins
cur.execute("""
    SELECT c.name, dc.quantity, c.type_line
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = '8c22deb9-80bd-489f-8e87-1344eabac698'
    ORDER BY c.type_line, c.name
""")
rows = cur.fetchall()
total_qty = 0
land_entries = 0
land_qty = 0
all_entries = 0
for r in rows:
    name, qty, type_line = r
    total_qty += qty
    all_entries += 1
    is_land = 'land' in (type_line or '').lower()
    if is_land:
        land_entries += 1
        land_qty += qty
    if qty > 1:
        print(f'  QTY={qty}: {name} [{type_line}]{"  *** LAND" if is_land else ""}')

print(f'\nGoblins deck: {all_entries} DB entries, {total_qty} total qty')
print(f'  Lands: {land_entries} entries (unique), {land_qty} total qty')
print(f'  Non-lands: {all_entries - land_entries} entries, {total_qty - land_qty} total qty')
print(f'  DeckArchetypeAnalyzer sees: {land_entries} lands (should be {land_qty})')

# 94-card deck
cur.execute("""
    SELECT c.name, dc.quantity, c.type_line
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = 'd5e25e80-5c22-42b2-8eb8-59624b1f149a'
""")
rows = cur.fetchall()
total_qty = sum(r[1] for r in rows)
land_entries = sum(1 for r in rows if 'land' in (r[2] or '').lower())
land_qty = sum(r[1] for r in rows if 'land' in (r[2] or '').lower())
print(f'\n94-card deck: {len(rows)} entries, {total_qty} total qty')
print(f'  Lands: {land_entries} entries (unique), {land_qty} total qty')

conn.close()
print('\n✅ Done')
