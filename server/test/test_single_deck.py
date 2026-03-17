#!/usr/bin/env python3
"""Teste de performance com 1 deck."""

import time
import requests
import jwt
import psycopg2

SECRET = 'your-super-secret-and-long-string-for-jwt'
BASE = 'http://localhost:8080'

# Deck Goblins (aggro, 95 cartas)
DECK_ID = '8c22deb9-80bd-489f-8e87-1344eabac698'
USER_ID = '18df0188-9f27-4e20-84fe-a9fa2c39951c'

def main():
    token = jwt.encode({'userId': USER_ID}, SECRET, algorithm='HS256')
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

    print('=' * 60)
    print('TESTE DE PERFORMANCE - 1 DECK (Goblins Aggro)')
    print('=' * 60)
    print()

    # Limpar cache primeiro
    conn = psycopg2.connect('postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder')
    cur = conn.cursor()
    cur.execute('DELETE FROM ai_optimize_cache WHERE deck_id = %s', (DECK_ID,))
    conn.commit()
    print(f'Cache limpo para deck {DECK_ID[:8]}...')
    conn.close()
    print()

    # Testar optimize
    print('Iniciando otimizacao...')
    start = time.time()

    r = requests.post(
        f'{BASE}/ai/optimize',
        headers=headers,
        json={'deck_id': DECK_ID, 'archetype': 'aggro'},
        timeout=120
    )

    elapsed = time.time() - start

    print(f'Status: {r.status_code}')
    print(f'Tempo: {elapsed:.1f}s')
    print()

    if r.status_code == 200:
        data = r.json()
        print(f'Mode: {data.get("mode")}')
        print(f'Additions: {len(data.get("additions", []))}')
        print(f'Removals: {len(data.get("removals", []))}')
        print(f'Cache hit: {data.get("cache", {}).get("hit", False)}')
        
        post = data.get('post_analysis', {})
        print()
        print('POST ANALYSIS:')
        print(f'  Total cards: {post.get("total_cards")}')
        print(f'  Lands: {post.get("lands")}')
        print(f'  Avg CMC: {post.get("average_cmc")}')
        
        # Mostrar algumas sugestoes
        if data.get('additions'):
            print()
            print('TOP 5 ADDITIONS:')
            for item in data['additions'][:5]:
                if isinstance(item, dict):
                    print(f'  + {item.get("name", item)}')
                else:
                    print(f'  + {item}')
                
        if data.get('removals'):
            print()
            print('TOP 5 REMOVALS:')
            for item in data['removals'][:5]:
                if isinstance(item, dict):
                    print(f'  - {item.get("name", item)}')
                else:
                    print(f'  - {item}')
    else:
        print(f'ERRO: {r.text[:300]}')

    print()
    print('=' * 60)

if __name__ == '__main__':
    main()
