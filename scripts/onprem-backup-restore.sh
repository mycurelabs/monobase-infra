#!/usr/bin/env bash
# Operator helper for restoring from the on-prem Velero mirror.
#
# Subcommands:
#   list                        List Kopia repos + recent snapshots in the mirror.
#   extract --pvc=NAME [...]    Restore one PVC snapshot to a local directory.
#   boot-postgres --data=DIR    Boot postgres:16 against an extracted data dir.
#   cleanup                     Tear down lingering rclone/kopia state + temp dirs.
#
# Why this is more involved than plain `kopia restore`:
# Velero's data-mover writes Kopia repos via the S3 backend (flat blob layout).
# `kopia connect filesystem` rejects that layout (kopia/kopia#2065), so we
# round-trip the local mirror through an ephemeral `rclone serve s3` instance
# bound to 127.0.0.1 and connect kopia via its S3 backend. The rclone server
# lives only for the duration of a single subcommand invocation.
#
# See docs/operations/RESTORE_FROM_ONPREM.md for full context (Path B).

set -euo pipefail

# ----- defaults -----
BACKUP_DIR=/var/backups/mycure
CONFIG_DIR=/etc/mycure-backup
REPO=mycure-production
PVC=data-postgresql-primary-0
SNAPSHOT=latest
TARGET=/tmp/pg-restore
RCLONE_BIN=/usr/local/bin/rclone
KOPIA_BIN=/usr/local/bin/kopia
KOPIA_HOME=/var/lib/mycure-backup
POSTGRES_IMAGE=postgres:16
CONTAINER_NAME=pg-restore
PG_UID=999
DATA_SUBDIR=data            # kopia restores the parent PVC mount; data lives one level down

# Used internally by the trap cleanup
RCLONE_PID=""
PORT=""

# ----- helpers -----
log()  { printf '\033[1;34m[restore]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[restore]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[restore]\033[0m %s\n' "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || err "must run as root (use sudo)"; }

usage() {
  cat <<EOF
Usage: sudo $0 SUBCOMMAND [flags]

Subcommands:
  list                          List repos + recent snapshots in the mirror.
  extract                       Restore one PVC snapshot to a local directory.
  boot-postgres                 Boot postgres:16 against an extracted data dir.
  cleanup                       Tear down rclone/kopia state + temp dirs.

Flags (common):
  --backup-dir=PATH             Mirror root (default: $BACKUP_DIR)
  --repo=NAME                   Velero/Kopia repo name (default: $REPO)
  -h, --help                    This help.

Flags (extract):
  --pvc=NAME                    PVC name in the Velero repo (default: $PVC)
                                e.g. data-postgresql-primary-0, datadir-mongodb-0
  --snapshot=ID|latest          Snapshot id, or "latest" (default: latest)
  --target=PATH                 Where to restore (default: $TARGET)

Flags (boot-postgres):
  --data=PATH                   Postgres data dir to boot against
                                (default: <target>/$DATA_SUBDIR)
  --image=REF                   Postgres image (default: $POSTGRES_IMAGE)
  --container-name=NAME         Container name (default: $CONTAINER_NAME)

Examples:
  sudo $0 list
  sudo $0 extract --pvc=data-postgresql-primary-0
  sudo $0 boot-postgres
  sudo $0 cleanup
EOF
}

# ----- ephemeral S3 server + kopia connection -----
# Stand up rclone serve s3 on a random localhost port with random creds.
# Connect kopia to it via the S3 backend, scoped to the chosen Velero repo.
# Cleaned up by the EXIT trap.
start_kopia() {
  [[ -d "$BACKUP_DIR/spaces" ]] || err "mirror not found at $BACKUP_DIR/spaces"
  [[ -r "$CONFIG_DIR/kopia.password" ]] || err "missing $CONFIG_DIR/kopia.password"
  command -v "$RCLONE_BIN" >/dev/null || err "$RCLONE_BIN not installed (run onprem-backup-setup.sh first)"
  command -v "$KOPIA_BIN" >/dev/null || err "$KOPIA_BIN not installed"

  PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")
  local access_key secret_key password
  access_key=$(openssl rand -hex 8)
  secret_key=$(openssl rand -hex 16)
  password=$(<"$CONFIG_DIR/kopia.password")

  log "starting ephemeral rclone S3 server on 127.0.0.1:$PORT"
  "$RCLONE_BIN" serve s3 "$BACKUP_DIR/spaces" \
    --addr "127.0.0.1:$PORT" \
    --auth-key "$access_key,$secret_key" \
    --vfs-cache-mode off \
    --no-checksum \
    >/tmp/onprem-restore-rclone.log 2>&1 &
  RCLONE_PID=$!

  # Wait for bind
  local i
  for i in $(seq 1 30); do
    curl -s --max-time 1 "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break
    sleep 0.5
  done

  # Kopia needs HOME + XDG dirs (it stores connection state and a cache).
  mkdir -p "$KOPIA_HOME" "$KOPIA_HOME/cache" "$KOPIA_HOME/config"
  chmod 0700 "$KOPIA_HOME"
  export HOME="$KOPIA_HOME"
  export XDG_CACHE_HOME="$KOPIA_HOME/cache"
  export XDG_CONFIG_HOME="$KOPIA_HOME/config"
  export KOPIA_CHECK_FOR_UPDATES=false

  "$KOPIA_BIN" repository disconnect >/dev/null 2>&1 || true
  log "connecting kopia to s3://infrastructure/kopia/$REPO/"
  "$KOPIA_BIN" repository connect s3 \
    --endpoint="127.0.0.1:$PORT" \
    --disable-tls \
    --bucket=infrastructure \
    --prefix="kopia/$REPO/" \
    --access-key="$access_key" \
    --secret-access-key="$secret_key" \
    --password="$password" >/dev/null
}

stop_kopia() {
  if [[ -n "${HOME:-}" ]] && [[ -d "${HOME}/.config/kopia" || -d "$KOPIA_HOME/config/kopia" ]]; then
    "$KOPIA_BIN" repository disconnect >/dev/null 2>&1 || true
  fi
  if [[ -n "${RCLONE_PID:-}" ]]; then
    kill "$RCLONE_PID" 2>/dev/null || true
    wait "$RCLONE_PID" 2>/dev/null || true
  fi
}

# ----- list -----
cmd_list() {
  start_kopia
  log "available snapshots for repo '$REPO':"
  echo
  "$KOPIA_BIN" snapshot list --all --max-results=200
}

# ----- extract -----
resolve_snapshot_id() {
  local pvc_suffix="/$PVC"
  # awk: under the source header ending with our PVC name, capture the
  # snapshot id (4th field after the date+time+tz) from each indented
  # snapshot line; reset state on blank line or any non-indented line.
  "$KOPIA_BIN" snapshot list --all --max-results=200 2>/dev/null | \
    awk -v pvc="$pvc_suffix" '
      BEGIN              {flag=0; id=""}
      /^$/               {flag=0; next}
      $0 ~ (pvc "$")     {flag=1; next}
      /^[^ ]/            {flag=0}
      flag && /^[[:space:]]+[0-9]{4}-/  {id=$4}
      END                {print id}'
}

cmd_extract() {
  start_kopia

  if [[ "$SNAPSHOT" == "latest" ]]; then
    SNAPSHOT=$(resolve_snapshot_id)
    [[ -n "$SNAPSHOT" ]] || err "could not find a snapshot for pvc=$PVC under repo=$REPO"
    log "resolved latest snapshot: $SNAPSHOT"
  fi

  if [[ -e "$TARGET" ]] && [[ -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
    err "target $TARGET is not empty; pass --target to a fresh dir or remove first"
  fi
  mkdir -p "$TARGET"

  log "restoring snapshot $SNAPSHOT -> $TARGET (this can take several minutes)"
  time "$KOPIA_BIN" snapshot restore "$SNAPSHOT" "$TARGET" 2>&1 | tail -3

  log "restore complete; data is at $TARGET/$DATA_SUBDIR (the PVC's mountpoint was captured one level up)"
  echo
  log "next: sudo $0 boot-postgres --data=$TARGET/$DATA_SUBDIR"
}

# ----- boot-postgres -----
cmd_boot_postgres() {
  local data="${DATA_OVERRIDE:-$TARGET/$DATA_SUBDIR}"
  [[ -f "$data/PG_VERSION" ]] || err "$data does not look like a Postgres data dir (no PG_VERSION)"

  command -v docker >/dev/null || err "docker is not installed"

  # Drop minimal configs that stock postgres expects in the data dir
  # (Bitnami keeps them outside the PVC).
  log "writing minimal postgresql.conf + pg_hba.conf into $data"
  cat > "$data/postgresql.conf" <<'CONF'
listen_addresses = '*'
port = 5432
shared_buffers = 256MB
max_wal_size = 1GB
log_timezone = 'UTC'
timezone = 'UTC'
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'
default_text_search_config = 'pg_catalog.english'
CONF
  cat > "$data/pg_hba.conf" <<'CONF'
# Throwaway restore-drill container — trust local connections only.
local all all                trust
host  all all 127.0.0.1/32   trust
host  all all 0.0.0.0/0      trust
CONF

  chown -R "$PG_UID:$PG_UID" "$data"
  rm -f "$data/postmaster.pid"

  log "booting $POSTGRES_IMAGE as container '$CONTAINER_NAME'"
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker run -d --name "$CONTAINER_NAME" \
    -v "$data":/var/lib/postgresql/data \
    -e POSTGRES_PASSWORD=dummyforinitdb \
    "$POSTGRES_IMAGE" >/dev/null

  log "waiting for postgres to be ready (WAL replay)…"
  local i
  for i in $(seq 1 60); do
    docker exec "$CONTAINER_NAME" pg_isready -U postgres 2>/dev/null && break
    sleep 3
  done

  log "ready. quick sanity:"
  docker exec "$CONTAINER_NAME" psql -U postgres -c "
    SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
    FROM pg_database WHERE datistemplate = false
    ORDER BY pg_database_size(datname) DESC;" 2>/dev/null
  echo
  log "container '$CONTAINER_NAME' left running so you can connect:"
  echo "  docker exec -it $CONTAINER_NAME psql -U postgres -d hapihub"
  echo "  docker exec    $CONTAINER_NAME pg_dump -U postgres -Fc -d hapihub > /tmp/hapihub.pgc"
  echo
  log "tear down with: sudo $0 cleanup"
}

# ----- cleanup -----
cmd_cleanup() {
  log "removing container '$CONTAINER_NAME' (if any)"
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

  log "killing any lingering rclone serve s3 from earlier runs"
  pkill -f "rclone serve s3" 2>/dev/null || true

  log "disconnecting kopia (if connected)"
  HOME="$KOPIA_HOME" XDG_CONFIG_HOME="$KOPIA_HOME/config" XDG_CACHE_HOME="$KOPIA_HOME/cache" \
    "$KOPIA_BIN" repository disconnect >/dev/null 2>&1 || true

  log "removing temp restore tree at $TARGET (if any)"
  rm -rf "$TARGET"

  log "removing scratch logs"
  rm -f /tmp/onprem-restore-rclone.log

  log "cleanup done"
}

# ----- arg parsing -----
[[ $# -gt 0 ]] || { usage; exit 1; }

SUBCMD="$1"; shift
DATA_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir=*)     BACKUP_DIR="${1#*=}";       shift;;
    --repo=*)           REPO="${1#*=}";             shift;;
    --pvc=*)            PVC="${1#*=}";              shift;;
    --snapshot=*)       SNAPSHOT="${1#*=}";         shift;;
    --target=*)         TARGET="${1#*=}";           shift;;
    --data=*)           DATA_OVERRIDE="${1#*=}";    shift;;
    --image=*)          POSTGRES_IMAGE="${1#*=}";   shift;;
    --container-name=*) CONTAINER_NAME="${1#*=}";   shift;;
    -h|--help)          usage; exit 0;;
    *) err "unknown flag: $1 (see --help)";;
  esac
done

need_root
trap stop_kopia EXIT

case "$SUBCMD" in
  list)          cmd_list ;;
  extract)       cmd_extract ;;
  boot-postgres) cmd_boot_postgres ;;
  cleanup)       cmd_cleanup ;;
  -h|--help)     usage ;;
  *)             err "unknown subcommand: $SUBCMD (see --help)" ;;
esac
