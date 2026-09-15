#!/usr/bin/env bash
# pg-logical-backup restore DRILL — the REAL scratch-restore gate.
#
# The nightly CronJob's in-line `pg_restore --list` / full-decompress checks only
# prove the archive is READABLE. This drill proves the dump actually RESTORES into
# a working database and comes back with ROWS. Run it BEFORE flipping
# pgLogicalBackup.enabled: true (and again before prod promotion).
#
# It pulls the newest crypt dump for a path, restores it into a THROWAWAY Postgres
# (a disposable Docker container — nothing touches prod, nothing persists), and
# asserts the required tables came back non-empty. Non-zero exit = do NOT activate.
#
# Usage:
#   scripts/pg-logical-backup-restore-drill.sh \
#     --remote pgdump-crypt:pgdump-preprod \
#     [--rclone-conf ~/.config/rclone/rclone.conf] \
#     [--pg-image docker.io/bitnamilegacy/postgresql:16.4.0-debian-12-r13] \
#     [--require organizations,accounts] [--min-rows 1]
#
# Prereqs: rclone (with the crypt remote configured), docker.
set -euo pipefail

REMOTE=""
RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"
PG_IMAGE="docker.io/bitnamilegacy/postgresql:16.4.0-debian-12-r13"
REQUIRE="organizations,accounts"
MIN_ROWS=1
SCRATCH_DB="pgdump_restore_scratch"

while [ $# -gt 0 ]; do
  case "$1" in
    --remote)      REMOTE="$2"; shift 2 ;;
    --rclone-conf) RCLONE_CONF="$2"; shift 2 ;;
    --pg-image)    PG_IMAGE="$2"; shift 2 ;;
    --require)     REQUIRE="$2"; shift 2 ;;
    --min-rows)    MIN_ROWS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REMOTE" ] || { echo "ERROR: --remote is required (e.g. pgdump-crypt:pgdump-preprod)" >&2; exit 2; }

WORK="$(mktemp -d)"
CONTAINER="pgdump-drill-$$"
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "[drill] newest dump under ${REMOTE}"
NEWEST="$(rclone --config "$RCLONE_CONF" lsf --dirs-only "$REMOTE" | sort | tail -1)"
[ -n "$NEWEST" ] || { echo "ERROR: no runs at ${REMOTE}" >&2; exit 1; }
echo "[drill] run = ${NEWEST}"
rclone --config "$RCLONE_CONF" copy "${REMOTE}/${NEWEST}" "$WORK" --include "*.dump" --stats-one-line
DUMP="$(ls "$WORK"/*.dump | head -1)"
echo "[drill] dump = $(ls -lh "$DUMP")"

echo "[drill] boot throwaway postgres (${PG_IMAGE})"
docker run -d --name "$CONTAINER" -e POSTGRESQL_PASSWORD=drill -e POSTGRES_PASSWORD=drill \
  "$PG_IMAGE" >/dev/null
# Wait for readiness.
for _ in $(seq 1 60); do
  docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done

echo "[drill] create scratch db + restore"
docker exec "$CONTAINER" createdb -U postgres "$SCRATCH_DB"
docker cp "$DUMP" "$CONTAINER:/tmp/restore.dump"
docker exec "$CONTAINER" pg_restore -U postgres -d "$SCRATCH_DB" \
  --no-owner --no-privileges -j2 /tmp/restore.dump || {
  echo "[drill] ERROR: pg_restore failed" >&2; exit 1; }

echo "[drill] row-count assertions (require: ${REQUIRE})"
TOTAL=0
IFS=',' read -r -a TABLES <<< "$REQUIRE"
for t in "${TABLES[@]}"; do
  N="$(docker exec "$CONTAINER" psql -U postgres -d "$SCRATCH_DB" -tAc "SELECT count(*) FROM ${t}")" || {
    echo "[drill] ERROR: table ${t} missing after restore" >&2; exit 1; }
  echo "[drill]   ${t} = ${N} rows"
  TOTAL=$((TOTAL + N))
done
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  echo "[drill] ERROR: only ${TOTAL} rows across required tables (< ${MIN_ROWS}) — empty/structure-only" >&2
  exit 1
fi
echo "[drill] PASS — dump restores into a working database (${TOTAL} rows verified). Safe to activate."
