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
RCLONE_TRANSFERS=2
RCLONE_CHECKERS=4
NOTIFY_ON=both                                  # both | failure-only | success-only | off

CONFIG_DIR=/etc/mycure-backup
RCLONE_CONFIG=/etc/rclone/rclone.conf
LOG_FILE=/var/log/mycure-backup-mirror.log
SERVICE_NAME=mycure-backup-mirror
SYSTEMD_DIR=/etc/systemd/system
NOTIFY_BIN=/usr/local/sbin/mycure-backup-notify
WEBHOOK_FILE=$CONFIG_DIR/discord-webhook.url

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
log "ensuring dependencies (rclone, kopia)…"
apt-get update -qq
apt-get install -y -qq rclone curl ca-certificates cryptsetup-bin >/dev/null

if ! command -v kopia >/dev/null || ! kopia --version 2>/dev/null | grep -q "$KOPIA_VERSION"; then
  log "installing kopia v$KOPIA_VERSION…"
  arch=$(uname -m)
  case "$arch" in
    x86_64)  kopia_arch=x64;;
    aarch64) kopia_arch=arm64;;
    *) err "unsupported architecture for kopia: $arch";;
  esac
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
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
mkdir -p "$CONFIG_DIR"
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

# ---------- log file ----------
touch "$LOG_FILE"
chown "$SERVICE_USER:$SERVICE_USER" "$LOG_FILE"
chmod 0640 "$LOG_FILE"

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
# Send a Discord webhook notification about the on-prem backup mirror.
# Usage: mycure-backup-notify success|failure|test [extra_message]
# Silent no-op if /etc/mycure-backup/discord-webhook.url is missing/empty.
set -euo pipefail

WEBHOOK_FILE=/etc/mycure-backup/discord-webhook.url
LOG_FILE=/var/log/mycure-backup-mirror.log
SERVICE_NAME=mycure-backup-mirror

[[ -r "$WEBHOOK_FILE" ]] || exit 0
url=$(<"$WEBHOOK_FILE")
[[ -n "$url" ]] || exit 0

case "${1:-}" in
  success) title=":white_check_mark: On-prem backup mirror succeeded"; color=3066993 ;;
  failure) title=":x: On-prem backup mirror FAILED"; color=15158332 ;;
  test)    title=":bell: On-prem backup mirror — test notification"; color=10181046 ;;
  *)       title="On-prem backup mirror: ${1:-unknown}"; color=8421504 ;;
esac

extra="${2:-}"
hostname=$(hostname -f 2>/dev/null || hostname)
timestamp=$(date -u -Iseconds 2>/dev/null || date -u +%FT%TZ)

# Try to pull a few useful stats from the most recent journal entry for the
# service so the message is informative.
elapsed="unknown"
mirrored="see log"
if command -v systemctl >/dev/null; then
  # ActiveEnterTimestamp - InactiveEnterTimestamp gives the run duration.
  start_ts=$(systemctl show "$SERVICE_NAME.service" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  end_ts=$(systemctl show "$SERVICE_NAME.service" -p InactiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  if [[ "$end_ts" -gt "$start_ts" ]] && [[ "$start_ts" -gt 0 ]]; then
    delta_us=$((end_ts - start_ts))
    elapsed=$(awk -v u="$delta_us" 'BEGIN{s=u/1000000; printf (s>=3600)?"%dh%dm":(s>=60)?"%dm%ds":"%ds", (s>=3600)?int(s/3600):(s>=60)?int(s/60):int(s), (s>=3600)?int((s%3600)/60):(s>=60)?int(s%60):0}')
  fi
fi
if [[ -r /var/backups/mycure/spaces ]]; then
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
    '{username:"mycure-backup",embeds:[{title:$title,color:$color,timestamp:$ts,fields:(
       [
         {name:"Host",value:$host,inline:true},
         {name:"Duration",value:$elapsed,inline:true},
         {name:"Mirrored",value:$mirrored,inline:true}
       ]
       + (if $extra == "" then [] else [{name:"Note",value:$extra,inline:false}] end)
     )}]}')
else
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  payload=$(printf '{"username":"mycure-backup","embeds":[{"title":"%s","color":%d,"timestamp":"%s","fields":[{"name":"Host","value":"%s","inline":true},{"name":"Duration","value":"%s","inline":true},{"name":"Mirrored","value":"%s","inline":true}]}]}' \
    "$(esc "$title")" "$color" "$timestamp" "$(esc "$hostname")" "$(esc "$elapsed")" "$(esc "$mirrored")")
fi

curl -sS -m 15 -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null || true
NOTIFY

# ---------- systemd service + timer ----------
log "writing systemd unit $SERVICE_NAME.service"
# ExecStartPost only fires on ExecStart success → success notification.
# OnFailure= triggers a sibling unit → failure notification.
case "$NOTIFY_ON" in
  both)          notify_success="ExecStartPost=$NOTIFY_BIN success"; failure_onfailure="OnFailure=${SERVICE_NAME}-failure.service" ;;
  success-only)  notify_success="ExecStartPost=$NOTIFY_BIN success"; failure_onfailure="" ;;
  failure-only)  notify_success="";                                  failure_onfailure="OnFailure=${SERVICE_NAME}-failure.service" ;;
  off)           notify_success="";                                  failure_onfailure="" ;;
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
ExecStart=/usr/bin/rclone sync spaces:$BUCKET/ $BACKUP_DIR/spaces/ \\
  --max-age $MAX_AGE \\
  --transfers $RCLONE_TRANSFERS \\
  --checkers $RCLONE_CHECKERS \\
  --log-file=$LOG_FILE \\
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
# the failure mode (e.g. service user permission drift).
cat > "$SYSTEMD_DIR/${SERVICE_NAME}-failure.service" <<UNIT
[Unit]
Description=Notify on failure of $SERVICE_NAME.service

[Service]
Type=oneshot
ExecStart=$NOTIFY_BIN failure
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
echo "  timer         : $TIMER_ON_CALENDAR"
next_run=$(systemctl list-timers --no-legend --no-pager "$SERVICE_NAME.timer" 2>/dev/null | awk '{print $1, $2, $3}' | head -1)
echo "  next run      : ${next_run:-see: systemctl list-timers}"
if [[ -f "$WEBHOOK_FILE" ]]; then
  echo "  notifications : Discord webhook configured (mode: $NOTIFY_ON)"
else
  echo "  notifications : disabled (set DISCORD_WEBHOOK_URL to enable)"
fi
echo
echo "Verify:"
echo "  systemctl status $SERVICE_NAME.timer"
echo "  sudo -u $SERVICE_USER rclone --config $RCLONE_CONFIG size spaces:$BUCKET"
echo "  sudo systemctl start $SERVICE_NAME.service   # trigger now"
echo "  journalctl -u $SERVICE_NAME.service -f"

# Fire a one-shot test notification on first-time-with-webhook installs so the
# operator can confirm the channel is wired up before the first scheduled run.
if [[ -f "$WEBHOOK_FILE" ]] && [[ "$NOTIFY_ON" != "off" ]]; then
  log "sending test notification to Discord…"
  "$NOTIFY_BIN" test "setup script completed on $(hostname -f 2>/dev/null || hostname)" || warn "test notification failed (non-fatal)"
fi
