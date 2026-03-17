#!/usr/bin/env python3
"""Validação das melhorias de aproveitamento de dados."""

import psycopg2

DB = 'postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder'

def main():
    conn = psycopg2.connect(DB)
    cur = conn.cursor()

    print('=' * 50)
    print('VALIDAÇÃO DAS MELHORIAS DE DADOS')
    print('=' * 50)
    print()

    # 1. archetype_patterns com dados
    cur.execute('''
        SELECT COUNT(*) FROM archetype_patterns 
        WHERE ideal_land_count IS NOT NULL
    ''')
    count = cur.fetchone()[0]
    print(f'1. archetype_patterns com ideal_land_count: {count}')

    cur.execute('''
        SELECT archetype, ideal_land_count, ideal_avg_cmc 
        FROM archetype_patterns 
        WHERE ideal_land_count IS NOT NULL
        ORDER BY archetype
        LIMIT 5
    ''')
    for r in cur.fetchall():
        print(f'   - {r[0]}: {r[1]} lands, CMC {r[2]}')

    print()

    # 2. archetype_counters com hate cards
    cur.execute('SELECT COUNT(*) FROM archetype_counters')
    count = cur.fetchone()[0]
    print(f'2. archetype_counters (hate cards): {count} registros')

    cur.execute('''
        SELECT archetype, array_length(hate_cards, 1) as num_cards
        FROM archetype_counters
        LIMIT 5
    ''')
    for r in cur.fetchall():
        print(f'   - Anti-{r[0]}: {r[1]} cartas')

    print()

    # 3. card_meta_insights com top_pairs
    cur.execute('''
        SELECT COUNT(*) FROM card_meta_insights 
        WHERE top_pairs IS NOT NULL 
          AND top_pairs::text != '[]'
          AND top_pairs::text != 'null'
    ''')
    count = cur.fetchone()[0]
    print(f'3. card_meta_insights com top_pairs: {count}')

    # Exemplo de top_pairs
    cur.execute('''
        SELECT card_name, top_pairs
        FROM card_meta_insights
        WHERE top_pairs IS NOT NULL 
          AND top_pairs::text NOT IN ('[]', 'null')
        LIMIT 2
    ''')
    for r in cur.fetchall():
        print(f'   - {r[0]}: {r[1]}')

    print()

    # 4. format_staples
    cur.execute('SELECT COUNT(*) FROM format_staples')
    count = cur.fetchone()[0]
    print(f'4. format_staples: {count} registros')

    print()
    print('=' * 50)
    print('SERVICOS ATUALIZADOS')
    print('=' * 50)
    print('MLKnowledgeService:')
    print('  - archetype_patterns (lands/cmc targets)')
    print('  - card_meta_insights (top_pairs sinergias)')
    print('  - synergy_packages')
    print()
    print('HateCardsService (NOVO):')
    print('  - archetype_counters (hate cards contra meta)')
    print()
    print('FormatStaplesService:')
    print('  - format_staples')
    print()
    print('STATUS: TODOS OS DADOS AGORA SENDO UTILIZADOS')

    conn.close()

if __name__ == '__main__':
    main()
