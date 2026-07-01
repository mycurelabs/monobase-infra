#!/usr/bin/env bash
# Repeatable SigNoz PoC bring-up on vanaheim (Docker, latest, via foundryctl). Idempotent.
# See poc/signoz/README.md for the architecture. PoC for #2096.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.local/bin:$PATH"
DATADIR="${SIGNOZ_POC_DATADIR:-$PWD}"   # foundry generates ./pours/ here (gitignored)
BRIDGE_PORT=14317
UI=http://localhost:8080

# 1) foundryctl (SigNoz installer CLI; user-local, no sudo, no native SigNoz).
command -v foundryctl >/dev/null 2>&1 || curl -fsSL https://signoz.io/foundry.sh | bash

# 2) SigNoz as Docker containers (latest). Generates + starts compose in DATADIR (./pours).
[ "$DATADIR" != "$PWD" ] && { mkdir -p "$DATADIR"; cp -f casting.yaml "$DATADIR/casting.yaml"; }
( cd "$DATADIR" && foundryctl cast -f casting.yaml )

# 3) Native tailnet bridge. Docker-published ports are NOT reachable over tailscale
#    (only native listeners are, like Ollama's). Re-expose OTLP on a host-network
#    listener :14317 -> docker 127.0.0.1:4317 so remote tailnet peers (the cluster
#    egress) can reach it.
if ! docker ps --format '{{.Names}}' | grep -qx signoz-tailnet-bridge; then
  docker rm -f signoz-tailnet-bridge >/dev/null 2>&1 || true
  docker run -d --name signoz-tailnet-bridge --network host --restart unless-stopped \
    alpine/socat "TCP-LISTEN:${BRIDGE_PORT},fork,reuseaddr" "TCP:127.0.0.1:4317" >/dev/null
fi

# 4) One-time onboarding (admin/org). REQUIRED: without an org, SigNoz's opamp server
#    refuses to push the OTLP receiver config to the collector ("cannot create agent
#    without orgId") and ingestion silently fails. Creds saved locally (gitignored).
CREDS=.admin-creds
if [ ! -f "$CREDS" ]; then
  for _ in $(seq 1 30); do curl -fsS -o /dev/null "$UI" && break || sleep 2; done
  PW="$(openssl rand -base64 15)"
  resp="$(curl -sS -X POST "$UI/api/v1/register" -H 'Content-Type: application/json' \
    -d "{\"name\":\"admin\",\"orgName\":\"mycure\",\"email\":\"admin@mycure.local\",\"password\":\"$PW\"}" || true)"
  if printf '%s' "$resp" | grep -q '"status":"success"'; then
    printf 'email=admin@mycure.local\npassword=%s\n' "$PW" > "$CREDS"; chmod 600 "$CREDS"
    echo ">> admin/org created; creds -> $CREDS"
    docker restart signoz-ingester-1 >/dev/null   # re-handshake opamp -> binds OTLP receiver
  else
    echo ">> register skipped/failed (already set up?): $(printf '%s' "$resp" | head -c 120)"
  fi
fi

echo ">> SigNoz UI:   $UI   (tailnet: http://100.120.88.93:8080)"
echo ">> OTLP ingest: 100.120.88.93:${BRIDGE_PORT} (gRPC, for tailnet peers)"
[ -f "$CREDS" ] && echo ">> admin login in $CREDS"
docker ps --filter name=signoz --format 'table {{.Names}}\t{{.Status}}'
