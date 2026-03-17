#!/usr/bin/env python3
"""Check DB schema and query quality for optimize pipeline - Part 2."""
import psycopg2

conn = psycopg2.connect('postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder')
cur = conn.cursor()

# format_staples is EMPTY - check
cur.execute("SELECT count(*) FROM format_staples")
print(f'format_staples rows: {cur.fetchone()[0]}')

# How many unique card NAMES exist?  (not printings)
cur.execute("SELECT count(DISTINCT name) FROM cards")
print(f'Unique card names: {cur.fetchone()[0]}')

# Total printings
cur.execute("SELECT count(*) FROM cards")
print(f'Total printings: {cur.fetchone()[0]}')

# How many distinct mono-U non-land cards?
cur.execute("""
    SELECT count(DISTINCT name)
    FROM cards
    WHERE type_line NOT ILIKE '%%land%%'
      AND oracle_text IS NOT NULL
      AND (color_identity <@ ARRAY['U']::text[] OR color_identity = '{}')
""")
print(f'Distinct mono-U non-land: {cur.fetchone()[0]}')

# Multi-color: WUBG (4 colors, like Atraxa minus red)
cur.execute("""
    SELECT count(DISTINCT name)
    FROM cards
    WHERE type_line NOT ILIKE '%%land%%'
      AND oracle_text IS NOT NULL
      AND (color_identity <@ ARRAY['W','U','B','G']::text[] OR color_identity = '{}')
""")
print(f'Distinct WUBG non-land: {cur.fetchone()[0]}')

# Mono-R (like Krenko)
cur.execute("""
    SELECT count(DISTINCT name)
    FROM cards
    WHERE type_line NOT ILIKE '%%land%%'
      AND oracle_text IS NOT NULL
      AND (color_identity <@ ARRAY['R']::text[] OR color_identity = '{}')
""")
print(f'Distinct mono-R non-land: {cur.fetchone()[0]}')

# Check: does the broad query get Counterspell for mono-U? 
cur.execute("""
    SELECT name FROM cards WHERE LOWER(name) = 'counterspell' LIMIT 3
""")
rows = cur.fetchall()
print(f'\nCounterspell printings: {len(rows)}')
for r in rows:
    print(f'  {r[0]}')

# Check: are duplicates being properly handled by _dedupeCandidatesByName?
# The broad query returns multiple printings. If dedup happens at app level, that's fine.
# But LIMIT 300 at SQL level means we waste slots on dupes.

# For mono-U with LIMIT 300, how many UNIQUE names do we get?
cur.execute("""
    SELECT name
    FROM cards
    WHERE type_line NOT ILIKE '%%land%%'
      AND name NOT LIKE 'A-%%'
      AND oracle_text IS NOT NULL
      AND (color_identity <@ ARRAY['U']::text[] OR color_identity = '{}')
    ORDER BY name ASC
    LIMIT 300
""")
all_names = [r[0] for r in cur.fetchall()]
unique_names = set(all_names)
print(f'\nMono-U broad query: {len(all_names)} rows, {len(unique_names)} unique names')

# For WUBG with LIMIT 300?
cur.execute("""
    SELECT name
    FROM cards
    WHERE type_line NOT ILIKE '%%land%%'
      AND name NOT LIKE 'A-%%'
      AND oracle_text IS NOT NULL
      AND (color_identity <@ ARRAY['W','U','B','G']::text[] OR color_identity = '{}')
    ORDER BY name ASC
    LIMIT 300
""")
all_names = [r[0] for r in cur.fetchall()]
unique_names = set(all_names)
print(f'WUBG broad query: {len(all_names)} rows, {len(unique_names)} unique names, last={all_names[-1] if all_names else "none"}')

# Check card_legalities
cur.execute("SELECT count(*) FROM card_legalities")
print(f'\ncard_legalities rows: {cur.fetchone()[0]}')

# Check: does LEFT JOIN card_legalities filter correctly?
cur.execute("""
    SELECT count(DISTINCT c.name)
    FROM cards c
    LEFT JOIN card_legalities cl ON cl.card_id = c.id AND cl.format = 'commander'
    WHERE (cl.status = 'legal' OR cl.status = 'restricted' OR cl.status IS NULL)
      AND c.type_line NOT ILIKE '%%land%%'
      AND c.oracle_text IS NOT NULL
      AND (c.color_identity <@ ARRAY['U']::text[] OR c.color_identity = '{}')
""")
print(f'Mono-U with legality filter: {cur.fetchone()[0]} distinct names')

# Check Jin deck details
cur.execute("""
    SELECT c.name, dc.quantity, c.type_line, c.color_identity
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = 'f2a2a34a-4561-4a77-886d-7067b672ac85'
      AND c.type_line ILIKE '%%land%%'
    ORDER BY c.name
""")
print('\n=== Jin deck LANDS ===')
total_lands = 0
for r in cur.fetchall():
    total_lands += r[1]
    print(f'  {r[0]} x{r[1]} [{r[2]}] identity={r[3]}')
print(f'  Total lands: {total_lands}')

# Check goblins deck lands
cur.execute("""
    SELECT c.name, dc.quantity, c.type_line
    FROM deck_cards dc
    JOIN cards c ON c.id = dc.card_id
    WHERE dc.deck_id = '8c22deb9-80bd-489f-8e87-1344eabac698'
      AND c.type_line ILIKE '%%land%%'
    ORDER BY c.name
""")
print('\n=== Goblins deck LANDS ===')
total_lands = 0
for r in cur.fetchall():
    total_lands += r[1]
    print(f'  {r[0]} x{r[1]}')
print(f'  Total lands: {total_lands}')

conn.close()
print('\n✅ Done')
