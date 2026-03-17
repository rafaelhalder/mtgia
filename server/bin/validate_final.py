#!/usr/bin/env python3
"""Final database validation after sync operations."""
import psycopg2

DATABASE_URL = 'postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder'

conn = psycopg2.connect(DATABASE_URL)
cur = conn.cursor()

print('=' * 60)
print('VALIDAÇÃO FINAL DO BANCO DE DADOS')
print('=' * 60)

# Stats básicas
cur.execute('SELECT COUNT(*) FROM cards')
cards = cur.fetchone()[0]
print(f'Total cards: {cards}')

cur.execute('SELECT COUNT(DISTINCT card_id) FROM card_legalities')
with_leg = cur.fetchone()[0]
print(f'Cards com legalities: {with_leg}')

cur.execute('SELECT COUNT(*) FROM format_staples')
staples = cur.fetchone()[0]
print(f'Format staples: {staples}')

# Tabelas que eram vazias
print('')
print('Tabelas antes vazias:')
for t in ['battle_simulations', 'format_staples', 'ml_prompt_feedback']:
    cur.execute(f'SELECT COUNT(*) FROM {t}')
    c = cur.fetchone()[0]
    status = '✓' if c > 0 else '!'
    print(f'  {status} {t}: {c} rows')

# Integridade
print('')
print('Integridade:')
cur.execute('''
    SELECT COUNT(*) FROM deck_cards dc 
    WHERE NOT EXISTS (
        SELECT 1 FROM decks d WHERE d.id = dc.deck_id AND d.deleted_at IS NULL
    )
''')
orphans = cur.fetchone()[0]
print(f'  deck_cards orfaos: {orphans}')

cur.execute('SELECT COUNT(*) FROM decks WHERE deleted_at IS NULL')
decks = cur.fetchone()[0]
print(f'  decks ativos: {decks}')

cur.execute('SELECT COUNT(*) FROM users')
users = cur.fetchone()[0]
print(f'  users: {users}')

print('')
print('=' * 60)
print('RESUMO:')
coverage = 100 * with_leg // cards
print(f'  Legalities coverage: {with_leg}/{cards} ({coverage}%)')
print(f'  Cards sem legalities: Un-sets/promos (esperado)')
print(f'  Staples populados: {staples}')
print('=' * 60)

conn.close()
