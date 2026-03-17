#!/usr/bin/env python3
"""
Auditoria de dados subutilizados no banco.
Identifica tabelas/colunas com dados que poderiam ser melhor aproveitados.
"""

import psycopg2
from collections import defaultdict

DB_URL = "postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder"

def main():
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    
    print("=" * 60)
    print("AUDITORIA DE DADOS SUBUTILIZADOS")
    print("=" * 60)
    
    # 1. Listar todas as tabelas com contagem
    print("\n📊 TABELAS E QUANTIDADE DE REGISTROS:")
    cur.execute("""
        SELECT relname, n_live_tup 
        FROM pg_stat_user_tables
        ORDER BY n_live_tup DESC
    """)
    for row in cur.fetchall():
        print(f"  {row[0]}: {row[1]:,} rows")
    
    # 2. card_meta_insights - dados de popularidade
    print("\n" + "=" * 60)
    print("🔍 ANÁLISE: card_meta_insights (dados de meta/popularidade)")
    print("=" * 60)
    
    cur.execute("SELECT COUNT(*) FROM card_meta_insights")
    total = cur.fetchone()[0]
    print(f"Total de registros: {total}")
    
    cur.execute("""
        SELECT 
            COUNT(NULLIF(usage_count, 0)) as with_usage,
            COUNT(NULLIF(meta_deck_count, 0)) as with_meta_deck,
            COUNT(CASE WHEN array_length(common_archetypes, 1) > 0 THEN 1 END) as with_archetypes,
            COUNT(CASE WHEN top_pairs IS NOT NULL AND top_pairs::text != '{}' AND top_pairs::text != 'null' THEN 1 END) as with_pairs,
            COUNT(learned_role) as with_role,
            COUNT(NULLIF(versatility_score, 0)) as with_versatility
        FROM card_meta_insights
    """)
    row = cur.fetchone()
    print(f"  usage_count (popularidade): {row[0]}/{total} ({100*row[0]//total}%)")
    print(f"  meta_deck_count: {row[1]}/{total}")
    print(f"  common_archetypes: {row[2]}/{total}")
    print(f"  top_pairs (cartas sinérgicas): {row[3]}/{total}")
    print(f"  learned_role (função da carta): {row[4]}/{total}")
    print(f"  versatility_score: {row[5]}/{total}")
    
    # Exemplos de dados
    print("\n  Exemplos de top_pairs:")
    cur.execute("""
        SELECT card_name, top_pairs 
        FROM card_meta_insights 
        WHERE top_pairs IS NOT NULL AND top_pairs::text != '{}' AND top_pairs::text != 'null'
        LIMIT 3
    """)
    for r in cur.fetchall():
        print(f"    {r[0]}: {r[1]}")
    
    # 3. cards - colunas especiais
    print("\n" + "=" * 60)
    print("🔍 ANÁLISE: cards (colunas potencialmente subutilizadas)")
    print("=" * 60)
    
    cur.execute("""
        SELECT 
            COUNT(*) as total,
            COUNT(ai_description) as with_ai_desc,
            COUNT(price_usd) as with_price,
            COUNT(NULLIF(price_usd, 0)) as with_price_nonzero,
            COUNT(collector_number) as with_collector,
            COUNT(rarity) as with_rarity
        FROM cards
    """)
    row = cur.fetchone()
    print(f"Total de cartas: {row[0]}")
    print(f"  ai_description: {row[1]} ({100*row[1]//row[0]}%)")
    print(f"  price_usd (qualquer): {row[2]} ({100*row[2]//row[0]}%)")
    print(f"  price_usd (> 0): {row[3]} ({100*row[3]//row[0]}%)")
    print(f"  collector_number: {row[4]} ({100*row[4]//row[0]}%)")
    print(f"  rarity: {row[5]} ({100*row[5]//row[0]}%)")
    
    # 4. decks - colunas de análise
    print("\n" + "=" * 60)
    print("🔍 ANÁLISE: decks (colunas de análise)")
    print("=" * 60)
    
    cur.execute("""
        SELECT 
            COUNT(*) as total,
            COUNT(synergy_score) as with_synergy,
            COUNT(archetype) as with_archetype,
            COUNT(strengths) as with_strengths,
            COUNT(weaknesses) as with_weaknesses,
            COUNT(bracket) as with_bracket,
            COUNT(pricing_total) as with_pricing
        FROM decks
        WHERE deleted_at IS NULL
    """)
    row = cur.fetchone()
    print(f"Total de decks ativos: {row[0]}")
    print(f"  synergy_score: {row[1]} ({100*row[1]//max(1,row[0])}%)")
    print(f"  archetype: {row[2]} ({100*row[2]//max(1,row[0])}%)")
    print(f"  strengths: {row[3]} ({100*row[3]//max(1,row[0])}%)")
    print(f"  weaknesses: {row[4]} ({100*row[4]//max(1,row[0])}%)")
    print(f"  bracket: {row[5]} ({100*row[5]//max(1,row[0])}%)")
    print(f"  pricing_total: {row[6]} ({100*row[6]//max(1,row[0])}%)")
    
    # 5. card_legalities
    print("\n" + "=" * 60)
    print("🔍 ANÁLISE: card_legalities")
    print("=" * 60)
    
    cur.execute("SELECT COUNT(*) FROM card_legalities")
    leg_total = cur.fetchone()[0]
    cur.execute("SELECT COUNT(DISTINCT card_id) FROM card_legalities")
    leg_cards = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM cards")
    cards_total = cur.fetchone()[0]
    print(f"Total de registros: {leg_total}")
    print(f"Cartas com legalidades: {leg_cards}/{cards_total} ({100*leg_cards//cards_total}%)")
    
    # 6. Tabelas vazias ou quase vazias
    print("\n" + "=" * 60)
    print("⚠️ TABELAS VAZIAS/SUBUTILIZADAS:")
    print("=" * 60)
    
    tables_to_check = [
        "deck_matchups",
        "battle_simulations", 
        "rules",
        "sync_state"
    ]
    
    for table in tables_to_check:
        try:
            cur.execute(f"SELECT COUNT(*) FROM {table}")
            count = cur.fetchone()[0]
            status = "✅" if count > 0 else "❌ VAZIA"
            print(f"  {table}: {count} rows {status}")
        except:
            print(f"  {table}: não existe")
    
    # 7. Resumo de oportunidades
    print("\n" + "=" * 60)
    print("💡 OPORTUNIDADES DE MELHORIA:")
    print("=" * 60)
    
    opportunities = []
    
    # card_meta_insights
    if total > 0:
        opportunities.append({
            "tabela": "card_meta_insights",
            "campo": "usage_count + top_pairs",
            "dados": f"{total} registros",
            "uso_atual": "Apenas ORDER BY na filler query",
            "sugestão": "Usar top_pairs para sugerir sinergias; usar usage_count para ranking de sugestões"
        })
    
    # cards.ai_description
    cur.execute("SELECT COUNT(ai_description) FROM cards")
    ai_desc = cur.fetchone()[0]
    if ai_desc > 0:
        opportunities.append({
            "tabela": "cards",
            "campo": "ai_description",
            "dados": f"{ai_desc} cartas com descrição IA",
            "uso_atual": "Não usado no optimize",
            "sugestão": "Incluir no contexto do LLM para melhor compreensão"
        })
    
    # cards.price_usd
    cur.execute("SELECT COUNT(NULLIF(price_usd, 0)) FROM cards")
    prices = cur.fetchone()[0]
    if prices > 0:
        opportunities.append({
            "tabela": "cards",
            "campo": "price_usd",
            "dados": f"{prices} cartas com preço",
            "uso_atual": "Usado para calcular pricing_total do deck",
            "sugestão": "Oferecer modo 'budget' que prefere cartas mais baratas"
        })
    
    # decks analysis fields
    opportunities.append({
        "tabela": "decks",
        "campo": "synergy_score, archetype, bracket",
        "dados": "Campos de análise",
        "uso_atual": "Calculados mas não persistidos consistentemente",
        "sugestão": "Salvar análise após optimize para histórico e comparação"
    })
    
    for i, opp in enumerate(opportunities, 1):
        print(f"\n{i}. {opp['tabela']}.{opp['campo']}")
        print(f"   Dados: {opp['dados']}")
        print(f"   Uso atual: {opp['uso_atual']}")
        print(f"   Sugestão: {opp['sugestão']}")
    
    conn.close()
    
    print("\n" + "=" * 60)
    print("FIM DA AUDITORIA")
    print("=" * 60)

if __name__ == "__main__":
    main()
