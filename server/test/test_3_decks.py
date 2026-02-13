#!/usr/bin/env python3
"""Teste de fluxo com 3 decks diferentes"""

import requests
import json
import time

API = "https://evolution-cartinhas.8ktevp.easypanel.host"
TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIxOGRmMDE4OC05ZjI3LTRlMjAtODRmZS1hOWZhMmMzOTk1MWMiLCJ1c2VybmFtZSI6InJhZmEiLCJpYXQiOjE3NzA5Mjk4MjMsImV4cCI6MTc3MTAxNjIyM30.D_z6_dyOvnfMBmGSLd3fb73NHBQVLaU06BSHC7ajZRs"

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

def test_deck(deck_id, archetype, name):
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")
    
    try:
        resp = requests.post(
            f"{API}/ai/optimize",
            headers=headers,
            json={"deck_id": deck_id, "archetype": archetype},
            timeout=90
        )
        
        if resp.status_code != 200:
            print(f"  ERRO: {resp.status_code} - {resp.text[:200]}")
            return
        
        data = resp.json()
        analysis = data.get("deck_analysis", {})
        
        print(f"  Arquétipo detectado: {analysis.get('detected_archetype')}")
        print(f"  CMC médio: {analysis.get('average_cmc')}")
        print(f"  Total cartas: {analysis.get('total_cards')}")
        print(f"  Tema: {data.get('theme')}")
        
        # Mostrar core_cards
        theme = data.get('theme', {})
        if isinstance(theme, dict):
            core = theme.get('core_cards', [])
            print(f"  Core Cards: {core if core else '(nenhum)'}")
        
        print(f"  Removals: {len(data.get('removals', []))} cartas")
        print(f"  Additions: {len(data.get('additions', []))} cartas")
        
        if data.get("reasoning"):
            print(f"  Raciocínio: {data['reasoning'][:100]}...")
    except Exception as e:
        print(f"  ERRO: {e}")

def main():
    print("="*60)
    print("  TESTE DE FLUXO: 3 DECKS")
    print("="*60)
    
    # Buscar decks do usuário
    print("\nBuscando decks existentes...")
    try:
        resp = requests.get(f"{API}/decks", headers=headers, timeout=30)
        decks = resp.json() if resp.status_code == 200 else []
    except:
        decks = []
    
    if isinstance(decks, list) and len(decks) >= 3:
        print(f"Encontrou {len(decks)} decks")
        test_deck(decks[0]["id"], "aggro", f"DECK 1: {decks[0]['name']}")
        time.sleep(2)
        test_deck(decks[1]["id"], "control", f"DECK 2: {decks[1]['name']}")
        time.sleep(2)
        test_deck(decks[2]["id"], "midrange", f"DECK 3: {decks[2]['name']}")
    else:
        # Criar decks de teste
        print("Criando decks de teste...")
        
        # Buscar cartas
        goblins = requests.get(f"{API}/cards?name=goblin&limit=8", timeout=30).json().get("data", [])
        counters = requests.get(f"{API}/cards?name=counter&limit=8", timeout=30).json().get("data", [])
        dragons = requests.get(f"{API}/cards?name=dragon&limit=8", timeout=30).json().get("data", [])
        
        deck_ids = []
        
        # Deck 1: Goblins
        if goblins:
            cards1 = [{"card_id": c["id"], "quantity": 4} for c in goblins[:8]]
            resp1 = requests.post(f"{API}/decks", headers=headers, json={
                "name": "Test Goblin Aggro", "format": "Modern", "cards": cards1
            }, timeout=30)
            deck1_id = resp1.json().get("id")
            if deck1_id:
                deck_ids.append(("Goblin Aggro", deck1_id, "aggro"))
                print(f"  Deck 1 criado: {deck1_id}")
        
        # Deck 2: Control
        if counters:
            cards2 = [{"card_id": c["id"], "quantity": 4} for c in counters[:8]]
            resp2 = requests.post(f"{API}/decks", headers=headers, json={
                "name": "Test Blue Control", "format": "Standard", "cards": cards2
            }, timeout=30)
            deck2_id = resp2.json().get("id")
            if deck2_id:
                deck_ids.append(("Blue Control", deck2_id, "control"))
                print(f"  Deck 2 criado: {deck2_id}")
        
        # Deck 3: Dragons
        if dragons:
            cards3 = [{"card_id": c["id"], "quantity": 4} for c in dragons[:8]]
            resp3 = requests.post(f"{API}/decks", headers=headers, json={
                "name": "Test Dragon Tribal", "format": "Modern", "cards": cards3
            }, timeout=30)
            deck3_id = resp3.json().get("id")
            if deck3_id:
                deck_ids.append(("Dragon Tribal", deck3_id, "midrange"))
                print(f"  Deck 3 criado: {deck3_id}")
        
        for i, (name, deck_id, archetype) in enumerate(deck_ids, 1):
            test_deck(deck_id, archetype, f"DECK {i}: {name}")
            time.sleep(2)
    
    print("\n" + "="*60)
    print("  TESTE CONCLUÍDO")
    print("="*60)

if __name__ == "__main__":
    main()
