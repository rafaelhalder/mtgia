#!/usr/bin/env python3
"""
Análise de saúde do banco de dados.
Verifica tabelas vazias, índices faltantes e integridade.
"""

import psycopg2

DB_URL = "postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder"


def main():
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    
    print("=" * 80)
    print("ANÁLISE DE SAÚDE DO BANCO DE DADOS")
    print("=" * 80)
    
    # 1. Tabelas vazias
    cur.execute("""
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """)
    tables = [r[0] for r in cur.fetchall()]
    
    empty_tables = []
    small_tables = []
    
    for table in tables:
        try:
            cur.execute(f'SELECT COUNT(*) FROM "{table}"')
            count = cur.fetchone()[0]
            if count == 0:
                empty_tables.append(table)
            elif count < 5:
                small_tables.append((table, count))
        except Exception as e:
            print(f"Erro em {table}: {e}")
    
    print("\n[1] TABELAS VAZIAS (0 rows):")
    if empty_tables:
        for t in empty_tables:
            print(f"   - {t}")
    else:
        print("   Nenhuma tabela vazia")
    
    print("\n[2] TABELAS COM POUCOS DADOS (<5 rows):")
    if small_tables:
        for t, c in small_tables:
            print(f"   - {t}: {c} rows")
    else:
        print("   Todas as tabelas têm dados suficientes")
    
    # 2. Verificar dados órfãos em deck_cards
    print("\n" + "=" * 80)
    print("[3] INTEGRIDADE REFERENCIAL")
    print("=" * 80)
    
    # deck_cards sem deck válido
    cur.execute("""
        SELECT COUNT(*) FROM deck_cards dc 
        WHERE NOT EXISTS (SELECT 1 FROM decks d WHERE d.id = dc.deck_id)
    """)
    orphan_deck_cards = cur.fetchone()[0]
    print(f"\n   deck_cards órfãos (sem deck): {orphan_deck_cards}")
    
    # deck_cards sem card válido
    cur.execute("""
        SELECT COUNT(*) FROM deck_cards dc 
        WHERE NOT EXISTS (SELECT 1 FROM cards c WHERE c.id = dc.card_id)
    """)
    orphan_cards = cur.fetchone()[0]
    print(f"   deck_cards com card inválido: {orphan_cards}")
    
    # decks sem cards
    cur.execute("""
        SELECT COUNT(*) FROM decks d
        WHERE NOT EXISTS (SELECT 1 FROM deck_cards dc WHERE dc.deck_id = d.id)
        AND d.deleted_at IS NULL
    """)
    empty_decks = cur.fetchone()[0]
    print(f"   decks sem cartas: {empty_decks}")
    
    # cards sem legalities
    cur.execute("""
        SELECT COUNT(*) FROM cards c
        WHERE NOT EXISTS (SELECT 1 FROM card_legalities cl WHERE cl.card_id = c.id)
    """)
    cards_no_legalities = cur.fetchone()[0]
    print(f"   cards sem legalities: {cards_no_legalities}")
    
    # 3. Verificar índices
    print("\n" + "=" * 80)
    print("[4] ÍNDICES IMPORTANTES")
    print("=" * 80)
    
    important_indexes = [
        ("cards", "name"),
        ("cards", "scryfall_id"),
        ("cards", "type_line"),
        ("deck_cards", "deck_id"),
        ("deck_cards", "card_id"),
        ("decks", "user_id"),
        ("card_legalities", "card_id"),
        ("card_legalities", "format"),
        ("card_meta_insights", "card_name"),
        ("notifications", "user_id"),
        ("user_follows", "follower_id"),
        ("user_follows", "following_id"),
        ("trade_offers", "sender_id"),
        ("trade_offers", "receiver_id"),
    ]
    
    missing_indexes = []
    
    for table, column in important_indexes:
        cur.execute("""
            SELECT COUNT(*) FROM pg_indexes 
            WHERE tablename = %s 
            AND (indexdef ILIKE %s OR indexdef ILIKE %s)
        """, (table, f'%({column})%', f'%({column},%'))
        
        has_idx = cur.fetchone()[0] > 0
        if not has_idx:
            missing_indexes.append(f"{table}.{column}")
    
    if missing_indexes:
        print("\n   ÍNDICES FALTANDO:")
        for idx in missing_indexes:
            print(f"   - {idx}")
    else:
        print("\n   Todos os índices importantes existem")
    
    # 4. Estatísticas gerais
    print("\n" + "=" * 80)
    print("[5] ESTATÍSTICAS GERAIS")
    print("=" * 80)
    
    cur.execute("SELECT COUNT(*) FROM users")
    user_count = cur.fetchone()[0]
    print(f"\n   Usuários: {user_count}")
    
    cur.execute("SELECT COUNT(*) FROM cards")
    card_count = cur.fetchone()[0]
    print(f"   Cartas: {card_count}")
    
    cur.execute("SELECT COUNT(*) FROM decks WHERE deleted_at IS NULL")
    deck_count = cur.fetchone()[0]
    print(f"   Decks ativos: {deck_count}")
    
    cur.execute("SELECT COUNT(*) FROM deck_cards")
    deck_cards_count = cur.fetchone()[0]
    print(f"   Entradas em deck_cards: {deck_cards_count}")
    
    cur.execute("SELECT COUNT(*) FROM card_meta_insights")
    meta_count = cur.fetchone()[0]
    print(f"   Card meta insights: {meta_count}")
    
    cur.execute("SELECT COUNT(*) FROM ai_optimize_cache")
    cache_count = cur.fetchone()[0]
    print(f"   Cache de otimização: {cache_count}")
    
    # 5. Verificar colunas com valores nulos inesperados
    print("\n" + "=" * 80)
    print("[6] COLUNAS COM MUITOS NULOS")
    print("=" * 80)
    
    critical_columns = [
        ("cards", "name"),
        ("cards", "image_url"),
        ("cards", "type_line"),
        ("decks", "name"),
        ("decks", "format"),
        ("users", "email"),
        ("users", "username"),
    ]
    
    for table, column in critical_columns:
        cur.execute(f"""
            SELECT 
                COUNT(*) FILTER (WHERE "{column}" IS NULL) as nulls,
                COUNT(*) as total
            FROM "{table}"
        """)
        nulls, total = cur.fetchone()
        if nulls > 0 and total > 0:
            pct = (nulls / total) * 100
            print(f"   {table}.{column}: {nulls}/{total} nulos ({pct:.1f}%)")
    
    conn.close()
    print("\n" + "=" * 80)
    print("ANÁLISE CONCLUÍDA")
    print("=" * 80)


if __name__ == "__main__":
    main()
