#!/usr/bin/env python3
"""Quick probe: hit one incomplete deck and dump the FULL raw result."""
import json, time, jwt, requests

BASE = "http://localhost:8080"
SECRET = "your-super-secret-and-long-string-for-jwt"

# Use a small deck - Krenko 25 cards
USER_ID = "18a56811-b72c-495f-a505-519a8fb42526"
DECK_ID = "88887282-d112-4e3d-876c-d3faf209ab29"

token = jwt.encode({"userId": USER_ID}, SECRET, algorithm="HS256")
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# Submit
print("Submitting optimize (complete mode)...")
resp = requests.post(f"{BASE}/ai/optimize", headers=headers, json={
    "deck_id": DECK_ID,
    "archetype": "aggro",
    "mode": "complete"
})

print(f"HTTP {resp.status_code}")
body = resp.json()
print(f"Initial response keys: {list(body.keys())}")

if resp.status_code == 200:
    # Sync response
    print("\n=== SYNC RESPONSE (full dump) ===")
    print(json.dumps(body, indent=2, ensure_ascii=False)[:5000])
elif resp.status_code == 202:
    job_id = body.get("job_id")
    print(f"Job ID: {job_id}")
    
    # Poll
    for i in range(100):
        time.sleep(2)
        pr = requests.get(f"{BASE}/ai/optimize/jobs/{job_id}", headers=headers)
        pj = pr.json()
        status = pj.get("status", "?")
        stage = pj.get("stage", "?")
        print(f"  [{i+1}] status={status} stage={stage}")
        
        if status == "completed":
            print("\n=== COMPLETED RESPONSE (full dump) ===")
            full_dump = json.dumps(pj, indent=2, ensure_ascii=False)
            # Save full dump 
            with open("test/artifacts/ai_optimize/raw_complete_response.json", "w") as f:
                f.write(full_dump)
            # Print first 8000 chars
            print(full_dump[:8000])
            if len(full_dump) > 8000:
                print(f"\n... truncated ({len(full_dump)} total chars)")
            
            # Analyze the result
            result = pj.get("result", {})
            print(f"\n=== RESULT ANALYSIS ===")
            print(f"result keys: {list(result.keys())}")
            
            additions = result.get("additions_detailed", result.get("additions", []))
            removals = result.get("removals_detailed", result.get("removals", []))
            print(f"additions: {len(additions)} entries, total qty={sum(a.get('quantity',1) for a in additions)}")
            print(f"removals: {len(removals)} entries, total qty={sum(r.get('quantity',1) for r in removals)}")
            
            pa = result.get("post_analysis", {})
            print(f"post_analysis keys: {list(pa.keys()) if isinstance(pa, dict) else type(pa)}")
            if isinstance(pa, dict):
                print(f"  lands: {pa.get('lands', {})}")
                print(f"  avg_cmc: {pa.get('avg_cmc')}")
                print(f"  mana_balance: {pa.get('mana_balance', {})}")
                
            warnings = result.get("warnings", [])
            print(f"warnings type: {type(warnings).__name__}")
            if isinstance(warnings, dict):
                print(f"  warnings keys: {list(warnings.keys())}")
                inv = warnings.get("invalid_cards", [])
                print(f"  invalid_cards: {len(inv)} → {inv[:5]}")
            elif isinstance(warnings, list):
                print(f"  warnings count: {len(warnings)}")
            
            break
        elif status == "failed":
            print(f"FAILED: {pj.get('error')}")
            break
    else:
        print("TIMEOUT after 100 polls")
else:
    print(json.dumps(body, indent=2)[:2000])
