#!/usr/bin/env python3
"""
Popula archetype_patterns com valores conhecidos de referência para Commander.
Baseado em dados do EDHREC e práticas estabelecidas da comunidade.
"""
import psycopg2

DB = "postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder"

# Referências conhecidas para Commander (100 cards)
ARCHETYPE_REFERENCE = {
    # Aggro/Fast decks - menos lands, CMC baixo
    "aggro": {"lands": 32, "cmc": 2.4, "ramp": 10, "draw": 8, "removal": 8},
    "burn": {"lands": 32, "cmc": 2.2, "ramp": 8, "draw": 8, "removal": 6},
    "voltron": {"lands": 34, "cmc": 2.6, "ramp": 12, "draw": 10, "removal": 8},
    "weenie": {"lands": 32, "cmc": 2.0, "ramp": 8, "draw": 8, "removal": 6},
    "tokens": {"lands": 34, "cmc": 2.8, "ramp": 10, "draw": 10, "removal": 8},
    
    # Midrange - equilibrado
    "midrange": {"lands": 36, "cmc": 3.2, "ramp": 12, "draw": 10, "removal": 10},
    "value": {"lands": 36, "cmc": 3.4, "ramp": 12, "draw": 12, "removal": 10},
    "goodstuff": {"lands": 36, "cmc": 3.2, "ramp": 12, "draw": 10, "removal": 12},
    "stompy": {"lands": 35, "cmc": 3.6, "ramp": 14, "draw": 8, "removal": 8},
    
    # Control - mais lands, CMC mais alto
    "control": {"lands": 38, "cmc": 3.6, "ramp": 10, "draw": 14, "removal": 14},
    "stax": {"lands": 36, "cmc": 2.8, "ramp": 12, "draw": 10, "removal": 8},
    "pillowfort": {"lands": 37, "cmc": 3.4, "ramp": 10, "draw": 12, "removal": 10},
    
    # Combo - varia, mas geralmente mais tutors
    "combo": {"lands": 34, "cmc": 2.8, "ramp": 14, "draw": 14, "removal": 8},
    "storm": {"lands": 32, "cmc": 2.0, "ramp": 16, "draw": 16, "removal": 4},
    "spellslinger": {"lands": 34, "cmc": 2.6, "ramp": 12, "draw": 14, "removal": 10},
    
    # Tribal - depende da tribo
    "tribal": {"lands": 35, "cmc": 3.0, "ramp": 10, "draw": 10, "removal": 8},
    "elves": {"lands": 32, "cmc": 2.2, "ramp": 12, "draw": 10, "removal": 6},
    "goblins": {"lands": 32, "cmc": 2.4, "ramp": 8, "draw": 8, "removal": 6},
    "zombies": {"lands": 35, "cmc": 3.2, "ramp": 10, "draw": 10, "removal": 8},
    "dragons": {"lands": 37, "cmc": 4.2, "ramp": 14, "draw": 10, "removal": 8},
    "angels": {"lands": 37, "cmc": 4.0, "ramp": 14, "draw": 10, "removal": 8},
    "vampires": {"lands": 35, "cmc": 3.0, "ramp": 10, "draw": 10, "removal": 8},
    "wizards": {"lands": 34, "cmc": 2.8, "ramp": 10, "draw": 14, "removal": 8},
    "merfolk": {"lands": 33, "cmc": 2.6, "ramp": 8, "draw": 12, "removal": 6},
    "slivers": {"lands": 35, "cmc": 2.8, "ramp": 12, "draw": 8, "removal": 6},
    
    # Estratégias específicas
    "graveyard": {"lands": 35, "cmc": 3.2, "ramp": 10, "draw": 10, "removal": 10},
    "reanimator": {"lands": 35, "cmc": 3.4, "ramp": 12, "draw": 10, "removal": 8},
    "aristocrats": {"lands": 35, "cmc": 2.8, "ramp": 10, "draw": 10, "removal": 8},
    "artifacts": {"lands": 34, "cmc": 3.0, "ramp": 14, "draw": 12, "removal": 8},
    "enchantress": {"lands": 35, "cmc": 3.0, "ramp": 10, "draw": 12, "removal": 8},
    "landfall": {"lands": 40, "cmc": 3.4, "ramp": 16, "draw": 10, "removal": 8},
    "blink": {"lands": 36, "cmc": 3.2, "ramp": 10, "draw": 12, "removal": 10},
    "mill": {"lands": 36, "cmc": 3.0, "ramp": 10, "draw": 12, "removal": 10},
    "infect": {"lands": 34, "cmc": 2.4, "ramp": 10, "draw": 10, "removal": 8},
    "superfriends": {"lands": 37, "cmc": 3.8, "ramp": 14, "draw": 10, "removal": 12},
    "wheels": {"lands": 35, "cmc": 3.0, "ramp": 12, "draw": 14, "removal": 8},
    "lifegain": {"lands": 36, "cmc": 3.0, "ramp": 10, "draw": 10, "removal": 10},
    "sacrifice": {"lands": 35, "cmc": 2.8, "ramp": 10, "draw": 10, "removal": 8},
    "+1/+1 counters": {"lands": 35, "cmc": 2.8, "ramp": 10, "draw": 10, "removal": 8},
    "big mana": {"lands": 38, "cmc": 4.0, "ramp": 18, "draw": 10, "removal": 8},
}

# Cartas típicas por função
TYPICAL_CARDS = {
    "ramp": [
        "Sol Ring", "Arcane Signet", "Cultivate", "Kodama's Reach", 
        "Rampant Growth", "Farseek", "Nature's Lore", "Three Visits",
        "Fellwar Stone", "Mind Stone", "Commander's Sphere", "Thought Vessel"
    ],
    "draw": [
        "Rhystic Study", "Mystic Remora", "Sylvan Library", "Phyrexian Arena",
        "Night's Whisper", "Sign in Blood", "Read the Bones", "Harmonize",
        "Beast Whisperer", "Guardian Project", "The Great Henge", "Skullclamp"
    ],
    "removal": [
        "Swords to Plowshares", "Path to Exile", "Beast Within", "Generous Gift",
        "Chaos Warp", "Reality Shift", "Rapid Hybridization", "Pongify",
        "Assassin's Trophy", "Anguished Unmaking", "Vindicate", "Terminate"
    ],
    "wipes": [
        "Wrath of God", "Damnation", "Blasphemous Act", "Toxic Deluge",
        "Cyclonic Rift", "Farewell", "Vanquish the Horde", "Meathook Massacre"
    ],
}

def main():
    conn = psycopg2.connect(DB)
    cur = conn.cursor()
    
    print("=== Populando archetype_patterns ===\n")
    
    # Verificar registros existentes
    cur.execute("SELECT archetype, format FROM archetype_patterns")
    existing = {(r[0].lower(), r[1].lower()) for r in cur.fetchall()}
    print(f"Registros existentes: {len(existing)}")
    
    updated = 0
    inserted = 0
    
    for archetype, ref in ARCHETYPE_REFERENCE.items():
        # Determinar cartas típicas baseado no arquétipo
        typical_ramp = TYPICAL_CARDS["ramp"][:ref["ramp"]//2]
        typical_draw = TYPICAL_CARDS["draw"][:ref["draw"]//2]
        typical_removal = TYPICAL_CARDS["removal"][:ref["removal"]//2]
        
        if (archetype.lower(), 'commander') in existing:
            # UPDATE
            cur.execute("""
                UPDATE archetype_patterns SET
                    ideal_land_count = %s,
                    ideal_avg_cmc = %s,
                    typical_ramp = %s,
                    typical_draw = %s,
                    typical_removal = %s
                WHERE LOWER(archetype) = LOWER(%s) AND LOWER(format) = 'commander'
            """, (
                ref["lands"],
                ref["cmc"],
                typical_ramp, 
                typical_draw,
                typical_removal,
                archetype
            ))
            updated += 1
            print(f"  ✓ Updated: {archetype} (lands={ref['lands']}, cmc={ref['cmc']})")
        else:
            # INSERT
            cur.execute("""
                INSERT INTO archetype_patterns (
                    archetype, format, sample_size, 
                    ideal_land_count, ideal_avg_cmc,
                    typical_ramp, typical_draw, typical_removal,
                    core_cards, flex_options, typical_finishers, win_conditions
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                archetype,
                'commander',
                100,  # sample_size fictício
                ref["lands"],
                ref["cmc"],
                typical_ramp,
                typical_draw, 
                typical_removal,
                [],  # core_cards
                '[]',  # flex_options (JSONB)
                [],  # typical_finishers
                [],  # win_conditions
            ))
            inserted += 1
            print(f"  + Inserted: {archetype} (lands={ref['lands']}, cmc={ref['cmc']})")
    
    conn.commit()
    
    # Verificar resultado
    cur.execute("""
        SELECT archetype, ideal_land_count, ideal_avg_cmc 
        FROM archetype_patterns 
        WHERE ideal_land_count IS NOT NULL
        ORDER BY archetype
    """)
    results = cur.fetchall()
    
    print(f"\n=== Resultado Final ===")
    print(f"Updated: {updated}")
    print(f"Inserted: {inserted}")
    print(f"Total com land_count preenchido: {len(results)}")
    
    print(f"\n=== Amostra dos dados ===")
    for r in results[:10]:
        print(f"  {r[0]}: {r[1]} lands, CMC {r[2]}")
    
    conn.close()
    print("\n✅ Concluído!")

if __name__ == "__main__":
    main()
