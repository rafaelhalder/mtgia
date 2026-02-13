#!/usr/bin/env python3
"""
Script de teste completo para validar todos os endpoints da API
Executa via: sshpass -p 'PASS' ssh root@SERVER "docker exec CONTAINER curl ..." | python3 test_all_endpoints.py
"""

import subprocess
import json
import sys

SERVER = "143.198.230.247"
PASSWORD = "723235R@fa"
API_BASE = "http://localhost:8080"

def ssh_curl(endpoint, method="GET", data=None, headers=None, token=None):
    """Executa curl dentro do container via SSH"""
    curl_cmd = f"curl -s -X {method} 'http://localhost:8080{endpoint}'"
    
    if token:
        curl_cmd += f" -H 'Authorization: Bearer {token}'"
    
    if headers:
        for h in headers:
            curl_cmd += f" -H '{h}'"
    
    if data:
        # Usar base64 para evitar problemas de escape
        import base64
        json_b64 = base64.b64encode(json.dumps(data).encode()).decode()
        curl_cmd = f"echo {json_b64} | base64 -d | curl -s -X {method} 'http://localhost:8080{endpoint}' -H 'Content-Type: application/json' -d @-"
        if token:
            curl_cmd = f"echo {json_b64} | base64 -d | curl -s -X {method} 'http://localhost:8080{endpoint}' -H 'Content-Type: application/json' -H 'Authorization: Bearer {token}' -d @-"
    
    ssh_cmd = f"docker exec $(docker ps -q --filter name=evolution_cartinhas) sh -c \"{curl_cmd}\""
    full_cmd = f"sshpass -p '{PASSWORD}' ssh root@{SERVER} '{ssh_cmd}'"
    
    try:
        result = subprocess.run(full_cmd, shell=True, capture_output=True, text=True, timeout=30)
        if result.stdout.strip():
            return json.loads(result.stdout)
        return {"error": "Empty response", "stderr": result.stderr}
    except json.JSONDecodeError as e:
        return {"error": f"JSON decode error: {e}", "raw": result.stdout[:500]}
    except subprocess.TimeoutExpired:
        return {"error": "Timeout"}
    except Exception as e:
        return {"error": str(e)}

def test_endpoint(name, result, checks):
    """Valida resultado de um endpoint"""
    print(f"\n{'='*60}")
    print(f"📌 {name}")
    print(f"{'='*60}")
    
    if "error" in result:
        print(f"❌ ERRO: {result['error']}")
        return False
    
    all_pass = True
    for check_name, check_fn in checks.items():
        try:
            passed = check_fn(result)
            status = "✅" if passed else "❌"
            print(f"  {status} {check_name}")
            if not passed:
                all_pass = False
        except Exception as e:
            print(f"  ❌ {check_name}: Exception - {e}")
            all_pass = False
    
    return all_pass

def main():
    results = {"passed": 0, "failed": 0, "endpoints": []}
    
    # 1. HEALTH
    health = ssh_curl("/health")
    if test_endpoint("GET /health", health, {
        "status is healthy": lambda r: r.get("status") == "healthy",
        "has timestamp": lambda r: "timestamp" in r,
        "has version": lambda r: "version" in r,
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 2. AUTH - Login
    print("\n" + "="*60)
    print("📌 POST /auth/login")
    print("="*60)
    login = ssh_curl("/auth/login", "POST", {"email": "teste@teste.com", "password": "teste123"})
    token = login.get("token", "")
    if token:
        print(f"  ✅ Token obtido: {token[:30]}...")
        print(f"  ✅ User: {login.get('user', {}).get('username', 'N/A')}")
        results["passed"] += 1
    else:
        print(f"  ❌ Falha no login: {login}")
        results["failed"] += 1
        return  # Não dá para continuar sem token
    
    # 3. CARDS - Search
    cards = ssh_curl("/cards?name=Lightning%20Bolt&limit=50")
    if test_endpoint("GET /cards?name=Lightning Bolt", cards, {
        "has data array": lambda r: isinstance(r.get("data"), list),
        "no duplicates (cards == unique sets)": lambda r: len(r["data"]) == len(set(c.get("set_code","").lower() for c in r["data"])),
        "each card has required fields": lambda r: all(all(k in c for k in ["id", "name", "set_code"]) for c in r["data"]),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
        # Mostrar detalhes se houver duplicatas
        if isinstance(cards.get("data"), list):
            sets = [c.get("set_code","").lower() for c in cards["data"]]
            from collections import Counter
            dupes = {k:v for k,v in Counter(sets).items() if v > 1}
            if dupes:
                print(f"    ⚠️ Duplicatas encontradas: {dupes}")
    
    # 4. CARDS/PRINTINGS
    printings = ssh_curl("/cards/printings?name=Cyclonic%20Rift")
    if test_endpoint("GET /cards/printings?name=Cyclonic Rift", printings, {
        "has data array": lambda r: isinstance(r.get("data"), list),
        "no duplicate sets": lambda r: len(r["data"]) == len(set(c.get("set_code","").lower() for c in r["data"])),
        "reasonable number of editions (5-15)": lambda r: 5 <= len(r["data"]) <= 15,
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 5. CARDS/RESOLVE
    resolve = ssh_curl("/cards/resolve", "POST", {"cards": [{"name": "Sol Ring", "quantity": 1}]})
    if test_endpoint("POST /cards/resolve", resolve, {
        "has resolved array": lambda r: isinstance(r.get("resolved"), list),
        "resolved has card_id": lambda r: len(r["resolved"]) > 0 and "card_id" in r["resolved"][0],
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 6. DECKS - List
    decks = ssh_curl("/decks", token=token)
    if test_endpoint("GET /decks", decks, {
        "has decks array": lambda r: isinstance(r.get("decks"), list),
        "each deck has id and name": lambda r: all("id" in d and "name" in d for d in r.get("decks", [])),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 7. DECK Detail (se houver decks)
    if decks.get("decks"):
        deck_id = decks["decks"][0]["id"]
        deck_detail = ssh_curl(f"/decks/{deck_id}", token=token)
        if test_endpoint(f"GET /decks/{deck_id[:8]}...", deck_detail, {
            "has deck object": lambda r: isinstance(r.get("deck"), dict),
            "deck has cards array": lambda r: isinstance(r.get("deck", {}).get("cards"), list),
            "each card has required fields": lambda r: all(all(k in c for k in ["id", "name", "quantity"]) for c in r.get("deck", {}).get("cards", [])),
        }):
            results["passed"] += 1
        else:
            results["failed"] += 1
    
    # 8. BINDER
    binder = ssh_curl("/binder", token=token)
    if test_endpoint("GET /binder", binder, {
        "has items array": lambda r: isinstance(r.get("items"), list),
        "items have card info": lambda r: all("card" in i or "card_name" in i or "card_id" in i for i in r.get("items", [])) if r.get("items") else True,
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 9. TRADES
    trades = ssh_curl("/trades", token=token)
    if test_endpoint("GET /trades", trades, {
        "has trades array": lambda r: isinstance(r.get("trades"), list),
        "trades have status": lambda r: all("status" in t for t in r.get("trades", [])) if r.get("trades") else True,
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 10. CONVERSATIONS
    convs = ssh_curl("/conversations", token=token)
    if test_endpoint("GET /conversations", convs, {
        "has conversations array": lambda r: isinstance(r.get("conversations"), list),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 11. NOTIFICATIONS
    notifs = ssh_curl("/notifications", token=token)
    if test_endpoint("GET /notifications", notifs, {
        "has notifications array": lambda r: isinstance(r.get("notifications"), list),
        "has unread_count": lambda r: "unread_count" in r,
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 12. COMMUNITY - Decks
    comm_decks = ssh_curl("/community/decks?limit=10")
    if test_endpoint("GET /community/decks", comm_decks, {
        "has decks array": lambda r: isinstance(r.get("decks"), list),
        "decks are public": lambda r: all(d.get("is_public", True) for d in r.get("decks", [])),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 13. COMMUNITY - Users
    comm_users = ssh_curl("/community/users?q=rafa")
    if test_endpoint("GET /community/users?q=rafa", comm_users, {
        "has users array": lambda r: isinstance(r.get("users"), list),
        "users have username": lambda r: all("username" in u for u in r.get("users", [])),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 14. COMMUNITY - Marketplace
    market = ssh_curl("/community/marketplace?limit=10")
    if test_endpoint("GET /community/marketplace", market, {
        "has data array": lambda r: isinstance(r.get("data"), list),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 15. SETS
    sets_data = ssh_curl("/sets?limit=10")
    if test_endpoint("GET /sets", sets_data, {
        "has data array": lambda r: isinstance(r.get("data"), list),
        "sets have code and name": lambda r: all("code" in s and "name" in s for s in r.get("data", [])),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # 16. AUTH - Me
    me = ssh_curl("/auth/me", token=token)
    if test_endpoint("GET /auth/me", me, {
        "has user object": lambda r: isinstance(r.get("user"), dict),
        "user has id and email": lambda r: "id" in r.get("user", {}) and "email" in r.get("user", {}),
    }):
        results["passed"] += 1
    else:
        results["failed"] += 1
    
    # RESUMO FINAL
    print("\n" + "="*60)
    print("📊 RESUMO FINAL")
    print("="*60)
    total = results["passed"] + results["failed"]
    print(f"  ✅ Passou: {results['passed']}/{total}")
    print(f"  ❌ Falhou: {results['failed']}/{total}")
    
    if results["failed"] == 0:
        print("\n🎉 TODOS OS ENDPOINTS ESTÃO FUNCIONANDO CORRETAMENTE!")
    else:
        print(f"\n⚠️ {results['failed']} endpoint(s) com problemas. Verifique acima.")
    
    return results["failed"]

if __name__ == "__main__":
    sys.exit(main())
