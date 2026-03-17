#!/usr/bin/env python3
"""
Versão minimal para popular card_meta_insights.
Usa SQL puro com operações de batch otimizadas.
"""

import psycopg2

DATABASE_URL = 'postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder'

def main():
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = False
    cur = conn.cursor()
    
    print('📊 Iniciando population...')
    
    # Step 1: Update learned_role para cartas existentes que tem 'unknown'
    print('  Step 1: Atualizando roles...')
    cur.execute(r'''
        UPDATE card_meta_insights cmi
        SET learned_role = CASE 
            WHEN LOWER(c.oracle_text) ~ 'add \{[wubrg]\}' THEN 'ramp'
            WHEN LOWER(c.oracle_text) ~ 'destroy target|exile target' THEN 'removal'
            WHEN LOWER(c.oracle_text) ~ 'draw a card|draw \d+ cards' THEN 'draw'
            WHEN LOWER(c.oracle_text) ~ 'counter target spell' THEN 'counter'
            WHEN LOWER(c.oracle_text) ~ 'search your library' THEN 'tutor'
            WHEN LOWER(c.oracle_text) ~ 'from your graveyard' THEN 'recursion'
            WHEN LOWER(c.oracle_text) ~ 'create.*token' THEN 'tokens'
            WHEN LOWER(c.oracle_text) ~ 'hexproof|indestructible' THEN 'protection'
            ELSE 'utility'
        END,
        last_updated_at = NOW()
        FROM cards c
        WHERE LOWER(cmi.card_name) = LOWER(c.name)
        AND (cmi.learned_role = 'unknown' OR cmi.learned_role IS NULL)
    ''')
    updated_roles = cur.rowcount
    print(f'    ✓ {updated_roles} roles atualizados')
    
    # Step 2: Inserir cartas que não existem ainda (com ON CONFLICT para segurança)
    print('  Step 2: Inserindo cartas novas...')
    cur.execute(r'''
        INSERT INTO card_meta_insights 
        (id, card_name, usage_count, meta_deck_count, common_archetypes, common_formats, learned_role, versatility_score, last_updated_at)
        SELECT 
            gen_random_uuid(),
            c.name,
            CASE 
                WHEN LOWER(c.type_line) ~ 'land' AND LOWER(c.type_line) NOT LIKE '%basic%' THEN 30
                WHEN LOWER(c.oracle_text) ~ 'add \{' AND LOWER(c.type_line) ~ 'artifact' THEN 40
                WHEN LOWER(c.oracle_text) ~ 'destroy target|exile target' THEN 25
                WHEN LOWER(c.oracle_text) ~ 'draw' THEN 20
                WHEN c.cmc <= 2 THEN 10
                ELSE 5
            END,
            5,
            ARRAY['general'],
            ARRAY['commander'],
            CASE 
                WHEN LOWER(c.oracle_text) ~ 'add \{[wubrg]\}' THEN 'ramp'
                WHEN LOWER(c.oracle_text) ~ 'destroy target|exile target' THEN 'removal'  
                WHEN LOWER(c.oracle_text) ~ 'draw a card|draw \d+ cards' THEN 'draw'
                WHEN LOWER(c.oracle_text) ~ 'counter target spell' THEN 'counter'
                WHEN LOWER(c.oracle_text) ~ 'search your library' THEN 'tutor'
                WHEN LOWER(c.oracle_text) ~ 'from your graveyard' THEN 'recursion'
                WHEN LOWER(c.oracle_text) ~ 'create.*token' THEN 'tokens'
                ELSE 'utility'
            END,
            0.3,
            NOW()
        FROM cards c
        WHERE c.oracle_text IS NOT NULL 
        AND c.oracle_text != ''
        ON CONFLICT (card_name) DO NOTHING
    ''')
    inserted = cur.rowcount
    print(f'    ✓ {inserted} cartas inseridas')
    
    # Step 3: Boost para staples
    print('  Step 3: Boosting staples...')
    cur.execute('''
        UPDATE card_meta_insights cmi
        SET usage_count = GREATEST(cmi.usage_count, 50),
            versatility_score = GREATEST(cmi.versatility_score, 0.7)
        FROM format_staples fs
        WHERE LOWER(cmi.card_name) = LOWER(fs.card_name)
    ''')
    boosted = cur.rowcount
    print(f'    ✓ {boosted} staples com boost')
    
    conn.commit()
    
    # Estatísticas
    cur.execute('SELECT COUNT(*) FROM card_meta_insights')
    total = cur.fetchone()[0]
    
    cur.execute('''
        SELECT learned_role, COUNT(*) cnt
        FROM card_meta_insights
        GROUP BY learned_role
        ORDER BY cnt DESC
        LIMIT 10
    ''')
    
    print(f'\n✅ card_meta_insights: {total:,} total')
    print('\n=== Distribuição de Roles ===')
    for row in cur.fetchall():
        print(f'  {row[0]}: {row[1]:,}')
    
    conn.close()

if __name__ == '__main__':
    main()
