#!/usr/bin/env python3
"""
Teste: Criar 2 decks com comandantes aleatórios e validar otimização de IA.
"""

import requests
import json
import time
import sys

BASE_URL = "http://localhost:8080"

def main():
    # 1. Login
    print("=" * 60)
    print("=== 1. FAZENDO LOGIN ===")
    print("=" * 60)
    
    login_resp = requests.post(f"{BASE_URL}/auth/login", json={
        "email": "test_optimize@example.com",
        "password": "test123"
    }, timeout=10)

    if login_resp.status_code != 200:
        print(f"ERRO no login: {login_resp.status_code} - {login_resp.text}")
        sys.exit(1)

    data = login_resp.json()
    token = data.get("token")
    user_id = data.get("user", {}).get("id")
    print(f"✓ Login OK! User: {user_id}")

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    # 2. Comandantes selecionados (aleatórios da busca anterior)
    commanders = [
        {
            "id": "985ff7ac-b6ca-4078-9a6d-ec3b4e2505cf",
            "name": "Toxrill, the Corrosive",
            "archetype": "control"  # Slug monster, board control
        },
        {
            "id": "269dd1a9-5240-46dc-a174-36460dffca7d",
            "name": "Gev, Scaled Scorch",
            "archetype": "aggro"  # Fast creature-based
        }
    ]

    # 3. Criar 2 decks
    print("\n" + "=" * 60)
    print("=== 2. CRIANDO 2 DECKS COM COMANDANTES ===")
    print("=" * 60)
    
    deck_ids = []
    
    for i, cmd in enumerate(commanders, 1):
        deck_data = {
            "name": f"Test AI - {cmd['name']}",
            "format": "commander",
            "description": f"Deck de teste para validar otimização de IA com {cmd['name']}",
            "is_public": False,
            "cards": [
                {"card_id": cmd["id"], "quantity": 1, "is_commander": True}
            ]
        }
        
        resp = requests.post(f"{BASE_URL}/decks", headers=headers, json=deck_data, timeout=15)
        
        if resp.status_code in [200, 201]:
            deck = resp.json()
            deck_id = deck.get("id") or deck.get("deck", {}).get("id")
            deck_ids.append({
                "id": deck_id, 
                "commander": cmd["name"],
                "archetype": cmd["archetype"]
            })
            print(f"  ✓ Deck {i} criado: {deck_id}")
            print(f"    Comandante: {cmd['name']}")
            print(f"    Archetype: {cmd['archetype']}")
        else:
            print(f"  ✗ Erro criando deck {i}: {resp.status_code}")
            print(f"    {resp.text[:300]}")
            sys.exit(1)

    # 4. Testar otimização em cada deck
    print("\n" + "=" * 60)
    print("=== 3. TESTANDO OTIMIZAÇÃO DE IA ===")
    print("=" * 60)
    
    results = []
    
    for i, deck_info in enumerate(deck_ids, 1):
        deck_id = deck_info["id"]
        commander = deck_info["commander"]
        archetype = deck_info["archetype"]
        
        print(f"\n--- Deck {i}: {commander} ---")
        print(f"  ID: {deck_id}")
        print(f"  Archetype: {archetype}")
        print(f"  Iniciando otimização (mode=complete)...")
        
        start_time = time.time()
        
        optimize_resp = requests.post(
            f"{BASE_URL}/ai/optimize",
            headers=headers,
            json={
                "deck_id": deck_id,
                "archetype": archetype,
                "mode": "complete",
                "keep_theme": True
            },
            timeout=300  # 5 minutos para IA processar
        )
        
        # Handle async job (202) or sync result (200)
        if optimize_resp.status_code == 202:
            # Async job - need to poll
            job_data = optimize_resp.json()
            job_id = job_data.get("job_id")
            poll_url = job_data.get("poll_url", f"/ai/optimize/jobs/{job_id}")
            print(f"  Job iniciado: {job_id}")
            print(f"  Fazendo polling...")
            
            # Poll até completar (max 5 minutos)
            max_polls = 150  # 150 * 2s = 5 min
            poll_count = 0
            result = None
            
            while poll_count < max_polls:
                poll_count += 1
                time.sleep(2)
                
                poll_resp = requests.get(
                    f"{BASE_URL}{poll_url}",
                    headers=headers,
                    timeout=30
                )
                
                if poll_resp.status_code != 200:
                    continue
                
                poll_data = poll_resp.json()
                status = poll_data.get("status")
                
                if status == "completed":
                    result = poll_data.get("result", poll_data)
                    elapsed = time.time() - start_time
                    print(f"  ✓ Job completado em {elapsed:.1f}s ({poll_count} polls)")
                    break
                elif status == "failed":
                    error_msg = poll_data.get("error", "Unknown error")
                    print(f"  ✗ Job falhou: {error_msg}")
                    results.append({
                        "deck_id": deck_id,
                        "commander": commander,
                        "success": False,
                        "error": error_msg
                    })
                    result = None
                    break
                else:
                    # Still processing
                    stage = poll_data.get("current_stage", "?")
                    if poll_count % 5 == 0:
                        print(f"    ... stage {stage}, aguardando...")
            
            if poll_count >= max_polls:
                print(f"  ✗ Timeout após {max_polls * 2}s")
                results.append({
                    "deck_id": deck_id,
                    "commander": commander,
                    "success": False,
                    "error": "Timeout"
                })
                continue
            
            if result is None:
                continue
                
        elif optimize_resp.status_code == 200:
            result = optimize_resp.json()
            elapsed = time.time() - start_time
        else:
            print(f"  ✗ Erro na otimização: {optimize_resp.status_code}")
            print(f"    {optimize_resp.text[:500]}")
            results.append({
                "deck_id": deck_id,
                "commander": commander,
                "success": False,
                "error": optimize_resp.text[:500]
            })
            continue
        
        # Process result (from sync or async)
        additions = result.get("additions", [])
        removals = result.get("removals", [])
        post_analysis = result.get("post_analysis", {})
        cache_hit = result.get("cache", {}).get("hit", False)
        
        total_cards = post_analysis.get("total_cards", 0)
        lands = post_analysis.get("lands", 0)
        
        print(f"    Cache hit: {cache_hit}")
        print(f"    Adições: {len(additions)} cartas")
        print(f"    Remoções: {len(removals)} cartas")
        print(f"    Total final: {total_cards} cartas")
        print(f"    Lands: {lands}")
        
        # Validações
        success = True
        errors = []
        
        if total_cards != 100:
            success = False
            errors.append(f"Total deveria ser 100, mas é {total_cards}")
        
        if lands < 30 or lands > 42:
            errors.append(f"Lands fora do esperado (30-42): {lands}")
        
        results.append({
            "deck_id": deck_id,
            "commander": commander,
            "success": success,
            "total_cards": total_cards,
            "lands": lands,
            "additions": len(additions),
            "elapsed_seconds": elapsed,
            "errors": errors
        })

    # 5. Resumo final
    print("\n" + "=" * 60)
    print("=== 4. RESUMO FINAL ===")
    print("=" * 60)
    
    all_passed = True
    
    for r in results:
        status = "✓ PASSOU" if r.get("success") else "✗ FALHOU"
        print(f"\n  {status}: {r['commander']}")
        print(f"    Deck ID: {r['deck_id']}")
        
        if r.get("success"):
            print(f"    Total: {r['total_cards']} cartas")
            print(f"    Lands: {r['lands']}")
            print(f"    Tempo: {r['elapsed_seconds']:.1f}s")
            if r.get("errors"):
                print(f"    Avisos: {', '.join(r['errors'])}")
        else:
            all_passed = False
            if r.get("error"):
                print(f"    Erro: {r.get('error')[:200]}")
    
    print("\n" + "=" * 60)
    if all_passed:
        print("✓✓✓ TODOS OS TESTES PASSARAM ✓✓✓")
    else:
        print("✗✗✗ ALGUNS TESTES FALHARAM ✗✗✗")
    print("=" * 60)
    
    # Salvar resultados
    with open("test/artifacts/create_and_optimize_results.json", "w") as f:
        json.dump({
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "decks_created": len(deck_ids),
            "results": results,
            "all_passed": all_passed
        }, f, indent=2)
    
    print(f"\nResultados salvos em test/artifacts/create_and_optimize_results.json")
    
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
