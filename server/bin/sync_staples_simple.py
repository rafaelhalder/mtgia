#!/usr/bin/env python3
"""
Sync format staples using Scryfall API with valid query syntax.
Populates the `format_staples` table with popular commander cards.
"""

import psycopg2
import requests
import time
from datetime import datetime

DATABASE_URL = 'postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder'
SCRYFALL_API = 'https://api.scryfall.com/cards/search'

# Simple valid Scryfall queries for staples
STAPLE_QUERIES = [
    # Top Commander staples by EDHREC rank
    {'query': 'legal:commander is:commander', 'archetype': 'commanders', 'limit': 100},
    
    # Ramp
    {'query': 'legal:commander o:"add" t:creature cmc<4', 'archetype': 'ramp', 'limit': 50},
    {'query': 'legal:commander t:artifact o:"add"', 'archetype': 'ramp', 'limit': 50},
    
    # Removal
    {'query': 'legal:commander o:"destroy target creature"', 'archetype': 'removal', 'limit': 50},
    {'query': 'legal:commander o:"exile target"', 'archetype': 'removal', 'limit': 50},
    
    # Card draw
    {'query': 'legal:commander o:"draw" o:"card" t:instant', 'archetype': 'draw', 'limit': 50},
    {'query': 'legal:commander o:"draw" o:"cards" t:sorcery', 'archetype': 'draw', 'limit': 50},
    
    # Counterspells
    {'query': 'legal:commander o:"counter target spell"', 'archetype': 'control', 'limit': 50},
    
    # Tutors
    {'query': 'legal:commander o:"search your library"', 'archetype': 'combo', 'limit': 50},
    
    # Generic good stuff by color
    {'query': 'legal:commander c:w cmc<5', 'archetype': 'white', 'limit': 50},
    {'query': 'legal:commander c:u cmc<5', 'archetype': 'blue', 'limit': 50},
    {'query': 'legal:commander c:b cmc<5', 'archetype': 'black', 'limit': 50},
    {'query': 'legal:commander c:r cmc<5', 'archetype': 'red', 'limit': 50},
    {'query': 'legal:commander c:g cmc<5', 'archetype': 'green', 'limit': 50},
]


def fetch_scryfall(query: str, limit: int = 50) -> list:
    """Fetch cards from Scryfall API."""
    cards = []
    url = f"{SCRYFALL_API}?q={query}&order=edhrec&unique=cards"
    
    while url and len(cards) < limit:
        try:
            print(f"    Fetching: {url[:80]}...")
            resp = requests.get(url, timeout=30)
            
            if resp.status_code == 429:
                print("    Rate limited, waiting 1s...")
                time.sleep(1)
                continue
            
            if resp.status_code != 200:
                print(f"    ⚠️ Error {resp.status_code}: {resp.text[:100]}")
                break
            
            data = resp.json()
            cards.extend(data.get('data', []))
            url = data.get('next_page') if data.get('has_more') else None
            
            # Respect Scryfall rate limit
            time.sleep(0.1)
            
        except Exception as e:
            print(f"    ❌ Exception: {e}")
            break
    
    return cards[:limit]


def main():
    print("=" * 60)
    print("SYNC FORMAT STAPLES (Simple Version)")
    print("=" * 60)
    
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    # Check current count
    cur.execute("SELECT COUNT(*) FROM format_staples")
    before_count = cur.fetchone()[0]
    print(f"Current staples: {before_count}")
    
    total_inserted = 0
    
    for query_config in STAPLE_QUERIES:
        query = query_config['query']
        archetype = query_config['archetype']
        limit = query_config['limit']
        
        print(f"\n📥 Fetching {archetype} staples...")
        print(f"   Query: {query}")
        
        cards = fetch_scryfall(query, limit)
        print(f"   Found: {len(cards)} cards")
        
        for card in cards:
            card_name = card.get('name', '')
            scryfall_id = card.get('id', '')
            color_identity = card.get('color_identity', [])
            edhrec_rank = card.get('edhrec_rank')
            
            if not card_name:
                continue
            
            # Handle split cards - take first part
            card_name_clean = card_name.split(' // ')[0]
            
            # Upsert into format_staples
            try:
                cur.execute("""
                    INSERT INTO format_staples (
                        id, card_name, format, archetype, color_identity, 
                        edhrec_rank, scryfall_id, is_banned, last_synced_at, created_at
                    ) VALUES (
                        gen_random_uuid(), %s, 'commander', %s, %s, 
                        %s, %s, false, NOW(), NOW()
                    )
                    ON CONFLICT (card_name, format, archetype) DO UPDATE SET
                        edhrec_rank = EXCLUDED.edhrec_rank,
                        last_synced_at = NOW()
                """, (card_name_clean, archetype, color_identity, edhrec_rank, scryfall_id))
                total_inserted += 1
            except Exception as e:
                # Skip on any conflict
                pass
        
        conn.commit()
        print(f"   ✅ Inserted/updated staples for {archetype}")
    
    # Final count
    cur.execute("SELECT COUNT(*) FROM format_staples")
    after_count = cur.fetchone()[0]
    
    print()
    print("=" * 60)
    print(f"DONE! Staples: {before_count} → {after_count} (+{after_count - before_count})")
    print("=" * 60)
    
    conn.close()


if __name__ == '__main__':
    main()
