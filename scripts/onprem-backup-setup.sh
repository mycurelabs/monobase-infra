#!/usr/bin/env bash
# Sets up a Velero-backup pull-mirror on a Debian/Ubuntu host.
#
# Pulls the Kopia-encrypted contents of the cluster's BackupStorageLocation
# (mycure-doks-velero-backups in DO Spaces) to a local directory under a
# systemd timer. Restore tooling (kopia + rclone) is left in place so the
# host can serve as a recovery source when the cloud bucket is unreachable.
#
# Idempotent. Re-running with the same flags reconciles; re-running with
# different flags reconfigures.
#
# Usage:
#   sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… \
#     scripts/onprem-backup-setup.sh [flags]
#
# See docs/operations/ONPREM_BACKUP_SETUP.md for the full runbook.

set -euo pipefail

# ---------- defaults ----------
ENCRYPTION=none                                 # none | luks-file | luks-partition
LUKS_DEVICE=""
LUKS_FILE_SIZE=100G
BACKUP_DIR=/var/backups/mycure
BUCKET=mycure-doks-velero-backups
REGION=sgp1
RETENTION_DAYS=30
MAX_AGE=30d
SERVICE_USER=mycure-backup
TIMER_ON_CALENDAR="*-*-* 02:30:00 UTC"
YES_WIPE_DEVICE=0
KOPIA_VERSION=0.21.1
RCLONE_VERSION=1.69.1
RCLONE_BIN=/usr/local/bin/rclone
RCLONE_TRANSFERS=2
RCLONE_CHECKERS=4
NOTIFY_ON=both                                  # both | failure-only | success-only | off

CONFIG_DIR=/etc/mycure-backup
RCLONE_CONFIG=/etc/rclone/rclone.conf
SERVICE_NAME=mycure-backup-mirror
VERIFY_SERVICE_NAME=mycure-backup-verify
VERIFY_TIMER_ON_CALENDAR="Sun *-*-* 03:00:00 UTC"
VERIFY_FILES_PERCENT=5
VERIFY_BIN=/usr/local/sbin/mycure-backup-verify
SYSTEMD_DIR=/etc/systemd/system
NOTIFY_BIN=/usr/local/sbin/mycure-backup-notify
WEBHOOK_FILE=$CONFIG_DIR/discord-webhook.url
LOG_NAMESPACE=mycure-backup
JOURNALD_NAMESPACE_CONFIG=/etc/systemd/journald@${LOG_NAMESPACE}.conf
JOURNAL_MAX_USE=500M
JOURNAL_KEEP_FREE=2G
JOURNAL_MAX_RETENTION=4week

# ---------- helpers ----------
log()    { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn()   { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
err()    { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || err "must run as root (use sudo)"; }

usage() {
  cat <<EOF
Usage: sudo SPACES_ACCESS_KEY=… SPACES_SECRET_KEY=… KOPIA_PASSWORD=… $0 [flags]

Flags:
  --encryption=MODE       none | luks-file | luks-partition   (default: $ENCRYPTION)
  --luks-device=DEV       block device for luks-partition mode (e.g. /dev/sdb)
  --luks-file-size=SIZE   sparse-file size for luks-file mode  (default: $LUKS_FILE_SIZE)
  --backup-dir=PATH       mirror target directory              (default: $BACKUP_DIR)
  --bucket=NAME           DO Spaces bucket name                (default: $BUCKET)
  --region=REGION         DO Spaces region                     (default: $REGION)
  --retention-days=N      reference value, recorded in summary (default: $RETENTION_DAYS)
  --max-age=DURATION      rclone --max-age                     (default: $MAX_AGE)
  --service-user=USER     system user that runs the mirror     (default: $SERVICE_USER)
  --timer-on-calendar=S   systemd OnCalendar=                  (default: "$TIMER_ON_CALENDAR")
  --yes-wipe-device       required confirm for luks-partition mode
  --kopia-version=VER     kopia release tag to install         (default: $KOPIA_VERSION)
  --notify-on=MODE        both | failure-only | success-only | off  (default: $NOTIFY_ON)
  -h, --help              this help

Environment (required):
  SPACES_ACCESS_KEY       DO Spaces access key, read-only recommended
  SPACES_SECRET_KEY       DO Spaces secret key
  KOPIA_PASSWORD          Kopia repo password (gcloud secrets versions access
                          latest --secret=monobase-velero-repo-password)

Environment (optional):
  DISCORD_WEBHOOK_URL     Discord webhook for backup notifications. If set, the
                          script installs a notifier and writes the URL to
                          /etc/mycure-backup/discord-webhook.url so the timer
                          can use it. If unset, no notifier is configured and
                          any previously stored URL is left intact (pass an
                          empty string to clear it).
EOF
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --encryption=*)         ENCRYPTION="${1#*=}";          shift;;
    --luks-device=*)        LUKS_DEVICE="${1#*=}";         shift;;
    --luks-file-size=*)     LUKS_FILE_SIZE="${1#*=}";      shift;;
    --backup-dir=*)         BACKUP_DIR="${1#*=}";          shift;;
    --bucket=*)             BUCKET="${1#*=}";              shift;;
    --region=*)             REGION="${1#*=}";              shift;;
    --retention-days=*)     RETENTION_DAYS="${1#*=}";      shift;;
    --max-age=*)            MAX_AGE="${1#*=}";             shift;;
    --service-user=*)       SERVICE_USER="${1#*=}";        shift;;
    --timer-on-calendar=*)  TIMER_ON_CALENDAR="${1#*=}";   shift;;
    --kopia-version=*)      KOPIA_VERSION="${1#*=}";       shift;;
    --notify-on=*)          NOTIFY_ON="${1#*=}";           shift;;
    --discord-webhook-url=*) DISCORD_WEBHOOK_URL="${1#*=}";shift;;
    --yes-wipe-device)      YES_WIPE_DEVICE=1;             shift;;
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

: "${SPACES_ACCESS_KEY:?SPACES_ACCESS_KEY env var is required}"
: "${SPACES_SECRET_KEY:?SPACES_SECRET_KEY env var is required}"
: "${KOPIA_PASSWORD:?KOPIA_PASSWORD env var is required}"

command -v apt-get >/dev/null || err "this script targets apt-based distros only"

case "$ENCRYPTION" in
  none|luks-file|luks-partition) ;;
  *) err "--encryption must be one of: none | luks-file | luks-partition";;
esac

if [[ "$ENCRYPTION" == "luks-partition" ]]; then
  [[ -n "$LUKS_DEVICE" ]]                || err "--luks-device required for luks-partition mode"
  [[ -b "$LUKS_DEVICE" ]]                || err "$LUKS_DEVICE is not a block device"
  [[ "$YES_WIPE_DEVICE" -eq 1 ]]         || err "luks-partition mode wipes $LUKS_DEVICE; pass --yes-wipe-device to confirm"
  ! findmnt "$LUKS_DEVICE" >/dev/null    || err "$LUKS_DEVICE is currently mounted; unmount before continuing"
fi

# ---------- install dependencies ----------
log "ensuring dependencies (rclone, kopia, curl, cryptsetup, unzip, jq)…"
apt-get update -qq
apt-get install -y -qq curl ca-certificates cryptsetup-bin unzip jq python3 openssl >/dev/null

arch=$(uname -m)
case "$arch" in
  x86_64)  kopia_arch=x64; rclone_arch=amd64 ;;
  aarch64) kopia_arch=arm64; rclone_arch=arm64 ;;
  *) err "unsupported architecture: $arch";;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# rclone — pinned static binary (>= 1.65 needed for \`rclone serve s3\` which
# the verify helper uses). Ubuntu 24.04's apt ships v1.60, which lacks it.
# We install to /usr/local/bin so it shadows apt's /usr/bin/rclone in PATH.
if ! command -v "$RCLONE_BIN" >/dev/null || ! "$RCLONE_BIN" version 2>/dev/null | grep -q "rclone v$RCLONE_VERSION"; then
  log "installing rclone v$RCLONE_VERSION to $RCLONE_BIN…"
  curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${rclone_arch}.zip" -o "$tmp/rclone.zip"
  unzip -q "$tmp/rclone.zip" -d "$tmp"
  install -m 0755 "$tmp"/rclone-v*-linux-*/rclone "$RCLONE_BIN"
fi

# kopia — pinned static binary.
if ! command -v kopia >/dev/null || ! kopia --version 2>/dev/null | grep -q "$KOPIA_VERSION"; then
  log "installing kopia v$KOPIA_VERSION…"
  curl -fsSL "https://github.com/kopia/kopia/releases/download/v${KOPIA_VERSION}/kopia-${KOPIA_VERSION}-linux-${kopia_arch}.tar.gz" -o "$tmp/kopia.tgz"
  tar -xzf "$tmp/kopia.tgz" -C "$tmp"
  install -m 0755 "$tmp"/kopia-*-linux-*/kopia /usr/local/bin/kopia
fi

# ---------- service user ----------
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  log "creating system user $SERVICE_USER…"
  useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "$SERVICE_USER"
fi

# ---------- backup directory + optional encryption ----------
# Config dir must be traversable by the service user so it can read the
# webhook URL at runtime. Group-owned by the service user, mode 0750.
mkdir -p "$CONFIG_DIR"
chgrp "$SERVICE_USER" "$CONFIG_DIR"
chmod 0750 "$CONFIG_DIR"

case "$ENCRYPTION" in
  none)
    log "encryption=none — creating plain directory at $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
    chmod 0750 "$BACKUP_DIR"
    ;;
  luks-file|luks-partition)
    luks_key=$CONFIG_DIR/luks.key
    if [[ ! -f "$luks_key" ]]; then
      log "generating LUKS keyfile at $luks_key"
      umask 077
      head -c 64 /dev/urandom | base64 -w0 > "$luks_key"
      umask 022
    fi
    chmod 0400 "$luks_key"

    if [[ "$ENCRYPTION" == "luks-file" ]]; then
      img=$BACKUP_DIR.img
      if [[ ! -f "$img" ]]; then
        log "creating sparse LUKS-file at $img ($LUKS_FILE_SIZE)"
        mkdir -p "$(dirname "$img")"
        truncate -s "$LUKS_FILE_SIZE" "$img"
        cryptsetup luksFormat --batch-mode --key-file "$luks_key" "$img"
      fi
      target=$img
    else
      target=$LUKS_DEVICE
      if ! cryptsetup isLuks "$target"; then
        log "LUKS-formatting $target"
        cryptsetup luksFormat --batch-mode --key-file "$luks_key" "$target"
      fi
    fi

    mapper_name=mycure-backup
    if ! [[ -e "/dev/mapper/$mapper_name" ]]; then
      log "opening LUKS device as /dev/mapper/$mapper_name"
      cryptsetup open --key-file "$luks_key" "$target" "$mapper_name"
    fi

    if ! blkid "/dev/mapper/$mapper_name" >/dev/null 2>&1; then
      log "creating ext4 on /dev/mapper/$mapper_name"
      mkfs.ext4 -q "/dev/mapper/$mapper_name"
    fi

    mkdir -p "$BACKUP_DIR"
    if ! findmnt --target "$BACKUP_DIR" >/dev/null 2>&1; then
      log "mounting backup volume at $BACKUP_DIR"
      mount "/dev/mapper/$mapper_name" "$BACKUP_DIR"
    fi
    chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
    chmod 0750 "$BACKUP_DIR"

    # Persist open+mount at boot via a small systemd unit, so the timer can fire after reboot.
    cat > "$SYSTEMD_DIR/mycure-backup-volume.service" <<UNIT
[Unit]
Description=Open and mount the LUKS-encrypted Mycure backup volume
DefaultDependencies=no
After=local-fs-pre.target
Before=local-fs.target mycure-backup-mirror.timer

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/cryptsetup open --key-file ${luks_key} ${target} ${mapper_name}
ExecStart=/bin/mount /dev/mapper/${mapper_name} ${BACKUP_DIR}
ExecStop=/bin/umount ${BACKUP_DIR}
ExecStop=/sbin/cryptsetup close ${mapper_name}

[Install]
WantedBy=local-fs.target
UNIT
    systemctl daemon-reload
    systemctl enable mycure-backup-volume.service >/dev/null
    ;;
esac

# ---------- rclone config ----------
log "writing rclone config to $RCLONE_CONFIG"
mkdir -p "$(dirname "$RCLONE_CONFIG")"
umask 077
cat > "$RCLONE_CONFIG" <<EOF
[spaces]
type = s3
provider = DigitalOcean
region = $REGION
endpoint = $REGION.digitaloceanspaces.com
access_key_id = $SPACES_ACCESS_KEY
secret_access_key = $SPACES_SECRET_KEY
acl = private
EOF
umask 022
chgrp "$SERVICE_USER" "$RCLONE_CONFIG"
chmod 0640 "$RCLONE_CONFIG"

# ---------- kopia password ----------
log "writing kopia password to $CONFIG_DIR/kopia.password"
umask 077
printf '%s' "$KOPIA_PASSWORD" > "$CONFIG_DIR/kopia.password"
umask 022
chmod 0400 "$CONFIG_DIR/kopia.password"

# Scrub the env so accidental subshells don't see secrets.
unset SPACES_ACCESS_KEY SPACES_SECRET_KEY KOPIA_PASSWORD

# ---------- journald namespace (bounded log volume) ----------
# rclone writes to stdout, systemd captures it into a per-namespace journal
# with explicit size caps so logs can't grow unbounded. View with:
#   journalctl --namespace=$LOG_NAMESPACE -u $SERVICE_NAME.service [-f]
log "configuring bounded journal namespace $LOG_NAMESPACE (≤ $JOURNAL_MAX_USE)"
cat > "$JOURNALD_NAMESPACE_CONFIG" <<JOURNAL
# Bounded journal for the mycure-backup namespace. systemd spawns
# systemd-journald@${LOG_NAMESPACE}.service on first unit start.
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

# Reload the namespaced journald if it's already running, so caps apply on
# the next ExecStart. Initial start happens automatically when the service runs.
systemctl reload "systemd-journald@$LOG_NAMESPACE.service" 2>/dev/null || true

# Sweep the old plain log file from earlier versions of this script; logs
# now live in the namespaced journal, not /var/log/mycure-backup-mirror.log.
rm -f /var/log/mycure-backup-mirror.log

# ---------- discord webhook (optional) ----------
# If DISCORD_WEBHOOK_URL is set in env, write it to disk so the timer can
# read it. Empty string explicitly clears any previously stored URL.
# Unset env var means "leave existing config alone" (idempotent rerun).
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

# ---------- notify helper script ----------
# Reads the webhook URL at runtime; silently no-ops if absent or empty.
# Idempotent: overwriting the script is harmless.
log "installing notifier at $NOTIFY_BIN"
install -m 0755 /dev/stdin "$NOTIFY_BIN" <<'NOTIFY'
#!/usr/bin/env bash
# Send a Discord webhook notification about the on-prem backup mirror or
# the weekly Kopia repo integrity verification.
# Usage: mycure-backup-notify KIND [extra_message]
#   KIND ∈ start|success|failure|verify-start|verify-success|verify-failure|test
# Silent no-op if /etc/mycure-backup/discord-webhook.url is missing/empty.
set -euo pipefail

WEBHOOK_FILE=/etc/mycure-backup/discord-webhook.url

[[ -r "$WEBHOOK_FILE" ]] || exit 0
url=$(<"$WEBHOOK_FILE")
[[ -n "$url" ]] || exit 0

# kind -> (title, color, want_duration, want_mirrored, service_name)
# "want_*" toggles whether the embed includes those fields. service_name
# is the systemd unit we pull ActiveEnterTimestamp/Inactive from for the
# Duration field (mirror lifecycle vs. verify lifecycle).
kind="${1:-}"
case "$kind" in
  start)          title=":hourglass_flowing_sand: On-prem backup mirror started"; color=3447003;  want_duration=0; want_mirrored=0; SERVICE_NAME=mycure-backup-mirror ;;
  success)        title=":white_check_mark: On-prem backup mirror succeeded";     color=3066993;  want_duration=1; want_mirrored=1; SERVICE_NAME=mycure-backup-mirror ;;
  failure)        title=":x: On-prem backup mirror FAILED";                       color=15158332; want_duration=1; want_mirrored=1; SERVICE_NAME=mycure-backup-mirror ;;
  verify-start)   title=":mag: On-prem backup verification started";              color=3447003;  want_duration=0; want_mirrored=0; SERVICE_NAME=mycure-backup-verify ;;
  verify-success) title=":white_check_mark: On-prem backup verification passed";  color=3066993;  want_duration=1; want_mirrored=0; SERVICE_NAME=mycure-backup-verify ;;
  verify-failure) title=":rotating_light: On-prem backup verification FAILED";    color=15158332; want_duration=1; want_mirrored=0; SERVICE_NAME=mycure-backup-verify ;;
  test)           title=":bell: On-prem backup mirror — test notification";       color=10181046; want_duration=0; want_mirrored=0; SERVICE_NAME=mycure-backup-mirror ;;
  *)              title="On-prem backup: ${kind:-unknown}";                       color=8421504;  want_duration=1; want_mirrored=1; SERVICE_NAME=mycure-backup-mirror ;;
esac

extra="${2:-}"
hostname=$(hostname -f 2>/dev/null || hostname)
timestamp=$(date -u -Iseconds 2>/dev/null || date -u +%FT%TZ)

# Pull stats from systemd for success/failure messages so the embed is
# self-contained. ExecMainStartTimestampMonotonic is when ExecStart began
# (for start notifications, that's now; we don't compute elapsed in that case).
elapsed="unknown"
mirrored="see log"
if [[ "$want_duration" == "1" ]] && command -v systemctl >/dev/null; then
  start_ts=$(systemctl show "$SERVICE_NAME.service" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  end_ts=$(systemctl show "$SERVICE_NAME.service" -p InactiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  if [[ "$end_ts" -gt "$start_ts" ]] && [[ "$start_ts" -gt 0 ]]; then
    delta_us=$((end_ts - start_ts))
    elapsed=$(awk -v u="$delta_us" 'BEGIN{s=u/1000000; printf (s>=3600)?"%dh%dm":(s>=60)?"%dm%ds":"%ds", (s>=3600)?int(s/3600):(s>=60)?int(s/60):int(s), (s>=3600)?int((s%3600)/60):(s>=60)?int(s%60):0}')
  fi
fi
if [[ "$want_mirrored" == "1" ]] && [[ -r /var/backups/mycure/spaces ]]; then
  mirrored=$(du -sh /var/backups/mycure/spaces 2>/dev/null | awk '{print $1}')
  [[ -n "$mirrored" ]] || mirrored="see log"
fi

# Build the JSON payload with jq if available (handles escaping properly);
# fall back to a simple printf for hosts without jq.
if command -v jq >/dev/null; then
  payload=$(jq -nc \
    --arg title "$title" --argjson color "$color" \
    --arg host "$hostname" --arg ts "$timestamp" \
    --arg elapsed "$elapsed" --arg mirrored "$mirrored" \
    --arg extra "$extra" \
    --argjson want_duration "$want_duration" \
    --argjson want_mirrored "$want_mirrored" \
    '{username:"mycure-backup",embeds:[{title:$title,color:$color,timestamp:$ts,fields:(
       [{name:"Host",value:$host,inline:true}]
       + (if $want_duration == 1 then [{name:"Duration",value:$elapsed,inline:true}] else [] end)
       + (if $want_mirrored == 1 then [{name:"Mirrored",value:$mirrored,inline:true}] else [] end)
       + (if $extra == ""        then [] else [{name:"Note",value:$extra,inline:false}] end)
     )}]}')
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  fields="{\"name\":\"Host\",\"value\":\"$(esc "$hostname")\",\"inline\":true}"
  [[ "$want_duration" == "1" ]] && fields+=",{\"name\":\"Duration\",\"value\":\"$(esc "$elapsed")\",\"inline\":true}"
  [[ "$want_mirrored" == "1" ]] && fields+=",{\"name\":\"Mirrored\",\"value\":\"$(esc "$mirrored")\",\"inline\":true}"
  [[ -n "$extra"             ]] && fields+=",{\"name\":\"Note\",\"value\":\"$(esc "$extra")\",\"inline\":false}"
  payload="{\"username\":\"mycure-backup\",\"embeds\":[{\"title\":\"$(esc "$title")\",\"color\":$color,\"timestamp\":\"$timestamp\",\"fields\":[$fields]}]}"
fi

curl -sS -m 15 -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null || true
NOTIFY

# ---------- systemd service + timer ----------
log "writing systemd unit $SERVICE_NAME.service"
# ExecStartPre  fires before ExecStart → start notification (always on when
#   notifications are enabled, so a long-running mirror doesn't look hung).
#   The `-` prefix tells systemd to ignore a non-zero exit so a webhook
#   outage can never block the actual backup.
# ExecStartPost fires only on ExecStart success → success notification.
# OnFailure=    triggers a sibling unit → failure notification.
case "$NOTIFY_ON" in
  both)          notify_start="ExecStartPre=-$NOTIFY_BIN start";  notify_success="ExecStartPost=$NOTIFY_BIN success"; failure_onfailure="OnFailure=${SERVICE_NAME}-failure.service" ;;
  success-only)  notify_start="ExecStartPre=-$NOTIFY_BIN start";  notify_success="ExecStartPost=$NOTIFY_BIN success"; failure_onfailure="" ;;
  failure-only)  notify_start="ExecStartPre=-$NOTIFY_BIN start";  notify_success="";                                  failure_onfailure="OnFailure=${SERVICE_NAME}-failure.service" ;;
  off)           notify_start="";                                 notify_success="";                                  failure_onfailure="" ;;
esac

cat > "$SYSTEMD_DIR/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=Mirror Velero backups from DO Spaces (Mycure on-prem tier-4)
After=network-online.target
Wants=network-online.target
$( [[ "$ENCRYPTION" != "none" ]] && printf 'Requires=mycure-backup-volume.service\nAfter=mycure-backup-volume.service\n' )
$failure_onfailure

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
Environment=RCLONE_CONFIG=$RCLONE_CONFIG
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$SERVICE_NAME
$notify_start
ExecStart=$RCLONE_BIN sync spaces:$BUCKET/ $BACKUP_DIR/spaces/ \\
  --max-age $MAX_AGE \\
  --transfers $RCLONE_TRANSFERS \\
  --checkers $RCLONE_CHECKERS \\
  --log-level INFO \\
  --stats 5m \\
  --stats-one-line
$notify_success

# Hard cap so a runaway sync doesn't burn an entire day.
TimeoutStartSec=8h
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

[Install]
WantedBy=multi-user.target
UNIT

# Sibling unit fired via OnFailure= when the mirror service fails.
# Runs the notifier as root so it can read $WEBHOOK_FILE regardless of
# the failure mode (e.g. service user permission drift). Shares the
# same log namespace so all related events show up in one query.
cat > "$SYSTEMD_DIR/${SERVICE_NAME}-failure.service" <<UNIT
[Unit]
Description=Notify on failure of $SERVICE_NAME.service

[Service]
Type=oneshot
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=${SERVICE_NAME}-failure
ExecStart=$NOTIFY_BIN failure
UNIT

# ---------- verify helper + service + timer ----------
# Weekly Kopia repository integrity check. Connects to the mirrored repo
# (idempotent — connect is a no-op if already connected) and runs
# `kopia content verify --verify-files-percent=N`, which fetches a
# random sample of blobs and revalidates their checksums. Catches
# bit-rot, missing blobs, and password drift on cheap commodity.
log "installing verify helper at $VERIFY_BIN"
install -m 0755 /dev/stdin "$VERIFY_BIN" <<VERIFY
#!/usr/bin/env bash
# Layer 1 integrity check: bring the on-prem mirror fully up to date
# from upstream, then verify every local file's bytes against the
# upstream copy. The sync-then-check pair eliminates "mirror lag" false
# positives — after a fresh sync, any remaining differences are real
# corruption, not just files that were updated upstream since the last
# nightly sync.
#
# Catches:
#   - bit-rot on the local disk
#   - accidental local modifications
#   - mirror desync that produced corrupted (not just missing) files
#
# Does NOT validate Kopia repo internal consistency. Velero writes its
# Kopia repos via S3 in a flat layout that \`kopia connect filesystem\`
# rejects (kopia/kopia#2065), and the rclone-serve-s3 + kopia-connect-s3
# workaround stalls on large repos with HDD-backed mirrors. Structural
# validation is the quarterly restore drill in RESTORE_FROM_ONPREM.md.
set -euo pipefail

MIRROR_ROOT=$BACKUP_DIR/spaces
BUCKET=$BUCKET
RCLONE_CONFIG=$RCLONE_CONFIG
RCLONE_BIN=$RCLONE_BIN

[[ -d "\$MIRROR_ROOT" ]] || { echo "missing \$MIRROR_ROOT (no successful mirror run yet?)" >&2; exit 1; }
[[ -r "\$RCLONE_CONFIG" ]] || { echo "missing \$RCLONE_CONFIG" >&2; exit 1; }

# Step 1 — sync first so any pending upstream changes land locally.
# This closes the "lag" gap that would otherwise show up as false
# differences in the check below.
echo "==> pre-verify sync"
"\$RCLONE_BIN" sync "spaces:\$BUCKET" "\$MIRROR_ROOT" \\
  --config "\$RCLONE_CONFIG" \\
  --transfers 4 \\
  --checkers 8 \\
  --stats 1m --stats-one-line

# Step 2 — hash check. rclone check --combined emits one line per object:
#   = identical
#   - in src (remote) only — should be ~0 right after a sync
#   + in dst (local) only — unexpected (mirror retains extras)
#   * present in both but differ — CORRUPTION
#   ! read error — I/O FAULT
echo ""
echo "==> integrity check"
report=\$(mktemp)
trap 'rm -f "\$report"' EXIT

"\$RCLONE_BIN" check "spaces:\$BUCKET" "\$MIRROR_ROOT" \\
  --config "\$RCLONE_CONFIG" \\
  --checksum \\
  --combined "\$report" \\
  --transfers 4 \\
  --checkers 8 \\
  --stats 1m --stats-one-line || true   # exit code reflects ANY diff; we reinterpret

identical=\$(grep -c '^= ' "\$report" || true)
remote_only=\$(grep -c '^- ' "\$report" || true)
local_only=\$(grep -c '^+ ' "\$report" || true)
differ=\$(grep -c '^\* ' "\$report" || true)
errored=\$(grep -c '^! ' "\$report" || true)

echo ""
echo "==> summary"
printf "  identical   : %s\n" "\$identical"
printf "  remote-only : %s   (post-sync race, should be 0; small numbers OK)\n" "\$remote_only"
printf "  local-only  : %s\n" "\$local_only"
printf "  differ      : %s   (CORRUPTION)\n" "\$differ"
printf "  errored     : %s   (I/O FAULT)\n" "\$errored"

if [[ "\$differ" -gt 0 ]]; then
  echo ""
  echo "first 20 differ entries:" >&2
  grep '^\* ' "\$report" | head -20 >&2
fi
if [[ "\$errored" -gt 0 ]]; then
  echo ""
  echo "first 20 error entries:" >&2
  grep '^! ' "\$report" | head -20 >&2
fi

if [[ "\$differ" -gt 0 ]] || [[ "\$errored" -gt 0 ]]; then
  exit 1
fi
exit 0
VERIFY

log "writing systemd unit $VERIFY_SERVICE_NAME.service"
case "$NOTIFY_ON" in
  both)          v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_success="ExecStartPost=$NOTIFY_BIN verify-success"; v_onfailure="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  success-only)  v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_success="ExecStartPost=$NOTIFY_BIN verify-success"; v_onfailure="" ;;
  failure-only)  v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_success="";                                          v_onfailure="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  off)           v_start="";                                       v_success="";                                          v_onfailure="" ;;
esac

cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.service" <<UNIT
[Unit]
Description=Verify integrity of the on-prem Kopia backup repository
After=network-online.target
Wants=network-online.target
$v_onfailure

[Service]
Type=oneshot
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$VERIFY_SERVICE_NAME
$v_start
ExecStart=$VERIFY_BIN
$v_success

TimeoutStartSec=1h
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

log "writing systemd timer $VERIFY_SERVICE_NAME.timer"
cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Weekly timer for Mycure on-prem backup verification

[Timer]
OnCalendar=$VERIFY_TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=30m
Unit=$VERIFY_SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

log "writing systemd timer $SERVICE_NAME.timer"
cat > "$SYSTEMD_DIR/$SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Daily timer for Mycure on-prem backup mirror

[Timer]
OnCalendar=$TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=10m
Unit=$SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

# ---------- credential validation (dry-run) ----------
log "validating credentials with rclone lsd …"
if ! sudo -u "$SERVICE_USER" RCLONE_CONFIG="$RCLONE_CONFIG" \
      rclone lsd "spaces:$BUCKET/" >/dev/null 2>&1; then
  err "rclone failed to list spaces:$BUCKET — check SPACES_ACCESS_KEY/SECRET and bucket name"
fi
log "credentials OK"

# ---------- enable + start timer ----------
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.timer" >/dev/null
log "$SERVICE_NAME.timer enabled"
systemctl enable --now "$VERIFY_SERVICE_NAME.timer" >/dev/null
log "$VERIFY_SERVICE_NAME.timer enabled"

# ---------- summary ----------
echo
log "setup complete — summary:"
echo "  encryption    : $ENCRYPTION"
[[ "$ENCRYPTION" == "luks-partition" ]] && echo "  luks device   : $LUKS_DEVICE"
[[ "$ENCRYPTION" == "luks-file"      ]] && echo "  luks file     : $BACKUP_DIR.img ($LUKS_FILE_SIZE)"
echo "  backup dir    : $BACKUP_DIR"
echo "  bucket        : spaces:$BUCKET ($REGION)"
echo "  service user  : $SERVICE_USER"
echo "  retention ref : ${RETENTION_DAYS}d (rclone --max-age=$MAX_AGE)"
echo "  mirror timer  : $TIMER_ON_CALENDAR"
mirror_next=$(systemctl list-timers --no-legend --no-pager "$SERVICE_NAME.timer" 2>/dev/null | awk '{print $1, $2, $3}' | head -1)
echo "  next mirror   : ${mirror_next:-see: systemctl list-timers}"
echo "  verify timer  : $VERIFY_TIMER_ON_CALENDAR  (verifies ${VERIFY_FILES_PERCENT}% of blobs)"
verify_next=$(systemctl list-timers --no-legend --no-pager "$VERIFY_SERVICE_NAME.timer" 2>/dev/null | awk '{print $1, $2, $3}' | head -1)
echo "  next verify   : ${verify_next:-see: systemctl list-timers}"
if [[ -f "$WEBHOOK_FILE" ]]; then
  echo "  notifications : Discord webhook configured (mode: $NOTIFY_ON)"
else
  echo "  notifications : disabled (set DISCORD_WEBHOOK_URL to enable)"
fi
echo
echo "Verify:"
echo "  systemctl status $SERVICE_NAME.timer $VERIFY_SERVICE_NAME.timer"
echo "  sudo -u $SERVICE_USER rclone --config $RCLONE_CONFIG size spaces:$BUCKET"
echo "  sudo systemctl start $SERVICE_NAME.service   # trigger mirror now"
echo "  sudo systemctl start $VERIFY_SERVICE_NAME.service   # trigger verify now (needs ≥1 successful mirror)"
echo "  sudo journalctl --namespace=$LOG_NAMESPACE -u $SERVICE_NAME.service -f"
echo "  sudo journalctl --namespace=$LOG_NAMESPACE -u $VERIFY_SERVICE_NAME.service -f"

# Fire a one-shot test notification on first-time-with-webhook installs so the
# operator can confirm the channel is wired up before the first scheduled run.
if [[ -f "$WEBHOOK_FILE" ]] && [[ "$NOTIFY_ON" != "off" ]]; then
  log "sending test notification to Discord…"
  "$NOTIFY_BIN" test "setup script completed on $(hostname -f 2>/dev/null || hostname)" || warn "test notification failed (non-fatal)"
fi
