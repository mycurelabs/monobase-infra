#!/usr/bin/env bash
# Sets up an off-Google, ENCRYPTED on-prem mirror of a GCS bucket on a
# Debian/Ubuntu host — the "cloud→host" leg for the uploads bucket
# (gs://mc-v4-prod.appspot.com), Tier 2 of monobase-mycure#3878.
#
# Sibling of onprem-backup-setup.sh (the Spaces/Kopia mirror). Kept SEPARATE so
# the live, battle-tested Velero mirror is never touched. Reuses the same
# scaffolding shape: pinned rclone, a bounded journald namespace, a Discord
# notifier, a weekly integrity check, and systemd timers.
#
# WHY crypt (the one real difference from the Kopia mirror):
# the Velero mirror pulls blobs that are ALREADY Kopia-encrypted, so plaintext
# never rests on the host. Raw GCS objects are plaintext PHI, so we pull them
# THROUGH an rclone `crypt` remote — files (and filenames) land encrypted at
# rest. The crypt password lives ONLY on this host; a downstream host→host
# replica (backup-mirror-setup.sh, #400) receives ciphertext only and never the
# password — same "ciphertext-only replicas, secret supplied at restore" model
# as Kopia. Restore = `rclone` with the crypt password provided at restore time.
#
# Idempotent. Re-running with the same flags reconciles.
#
# Usage:
#   sudo GCS_SA_JSON=/path/ro-sa.json GCS_CRYPT_PASSWORD=… \
#     scripts/gcs-onprem-mirror.sh --bucket=mc-v4-prod.appspot.com [flags]
#
# See docs/operations/GCS_ONPREM_MIRROR.md for the full runbook.

set -euo pipefail

# ---------- defaults ----------
BUCKET=""                                        # GCS bucket (no gs:// prefix), REQUIRED
INCLUDE_PREFIX=""                                # optional: mirror only this object prefix (huge buckets)
BACKUP_DIR=/var/backups/mycure-gcs               # crypt vault root (holds ONLY ciphertext)
SERVICE_USER=mycure-backup                       # reuse the Velero mirror's user if present
TIMER_ON_CALENDAR="*-*-* 04:30,16:30 UTC"        # ~30m after the STS runs (Tier 1); twice daily
VERIFY_TIMER_ON_CALENDAR="Sun *-*-* 05:00:00 UTC"
RCLONE_VERSION=1.69.1
RCLONE_BIN=/usr/local/bin/rclone
RCLONE_TRANSFERS=4
RCLONE_CHECKERS=8
NOTIFY_ON=both                                   # both | failure-only | success-only | off
ROTATE_CRYPT=0                                   # 1 = intentionally re-key an existing vault

CONFIG_DIR=/etc/mycure-gcs
RCLONE_CONFIG=/etc/rclone/gcs.conf
SA_DEST=$CONFIG_DIR/ro-sa.json
SERVICE_NAME=mycure-gcs-mirror
VERIFY_SERVICE_NAME=mycure-gcs-verify
MIRROR_BIN=/usr/local/sbin/mycure-gcs-mirror
VERIFY_BIN=/usr/local/sbin/mycure-gcs-verify
NOTIFY_BIN=/usr/local/sbin/mycure-gcs-notify
SYSTEMD_DIR=/etc/systemd/system
WEBHOOK_FILE=$CONFIG_DIR/discord-webhook.url
LOG_NAMESPACE=mycure-gcs
JOURNALD_NAMESPACE_CONFIG=/etc/systemd/journald@${LOG_NAMESPACE}.conf
JOURNAL_MAX_USE=500M
JOURNAL_KEEP_FREE=2G
JOURNAL_MAX_RETENTION=4week

# ---------- helpers ----------
log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || err "must run as root (use sudo)"; }

usage() {
  cat <<EOF
Usage: sudo GCS_SA_JSON=/path/ro-sa.json GCS_CRYPT_PASSWORD=… $0 --bucket=NAME [flags]

Flags:
  --bucket=NAME           GCS bucket to mirror, no gs:// prefix    (REQUIRED)
  --include-prefix=PREFIX rclone include filter, e.g. "uploads/**" (default: whole bucket)
  --backup-dir=PATH       local crypt vault root (ciphertext only) (default: $BACKUP_DIR)
  --service-user=USER     system user that runs the mirror         (default: $SERVICE_USER)
  --timer-on-calendar=S   systemd OnCalendar= for the mirror       (default: "$TIMER_ON_CALENDAR")
  --verify-on-calendar=S  systemd OnCalendar= for the weekly check (default: "$VERIFY_TIMER_ON_CALENDAR")
  --notify-on=MODE        both | failure-only | success-only | off (default: $NOTIFY_ON)
  --rotate-crypt-password intentionally re-key an existing vault (re-downloads all)
  -h, --help              this help

Environment (required):
  GCS_SA_JSON             path to a READ-ONLY GCS service-account JSON key
                          (roles/storage.objectViewer on the bucket only)
  GCS_CRYPT_PASSWORD      rclone crypt password. Held ONLY on this host; escrow
                          it out-of-band (reuse the #3882 age/Shamir policy) —
                          it is the GCS-mirror analogue of the Kopia password.

Environment (optional):
  GCS_CRYPT_PASSWORD2     rclone crypt salt (password2). Recommended for extra
                          strength; if unset, rclone's default salt is used.
  DISCORD_WEBHOOK_URL     Discord webhook for notifications (same behavior as
                          onprem-backup-setup.sh; empty string clears it).
EOF
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket=*)             BUCKET="${1#*=}";              shift;;
    --include-prefix=*)     INCLUDE_PREFIX="${1#*=}";      shift;;
    --backup-dir=*)         BACKUP_DIR="${1#*=}";          shift;;
    --service-user=*)       SERVICE_USER="${1#*=}";        shift;;
    --timer-on-calendar=*)  TIMER_ON_CALENDAR="${1#*=}";   shift;;
    --verify-on-calendar=*) VERIFY_TIMER_ON_CALENDAR="${1#*=}"; shift;;
    --notify-on=*)          NOTIFY_ON="${1#*=}";           shift;;
    --rotate-crypt-password) ROTATE_CRYPT=1;               shift;;
    --discord-webhook-url=*) DISCORD_WEBHOOK_URL="${1#*=}";shift;;
    -h|--help)              usage; exit 0;;
    *) err "unknown flag: $1 (see --help)";;
  esac
done

case "$NOTIFY_ON" in
  both|failure-only|success-only|off) ;;
  *) err "--notify-on must be one of: both | failure-only | success-only | off";;
esac

# ---------- preflight ----------
need_root
[[ -n "$BUCKET" ]] || err "--bucket is required (the GCS bucket name, no gs:// prefix)"
: "${GCS_SA_JSON:?GCS_SA_JSON env var (path to read-only SA JSON) is required}"
: "${GCS_CRYPT_PASSWORD:?GCS_CRYPT_PASSWORD env var is required}"
[[ -r "$GCS_SA_JSON" ]] || err "GCS_SA_JSON=$GCS_SA_JSON is not readable"
command -v apt-get >/dev/null || err "this script targets apt-based distros only"

# ---------- install dependencies ----------
log "ensuring dependencies (rclone, curl, jq, unzip)…"
apt-get update -qq
apt-get install -y -qq curl ca-certificates unzip jq >/dev/null

arch=$(uname -m)
case "$arch" in
  x86_64)  rclone_arch=amd64 ;;
  aarch64) rclone_arch=arm64 ;;
  *) err "unsupported architecture: $arch";;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# rclone — pinned static binary (same pin as onprem-backup-setup.sh).
if ! command -v "$RCLONE_BIN" >/dev/null || ! "$RCLONE_BIN" version 2>/dev/null | grep -q "rclone v$RCLONE_VERSION"; then
  log "installing rclone v$RCLONE_VERSION to $RCLONE_BIN…"
  curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${rclone_arch}.zip" -o "$tmp/rclone.zip"
  unzip -q "$tmp/rclone.zip" -d "$tmp"
  install -m 0755 "$tmp"/rclone-v*-linux-*/rclone "$RCLONE_BIN"
fi

# ---------- service user ----------
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  log "creating system user $SERVICE_USER…"
  useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "$SERVICE_USER"
fi

# ---------- config dir + crypt vault ----------
mkdir -p "$CONFIG_DIR"
chgrp "$SERVICE_USER" "$CONFIG_DIR"
chmod 0750 "$CONFIG_DIR"

log "installing read-only SA key to $SA_DEST"
umask 077
install -m 0640 "$GCS_SA_JSON" "$SA_DEST"
chgrp "$SERVICE_USER" "$SA_DEST"
umask 022

log "creating crypt vault at $BACKUP_DIR (holds ciphertext only)"
mkdir -p "$BACKUP_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
chmod 0750 "$BACKUP_DIR"

# ---------- rclone config (gcs source + crypt sink) ----------
# crypt password/salt are stored OBSCURED (reversible, like kopia.password/
# luks.key already are on this host) in a 0640 root:service file — never in git,
# never propagated to a host→host replica.
# Idempotency guard for the ONE input that is NOT safely reconcilable: a changed
# crypt password silently orphans the whole vault — old ciphertext becomes
# undecryptable, `sync` then treats all of it as extraneous and moves 302 GB into
# archive/<date>, and re-downloads the bucket at egress. rclone obscure is
# non-deterministic (random IV), so compare via `reveal`, not string equality.
if [[ -f "$RCLONE_CONFIG" ]] && grep -q '^\[gcs-crypt\]' "$RCLONE_CONFIG" && [[ "$ROTATE_CRYPT" -eq 0 ]]; then
  existing_ob=$(awk '/^\[gcs-crypt\]/{f=1} f&&/^password *=/{print $3; exit}' "$RCLONE_CONFIG")
  if [[ -n "$existing_ob" ]] && [[ "$("$RCLONE_BIN" reveal "$existing_ob" 2>/dev/null)" != "$GCS_CRYPT_PASSWORD" ]]; then
    err "GCS_CRYPT_PASSWORD differs from the existing vault's key ($RCLONE_CONFIG). Re-keying orphans the \
whole encrypted vault (old ciphertext unreadable + full re-download at egress). Pass --rotate-crypt-password \
to re-key intentionally."
  fi
fi

log "writing rclone config to $RCLONE_CONFIG"
obscured_pw=$("$RCLONE_BIN" obscure "$GCS_CRYPT_PASSWORD")
salt_line=""
if [[ -n "${GCS_CRYPT_PASSWORD2:-}" ]]; then
  obscured_salt=$("$RCLONE_BIN" obscure "$GCS_CRYPT_PASSWORD2")
  salt_line="password2 = $obscured_salt"
fi
mkdir -p "$(dirname "$RCLONE_CONFIG")"
umask 077
cat > "$RCLONE_CONFIG" <<EOF
[gcs-src]
type = google cloud storage
service_account_file = $SA_DEST

[gcs-crypt]
type = crypt
remote = $BACKUP_DIR/vault
filename_encryption = standard
directory_name_encryption = true
password = $obscured_pw
$salt_line
EOF
umask 022
chgrp "$SERVICE_USER" "$RCLONE_CONFIG"
chmod 0640 "$RCLONE_CONFIG"

# Scrub secrets from the env so subshells can't see them.
unset GCS_CRYPT_PASSWORD GCS_CRYPT_PASSWORD2 obscured_pw obscured_salt

# ---------- journald namespace (bounded log volume) ----------
log "configuring bounded journal namespace $LOG_NAMESPACE (≤ $JOURNAL_MAX_USE)"
cat > "$JOURNALD_NAMESPACE_CONFIG" <<JOURNAL
[Journal]
Storage=persistent
SystemMaxUse=$JOURNAL_MAX_USE
SystemKeepFree=$JOURNAL_KEEP_FREE
SystemMaxFileSize=100M
MaxRetentionSec=$JOURNAL_MAX_RETENTION
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToWall=no
JOURNAL
chmod 0644 "$JOURNALD_NAMESPACE_CONFIG"
systemctl reload "systemd-journald@$LOG_NAMESPACE.service" 2>/dev/null || true

# ---------- discord webhook (optional) ----------
if [[ -v DISCORD_WEBHOOK_URL ]]; then
  if [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
    rm -f "$WEBHOOK_FILE"
    log "DISCORD_WEBHOOK_URL was empty — cleared $WEBHOOK_FILE"
  else
    umask 077
    printf '%s' "$DISCORD_WEBHOOK_URL" > "$WEBHOOK_FILE"
    umask 022
    chgrp "$SERVICE_USER" "$WEBHOOK_FILE"
    chmod 0640 "$WEBHOOK_FILE"
    log "Discord webhook stored at $WEBHOOK_FILE"
  fi
  unset DISCORD_WEBHOOK_URL
fi

# ---------- notify helper ----------
log "installing notifier at $NOTIFY_BIN"
install -m 0755 /dev/stdin "$NOTIFY_BIN" <<NOTIFY
#!/usr/bin/env bash
# Discord notifier for the on-prem GCS mirror / weekly cryptcheck.
# Usage: $(basename "$NOTIFY_BIN") KIND [extra]
#   KIND ∈ start|success|failure|verify-start|verify-success|verify-failure|test
set -euo pipefail
WEBHOOK_FILE=$WEBHOOK_FILE
BACKUP_DIR=$BACKUP_DIR
MIRROR_SVC=$SERVICE_NAME
VERIFY_SVC=$VERIFY_SERVICE_NAME
NOTIFY
cat >> "$NOTIFY_BIN" <<'NOTIFY'
[[ -r "$WEBHOOK_FILE" ]] || exit 0
url=$(<"$WEBHOOK_FILE"); [[ -n "$url" ]] || exit 0

kind="${1:-}"
case "$kind" in
  start)          title=":hourglass_flowing_sand: GCS on-prem mirror started"; color=3447003;  want_dur=0; want_size=0; SVC=$MIRROR_SVC ;;
  success)        title=":white_check_mark: GCS on-prem mirror succeeded";     color=3066993;  want_dur=1; want_size=1; SVC=$MIRROR_SVC ;;
  failure)        title=":x: GCS on-prem mirror FAILED";                       color=15158332; want_dur=1; want_size=1; SVC=$MIRROR_SVC ;;
  verify-start)   title=":mag: GCS mirror cryptcheck started";                 color=3447003;  want_dur=0; want_size=0; SVC=$VERIFY_SVC ;;
  verify-success) title=":white_check_mark: GCS mirror cryptcheck passed";     color=3066993;  want_dur=1; want_size=0; SVC=$VERIFY_SVC ;;
  verify-failure) title=":rotating_light: GCS mirror cryptcheck FAILED";       color=15158332; want_dur=1; want_size=0; SVC=$VERIFY_SVC ;;
  test)           title=":bell: GCS on-prem mirror — test notification";       color=10181046; want_dur=0; want_size=0; SVC=$MIRROR_SVC ;;
  *)              title="GCS on-prem mirror: ${kind:-unknown}";                color=8421504;  want_dur=1; want_size=1; SVC=$MIRROR_SVC ;;
esac

extra="${2:-}"
hostname=$(hostname -f 2>/dev/null || hostname)
timestamp=$(date -u -Iseconds 2>/dev/null || date -u +%FT%TZ)

elapsed="unknown"; size="see log"
if [[ "$want_dur" == "1" ]] && command -v systemctl >/dev/null; then
  s=$(systemctl show "$SVC.service" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  e=$(systemctl show "$SVC.service" -p InactiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  if [[ "$e" -gt "$s" ]] && [[ "$s" -gt 0 ]]; then
    elapsed=$(awk -v u="$((e-s))" 'BEGIN{x=u/1000000; printf (x>=3600)?"%dh%dm":(x>=60)?"%dm%ds":"%ds",(x>=3600)?int(x/3600):(x>=60)?int(x/60):int(x),(x>=3600)?int((x%3600)/60):(x>=60)?int(x%60):0}')
  fi
fi
if [[ "$want_size" == "1" ]] && [[ -r "$BACKUP_DIR" ]]; then
  size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}'); [[ -n "$size" ]] || size="see log"
fi

if command -v jq >/dev/null; then
  payload=$(jq -nc --arg title "$title" --argjson color "$color" --arg host "$hostname" \
    --arg ts "$timestamp" --arg elapsed "$elapsed" --arg size "$size" --arg extra "$extra" \
    --argjson wd "$want_dur" --argjson ws "$want_size" \
    '{username:"mycure-gcs",embeds:[{title:$title,color:$color,timestamp:$ts,fields:(
       [{name:"Host",value:$host,inline:true}]
       + (if $wd==1 then [{name:"Duration",value:$elapsed,inline:true}] else [] end)
       + (if $ws==1 then [{name:"Vault size",value:$size,inline:true}] else [] end)
       + (if $extra=="" then [] else [{name:"Note",value:$extra,inline:false}] end))}]}')
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  fields="{\"name\":\"Host\",\"value\":\"$(esc "$hostname")\",\"inline\":true}"
  [[ "$want_dur" == "1" ]]  && fields+=",{\"name\":\"Duration\",\"value\":\"$(esc "$elapsed")\",\"inline\":true}"
  [[ "$want_size" == "1" ]] && fields+=",{\"name\":\"Vault size\",\"value\":\"$(esc "$size")\",\"inline\":true}"
  [[ -n "$extra" ]]         && fields+=",{\"name\":\"Note\",\"value\":\"$(esc "$extra")\",\"inline\":false}"
  payload="{\"username\":\"mycure-gcs\",\"embeds\":[{\"title\":\"$(esc "$title")\",\"color\":$color,\"timestamp\":\"$timestamp\",\"fields\":[$fields]}]}"
fi
curl -sS -m 15 -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null || true
NOTIFY

# ---------- optional include filter ----------
include_line=""
if [[ -n "$INCLUDE_PREFIX" ]]; then
  include_line="  --include \"$INCLUDE_PREFIX\" \\"$'\n'
fi

# ---------- mirror runner (needs a wrapper for the dated --backup-dir) ----------
# sync current state into gcs-crypt:current; moved/deleted objects are preserved
# (encrypted) under gcs-crypt:archive/<date> so a source-side deletion or
# ransomware wipe cannot erase the on-prem history. Both paths are inside the
# crypt remote → encrypted at rest, and both ride the host→host mirror (#400).
log "installing mirror runner at $MIRROR_BIN"
install -m 0755 /dev/stdin "$MIRROR_BIN" <<RUNNER
#!/usr/bin/env bash
set -euo pipefail
export RCLONE_CONFIG=$RCLONE_CONFIG
DATE=\$(date -u +%F)
exec $RCLONE_BIN sync gcs-src:$BUCKET gcs-crypt:current \\
  --backup-dir "gcs-crypt:archive/\$DATE" \\
${include_line}  --transfers $RCLONE_TRANSFERS \\
  --checkers $RCLONE_CHECKERS \\
  --fast-list \\
  --log-level INFO \\
  --stats 5m --stats-one-line
RUNNER

# ---------- verify runner (cryptcheck: source vs decrypted crypt) ----------
log "installing verify runner at $VERIFY_BIN"
install -m 0755 /dev/stdin "$VERIFY_BIN" <<VERIFY
#!/usr/bin/env bash
# Weekly integrity check: rclone cryptcheck hashes the GCS source and compares
# against the DECRYPTED view of the on-prem crypt vault — proving the encrypted
# copy is complete and uncorrupted AND that the crypt password still decrypts it
# (catches bit-rot, partial syncs, and password/salt drift). Read-only.
set -euo pipefail
export RCLONE_CONFIG=$RCLONE_CONFIG
exec $RCLONE_BIN cryptcheck gcs-src:$BUCKET gcs-crypt:current \\
${include_line}  --one-way \\
  --transfers $RCLONE_CHECKERS \\
  --stats 1m --stats-one-line
VERIFY

# ---------- systemd units ----------
case "$NOTIFY_ON" in
  both)         n_start="ExecStartPre=-$NOTIFY_BIN start"; n_ok="ExecStartPost=$NOTIFY_BIN success"; n_fail="OnFailure=${SERVICE_NAME}-failure.service" ;;
  success-only) n_start="ExecStartPre=-$NOTIFY_BIN start"; n_ok="ExecStartPost=$NOTIFY_BIN success"; n_fail="" ;;
  failure-only) n_start="ExecStartPre=-$NOTIFY_BIN start"; n_ok="";                                  n_fail="OnFailure=${SERVICE_NAME}-failure.service" ;;
  off)          n_start="";                                n_ok="";                                  n_fail="" ;;
esac

log "writing systemd unit $SERVICE_NAME.service"
cat > "$SYSTEMD_DIR/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=Mirror GCS bucket $BUCKET to encrypted on-prem vault (Mycure DR tier-2)
After=network-online.target
Wants=network-online.target
# Refuse to start unless the vault's disk is mounted — otherwise an unmounted
# target lets rclone recreate a 302 GB tree on the root FS (the #397/cb2e6d3
# guard, carried by #403). No LUKS/imperative-mount mode here, so the single
# unconditional line is correct; no-op if BACKUP_DIR is on root (-.mount).
RequiresMountsFor=$BACKUP_DIR
$n_fail

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$SERVICE_NAME
$n_start
ExecStart=$MIRROR_BIN
$n_ok

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
ExecStart=$NOTIFY_BIN failure
UNIT

case "$NOTIFY_ON" in
  both)         v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_ok="ExecStartPost=$NOTIFY_BIN verify-success"; v_fail="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  success-only) v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_ok="ExecStartPost=$NOTIFY_BIN verify-success"; v_fail="" ;;
  failure-only) v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_ok="";                                          v_fail="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  off)          v_start="";                                       v_ok="";                                          v_fail="" ;;
esac

log "writing systemd unit $VERIFY_SERVICE_NAME.service"
cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.service" <<UNIT
[Unit]
Description=Weekly cryptcheck of the on-prem GCS mirror
After=network-online.target
Wants=network-online.target
RequiresMountsFor=$BACKUP_DIR
$v_fail

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$VERIFY_SERVICE_NAME
$v_start
ExecStart=$VERIFY_BIN
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
ExecStart=$NOTIFY_BIN verify-failure
UNIT

log "writing systemd timers"
cat > "$SYSTEMD_DIR/$SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Timer for the Mycure on-prem GCS mirror

[Timer]
OnCalendar=$TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=10m
Unit=$SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Weekly timer for the Mycure on-prem GCS mirror cryptcheck

[Timer]
OnCalendar=$VERIFY_TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=30m
Unit=$VERIFY_SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

# ---------- credential validation (dry-run) ----------
log "validating the read-only SA with rclone lsd gcs-src:$BUCKET …"
if ! sudo -u "$SERVICE_USER" RCLONE_CONFIG="$RCLONE_CONFIG" \
      "$RCLONE_BIN" lsd "gcs-src:$BUCKET" >/dev/null 2>&1; then
  err "rclone failed to list gcs-src:$BUCKET — check the SA has storage.objectViewer on the bucket"
fi
log "credentials OK"

# ---------- enable timers ----------
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.timer" >/dev/null
systemctl enable --now "$VERIFY_SERVICE_NAME.timer" >/dev/null
log "$SERVICE_NAME.timer + $VERIFY_SERVICE_NAME.timer enabled"

# ---------- summary ----------
echo
log "setup complete — summary:"
echo "  source bucket : gcs-src:$BUCKET${INCLUDE_PREFIX:+  (prefix: $INCLUDE_PREFIX)}"
echo "  crypt vault   : $BACKUP_DIR/vault  (ENCRYPTED at rest; ciphertext-only)"
echo "  service user  : $SERVICE_USER"
echo "  mirror timer  : $TIMER_ON_CALENDAR"
echo "  verify timer  : $VERIFY_TIMER_ON_CALENDAR  (rclone cryptcheck)"
if [[ -f "$WEBHOOK_FILE" ]]; then
  echo "  notifications : Discord webhook configured (mode: $NOTIFY_ON)"
else
  echo "  notifications : disabled (set DISCORD_WEBHOOK_URL to enable)"
fi
echo
echo "Next:"
echo "  sudo systemctl start $SERVICE_NAME.service          # trigger the first pull now"
echo "  sudo journalctl --namespace=$LOG_NAMESPACE -u $SERVICE_NAME.service -f"
echo "  # host→host (#400): authorize a replica to pull \$BACKUP_DIR to vanaheim"
echo "  # restore: rclone --config <cfg-with-crypt-pw> copy gcs-crypt:current/<path> ./  (password supplied at restore)"

if [[ -f "$WEBHOOK_FILE" ]] && [[ "$NOTIFY_ON" != "off" ]]; then
  "$NOTIFY_BIN" test "gcs-onprem-mirror setup completed on $(hostname -f 2>/dev/null || hostname)" || warn "test notification failed (non-fatal)"
fi
