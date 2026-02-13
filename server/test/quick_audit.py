#!/usr/bin/env python3
"""Quick audit of all API endpoints."""
import requests
import time
import json

API = "https://evolution-cartinhas.8ktevp.easypanel.host"
ts = str(int(time.time()))

results = []

def test(name, method, path, headers=None, json_data=None, expected=None):
    try:
        r = requests.request(method, f"{API}{path}", headers=headers, json=json_data, timeout=30)
        status = "OK" if (expected is None or r.status_code in expected) else "FAIL"
        body = r.json() if r.headers.get("content-type","").startswith("application/json") else r.text[:100]
        results.append((name, r.status_code, status, body))
        print(f"  {'✅' if status == 'OK' else '❌'} {name}: {r.status_code}")
        return r
    except Exception as e:
        results.append((name, 0, "ERROR", str(e)))
        print(f"  ❌ {name}: ERROR - {e}")
        return None

# ── Auth ──
print("\n═══ AUTH ═══")
r = test("Register", "POST", "/auth/register", json_data={
    "username": f"audit_{ts}", "email": f"audit_{ts}@test.com", "password": "Test123!"
}, expected=[201])

data = r.json() if r else {}
token = data.get("token", "")
user_id = data.get("user", {}).get("id", "")
headers = {"Authorization": f"Bearer {token}"}
print(f"  → User: {user_id[:12]}...")

time.sleep(5)
test("Login", "POST", "/auth/login", json_data={
    "email": f"audit_{ts}@test.com", "password": "Test123!"
}, expected=[200])

time.sleep(5)
test("GET /auth/me", "GET", "/auth/me", headers=headers, expected=[200])

# ── Health ──
print("\n═══ HEALTH ═══")
test("Health", "GET", "/health", expected=[200])
test("Health/live", "GET", "/health/live", expected=[200])
test("Health/ready", "GET", "/health/ready", expected=[200])

# ── Cards ──
print("\n═══ CARDS ═══")
test("Search cards", "GET", "/cards?name=Lightning&limit=3", expected=[200])
test("Card printings", "GET", "/cards/printings?name=Sol%20Ring&limit=5", expected=[200])
test("Resolve card", "POST", "/cards/resolve", json_data={"name": "Dark Ritual"}, expected=[200])

# ── Sets ──
print("\n═══ SETS ═══")
test("List sets", "GET", "/sets?limit=3", expected=[200])

# ── Rules ──
print("\n═══ RULES ═══")
test("List rules", "GET", "/rules?limit=3", expected=[200])

# ── Decks ──
print("\n═══ DECKS ═══")
test("List decks", "GET", "/decks", headers=headers, expected=[200])
r = test("Create deck", "POST", "/decks", headers=headers, json_data={
    "name": f"Audit Deck {ts}", "format": "commander"
}, expected=[200, 201])
deck_id = ""
if r and r.status_code in [200, 201]:
    deck_id = r.json().get("id", r.json().get("deck", {}).get("id", ""))
    print(f"  → Deck: {deck_id[:12]}...")

if deck_id:
    test("Get deck", "GET", f"/decks/{deck_id}", headers=headers, expected=[200])
    test("Deck analysis", "POST", f"/decks/{deck_id}/analysis", headers=headers, expected=[200])
    test("Deck validate", "POST", f"/decks/{deck_id}/validate", headers=headers, expected=[200, 400, 422])
    test("Deck export", "GET", f"/decks/{deck_id}/export", headers=headers, expected=[200])
    test("Deck simulate", "GET", f"/decks/{deck_id}/simulate", headers=headers, expected=[200, 400, 422])

# ── Community ──
print("\n═══ COMMUNITY ═══")
test("Public decks", "GET", "/community/decks?limit=3", expected=[200])
test("Search users", "GET", "/community/users?q=a&limit=3", expected=[200])
test("Marketplace", "GET", "/community/marketplace?limit=3", expected=[200])

# ── Binder ──
print("\n═══ BINDER ═══")
test("My binder", "GET", "/binder?limit=3", headers=headers, expected=[200])

# ── Trades ──
print("\n═══ TRADES ═══")
test("My trades", "GET", "/trades?limit=3", headers=headers, expected=[200])

# ── Conversations ──
print("\n═══ CONVERSATIONS ═══")
test("List conversations", "GET", "/conversations", headers=headers, expected=[200])

# ── Notifications ──
print("\n═══ NOTIFICATIONS ═══")
test("Notif count", "GET", "/notifications/count", headers=headers, expected=[200])
test("Notif list", "GET", "/notifications?limit=5", headers=headers, expected=[200])
test("Mark all read", "PUT", "/notifications/read-all", headers=headers, expected=[200])

# ── AI ──
print("\n═══ AI ═══")
time.sleep(1)
test("AI explain", "POST", "/ai/explain", headers=headers, json_data={"card_name": "Sol Ring"}, expected=[200])
time.sleep(1)
test("AI archetypes", "POST", "/ai/archetypes", headers=headers, json_data={
    "format": "commander", "colors": ["R"]
}, expected=[200])
time.sleep(1)
test("AI generate", "POST", "/ai/generate", headers=headers, json_data={
    "description": "goblin aggro deck", "format": "commander"
}, expected=[200])

# ── Import ──
print("\n═══ IMPORT ═══")
test("Import validate", "POST", "/import/validate", headers=headers, json_data={
    "text": "1x Sol Ring\n1x Lightning Bolt"
}, expected=[200])

# ── Market ──
print("\n═══ MARKET ═══")
test("Market movers", "GET", "/market/movers", expected=[200])

# ── Summary ──
print("\n" + "═" * 60)
ok = sum(1 for _, _, s, _ in results if s == "OK")
fail = sum(1 for _, _, s, _ in results if s != "OK")
print(f"  TOTAL: {ok} ✅ passed | {fail} ❌ failed | {len(results)} total")

if fail > 0:
    print("\n  FAILURES:")
    for name, code, status, body in results:
        if status != "OK":
            detail = str(body)[:100] if body else ""
            print(f"    ❌ {name}: {code} — {detail}")
