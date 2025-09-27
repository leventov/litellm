#!/usr/bin/env bash
set -euo pipefail

# Smoke checks for internal-only LiteLLM deployment on Fly Machines.
# Requirements (env):
#   LITELLM_APP   - Fly app name for LiteLLM (default: pocketlitellm)
#   PG_APP        - Fly app name for Postgres   (default: pocketpg)
#   MASTER_KEY    - LiteLLM master key for Authorization: Bearer
#   PG_DSN        - Postgres DSN for psql on pocketpg machine

LITELLM_APP="${LITELLM_APP:-pocketlitellm}"
PG_APP="${PG_APP:-pocketpg}"
MASTER_KEY="${MASTER_KEY:-}"
PG_DSN="${PG_DSN:-}"

if [[ -z "$MASTER_KEY" ]]; then
  echo "ERROR: MASTER_KEY env var required" >&2
  exit 1
fi
if [[ -z "$PG_DSN" ]]; then
  echo "ERROR: PG_DSN env var required (e.g., postgresql://litellm:PW@127.0.0.1:5432/postgres?sslmode=disable)" >&2
  exit 1
fi

echo "[1/4] Verifying LiteLLM has no public IPs"
if fly ips list -a "$LITELLM_APP" | grep -qiE 'IPv4|IPv6'; then
  echo "ERROR: Public IPs found on $LITELLM_APP" >&2
  exit 1
fi
echo "OK: no public IPs"

echo "[2/4] Readiness over internal listener (127.0.0.1:4000)"
fly ssh console -a "$LITELLM_APP" -C "python - << 'PY'
import urllib.request
u = 'http://127.0.0.1:4000/health/readiness'
print(urllib.request.urlopen(u, timeout=10).read().decode())
PY"

echo "[3/4] Chat completion to grok-4-fast and print response snippet"
fly ssh console -a "$LITELLM_APP" -C "python - << 'PY'
import json, urllib.request
h={'Authorization':'Bearer ${MASTER_KEY}','Content-Type':'application/json'}
u='http://127.0.0.1:4000/v1/chat/completions'
body={'model':'grok-4-fast','messages':[{'role':'user','content':'smoke test: say ok'}]}
r=urllib.request.urlopen(urllib.request.Request(u,data=json.dumps(body).encode(),headers=h),timeout=60).read().decode()
open('/tmp/chat.json','w').write(r)
print('CHAT_OK')
PY"
fly ssh console -a "$LITELLM_APP" -C "sed -n '1,80p' /tmp/chat.json"

echo "[4/4] Verify a spend log row was written (latest)"
fly ssh console -a "$PG_APP" -C "psql -X -tAc 'SELECT request_id, model, total_tokens, spend, \"startTime\", status FROM \"litellm\".\"LiteLLM_SpendLogs\" ORDER BY \"startTime\" DESC LIMIT 1;' \"$PG_DSN\""

echo "DONE: smoke checks passed"


