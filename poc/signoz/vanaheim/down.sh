#!/usr/bin/env bash
# Tear down the vanaheim SigNoz PoC (containers + bridge). Add --purge to drop volumes.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
DATADIR="${SIGNOZ_POC_DATADIR:-$(cd "$(dirname "$0")" && pwd)}"
docker rm -f signoz-tailnet-bridge >/dev/null 2>&1 || true
COMPOSE="$DATADIR/pours/deployment/compose.yaml"
if [ -f "$COMPOSE" ]; then
  if [ "${1:-}" = "--purge" ]; then docker compose -f "$COMPOSE" down -v; else docker compose -f "$COMPOSE" down; fi
else
  docker ps -a --filter name=signoz --format '{{.Names}}' | xargs -r docker rm -f
fi
echo ">> vanaheim SigNoz PoC stopped."
