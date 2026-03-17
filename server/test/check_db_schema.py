#!/usr/bin/env python3
"""Check DB schema and query quality for optimize pipeline."""
import psycopg2

conn = psycopg2.connect('postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder')
cur = conn.cursor()

# 1. Check cards table columns
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='cards' ORDER BY ordinal_position")
print('=== cards columns ===')
for r in cur.fetchall():
    print(f'  {r[0]}')

# 2. Check if edhrec_rank exists in cards
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='cards' AND column_name='edhrec_rank'")
print(f'\nedhrec_rank in cards table: {bool(cur.fetchall())}')

# 3. format_staples columns
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='format_staples' ORDER BY ordinal_position")
print('\n=== format_staples columns ===')
for r in cur.fetchall():
    print(f'  {r[0]}')

# 4. card_meta_insights columns
cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='card_meta_insights' ORDER BY ordinal_position")
print('\n=== card_meta_insights columns ===')
for r in cur.fetchall():
    print(f'  {r[0]}')

# 5. Count cards
cur.execute('SELECT count(*) FROM cards')
print(f'\nTotal cards: {cur.fetchone()[0]}')

cur.execute('SELECT count(*) FROM format_staples')
print(f'Total format_staples: {cur.fetchone()[0]}')

cur.execute('SELECT count(*) FROM card_meta_insights')
print(f'Total card_meta_insights: {cur.fetchone()[0]}')

# 6. What do the broad filler queries ACTUALLY return? (alphabetically ordered)
cur.execute("""
    SELECT c.name 
    FROM cards c
    WHERE c.type_line NOT ILIKE '%%land%%'
      AND c.name NOT LIKE 'A-%%'
      AND c.oracle_text IS NOT NULL
      AND (c.color_identity <@ ARRAY['U']::text[] OR c.color_identity = '{}')
    ORDER BY c.name ASC
    LIMIT 10
""")
print('\n=== First 10 cards for mono-U broad query (ORDER BY name ASC) ===')
for r in cur.fetchall():
    print(f'  {r[0]}')

# What's the card at position 300?
cur.execute("""
    SELECT c.name 
    FROM cards c
    WHERE c.type_line NOT ILIKE '%%land%%'
      AND c.name NOT LIKE 'A-%%'
      AND c.oracle_text IS NOT NULL
      AND (c.color_identity <@ ARRAY['U']::text[] OR c.color_identity = '{}')
    ORDER BY c.name ASC
    LIMIT 1 OFFSET 299
""")
res = cur.fetchone()
print(f'\nCard at position 300 (mono-U, alphabetically): {res[0] if res else "none"}')

# Count total valid non-lands for mono-U
cur.execute("""
    SELECT count(*) 
    FROM cards c
    WHERE c.type_line NOT ILIKE '%%land%%'
      AND c.name NOT LIKE 'A-%%'
      AND c.oracle_text IS NOT NULL
      AND (c.color_identity <@ ARRAY['U']::text[] OR c.color_identity = '{}')
""")
print(f'Total valid non-land mono-U cards: {cur.fetchone()[0]}')

# 7. Check if format_staples could be used for ranking
cur.execute("""
    SELECT fs.name, fs.edhrec_rank
    FROM format_staples fs
    WHERE fs.format = 'commander' AND fs.is_banned = false
    ORDER BY fs.edhrec_rank ASC NULLS LAST
    LIMIT 10
""")
print('\n=== Top 10 format_staples by edhrec_rank ===')
for r in cur.fetchall():
    print(f'  {r[0]}: rank {r[1]}')

# 8. Check Jin (100 cards, 10 lands) deck
cur.execute("""
    SELECT c.name, dc.quantity, c.type_line
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = 'f2a2a34a-4561-4a77-886d-7067b672ac85'
    ORDER BY c.type_line
""")
print('\n=== Jin deck (should have 10 lands) ===')
land_count = 0
total = 0
for r in cur.fetchall():
    total += r[1]
    if 'land' in (r[2] or '').lower():
        land_count += r[1]
        print(f'  LAND: {r[0]} x{r[1]}')
print(f'  Total cards: {total}, Lands: {land_count}')

# 9. Check goblins (100 cards, 18 lands) deck
cur.execute("""
    SELECT c.name, dc.quantity, c.type_line
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = '8c22deb9-80bd-489f-8e87-1344eabac698'
    ORDER BY c.type_line
""")
print('\n=== Goblins deck (should have 18 lands) ===')
land_count = 0
total = 0
for r in cur.fetchall():
    total += r[1]
    if 'land' in (r[2] or '').lower():
        land_count += r[1]
print(f'  Total cards: {total}, Lands: {land_count}')

conn.close()
print('\n✅ Done')
