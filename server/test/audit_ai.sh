#!/bin/bash
API="https://evolution-cartinhas.8ktevp.easypanel.host"
TS=$(date +%s)

echo "=== AI & IMPORT ENDPOINTS ==="

REG=$(curl -s -m 15 -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"ai_${TS}\",\"email\":\"ai_${TS}@t.com\",\"password\":\"Test123!\"}")
TOKEN=$(echo "$REG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
echo "Auth: OK"

sleep 6

# Archetypes
R=$(curl -s -w "\n%{http_code}" -m 20 -X POST "$API/ai/archetypes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"format\":\"commander\",\"colors\":[\"R\",\"G\"]}")
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | sed '$d')
echo ""
echo "Archetypes: $CODE"
echo "$BODY" | head -c 300
echo ""

# Generate
R=$(curl -s -w "\n%{http_code}" -m 20 -X POST "$API/ai/generate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"description\":\"goblin aggro deck\",\"format\":\"commander\"}")
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | sed '$d')
echo ""
echo "Generate: $CODE"
echo "$BODY" | head -c 300
echo ""

# Explain
R=$(curl -s -w "\n%{http_code}" -m 20 -X POST "$API/ai/explain" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"card_name\":\"Sol Ring\"}")
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | sed '$d')
echo ""
echo "Explain: $CODE"
echo "$BODY" | head -c 300
echo ""

# Import validate
R=$(curl -s -w "\n%{http_code}" -m 15 -X POST "$API/import/validate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"1 Sol Ring\n1 Command Tower\",\"format\":\"commander\"}")
CODE=$(echo "$R" | tail -1)
echo ""
echo "Import validate: $CODE"

echo ""
echo "=== FIM ==="
