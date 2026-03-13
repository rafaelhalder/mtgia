#!/usr/bin/env python3
"""Check cards without legalities."""
import psycopg2

conn = psycopg2.connect('postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder')
cur = conn.cursor()

# Ver exemplos das cartas faltantes
cur.execute('''
    SELECT c.name, c.set_code, c.type_line
    FROM cards c 
    WHERE NOT EXISTS (SELECT 1 FROM card_legalities cl WHERE cl.card_id = c.id)
    ORDER BY c.name
    LIMIT 20
''')
print('=== Cartas sem legalities (exemplos) ===')
for row in cur.fetchall():
    tl = row[2][:50] if row[2] else '?'
    print(f'  {row[0]} [{row[1]}] - {tl}')

# Contagem por tipo
cur.execute('''
    SELECT 
        CASE 
            WHEN type_line ILIKE '%%token%%' THEN 'Token'
            WHEN type_line ILIKE '%%emblem%%' THEN 'Emblem'  
            WHEN type_line ILIKE '%%card%%' THEN 'Card'
            WHEN name LIKE '%%//%%' THEN 'Split/Double'
            ELSE 'Other'
        END as category,
        COUNT(*) 
    FROM cards c 
    WHERE NOT EXISTS (SELECT 1 FROM card_legalities cl WHERE cl.card_id = c.id)
    GROUP BY 1
    ORDER BY 2 DESC
''')
print()
print('=== Cartas faltantes por categoria ===')
for row in cur.fetchall():
    print(f'  {row[0]}: {row[1]}')

# Total
cur.execute('''
    SELECT COUNT(*) FROM cards c 
    WHERE NOT EXISTS (SELECT 1 FROM card_legalities cl WHERE cl.card_id = c.id)
''')
print(f'''
Total sem legalities: {cur.fetchone()[0]}
''')

conn.close()
