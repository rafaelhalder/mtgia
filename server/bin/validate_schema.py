#!/usr/bin/env python3
"""
Validação das tabelas core do projeto.
Compara schema real do PostgreSQL com documentação.
"""

import psycopg2

DB_URL = "postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder"

# Tabelas core documentadas no guia
CORE_TABLES = [
    "users", "cards", "card_legalities", "decks", "deck_cards",
    "ai_optimize_cache", "card_meta_insights", "rules", 
    "deck_matchups", "battle_simulations",
    "user_binder_items", "trade_offers", "trade_items", 
    "trade_messages", "trade_status_history",
    "conversations", "direct_messages", "notifications", "user_follows"
]

# Schema esperado do guia (colunas documentadas)
EXPECTED_SCHEMA = {
    "users": [
        "id", "username", "email", "password_hash", "created_at",
        "display_name", "avatar_url", "updated_at", "location_state",
        "location_city", "trade_notes", "fcm_token"
    ],
    "cards": [
        "id", "scryfall_id", "name", "mana_cost", "type_line", "oracle_text",
        "colors", "color_identity", "image_url", "set_code", "rarity", "cmc",
        "price_usd", "price_usd_foil", "collector_number", "foil",
        "ai_description", "price", "price_updated_at", "created_at"
    ],
    "card_legalities": ["id", "card_id", "format", "status"],
    "decks": [
        "id", "user_id", "name", "format", "description", "is_public",
        "synergy_score", "strengths", "weaknesses", "archetype", "bracket",
        "pricing_total", "pricing_currency", "pricing_missing_cards",
        "pricing_updated_at", "created_at", "deleted_at"
    ],
    "deck_cards": [
        "id", "deck_id", "card_id", "quantity", "is_commander", "condition"
    ],
    "ai_optimize_cache": [
        "id", "cache_key", "user_id", "deck_id", "deck_signature",
        "payload", "created_at", "expires_at"
    ],
    "card_meta_insights": [
        "id", "card_name", "usage_count", "meta_deck_count", "common_archetypes",
        "common_formats", "top_pairs", "learned_role", "versatility_score",
        "last_updated_at"
    ],
}


def main():
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    
    print("=" * 80)
    print("VALIDAÇÃO DE SCHEMA: PostgreSQL vs Documentação")
    print("=" * 80)
    
    issues = []
    
    for table in CORE_TABLES:
        # Obter colunas reais do banco
        cur.execute("""
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_name = %s AND table_schema = 'public'
            ORDER BY ordinal_position
        """, (table,))
        
        rows = cur.fetchall()
        
        if not rows:
            print(f"\n❌ {table.upper()} - TABELA NÃO ENCONTRADA!")
            issues.append(f"{table}: tabela não existe")
            continue
        
        db_columns = {r[0] for r in rows}
        
        print(f"\n📋 {table.upper()} ({len(rows)} colunas)")
        
        # Verificar contra documentação se disponível
        if table in EXPECTED_SCHEMA:
            expected = set(EXPECTED_SCHEMA[table])
            
            # Colunas no banco mas não documentadas
            undocumented = db_columns - expected
            if undocumented:
                print(f"   ⚠️  NÃO DOCUMENTADAS: {', '.join(sorted(undocumented))}")
                issues.append(f"{table}: colunas não documentadas: {undocumented}")
            
            # Colunas documentadas mas não existem
            missing = expected - db_columns
            if missing:
                print(f"   🔴 FALTANDO NO BANCO: {', '.join(sorted(missing))}")
                issues.append(f"{table}: colunas faltando no banco: {missing}")
            
            # Colunas OK
            ok = expected & db_columns
            if len(ok) == len(expected) and not undocumented:
                print(f"   ✅ Schema OK ({len(ok)} colunas)")
            else:
                print(f"   ✅ {len(ok)}/{len(expected)} colunas documentadas presentes")
        else:
            # Apenas listar colunas
            for col, dtype, nullable in rows:
                null_str = "NULL" if nullable == "YES" else "NOT NULL"
                print(f"   - {col:<25} {dtype:<20} {null_str}")
    
    # Tabelas extras
    print("\n" + "=" * 80)
    print("TABELAS ADICIONAIS (não documentadas)")
    print("=" * 80)
    
    cur.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """)
    
    all_tables = [r[0] for r in cur.fetchall()]
    extra_tables = sorted(set(all_tables) - set(CORE_TABLES))
    
    for table in extra_tables:
        cur.execute("""
            SELECT COUNT(*) FROM information_schema.columns 
            WHERE table_name = %s AND table_schema = 'public'
        """, (table,))
        col_count = cur.fetchone()[0]
        
        try:
            cur.execute(f'SELECT COUNT(*) FROM "{table}"')
            row_count = cur.fetchone()[0]
        except:
            row_count = "?"
        
        status = "⚠️ " if row_count == 0 or row_count == "?" else "  "
        print(f"   {status}{table:<35} {col_count:>3} cols, {row_count:>8} rows")
    
    # Resumo de issues
    print("\n" + "=" * 80)
    print("RESUMO DE ISSUES")
    print("=" * 80)
    
    if issues:
        for issue in issues:
            print(f"   🔸 {issue}")
    else:
        print("   ✅ Nenhuma divergência encontrada!")
    
    conn.close()
    print("\n" + "=" * 80)


if __name__ == "__main__":
    main()
