#!/bin/bash
set -e

API="https://evolution-cartinhas.8ktevp.easypanel.host"

# 1. Login
echo "=== LOGIN ==="
TOKEN=$(curl -s -m 20 -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"rafaelhalder@gmail.com","password":"12345678"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")
echo "Token: ${TOKEN:0:20}..."

sleep 3

# 2. List decks
echo ""
echo "=== DECKS ==="
DECKS_JSON=$(curl -s -m 20 "$API/decks" -H "Authorization: Bearer $TOKEN")
echo "$DECKS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
decks = data if isinstance(data, list) else data.get('data', [])
for d in decks[:8]:
    print(f'  {d[\"id\"]} | {d[\"name\"]} | cards={d.get(\"card_count\",\"?\")}')" 2>/dev/null

# 3. Get first deck ID with cards
DECK_ID=$(echo "$DECKS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
decks = data if isinstance(data, list) else data.get('data', [])
for d in decks:
    cc = d.get('card_count', 0)
    if isinstance(cc, int) and cc > 0:
        print(d['id'])
        break
" 2>/dev/null)
echo ""
echo "Testing deck: $DECK_ID"

# 4. Test recommendations
if [ -n "$DECK_ID" ]; then
  echo ""
  echo "=== RECOMMENDATIONS ==="
  RECO=$(curl -s -m 30 -X POST "$API/decks/$DECK_ID/recommendations" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json")
  echo "$RECO" | python3 -m json.tool 2>/dev/null || echo "$RECO"
fi

echo ""
echo "=== DONE ==="
