#!/usr/bin/env bash
# Generic host->host read-only backup-mirror tier.
#
# Replicates one host's backup directory onto another host over SSH, read-only,
# WITHOUT giving the replica any of the source's backend credentials (DO Spaces
# key, Kopia password, ...). The replica pulls the already-encrypted blob files;
# it never decrypts and holds no secrets. This is the peer-host tier layered on
# top of the DO-Spaces->on-prem mirror (see docs/operations/ONPREM_BACKUP_SETUP.md).
#
# Topology is emergent, nothing is hardcoded:
#   - Chain:   Spaces -> niflheim -> vanaheim -> next box (run --role=source on
#              each intermediate host, pointing --allowed-path at its target dir).
#   - Fan-out: one source authorizes N replicas (N --role=source runs, distinct
#              --replica-name / --replica-ip) for redundancy.
#
# Two roles:
#   --role=source    Run on the host that HOLDS backup data. Authorizes a replica
#                    to read ONE directory, read-only, via an rrsync-jailed,
#                    IP-locked SSH forced command. Installs no timers.
#   --role=replica   Run on the host that PULLS a copy. Generates a dedicated
#                    keypair, installs an rsync pull service+timer, a weekly
#                    checksum verify, a bounded journal namespace, and a Discord
#                    notifier (same scaffolding as onprem-backup-setup.sh).
#
# Security model:
#   - Key is `rrsync -ro` (read-only) + path-jailed + from=<ip> locked. A stolen
#     replica key can only READ the encrypted backup — no shell, no write-back
#     (ransomware on a replica cannot corrupt the source), no other paths.
#   - Blobs are encrypted at rest; a replica without the password leaks nothing.
#   - Pull-only: the source needs zero access to the replica.
#   - Intended to run over Tailscale (lock --replica-ip to the tailnet IP).
#
# Idempotent. Re-running reconciles.
#
# See docs/operations/BACKUP_MIRROR_TIERS.md for the full runbook.

set -euo pipefail

# ---------- shared defaults ----------
ROLE=""
CONFIG_DIR=/etc/backup-mirror
SYSTEMD_DIR=/etc/systemd/system
RSYNC_BIN=/usr/bin/rsync

# ---------- source-role defaults ----------
ALLOWED_PATH=/mnt/storage/mycure          # dir this host exposes read-only
REPLICA_NAME=""                            # label for the authorized_keys line
REPLICA_PUBKEY=""                          # inline "ssh-ed25519 AAAA... [comment]"
REPLICA_PUBKEY_FILE=""                     # or a file to read it from
REPLICA_IP=""                              # from= lock (replica's tailnet IP)
REPLICA_USER=backup-replica                # SSH principal on this host
RRSYNC_BIN=/usr/bin/rrsync

# ---------- replica-role defaults ----------
SOURCE_HOST=""                             # source host/IP (system-resolvable!)
SOURCE_PATH=spaces                         # path RELATIVE to the source rrsync jail
SOURCE_USER=backup-replica
TARGET_DIR=""                              # where the copy lands on this host
NAME=""                                    # instance label (units/journal/env)
TIMER_ON_CALENDAR="*-*-* 05,17:00:00 Asia/Manila"
VERIFY_TIMER_ON_CALENDAR="Sun *-*-* 06:00:00 Asia/Manila"
SSH_KEY=""                                 # default: $CONFIG_DIR/<name>.key
MIRROR_USER=backup-mirror                  # system user that runs the pull
NOTIFY_ON=both                             # both | failure-only | success-only | off
WEBHOOK_FILE=""                            # default: $CONFIG_DIR/discord-webhook.url
JOURNAL_MAX_USE=200M
JOURNAL_KEEP_FREE=2G
JOURNAL_MAX_RETENTION=4week
NOTIFY_BIN=/usr/local/sbin/backup-mirror-notify
RUN_BIN=/usr/local/sbin/backup-mirror-run
VERIFY_BIN=/usr/local/sbin/backup-mirror-verify

# ---------- helpers ----------
log()  { printf '\033[1;34m[backup-mirror]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[backup-mirror]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[backup-mirror]\033[0m %s\n' "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || err "must run as root (use sudo)"; }

usage() {
  cat <<EOF
Usage:
  Source host (holds backup data):
    sudo $0 --role=source --replica-name=NAME --replica-ip=IP \\
      --replica-pubkey="ssh-ed25519 AAAA..."   [--allowed-path=DIR]

  Replica host (pulls a copy):
    sudo [DISCORD_WEBHOOK_URL=...] $0 --role=replica --name=NAME \\
      --source-host=HOST --target-dir=DIR \\
      [--source-path=spaces] [--timer-on-calendar="*-*-* 05,17:00:00 Asia/Manila"]

Common:
  --role=source|replica       (required)
  -h, --help

Source flags:
  --allowed-path=DIR          dir exposed read-only         (default: $ALLOWED_PATH)
  --replica-name=NAME         label for the authorized_keys line (required)
  --replica-ip=IP             from= lock, replica tailnet IP     (required)
  --replica-pubkey=STR        replica public key (inline)
  --replica-pubkey-file=PATH  ...or read it from a file
  --replica-user=USER         SSH principal on this host    (default: $REPLICA_USER)

Replica flags:
  --name=NAME                 instance label                (required)
  --source-host=HOST          source host/IP, system-resolvable (required)
  --source-path=PATH          path under the source jail    (default: $SOURCE_PATH)
  --source-user=USER          SSH user on the source        (default: $SOURCE_USER)
  --target-dir=DIR            where the copy lands          (required)
  --timer-on-calendar=S       pull OnCalendar=              (default: "$TIMER_ON_CALENDAR")
  --verify-on-calendar=S      verify OnCalendar=            (default: "$VERIFY_TIMER_ON_CALENDAR")
  --ssh-key=PATH              private key path              (default: $CONFIG_DIR/<name>.key)
  --notify-on=MODE            both|failure-only|success-only|off (default: $NOTIFY_ON)
  DISCORD_WEBHOOK_URL (env)   optional Discord webhook for notifications
EOF
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role=*)               ROLE="${1#*=}";               shift;;
    --allowed-path=*)       ALLOWED_PATH="${1#*=}";       shift;;
    --replica-name=*)       REPLICA_NAME="${1#*=}";       shift;;
    --replica-pubkey=*)     REPLICA_PUBKEY="${1#*=}";     shift;;
    --replica-pubkey-file=*) REPLICA_PUBKEY_FILE="${1#*=}"; shift;;
    --replica-ip=*)         REPLICA_IP="${1#*=}";         shift;;
    --replica-user=*)       REPLICA_USER="${1#*=}";       shift;;
    --name=*)               NAME="${1#*=}";               shift;;
    --source-host=*)        SOURCE_HOST="${1#*=}";        shift;;
    --source-path=*)        SOURCE_PATH="${1#*=}";        shift;;
    --source-user=*)        SOURCE_USER="${1#*=}";        shift;;
    --target-dir=*)         TARGET_DIR="${1#*=}";         shift;;
    --timer-on-calendar=*)  TIMER_ON_CALENDAR="${1#*=}";  shift;;
    --verify-on-calendar=*) VERIFY_TIMER_ON_CALENDAR="${1#*=}"; shift;;
    --ssh-key=*)            SSH_KEY="${1#*=}";            shift;;
    --notify-on=*)          NOTIFY_ON="${1#*=}";          shift;;
    -h|--help)              usage; exit 0;;
    *) err "unknown flag: $1 (see --help)";;
  esac
done

need_root
case "$ROLE" in
  source|replica) ;;
  *) err "--role must be source or replica (see --help)";;
esac

# =====================================================================
# SOURCE ROLE
# =====================================================================
if [[ "$ROLE" == "source" ]]; then
  [[ -n "$REPLICA_NAME" ]] || err "--replica-name is required"
  [[ -n "$REPLICA_IP" ]]   || err "--replica-ip is required (from= lock)"
  [[ -d "$ALLOWED_PATH" ]] || err "--allowed-path $ALLOWED_PATH does not exist"
  command -v "$RRSYNC_BIN" >/dev/null || err "$RRSYNC_BIN not found (install rsync)"
  # Both are interpolated into the authorized_keys line — validate so a stray
  # value (e.g. --replica-ip='*') cannot silently defeat the from= lock.
  [[ "$REPLICA_NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || err "--replica-name must be [a-zA-Z0-9._-]"
  [[ "$REPLICA_IP" =~ ^[0-9a-fA-F:.]+$ ]]    || err "--replica-ip must be a bare IPv4/IPv6 address (no globs/CIDR/spaces)"

  # Resolve the pubkey (inline or file) and normalise to "type keydata".
  if [[ -n "$REPLICA_PUBKEY_FILE" ]]; then
    [[ -r "$REPLICA_PUBKEY_FILE" ]] || err "cannot read $REPLICA_PUBKEY_FILE"
    REPLICA_PUBKEY="$(<"$REPLICA_PUBKEY_FILE")"
  fi
  [[ -n "$REPLICA_PUBKEY" ]] || err "provide --replica-pubkey or --replica-pubkey-file"
  key_type="$(awk '{print $1}' <<<"$REPLICA_PUBKEY")"
  key_data="$(awk '{print $2}' <<<"$REPLICA_PUBKEY")"
  [[ "$key_type" == ssh-* && -n "$key_data" ]] || err "malformed public key"

  # Service user with a REAL shell — sshd runs the forced command via the login
  # shell, so nologin would break rrsync. command="" + restrict still prevent
  # any interactive use.
  if ! id -u "$REPLICA_USER" >/dev/null 2>&1; then
    log "creating SSH principal $REPLICA_USER"
    useradd --system --create-home --home-dir "/var/lib/$REPLICA_USER" \
            --shell /bin/bash --user-group "$REPLICA_USER"
  fi
  home="$(getent passwd "$REPLICA_USER" | cut -d: -f6)"
  [[ -n "$home" ]] || err "could not resolve home for $REPLICA_USER"

  # Grant read access to the exposed dir via its owning group. Refuse a
  # privileged (system-core, gid<100) group — genericity means --allowed-path
  # could be root-owned, and `usermod -aG root` is not what "read one dir" means.
  path_group="$(stat -c '%G' "$ALLOWED_PATH")"
  path_gid="$(getent group "$path_group" | cut -d: -f3)"
  [[ -n "$path_gid" && "$path_gid" -ge 100 ]] \
    || err "refusing to add $REPLICA_USER to privileged group $path_group (gid ${path_gid:-?}); expose a non-system-owned dir instead"
  if ! id -nG "$REPLICA_USER" | tr ' ' '\n' | grep -qx "$path_group"; then
    log "adding $REPLICA_USER to group $path_group (read $ALLOWED_PATH)"
    usermod -aG "$path_group" "$REPLICA_USER"
  fi

  install -d -m 0700 -o "$REPLICA_USER" -g "$REPLICA_USER" "$home/.ssh"
  ak="$home/.ssh/authorized_keys"
  touch "$ak"; chown "$REPLICA_USER:$REPLICA_USER" "$ak"; chmod 0600 "$ak"

  # One line per replica, keyed by the trailing marker comment. Rewrite that
  # line on re-run (idempotent); other replicas' lines are untouched (fan-out).
  marker="mirror-replica:$REPLICA_NAME"
  line="from=\"$REPLICA_IP\",restrict,command=\"$RRSYNC_BIN -ro $ALLOWED_PATH\" $key_type $key_data $marker"
  tmp="$(mktemp)"
  # Anchor to end-of-line: a substring match would let re-running for "vanaheim"
  # drop "vanaheim-2"'s line and silently revoke it (breaks fan-out).
  grep -vE " ${marker}$" "$ak" > "$tmp" 2>/dev/null || true
  printf '%s\n' "$line" >> "$tmp"
  install -m 0600 -o "$REPLICA_USER" -g "$REPLICA_USER" "$tmp" "$ak"
  rm -f "$tmp"

  echo
  log "source configured — summary:"
  echo "  replica name  : $REPLICA_NAME"
  echo "  replica ip    : $REPLICA_IP  (from= lock)"
  echo "  ssh principal : $REPLICA_USER"
  echo "  exposed (ro)  : $ALLOWED_PATH"
  echo "  authorized_keys entries:"
  grep -c '^from=' "$ak" | sed 's/^/    replicas authorized: /'
  echo
  echo "Verify the jail is read-only (run from the replica):"
  echo "  ssh -i <key> $REPLICA_USER@$(hostname -f 2>/dev/null || hostname)   # must NOT give a shell"
  exit 0
fi

# =====================================================================
# REPLICA ROLE
# =====================================================================
[[ -n "$NAME" ]]        || err "--name is required"
[[ -n "$SOURCE_HOST" ]] || err "--source-host is required"
[[ -n "$TARGET_DIR" ]]  || err "--target-dir is required"
[[ "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || err "--name must be [a-zA-Z0-9._-]"
case "$NOTIFY_ON" in both|failure-only|success-only|off) ;; *) err "bad --notify-on";; esac

command -v "$RSYNC_BIN" >/dev/null || err "$RSYNC_BIN not found (install rsync)"
command -v ssh-keygen  >/dev/null || err "ssh-keygen not found (install openssh-client)"

[[ -n "$SSH_KEY" ]]     || SSH_KEY="$CONFIG_DIR/$NAME.key"
[[ -n "$WEBHOOK_FILE" ]] || WEBHOOK_FILE="$CONFIG_DIR/discord-webhook.url"
KNOWN_HOSTS="$CONFIG_DIR/known_hosts"
SERVICE_NAME="backup-mirror-$NAME"
VERIFY_SERVICE_NAME="backup-mirror-verify-$NAME"
LOG_NAMESPACE="backup-mirror-$NAME"
JOURNALD_NAMESPACE_CONFIG="/etc/systemd/journald@${LOG_NAMESPACE}.conf"
ENV_FILE="$CONFIG_DIR/$NAME.env"

# ---------- service user ----------
if ! id -u "$MIRROR_USER" >/dev/null 2>&1; then
  log "creating system user $MIRROR_USER"
  useradd --system --no-create-home --home-dir "/var/lib/$MIRROR_USER" \
          --shell /usr/sbin/nologin --user-group "$MIRROR_USER"
fi

# ---------- config + target dirs ----------
install -d -m 0750 -o root -g "$MIRROR_USER" "$CONFIG_DIR"
install -d -m 0750 -o "$MIRROR_USER" -g "$MIRROR_USER" "$TARGET_DIR"

# ---------- dedicated keypair ----------
if [[ ! -f "$SSH_KEY" ]]; then
  log "generating dedicated ed25519 key at $SSH_KEY"
  ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" \
    -C "backup-mirror:$NAME@$(hostname -s 2>/dev/null || hostname)" >/dev/null
fi
chown "$MIRROR_USER:$MIRROR_USER" "$SSH_KEY" "$SSH_KEY.pub"
chmod 0600 "$SSH_KEY"; chmod 0644 "$SSH_KEY.pub"
touch "$KNOWN_HOSTS"; chown "$MIRROR_USER:$MIRROR_USER" "$KNOWN_HOSTS"; chmod 0644 "$KNOWN_HOSTS"

# ---------- discord webhook (optional, same semantics as onprem script) ----------
if [[ -v DISCORD_WEBHOOK_URL ]]; then
  if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    rm -f "$WEBHOOK_FILE"; log "cleared $WEBHOOK_FILE"
  else
    umask 077; printf '%s' "$DISCORD_WEBHOOK_URL" > "$WEBHOOK_FILE"; umask 022
    chgrp "$MIRROR_USER" "$WEBHOOK_FILE"; chmod 0640 "$WEBHOOK_FILE"
    log "stored Discord webhook at $WEBHOOK_FILE"
  fi
  unset DISCORD_WEBHOOK_URL
fi

# ---------- per-instance env ----------
umask 077
cat > "$ENV_FILE" <<ENV
# backup-mirror instance: $NAME  (managed by backup-mirror-setup.sh)
NAME=$NAME
SOURCE_USER=$SOURCE_USER
SOURCE_HOST=$SOURCE_HOST
SOURCE_PATH=$SOURCE_PATH
TARGET_DIR=$TARGET_DIR
SSH_KEY=$SSH_KEY
KNOWN_HOSTS=$KNOWN_HOSTS
WEBHOOK_FILE=$WEBHOOK_FILE
ENV
umask 022
chgrp "$MIRROR_USER" "$ENV_FILE"; chmod 0640 "$ENV_FILE"

# ---------- shared helper: notifier ----------
log "installing notifier at $NOTIFY_BIN"
install -m 0755 /dev/stdin "$NOTIFY_BIN" <<'NOTIFY'
#!/usr/bin/env bash
# Discord notification for a backup-mirror instance.
# Usage: backup-mirror-notify KIND NAME [extra]
#   KIND in start|success|failure|verify-start|verify-success|verify-failure|test
set -euo pipefail
kind="${1:-}"; name="${2:-}"; extra="${3:-}"
env_file="/etc/backup-mirror/${name}.env"
[[ -r "$env_file" ]] && . "$env_file"
WEBHOOK_FILE="${WEBHOOK_FILE:-/etc/backup-mirror/discord-webhook.url}"
[[ -r "$WEBHOOK_FILE" ]] || exit 0
url=$(<"$WEBHOOK_FILE"); [[ -n "$url" ]] || exit 0

case "$kind" in
  start)          title=":hourglass_flowing_sand: backup-mirror[$name] started";  color=3447003;  dur=0; sz=0; svc="backup-mirror-$name" ;;
  success)        title=":white_check_mark: backup-mirror[$name] succeeded";       color=3066993;  dur=1; sz=1; svc="backup-mirror-$name" ;;
  failure)        title=":x: backup-mirror[$name] FAILED";                         color=15158332; dur=1; sz=1; svc="backup-mirror-$name" ;;
  verify-start)   title=":mag: backup-mirror[$name] verify started";              color=3447003;  dur=0; sz=0; svc="backup-mirror-verify-$name" ;;
  verify-success) title=":white_check_mark: backup-mirror[$name] verify passed";  color=3066993;  dur=1; sz=0; svc="backup-mirror-verify-$name" ;;
  verify-failure) title=":rotating_light: backup-mirror[$name] verify FAILED";    color=15158332; dur=1; sz=0; svc="backup-mirror-verify-$name" ;;
  test)           title=":bell: backup-mirror[$name] test";                        color=10181046; dur=0; sz=0; svc="backup-mirror-$name" ;;
  *)              title="backup-mirror[$name]: ${kind:-unknown}";                   color=8421504;  dur=1; sz=1; svc="backup-mirror-$name" ;;
esac

host=$(hostname -f 2>/dev/null || hostname)
ts=$(date -u -Iseconds 2>/dev/null || date -u +%FT%TZ)
elapsed="unknown"; mirrored="see log"
if [[ "$dur" == 1 ]] && command -v systemctl >/dev/null; then
  s=$(systemctl show "$svc.service" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  e=$(systemctl show "$svc.service" -p InactiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  if [[ "$e" -gt "$s" && "$s" -gt 0 ]]; then
    elapsed=$(awk -v u=$((e-s)) 'BEGIN{x=u/1000000; printf (x>=3600)?"%dh%dm":(x>=60)?"%dm%ds":"%ds",(x>=3600)?int(x/3600):(x>=60)?int(x/60):int(x),(x>=3600)?int((x%3600)/60):(x>=60)?int(x%60):0}')
  fi
fi
if [[ "$sz" == 1 && -n "${TARGET_DIR:-}" && -d "${TARGET_DIR:-/nonexistent}" ]]; then
  mirrored=$(du -sh "$TARGET_DIR" 2>/dev/null | awk '{print $1}'); [[ -n "$mirrored" ]] || mirrored="see log"
fi

if command -v jq >/dev/null; then
  payload=$(jq -nc --arg t "$title" --argjson c "$color" --arg h "$host" --arg ts "$ts" \
    --arg el "$elapsed" --arg mi "$mirrored" --arg ex "$extra" --argjson d "$dur" --argjson s "$sz" \
    '{username:"backup-mirror",embeds:[{title:$t,color:$c,timestamp:$ts,fields:(
       [{name:"Host",value:$h,inline:true}]
       + (if $d==1 then [{name:"Duration",value:$el,inline:true}] else [] end)
       + (if $s==1 then [{name:"Mirrored",value:$mi,inline:true}] else [] end)
       + (if $ex=="" then [] else [{name:"Note",value:$ex,inline:false}] end))}]}')
else
  esc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  f="{\"name\":\"Host\",\"value\":\"$(esc "$host")\",\"inline\":true}"
  [[ "$dur" == 1 ]] && f+=",{\"name\":\"Duration\",\"value\":\"$(esc "$elapsed")\",\"inline\":true}"
  [[ "$sz" == 1 ]] && f+=",{\"name\":\"Mirrored\",\"value\":\"$(esc "$mirrored")\",\"inline\":true}"
  [[ -n "$extra" ]] && f+=",{\"name\":\"Note\",\"value\":\"$(esc "$extra")\",\"inline\":false}"
  payload="{\"username\":\"backup-mirror\",\"embeds\":[{\"title\":\"$(esc "$title")\",\"color\":$color,\"timestamp\":\"$ts\",\"fields\":[$f]}]}"
fi
curl -sS -m 15 -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null || true
NOTIFY

# ---------- shared helper: pull runner ----------
log "installing pull runner at $RUN_BIN"
install -m 0755 /dev/stdin "$RUN_BIN" <<'RUN'
#!/usr/bin/env bash
# Pull one backup-mirror instance. Usage: backup-mirror-run NAME
set -euo pipefail
name="${1:?usage: backup-mirror-run NAME}"
. "/etc/backup-mirror/${name}.env"
# --max-delete is a tripwire: if the source is empty/truncated (e.g. its own
# mount dropped and it rebuilt an empty tree), --delete would wipe this replica's
# good copy silently. Any bound turns that into a loud failure. Legit deletions
# are source-side Kopia TTL expiry — steady and modest, well under this ceiling.
# ponytail: fixed 10000-file bound; raise if a normal expiry ever trips it.
exec /usr/bin/rsync -a --delete --max-delete=10000 --numeric-ids --partial \
  -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS" \
  "$SOURCE_USER@$SOURCE_HOST:$SOURCE_PATH/" "$TARGET_DIR/" \
  --stats
RUN

# ---------- shared helper: verifier ----------
log "installing verifier at $VERIFY_BIN"
install -m 0755 /dev/stdin "$VERIFY_BIN" <<'VERIFY'
#!/usr/bin/env bash
# Weekly integrity check for a backup-mirror instance: content-level (checksum)
# diff between the source and the local copy. Any real difference => corruption
# or desync => non-zero exit => OnFailure notify.
# Usage: backup-mirror-verify NAME
set -euo pipefail
name="${1:?usage: backup-mirror-verify NAME}"
. "/etc/backup-mirror/${name}.env"
[[ -d "$TARGET_DIR" ]] || { echo "missing $TARGET_DIR (no successful pull yet?)" >&2; exit 1; }

echo "==> pre-verify sync (close lag so remaining diffs are real)"
/usr/bin/rsync -a --delete --max-delete=10000 --numeric-ids --partial \
  -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS" \
  "$SOURCE_USER@$SOURCE_HOST:$SOURCE_PATH/" "$TARGET_DIR/" --stats || exit 1

echo "==> checksum diff (rsync -anc, itemized)"
report=$(mktemp); errfile=$(mktemp); trap 'rm -f "$report" "$errfile"' EXIT
# -n dry-run, -c checksum, -i itemize. With --delete, any line means the local
# copy differs from source. On a settled content-addressed store this is empty.
# Keep stderr OUT of $report: an SSH warning or connection failure must surface
# as a transport error, not be miscounted as "corruption" on the one alert whose
# whole job is to mean corruption. A non-zero rsync exit is a real failure.
if ! /usr/bin/rsync -anci --delete --numeric-ids \
  -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS" \
  "$SOURCE_USER@$SOURCE_HOST:$SOURCE_PATH/" "$TARGET_DIR/" > "$report" 2>"$errfile"; then
  echo "verify rsync failed (transport/IO error, NOT necessarily corruption):" >&2
  cat "$errfile" >&2
  exit 1
fi

# Ignore pure "." dir-time itemizations and blank lines; anything else is a real
# content/size/presence difference.
diffs=$(grep -vE '^\.d|^$|^sending|^total|^sent|^$' "$report" | grep -cvE '^\.[df]\.\.t' || true)
echo "==> $diffs content difference(s)"
if [[ "$diffs" -gt 0 ]]; then
  echo "first 20:" >&2; grep -vE '^\.d|^$' "$report" | head -20 >&2
  exit 1
fi
exit 0
VERIFY

# ---------- journald namespace ----------
log "configuring bounded journal namespace $LOG_NAMESPACE (<= $JOURNAL_MAX_USE)"
cat > "$JOURNALD_NAMESPACE_CONFIG" <<JOURNAL
[Journal]
Storage=persistent
SystemMaxUse=$JOURNAL_MAX_USE
SystemKeepFree=$JOURNAL_KEEP_FREE
SystemMaxFileSize=50M
MaxRetentionSec=$JOURNAL_MAX_RETENTION
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToWall=no
JOURNAL
chmod 0644 "$JOURNALD_NAMESPACE_CONFIG"
systemctl reload "systemd-journald@$LOG_NAMESPACE.service" 2>/dev/null || true

# ---------- notify wiring ----------
case "$NOTIFY_ON" in
  both)         m_start="ExecStartPre=-$NOTIFY_BIN start $NAME";  m_ok="ExecStartPost=$NOTIFY_BIN success $NAME"; m_fail="OnFailure=${SERVICE_NAME}-failure.service"
                v_start="ExecStartPre=-$NOTIFY_BIN verify-start $NAME"; v_ok="ExecStartPost=$NOTIFY_BIN verify-success $NAME"; v_fail="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  success-only) m_start="ExecStartPre=-$NOTIFY_BIN start $NAME";  m_ok="ExecStartPost=$NOTIFY_BIN success $NAME"; m_fail=""
                v_start="ExecStartPre=-$NOTIFY_BIN verify-start $NAME"; v_ok="ExecStartPost=$NOTIFY_BIN verify-success $NAME"; v_fail="" ;;
  failure-only) m_start="ExecStartPre=-$NOTIFY_BIN start $NAME";  m_ok=""; m_fail="OnFailure=${SERVICE_NAME}-failure.service"
                v_start="ExecStartPre=-$NOTIFY_BIN verify-start $NAME"; v_ok=""; v_fail="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  off)          m_start=""; m_ok=""; m_fail=""; v_start=""; v_ok=""; v_fail="" ;;
esac

# ---------- pull service + timer ----------
log "writing $SERVICE_NAME.service + .timer"
cat > "$SYSTEMD_DIR/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=Read-only backup mirror pull ($NAME) from $SOURCE_HOST
After=network-online.target
Wants=network-online.target
# Don't run if the target disk isn't mounted — otherwise rsync would recreate
# the tree on the root filesystem and fill it.
RequiresMountsFor=$TARGET_DIR
$m_fail

[Service]
Type=oneshot
User=$MIRROR_USER
Group=$MIRROR_USER
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$SERVICE_NAME
$m_start
ExecStart=$RUN_BIN $NAME
$m_ok
TimeoutStartSec=8h
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

[Install]
WantedBy=multi-user.target
UNIT

cat > "$SYSTEMD_DIR/${SERVICE_NAME}-failure.service" <<UNIT
[Unit]
Description=Notify on failure of $SERVICE_NAME.service
[Service]
Type=oneshot
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=${SERVICE_NAME}-failure
ExecStart=$NOTIFY_BIN failure $NAME
UNIT

cat > "$SYSTEMD_DIR/$SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Timer for backup-mirror pull ($NAME)
[Timer]
OnCalendar=$TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=10m
Unit=$SERVICE_NAME.service
[Install]
WantedBy=timers.target
UNIT

# ---------- verify service + timer ----------
log "writing $VERIFY_SERVICE_NAME.service + .timer"
cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.service" <<UNIT
[Unit]
Description=Integrity verify for backup-mirror ($NAME)
After=network-online.target
Wants=network-online.target
RequiresMountsFor=$TARGET_DIR
$v_fail

[Service]
Type=oneshot
User=$MIRROR_USER
Group=$MIRROR_USER
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$VERIFY_SERVICE_NAME
$v_start
ExecStart=$VERIFY_BIN $NAME
$v_ok
TimeoutStartSec=2h
Nice=15
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UNIT

cat > "$SYSTEMD_DIR/${VERIFY_SERVICE_NAME}-failure.service" <<UNIT
[Unit]
Description=Notify on failure of $VERIFY_SERVICE_NAME.service
[Service]
Type=oneshot
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=${VERIFY_SERVICE_NAME}-failure
ExecStart=$NOTIFY_BIN verify-failure $NAME
UNIT

cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Weekly timer for backup-mirror verify ($NAME)
[Timer]
OnCalendar=$VERIFY_TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=30m
Unit=$VERIFY_SERVICE_NAME.service
[Install]
WantedBy=timers.target
UNIT

# ---------- enable ----------
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.timer" >/dev/null
systemctl enable --now "$VERIFY_SERVICE_NAME.timer" >/dev/null

pubkey="$(cat "$SSH_KEY.pub")"
echo
log "replica configured — summary:"
echo "  instance      : $NAME"
echo "  source        : $SOURCE_USER@$SOURCE_HOST:$SOURCE_PATH"
echo "  target dir    : $TARGET_DIR"
echo "  ssh key       : $SSH_KEY"
echo "  pull timer    : $TIMER_ON_CALENDAR"
echo "  verify timer  : $VERIFY_TIMER_ON_CALENDAR"
if [[ -f "$WEBHOOK_FILE" ]]; then echo "  notifications : Discord ($NOTIFY_ON)"; else echo "  notifications : disabled"; fi
echo
echo ">>> Next: authorize this replica on the SOURCE host ($SOURCE_HOST):"
echo
echo "    sudo scripts/backup-mirror-setup.sh --role=source \\"
echo "      --replica-name=$(hostname -s 2>/dev/null || hostname) \\"
echo "      --replica-ip=<this host's tailnet IP> \\"
echo "      --replica-pubkey=\"$pubkey\""
echo
echo "Then trigger the first pull:  sudo systemctl start $SERVICE_NAME.service"
echo "Tail it: sudo journalctl --namespace=$LOG_NAMESPACE -u $SERVICE_NAME.service -f"

# Fire a test notification on first-time-with-webhook installs.
if [[ -f "$WEBHOOK_FILE" ]] && [[ "$NOTIFY_ON" != "off" ]]; then
  "$NOTIFY_BIN" test "$NAME" "setup completed on $(hostname -f 2>/dev/null || hostname)" || true
fi
