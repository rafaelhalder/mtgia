#!/usr/bin/env python3
"""Verificar conteúdo das tabelas subutilizadas"""
import psycopg2

DB = "postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder"
conn = psycopg2.connect(DB)
cur = conn.cursor()

print("=== synergy_packages (combos conhecidos) ===")
cur.execute("""
    SELECT package_name, package_type, primary_archetype, 
           array_length(card_names, 1) as num_cards,
           occurrence_count, confidence_score
    FROM synergy_packages
    ORDER BY confidence_score DESC
    LIMIT 5
""")
for r in cur.fetchall():
    print(f"  {r[0]} ({r[1]}) - {r[4]}x, conf: {r[5]}")

print()
print("=== archetype_patterns (padrões de construção) ===")
cur.execute("""
    SELECT archetype, format, sample_size, ideal_land_count, ideal_avg_cmc
    FROM archetype_patterns
    ORDER BY sample_size DESC
    LIMIT 5
""")
for r in cur.fetchall():
    print(f"  {r[0]} ({r[1]}) - {r[2]} samples, lands: {r[3]}, cmc: {r[4]}")

print()
print("=== archetype_counters (matchups) ===")
cur.execute("SELECT * FROM archetype_counters LIMIT 3")
cols = [d[0] for d in cur.description]
print(f"  Colunas: {cols}")
for r in cur.fetchall():
    print(f"  {r}")

print()
print("=== rules (categorias) ===")
cur.execute("""
    SELECT category, COUNT(*) as cnt
    FROM rules
    GROUP BY category
    ORDER BY cnt DESC
    LIMIT 10
""")
for r in cur.fetchall():
    print(f"  {r[0]}: {r[1]} regras")

print()
print("=== card_meta_insights.top_pairs (sinergias) ===")
cur.execute("""
    SELECT card_name, top_pairs
    FROM card_meta_insights
    WHERE top_pairs IS NOT NULL 
      AND top_pairs::text != '[]'
      AND top_pairs::text != 'null'
    ORDER BY usage_count DESC
    LIMIT 3
""")
for r in cur.fetchall():
    pairs = r[1][:100] if r[1] else "N/A"
    print(f"  {r[0]}: {pairs}...")

conn.close()
