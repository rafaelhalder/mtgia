#!/usr/bin/env python3
"""
Sync missing card legalities using Scryfall API.
This script focuses ONLY on the 2,413 cards without legality data.
Much faster than full sync since we query only what's missing.
"""

import psycopg2
import requests
import time
import uuid

DATABASE_URL = 'postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder'
SCRYFALL_API = 'https://api.scryfall.com/cards/named'

FORMATS = ['commander', 'standard', 'modern', 'legacy', 'pioneer', 'pauper', 'vintage', 'historic', 'brawl']


def fetch_card_legalities(card_name: str) -> dict:
    """Fetch legalities for a card from Scryfall."""
    try:
        resp = requests.get(
            SCRYFALL_API,
            params={'exact': card_name},
            timeout=15
        )
        
        if resp.status_code == 429:
            print("    Rate limited, waiting 2s...")
            time.sleep(2)
            return fetch_card_legalities(card_name)
        
        if resp.status_code != 200:
            return {}
        
        data = resp.json()
        return data.get('legalities', {})
        
    except Exception as e:
        print(f"    Error fetching {card_name}: {e}")
        return {}


def main():
    print("=" * 60)
    print("SYNC MISSING CARD LEGALITIES")
    print("=" * 60)
    
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    # Get cards without legalities
    cur.execute("""
        SELECT c.id, c.name 
        FROM cards c 
        WHERE NOT EXISTS (
            SELECT 1 FROM card_legalities cl WHERE cl.card_id = c.id
        )
        ORDER BY c.name
        LIMIT 500
    """)
    
    cards_to_sync = cur.fetchall()
    total = len(cards_to_sync)
    
    print(f"Cards without legalities (batch of 500): {total}")
    
    if total == 0:
        print("✅ All cards have legalities!")
        return
    
    synced = 0
    skipped = 0
    
    for idx, (card_id, card_name) in enumerate(cards_to_sync):
        if idx % 50 == 0:
            print(f"\n📥 Progress: {idx}/{total} ({synced} synced, {skipped} skipped)")
        
        # Handle split cards - use first part for lookup
        lookup_name = card_name.split(' // ')[0]
        
        legalities = fetch_card_legalities(lookup_name)
        
        if not legalities:
            skipped += 1
            continue
        
        # Insert legalities for each format
        for fmt in FORMATS:
            status = legalities.get(fmt, 'not_legal')
            if status == 'not_legal':
                continue
            
            try:
                cur.execute("""
                    INSERT INTO card_legalities (id, card_id, format, status)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (card_id, format) DO UPDATE SET status = EXCLUDED.status
                """, (str(uuid.uuid4()), card_id, fmt, status))
            except Exception as e:
                pass  # Skip on error
        
        synced += 1
        
        # Commit every 50 cards
        if synced % 50 == 0:
            conn.commit()
        
        # Respect Scryfall rate limit (10 req/s = 100ms between)
        time.sleep(0.1)
    
    conn.commit()
    
    # Check remaining
    cur.execute("""
        SELECT COUNT(*) FROM cards c 
        WHERE NOT EXISTS (SELECT 1 FROM card_legalities cl WHERE cl.card_id = c.id)
    """)
    remaining = cur.fetchone()[0]
    
    print()
    print("=" * 60)
    print(f"DONE! Synced: {synced}, Skipped: {skipped}")
    print(f"Remaining cards without legalities: {remaining}")
    print("=" * 60)
    
    if remaining > 0:
        print(f"\n⚠️ Run this script again to sync more cards")
    
    conn.close()


if __name__ == '__main__':
    main()
