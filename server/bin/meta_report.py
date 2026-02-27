import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor

conn = psycopg2.connect(
    host=os.getenv('DB_HOST', '143.198.230.247'),
    port=int(os.getenv('DB_PORT', '5433')),
    dbname=os.getenv('DB_NAME', 'halder'),
    user=os.getenv('DB_USER', 'postgres'),
    password=os.getenv('DB_PASSWORD', 'postgres'),
)
cur = conn.cursor(cursor_factory=RealDictCursor)

cur.execute('SELECT COUNT(*)::int AS c FROM meta_decks')
total = cur.fetchone()['c']

cur.execute('SELECT format, COUNT(*)::int AS c FROM meta_decks GROUP BY format ORDER BY c DESC')
by_format = cur.fetchall()

cur.execute("SELECT COUNT(*)::int AS c FROM meta_decks WHERE source_url ILIKE 'https://www.mtgtop8.com/%'")
mtgtop8_count = cur.fetchone()['c']

cur.execute('''
SELECT format, archetype, placement, source_url, created_at
FROM meta_decks
ORDER BY created_at DESC
LIMIT 12
''')
latest = cur.fetchall()

print(json.dumps({
    'total_meta_decks': total,
    'by_format': by_format,
    'mtgtop8_count': mtgtop8_count,
    'latest_samples': latest,
}, ensure_ascii=False, default=str, indent=2))

cur.close()
conn.close()
