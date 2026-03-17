#!/usr/bin/env python3
"""
Popular tabela archetype_counters com mais estratégias de hate cards.
Baseado em conhecimento do metagame de Commander.
"""

import psycopg2
import uuid
from datetime import datetime

DATABASE_URL = 'postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder'

# Dados de counters: (archetype, counter_archetype, hate_cards[], priority, notes, effectiveness_score)
COUNTERS_DATA = [
    # Estratégias contra arquétipos principais
    ('landfall', None, ['Blood Moon', 'Confounding Conundrum', 'Ankh of Mishra', 'Tunnel Ignus', 'Zo-Zu the Punisher'], 1, 'Punish excessive land drops', 85),
    ('mill', None, ['Eldrazi Titans', 'Gaea\'s Blessing', 'Kozilek, Butcher of Truth', 'Ulamog, the Infinite Gyre'], 1, 'Shuffle graveyard back', 90),
    ('spellslinger', None, ['Rule of Law', 'Eidolon of Rhetoric', 'Damping Sphere', 'Deafening Silence'], 1, 'Limit spell casting', 85),
    ('stax', None, ['Force of Vigor', 'Cyclonic Rift', 'Vandalblast', 'Aura Shards'], 2, 'Remove stax pieces', 80),
    ('tribal', None, ['Engineered Plague', 'Extinction', 'Plague Engineer', 'Tsabo\'s Decree'], 2, 'Target creature types', 75),
    ('superfriends', None, ['The Immortal Sun', 'Pithing Needle', 'Sorcerous Spyglass', 'Hex Parasite'], 1, 'Stop planeswalker abilities', 85),
    ('aristocrats', None, ['Rest in Peace', 'Leyline of the Void', 'Grafdigger\'s Cage', 'Containment Priest'], 1, 'Exile creatures dying', 90),
    ('wheels', None, ['Spirit of the Labyrinth', 'Narset, Parter of Veils', 'Notion Thief', 'Alms Collector'], 1, 'Limit card draw', 90),
    ('reanimator', None, ['Grafdigger\'s Cage', 'Rest in Peace', 'Leyline of the Void', 'Scavenger Grounds'], 1, 'Exile graveyard', 95),
    ('storm', None, ['Rule of Law', 'Deafening Silence', 'Eidolon of the Great Revel', 'Damping Sphere'], 1, 'Limit spells per turn', 90),
    ('big_mana', None, ['Blood Moon', 'Magus of the Moon', 'Back to Basics', 'Price of Progress'], 2, 'Punish nonbasics', 80),
    ('equipment', None, ['Stony Silence', 'Null Rod', 'Collector Ouphe', 'Kappa Cannoneer'], 2, 'Disable artifacts', 85),
    ('counters', None, ['Solemnity', 'Torpor Orb', 'Hallowed Moonlight', 'Containment Priest'], 2, 'Prevent +1/+1 counters', 80),
    ('life_gain', None, ['Erebos, God of the Dead', 'Archfiend of Despair', 'Sulfuric Vortex', 'Tibalt, Rakish Instigator'], 2, 'Prevent life gain', 85),
    ('burn', None, ['Leyline of Sanctity', 'Orbs of Warding', 'Witchbane Orb', 'Imperial Mask'], 2, 'Prevent player targeting', 80),
    ('infect', None, ['Melira, Sylvok Outcast', 'Solemnity', 'Leeches', 'Heartmender'], 1, 'Prevent poison counters', 95),
    ('extra_turns', None, ['Stranglehold', 'Discontinuity', 'Time Stop', 'Summary Dismissal'], 1, 'Prevent extra turns', 90),
    ('theft', None, ['Homeward Path', 'Brand', 'Brooding Saurian', 'Gruul Charm'], 2, 'Reclaim stolen permanents', 85),
    ('chaos', None, ['Grand Abolisher', 'City of Solitude', 'Conqueror\'s Flail', 'Defense Grid'], 2, 'Limit opponent interaction', 75),
    ('hatebears', None, ['Pyroclasm', 'Anger of the Gods', 'Toxic Deluge', 'Massacre'], 2, 'Board wipes for small creatures', 80),
    
    # Counters contra cores específicas (color hosers)
    ('mono_white', None, ['Compost', 'Deathgrip', 'Gloom', 'Lifeforce'], 3, 'Anti-white tech', 70),
    ('mono_blue', None, ['Choke', 'Boil', 'Red Elemental Blast', 'Pyroblast'], 3, 'Anti-blue tech', 75),
    ('mono_black', None, ['Light of Day', 'Absolute Grace', 'Circle of Protection: Black'], 3, 'Anti-black tech', 70),
    ('mono_red', None, ['Circle of Protection: Red', 'Story Circle', 'Hydroblast', 'Blue Elemental Blast'], 3, 'Anti-red tech', 70),
    ('mono_green', None, ['Perish', 'Virtue\'s Ruin', 'Hibernation', 'Flashfires'], 3, 'Anti-green tech', 70),
]

def main():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    inserted = 0
    updated = 0
    
    for archetype, counter_archetype, hate_cards, priority, notes, effectiveness in COUNTERS_DATA:
        # Check if exists
        cur.execute('''
            SELECT id FROM archetype_counters 
            WHERE archetype = %s AND format = 'commander'
        ''', (archetype,))
        
        existing = cur.fetchone()
        
        if existing:
            # Update existing
            cur.execute('''
                UPDATE archetype_counters 
                SET hate_cards = %s, priority = %s, notes = %s, effectiveness_score = %s,
                    last_synced_at = NOW()
                WHERE id = %s
            ''', (hate_cards, priority, notes, effectiveness, existing[0]))
            updated += 1
        else:
            # Insert new
            cur.execute('''
                INSERT INTO archetype_counters 
                (id, archetype, counter_archetype, hate_cards, priority, format, notes, effectiveness_score, created_at, last_synced_at)
                VALUES (%s, %s, %s, %s, %s, 'commander', %s, %s, NOW(), NOW())
            ''', (str(uuid.uuid4()), archetype, counter_archetype, hate_cards, priority, notes, effectiveness))
            inserted += 1
    
    conn.commit()
    
    # Count total
    cur.execute('SELECT COUNT(*) FROM archetype_counters')
    total = cur.fetchone()[0]
    
    print(f'✅ archetype_counters: {inserted} inserted, {updated} updated, {total} total')
    
    # List all
    cur.execute('SELECT archetype, priority, effectiveness_score FROM archetype_counters ORDER BY archetype')
    print('\n=== Arquétipos com counters ===')
    for row in cur.fetchall():
        print(f'  {row[0]}: pri={row[1]}, eff={row[2]}')
    
    conn.close()

if __name__ == '__main__':
    main()
