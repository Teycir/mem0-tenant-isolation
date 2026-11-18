#!/usr/bin/env bash
# Bring up a disposable local mem0 instance with pgvector + stub OpenAI,
# then provision two principals (admin + role=user) and seed two tenants.
#
# Usage: MEM0_SRC=/path/to/mem0 [PORT=8000] ./poc/setup_local.sh
set -euo pipefail

MEM0_SRC="${MEM0_SRC:-$HOME/ResearchAIRedTeam/mem0}"
PORT="${PORT:-8000}"
POC_DIR="${POC_DIR:-/tmp/mem0-poc}"
WORK="$(cd "$(dirname "$0")/.." && pwd)"
BASE="http://127.0.0.1:$PORT"

[ -d "$MEM0_SRC/server" ] || { echo "MEM0_SRC must point at a mem0 checkout (got: $MEM0_SRC)"; exit 1; }
mkdir -p "$POC_DIR"

echo "[1/8] pgvector"
docker compose -f "$WORK/docker-compose.yml" up -d
for _ in $(seq 1 60); do
  docker exec mem0pg pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
docker exec mem0pg psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='mem0_app'" | grep -q 1 \
  || docker exec mem0pg psql -U postgres -c "CREATE DATABASE mem0_app"

echo "[2/8] python venv"
[ -x "$POC_DIR/venv/bin/python" ] || python3 -m venv "$POC_DIR/venv"
"$POC_DIR/venv/bin/pip" -q install -e "$MEM0_SRC" -r "$MEM0_SRC/server/requirements.txt"

echo "[3/8] stub OpenAI (embeddings + chat)"
pkill -f fake_openai.py 2>/dev/null || true
nohup "$POC_DIR/venv/bin/python" "$WORK/poc/fake_openai.py" >"$POC_DIR/fake_openai.log" 2>&1 &
sleep 2

echo "[4/8] env"
cat > "$POC_DIR/env.sh" <<EOF
export POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=8432 POSTGRES_USER=postgres POSTGRES_PASSWORD=pgpass
export POSTGRES_DB=postgres POSTGRES_COLLECTION_NAME=mem0 APP_DB_NAME=mem0_app
export OPENAI_API_KEY=sk-stub OPENAI_BASE_URL=http://127.0.0.1:9999/v1
export JWT_SECRET=poc-jwt-secret-0123456789abcdef MEM0_TELEMETRY=false
export HISTORY_DB_PATH=$POC_DIR/history.db DASHBOARD_URL=http://localhost:3000
export AUTH_DISABLED=false ADMIN_API_KEY=
EOF
# shellcheck disable=SC1090
. "$POC_DIR/env.sh"

echo "[5/8] migrations"
(cd "$MEM0_SRC/server" && "$POC_DIR/venv/bin/alembic" upgrade head)

echo "[6/8] server on :$PORT"
pkill -f "uvicorn main:app" 2>/dev/null || true
(cd "$MEM0_SRC/server" && setsid nohup "$POC_DIR/venv/bin/uvicorn" main:app \
  --host 127.0.0.1 --port "$PORT" </dev/null >"$POC_DIR/server.log" 2>&1 &)
for _ in $(seq 1 60); do
  curl -sf -o /dev/null "$BASE/docs" && break
  sleep 1
done

echo "[7/8] principals"
curl -s -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
  -d '{"name":"Admin","email":"admin@example.com","password":"AdminPass123"}' \
  -o "$POC_DIR/reg.json"
TOK=$("$POC_DIR/venv/bin/python" -c "import json;print(json.load(open('$POC_DIR/reg.json')).get('access_token',''))")
if [ -z "$TOK" ]; then   # re-run: account already exists, log in instead
  curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
    -d '{"email":"admin@example.com","password":"AdminPass123"}' -o "$POC_DIR/reg.json"
  TOK=$("$POC_DIR/venv/bin/python" -c "import json;print(json.load(open('$POC_DIR/reg.json')).get('access_token',''))")
fi
[ -n "$TOK" ] || { echo "admin auth failed; see $POC_DIR/reg.json"; exit 1; }
curl -s -X POST "$BASE/api-keys" -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d '{"label":"tenant-a-app"}' -o "$POC_DIR/keyA.json"
KA=$("$POC_DIR/venv/bin/python" -c "import json;print(json.load(open('$POC_DIR/keyA.json'))['key'])")
MEM0_SRC="$MEM0_SRC" "$POC_DIR/venv/bin/python" "$WORK/poc/mkuser.py" "$POC_DIR/keyB.txt" > "$POC_DIR/keyB.json"
KB=$(cat "$POC_DIR/keyB.txt")

echo "[8/8] seed tenants"
curl -s -X POST "$BASE/memories" -H "X-API-Key: $KA" -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Tenant Alice private: SSN 123-45-6789, API token sk-alice-secret"}],"user_id":"alice_tenant","infer":false}' >/dev/null
curl -s -X POST "$BASE/memories" -H "X-API-Key: $KB" -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Tenant Bob private: card 4111-1111-1111-1111"}],"user_id":"bob_tenant","infer":false}' >/dev/null

cat <<EOF

Ready.
  admin key      (role=admin) : $KA
  low-priv key   (role=user)  : $KB
  victim tenant               : alice_tenant

  BASE=$BASE KEY=$KB VICTIM=alice_tenant ./poc/poc_cross_tenant.sh
EOF
