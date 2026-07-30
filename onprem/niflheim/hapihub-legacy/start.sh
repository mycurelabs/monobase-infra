#!/usr/bin/env bash
# Safe (re)create/start of the hapihub v8 archive. Use this instead of bare `docker compose up`
# because env vars are passed through from env.sh (multiline PEM secrets cant use env_file).
# A plain restart/reboot does NOT need this (docker auto-restarts with baked-in env); this is for
# recreation: image bump, compose change, or `down && up`.
set -euo pipefail
cd "$(dirname "$0")"
[ -f env.sh ] || { echo "env.sh missing"; exit 1; }
set -a; . ./env.sh; set +a
docker compose up -d "$@"
echo "up. API: https://niflheim.tail06ec7f.ts.net/  (tailnet only)"
