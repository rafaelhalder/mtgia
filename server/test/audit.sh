#!/bin/bash
API="https://evolution-cartinhas.8ktevp.easypanel.host"
TS=$(date +%s)

echo "=== AUDIT COMPLETO DE ENDPOINTS ==="
echo ""

# 1. Register
echo "--- AUTH ---"
REG=$(curl -s -m 15 -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"username":"cur_'$TS'","email":"cur_'$TS'@t.com","password":"Test123!"}')
TOKEN=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
echo "  Register: OK (token recebido)"

sleep 6

# Auth me
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/auth/me" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  Auth/me: $CODE"

echo ""
echo "--- NOTIFICACOES ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/notifications/count" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | head -1)
echo "  Count: $CODE -> $BODY"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/notifications?limit=3" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  List: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 -X PUT "$API/notifications/read-all" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  Read-all: $CODE"

echo ""
echo "--- CONVERSATIONS ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/conversations" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  List: $CODE"

echo ""
echo "--- BINDER ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/binder?limit=1" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  List: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/binder/stats" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  Stats: $CODE"

echo ""
echo "--- TRADES ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/trades?limit=1" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  List: $CODE"

echo ""
echo "--- DECKS ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/decks" -H "Authorization: Bearer $TOKEN")
CODE=$(echo "$R" | tail -1)
echo "  List: $CODE"

# Create deck
R=$(curl -s -w "\n%{http_code}" -m 15 -X POST "$API/decks" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"AuditDeck","format":"commander","description":"test"}')
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | head -1)
DECK_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
echo "  Create: $CODE (id=$DECK_ID)"

if [ -n "$DECK_ID" ]; then
  R=$(curl -s -w "\n%{http_code}" -m 15 "$API/decks/$DECK_ID" -H "Authorization: Bearer $TOKEN")
  CODE=$(echo "$R" | tail -1)
  echo "  Detail: $CODE"

  R=$(curl -s -w "\n%{http_code}" -m 15 -X DELETE "$API/decks/$DECK_ID" -H "Authorization: Bearer $TOKEN")
  CODE=$(echo "$R" | tail -1)
  echo "  Delete: $CODE"
fi

echo ""
echo "--- COMMUNITY ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/community/decks?limit=2")
CODE=$(echo "$R" | tail -1)
echo "  Public decks: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/community/marketplace?limit=2")
CODE=$(echo "$R" | tail -1)
echo "  Marketplace: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/community/users?q=test")
CODE=$(echo "$R" | tail -1)
echo "  User search: $CODE"

echo ""
echo "--- CARDS ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/cards?name=Sol+Ring&limit=2")
CODE=$(echo "$R" | tail -1)
echo "  Search: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/cards/printings?name=Sol+Ring&limit=3")
CODE=$(echo "$R" | tail -1)
echo "  Printings: $CODE"

echo ""
echo "--- OUTROS ---"
R=$(curl -s -w "\n%{http_code}" -m 15 "$API/health")
CODE=$(echo "$R" | tail -1)
echo "  Health: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/sets")
CODE=$(echo "$R" | tail -1)
echo "  Sets: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/rules?limit=2")
CODE=$(echo "$R" | tail -1)
echo "  Rules: $CODE"

R=$(curl -s -w "\n%{http_code}" -m 15 "$API/market/movers")
CODE=$(echo "$R" | tail -1)
echo "  Market movers: $CODE"

echo ""
echo "--- AI (precisa OpenAI key no server) ---"
R=$(curl -s -w "\n%{http_code}" -m 20 -X POST "$API/ai/archetypes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"format":"commander","colors":["R","G"]}')
CODE=$(echo "$R" | tail -1)
echo "  Archetypes: $CODE"

echo ""
echo "=== AUDIT COMPLETO ==="
