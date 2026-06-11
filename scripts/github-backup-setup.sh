#!/usr/bin/env bash
# Sets up an off-cloud backup of an entire GitHub organization on a
# Debian/Ubuntu host.
#
# Wraps josegonzalez/python-github-backup (the `github-backup` tool) in a
# systemd timer. Pulls every repo in the org — code (bare/mirror clones,
# all refs), wikis, issues, pull requests + comments/reviews, releases +
# assets, labels, milestones, hooks — to a local directory, incrementally.
# A weekly verify pass runs `git fsck` across every mirrored repo so silent
# corruption is caught the same way the data mirror's weekly `rclone check`
# does.
#
# This is the source-code analogue of scripts/onprem-backup-setup.sh: where
# that mirrors production *data* (Velero/Kopia in DO Spaces) to an off-cloud
# host, this mirrors the org's *repositories* off GitHub.
#
# Idempotent. Re-running with the same flags reconciles; re-running with
# different flags reconfigures.
#
# Usage:
#   sudo GITHUB_TOKEN=… scripts/github-backup-setup.sh [flags]
#
# See docs/operations/GITHUB_BACKUP_SETUP.md for the full runbook.

set -euo pipefail

# ---------- defaults ----------
ORG=mycurelabs
BACKUP_DIR=/var/backups/mycure-github
SERVICE_USER=mycure-ghbackup
TIMER_ON_CALENDAR="*-*-* 02:00:00 UTC"
VERIFY_TIMER_ON_CALENDAR="Sun *-*-* 04:00:00 UTC"
GITHUB_BACKUP_VERSION=0.62.1
INCLUDE_LFS=0
INCLUDE_FORKS=0
THROTTLE_LIMIT=5000
THROTTLE_PAUSE=0.72
NOTIFY_ON=both                                  # both | failure-only | success-only | off

CONFIG_DIR=/etc/mycure-github-backup
TOKEN_FILE=$CONFIG_DIR/token
VENV_DIR=/opt/mycure-github-backup/venv
SERVICE_NAME=mycure-github-backup
VERIFY_SERVICE_NAME=mycure-github-backup-verify
RUN_BIN=/usr/local/sbin/mycure-github-backup-run
VERIFY_BIN=/usr/local/sbin/mycure-github-backup-verify
NOTIFY_BIN=/usr/local/sbin/mycure-github-backup-notify
SYSTEMD_DIR=/etc/systemd/system
WEBHOOK_FILE=$CONFIG_DIR/discord-webhook.url
REPO_COUNT_FILE=$CONFIG_DIR/repo-count.baseline
LOG_NAMESPACE=mycure-github-backup
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
Usage: sudo GITHUB_TOKEN=… $0 [flags]

Flags:
  --org=NAME                  GitHub organization to back up   (default: $ORG)
  --backup-dir=PATH           backup target directory          (default: $BACKUP_DIR)
  --service-user=USER         system user that runs the backup (default: $SERVICE_USER)
  --timer-on-calendar=S       systemd OnCalendar= for backup   (default: "$TIMER_ON_CALENDAR")
  --verify-timer-on-calendar=S systemd OnCalendar= for verify  (default: "$VERIFY_TIMER_ON_CALENDAR")
  --github-backup-version=VER github-backup PyPI version        (default: $GITHUB_BACKUP_VERSION)
  --include-lfs               also pull Git LFS objects (slower)
  --include-forks             also back up forked repos
  --throttle-limit=N          github-backup --throttle-limit    (default: $THROTTLE_LIMIT)
  --throttle-pause=SEC        github-backup --throttle-pause    (default: $THROTTLE_PAUSE)
  --notify-on=MODE            both | failure-only | success-only | off  (default: $NOTIFY_ON)
  -h, --help                  this help

Environment (required):
  GITHUB_TOKEN            Dedicated classic PAT with scopes: repo, read:org,
                          read:discussion. Stored root-owned at $TOKEN_FILE
                          and scrubbed from the environment after.

Environment (optional):
  DISCORD_WEBHOOK_URL     Discord webhook for backup notifications. If set, the
                          script installs a notifier and writes the URL to
                          $WEBHOOK_FILE so the timer can use it. If unset, no
                          notifier is configured and any previously stored URL
                          is left intact (pass an empty string to clear it).
EOF
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org=*)                      ORG="${1#*=}";                       shift;;
    --backup-dir=*)               BACKUP_DIR="${1#*=}";                shift;;
    --service-user=*)             SERVICE_USER="${1#*=}";              shift;;
    --timer-on-calendar=*)        TIMER_ON_CALENDAR="${1#*=}";         shift;;
    --verify-timer-on-calendar=*) VERIFY_TIMER_ON_CALENDAR="${1#*=}";  shift;;
    --github-backup-version=*)    GITHUB_BACKUP_VERSION="${1#*=}";     shift;;
    --include-lfs)                INCLUDE_LFS=1;                       shift;;
    --include-forks)              INCLUDE_FORKS=1;                     shift;;
    --throttle-limit=*)           THROTTLE_LIMIT="${1#*=}";            shift;;
    --throttle-pause=*)           THROTTLE_PAUSE="${1#*=}";            shift;;
    --notify-on=*)                NOTIFY_ON="${1#*=}";                 shift;;
    --discord-webhook-url=*)      DISCORD_WEBHOOK_URL="${1#*=}";       shift;;
    -h|--help)                    usage; exit 0;;
    *) err "unknown flag: $1 (see --help)";;
  esac
done

case "$NOTIFY_ON" in
  both|failure-only|success-only|off) ;;
  *) err "--notify-on must be one of: both | failure-only | success-only | off";;
esac

# ---------- preflight ----------
need_root

: "${GITHUB_TOKEN:?GITHUB_TOKEN env var is required (dedicated PAT: repo, read:org, read:discussion)}"

command -v apt-get >/dev/null || err "this script targets apt-based distros only"

# ---------- install dependencies ----------
log "ensuring dependencies (git, python3, python3-venv, curl, jq)…"
# A flaky/partial `apt-get update` (e.g. an unrelated third-party repo with a
# stale key, or a mirror mid-sync) shouldn't block the install — apt falls
# back to cached indices. Only the install itself is allowed to be fatal.
apt-get update -qq || warn "apt-get update reported errors; using cached package indices"
apt-get install -y -qq git python3 python3-venv python3-pip curl ca-certificates jq >/dev/null

# github-backup needs Python >= 3.10.
pyver=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
pymajor=${pyver%%.*}; pyminor=${pyver##*.}
if (( pymajor < 3 || (pymajor == 3 && pyminor < 10) )); then
  err "github-backup requires Python >= 3.10; this host has $pyver"
fi

if [[ "$INCLUDE_LFS" -eq 1 ]]; then
  log "installing git-lfs (--include-lfs given)…"
  apt-get install -y -qq git-lfs >/dev/null
  git lfs install --system >/dev/null 2>&1 || true
fi

# ---------- github-backup venv (pinned) ----------
# Install into a dedicated venv so we don't touch the system Python (Ubuntu
# 24.04 marks it externally-managed, PEP 668). Re-running reconciles to the
# pinned version.
installed_ver=""
if [[ -x "$VENV_DIR/bin/github-backup" ]]; then
  installed_ver=$("$VENV_DIR/bin/pip" show github-backup 2>/dev/null | awk '/^Version:/{print $2}')
fi
if [[ "$installed_ver" != "$GITHUB_BACKUP_VERSION" ]]; then
  log "installing github-backup==$GITHUB_BACKUP_VERSION into $VENV_DIR…"
  mkdir -p "$(dirname "$VENV_DIR")"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install --quiet "github-backup==$GITHUB_BACKUP_VERSION"
else
  log "github-backup==$GITHUB_BACKUP_VERSION already installed"
fi

# ---------- service user ----------
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  log "creating system user $SERVICE_USER…"
  useradd --system --no-create-home --shell /usr/sbin/nologin --user-group "$SERVICE_USER"
fi

# ---------- config + backup directories ----------
# Config dir must be traversable by the service user so it can read the
# token and webhook URL at runtime. Group-owned by the service user, 0750.
mkdir -p "$CONFIG_DIR"
chgrp "$SERVICE_USER" "$CONFIG_DIR"
chmod 0750 "$CONFIG_DIR"

log "creating backup directory at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$BACKUP_DIR"
chmod 0750 "$BACKUP_DIR"

# ---------- github token ----------
log "writing GitHub token to $TOKEN_FILE"
umask 077
printf '%s' "$GITHUB_TOKEN" > "$TOKEN_FILE"
umask 022
chgrp "$SERVICE_USER" "$TOKEN_FILE"
chmod 0640 "$TOKEN_FILE"

# Scrub the env so accidental subshells don't see the secret.
TOKEN_FOR_CHECK="$GITHUB_TOKEN"
unset GITHUB_TOKEN

# ---------- journald namespace (bounded log volume) ----------
log "configuring bounded journal namespace $LOG_NAMESPACE (≤ $JOURNAL_MAX_USE)"
cat > "$JOURNALD_NAMESPACE_CONFIG" <<JOURNAL
# Bounded journal for the $LOG_NAMESPACE namespace. systemd spawns
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

# ---------- notify helper script ----------
log "installing notifier at $NOTIFY_BIN"
install -m 0755 /dev/stdin "$NOTIFY_BIN" <<NOTIFY
#!/usr/bin/env bash
# Send a Discord webhook notification about the GitHub org backup or the
# weekly repo integrity verification.
# Usage: $(basename "$NOTIFY_BIN") KIND [extra_message]
#   KIND ∈ start|success|failure|verify-start|verify-success|verify-failure|test
# Silent no-op if $WEBHOOK_FILE is missing/empty.
set -euo pipefail

WEBHOOK_FILE=$WEBHOOK_FILE
BACKUP_DIR=$BACKUP_DIR

[[ -r "\$WEBHOOK_FILE" ]] || exit 0
url=\$(<"\$WEBHOOK_FILE")
[[ -n "\$url" ]] || exit 0

# kind -> (title, color, want_duration, want_repos, service_name)
kind="\${1:-}"
case "\$kind" in
  start)          title=":hourglass_flowing_sand: GitHub org backup started"; color=3447003;  want_duration=0; want_repos=0; SERVICE_NAME=$SERVICE_NAME ;;
  success)        title=":white_check_mark: GitHub org backup succeeded";     color=3066993;  want_duration=1; want_repos=1; SERVICE_NAME=$SERVICE_NAME ;;
  failure)        title=":x: GitHub org backup FAILED";                       color=15158332; want_duration=1; want_repos=1; SERVICE_NAME=$SERVICE_NAME ;;
  verify-start)   title=":mag: GitHub backup verification started";           color=3447003;  want_duration=0; want_repos=0; SERVICE_NAME=$VERIFY_SERVICE_NAME ;;
  verify-success) title=":white_check_mark: GitHub backup verification passed"; color=3066993; want_duration=1; want_repos=1; SERVICE_NAME=$VERIFY_SERVICE_NAME ;;
  verify-failure) title=":rotating_light: GitHub backup verification FAILED";  color=15158332; want_duration=1; want_repos=1; SERVICE_NAME=$VERIFY_SERVICE_NAME ;;
  test)           title=":bell: GitHub org backup — test notification";       color=10181046; want_duration=0; want_repos=0; SERVICE_NAME=$SERVICE_NAME ;;
  *)              title="GitHub org backup: \${kind:-unknown}";               color=8421504;  want_duration=1; want_repos=1; SERVICE_NAME=$SERVICE_NAME ;;
esac

extra="\${2:-}"
hostname=\$(hostname -f 2>/dev/null || hostname)
timestamp=\$(date -u -Iseconds 2>/dev/null || date -u +%FT%TZ)

elapsed="unknown"
repos="see log"
size="see log"
if [[ "\$want_duration" == "1" ]] && command -v systemctl >/dev/null; then
  start_ts=\$(systemctl show "\$SERVICE_NAME.service" -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  end_ts=\$(systemctl show "\$SERVICE_NAME.service" -p InactiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
  if [[ "\$end_ts" -gt "\$start_ts" ]] && [[ "\$start_ts" -gt 0 ]]; then
    delta_us=\$((end_ts - start_ts))
    elapsed=\$(awk -v u="\$delta_us" 'BEGIN{s=u/1000000; printf (s>=3600)?"%dh%dm":(s>=60)?"%dm%ds":"%ds", (s>=3600)?int(s/3600):(s>=60)?int(s/60):int(s), (s>=3600)?int((s%3600)/60):(s>=60)?int(s%60):0}')
  fi
fi
if [[ "\$want_repos" == "1" ]] && [[ -d "\$BACKUP_DIR" ]]; then
  repos=\$(find "\$BACKUP_DIR" -type d -name repository -prune 2>/dev/null | wc -l | tr -d ' ')
  [[ "\$repos" -gt 0 ]] || repos="see log"
  size=\$(du -sh "\$BACKUP_DIR" 2>/dev/null | awk '{print \$1}')
  [[ -n "\$size" ]] || size="see log"
fi

if command -v jq >/dev/null; then
  payload=\$(jq -nc \\
    --arg title "\$title" --argjson color "\$color" \\
    --arg host "\$hostname" --arg ts "\$timestamp" \\
    --arg elapsed "\$elapsed" --arg repos "\$repos" --arg size "\$size" \\
    --arg extra "\$extra" \\
    --argjson want_duration "\$want_duration" \\
    --argjson want_repos "\$want_repos" \\
    '{username:"mycure-github-backup",embeds:[{title:\$title,color:\$color,timestamp:\$ts,fields:(
       [{name:"Host",value:\$host,inline:true}]
       + (if \$want_duration == 1 then [{name:"Duration",value:\$elapsed,inline:true}] else [] end)
       + (if \$want_repos == 1 then [{name:"Repos",value:\$repos,inline:true},{name:"Size",value:\$size,inline:true}] else [] end)
       + (if \$extra == ""       then [] else [{name:"Note",value:\$extra,inline:false}] end)
     )}]}')
else
  esc() { printf '%s' "\$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'; }
  fields="{\\"name\\":\\"Host\\",\\"value\\":\\"\$(esc "\$hostname")\\",\\"inline\\":true}"
  [[ "\$want_duration" == "1" ]] && fields+=",{\\"name\\":\\"Duration\\",\\"value\\":\\"\$(esc "\$elapsed")\\",\\"inline\\":true}"
  [[ "\$want_repos" == "1" ]] && fields+=",{\\"name\\":\\"Repos\\",\\"value\\":\\"\$(esc "\$repos")\\",\\"inline\\":true},{\\"name\\":\\"Size\\",\\"value\\":\\"\$(esc "\$size")\\",\\"inline\\":true}"
  [[ -n "\$extra"             ]] && fields+=",{\\"name\\":\\"Note\\",\\"value\\":\\"\$(esc "\$extra")\\",\\"inline\\":false}"
  payload="{\\"username\\":\\"mycure-github-backup\\",\\"embeds\\":[{\\"title\\":\\"\$(esc "\$title")\\",\\"color\\":\$color,\\"timestamp\\":\\"\$timestamp\\",\\"fields\\":[\$fields]}]}"
fi

curl -sS -m 15 -X POST -H 'Content-Type: application/json' -d "\$payload" "\$url" >/dev/null || true
NOTIFY

# ---------- backup runner script ----------
# github-backup's --all is comprehensive but EXCLUDES private repos, forks,
# LFS, and attachments. Most org repos are private, so --private is mandatory;
# --attachments captures issue/PR comment uploads.
log "installing backup runner at $RUN_BIN"
install -m 0755 /dev/stdin "$RUN_BIN" <<RUN
#!/usr/bin/env bash
# Pull the entire $ORG GitHub organization to $BACKUP_DIR using github-backup.
# Captures: code (bare/mirror), wikis, issues, PRs + comments/reviews,
# releases + assets, labels, milestones, hooks, attachments. Incremental.
set -euo pipefail

TOKEN_FILE=$TOKEN_FILE
BACKUP_DIR=$BACKUP_DIR
REPO_COUNT_FILE=$REPO_COUNT_FILE

[[ -r "\$TOKEN_FILE" ]] || { echo "missing/unreadable \$TOKEN_FILE" >&2; exit 1; }

# Build the argument list. --all is comprehensive but excludes private repos,
# attachments, LFS, and forks — add the ones we want explicitly.
args=(
  "$ORG"
  --organization
  --token "\$(cat "\$TOKEN_FILE")"
  --output-directory "\$BACKUP_DIR"
  --all
  --private
  --attachments
  --incremental
  --bare
  --throttle-limit $THROTTLE_LIMIT
  --throttle-pause $THROTTLE_PAUSE
  --log-level info
)
[[ $INCLUDE_LFS   -eq 1 ]] && args+=(--lfs)
[[ $INCLUDE_FORKS -eq 1 ]] && args+=(--fork)

"$VENV_DIR/bin/github-backup" "\${args[@]}"

# Record how many repos we hold so the verify pass can detect an
# unexpected drop (deleted/renamed org, token scope loss, partial run).
# github-backup writes each repo's bare clone to <out>/repositories/<name>/repository.
find "\$BACKUP_DIR" -type d -name repository -prune 2>/dev/null | wc -l | tr -d ' ' > "\$REPO_COUNT_FILE"
echo "repos on disk: \$(cat "\$REPO_COUNT_FILE")"
RUN

# ---------- verify helper script ----------
# Weekly integrity check: git fsck across every mirrored repo, plus a
# repo-count sanity check against the last successful backup's baseline.
# This is the GitHub analogue of the data mirror's weekly rclone check.
log "installing verify helper at $VERIFY_BIN"
install -m 0755 /dev/stdin "$VERIFY_BIN" <<VERIFY
#!/usr/bin/env bash
# Verify the integrity of every mirrored repo under $BACKUP_DIR.
#
# Catches:
#   - on-disk git corruption (bit-rot, truncated objects)
#   - a silent drop in repo count vs the last successful backup
#
# Does NOT re-fetch from GitHub — run the backup service for that.
set -euo pipefail

BACKUP_DIR=$BACKUP_DIR
REPO_COUNT_FILE=$REPO_COUNT_FILE

[[ -d "\$BACKUP_DIR" ]] || { echo "missing \$BACKUP_DIR (no successful backup yet?)" >&2; exit 1; }

# github-backup lays out each repo's bare clone at <name>/repository and its
# wiki (if any) at <name>/wiki. fsck both; count only the repos for the
# baseline comparison (wikis are extra and not every repo has one).
mapfile -t targets < <(find "\$BACKUP_DIR" -type d \( -name repository -o -name wiki \) -prune 2>/dev/null | sort)
repo_total=\$(find "\$BACKUP_DIR" -type d -name repository -prune 2>/dev/null | wc -l | tr -d ' ')
fsck_total=\${#targets[@]}
[[ "\$fsck_total" -gt 0 ]] || { echo "no git repos found under \$BACKUP_DIR" >&2; exit 1; }

echo "==> git fsck across \$fsck_total git repos (\$repo_total repos + wikis)"
bad=0
for r in "\${targets[@]}"; do
  if ! git --git-dir="\$r" fsck --full --strict >/dev/null 2>&1; then
    echo "  CORRUPT: \$r" >&2
    bad=\$((bad + 1))
  fi
done

echo ""
echo "==> repo-count sanity"
baseline="unknown"
[[ -r "\$REPO_COUNT_FILE" ]] && baseline=\$(cat "\$REPO_COUNT_FILE")
echo "  repos now   : \$repo_total"
echo "  last backup : \$baseline"
count_drop=0
if [[ "\$baseline" =~ ^[0-9]+\$ ]] && [[ "\$repo_total" -lt "\$baseline" ]]; then
  echo "  WARNING: repo count dropped \$baseline -> \$repo_total" >&2
  count_drop=1
fi

echo ""
echo "==> summary"
printf "  repos         : %s\n" "\$repo_total"
printf "  git dirs fsck : %s\n" "\$fsck_total"
printf "  corrupt       : %s\n" "\$bad"
printf "  count drop    : %s\n" "\$count_drop"

if [[ "\$bad" -gt 0 ]] || [[ "\$count_drop" -gt 0 ]]; then
  exit 1
fi
exit 0
VERIFY

# ---------- systemd backup service + timer ----------
log "writing systemd unit $SERVICE_NAME.service"
case "$NOTIFY_ON" in
  both)          notify_start="ExecStartPre=-$NOTIFY_BIN start";  notify_success="ExecStartPost=$NOTIFY_BIN success"; failure_onfailure="OnFailure=${SERVICE_NAME}-failure.service" ;;
  success-only)  notify_start="ExecStartPre=-$NOTIFY_BIN start";  notify_success="ExecStartPost=$NOTIFY_BIN success"; failure_onfailure="" ;;
  failure-only)  notify_start="ExecStartPre=-$NOTIFY_BIN start";  notify_success="";                                  failure_onfailure="OnFailure=${SERVICE_NAME}-failure.service" ;;
  off)           notify_start="";                                 notify_success="";                                  failure_onfailure="" ;;
esac

cat > "$SYSTEMD_DIR/$SERVICE_NAME.service" <<UNIT
[Unit]
Description=Back up the $ORG GitHub organization to $BACKUP_DIR
After=network-online.target
Wants=network-online.target
$failure_onfailure

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
LogNamespace=$LOG_NAMESPACE
SyslogIdentifier=$SERVICE_NAME
$notify_start
ExecStart=$RUN_BIN
$notify_success

# Hard cap so a runaway backup doesn't burn an entire day.
TimeoutStartSec=4h
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

log "writing systemd timer $SERVICE_NAME.timer"
cat > "$SYSTEMD_DIR/$SERVICE_NAME.timer" <<UNIT
[Unit]
Description=Daily timer for the $ORG GitHub org backup

[Timer]
OnCalendar=$TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=10m
Unit=$SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

# ---------- systemd verify service + timer ----------
log "writing systemd unit $VERIFY_SERVICE_NAME.service"
case "$NOTIFY_ON" in
  both)          v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_success="ExecStartPost=$NOTIFY_BIN verify-success"; v_onfailure="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  success-only)  v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_success="ExecStartPost=$NOTIFY_BIN verify-success"; v_onfailure="" ;;
  failure-only)  v_start="ExecStartPre=-$NOTIFY_BIN verify-start"; v_success="";                                          v_onfailure="OnFailure=${VERIFY_SERVICE_NAME}-failure.service" ;;
  off)           v_start="";                                       v_success="";                                          v_onfailure="" ;;
esac

cat > "$SYSTEMD_DIR/$VERIFY_SERVICE_NAME.service" <<UNIT
[Unit]
Description=Verify integrity of the on-prem $ORG GitHub backup
$v_onfailure

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
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
Description=Weekly timer for $ORG GitHub backup verification

[Timer]
OnCalendar=$VERIFY_TIMER_ON_CALENDAR
Persistent=true
RandomizedDelaySec=30m
Unit=$VERIFY_SERVICE_NAME.service

[Install]
WantedBy=timers.target
UNIT

# ---------- credential validation (dry-run) ----------
log "validating GitHub token against api.github.com/orgs/$ORG …"
http_code=$(curl -sS -o /dev/null -w '%{http_code}' -m 20 \
  -H "Authorization: Bearer $TOKEN_FOR_CHECK" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/orgs/$ORG" || echo 000)
unset TOKEN_FOR_CHECK
case "$http_code" in
  200) log "credentials OK" ;;
  401) err "GitHub returned 401 — token is invalid or expired" ;;
  403) err "GitHub returned 403 — token lacks scope or is rate-limited (need repo, read:org)" ;;
  404) err "GitHub returned 404 for org '$ORG' — wrong org name, or token can't see it (need read:org)" ;;
  *)   err "GitHub credential check failed (HTTP $http_code) — check token and network" ;;
esac

# ---------- enable + start timers ----------
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME.timer" >/dev/null
log "$SERVICE_NAME.timer enabled"
systemctl enable --now "$VERIFY_SERVICE_NAME.timer" >/dev/null
log "$VERIFY_SERVICE_NAME.timer enabled"

# ---------- summary ----------
echo
log "setup complete — summary:"
echo "  organization  : $ORG"
echo "  backup dir    : $BACKUP_DIR"
echo "  tool          : github-backup==$GITHUB_BACKUP_VERSION ($VENV_DIR)"
echo "  service user  : $SERVICE_USER"
echo "  captures      : code (bare) + wikis + issues + PRs + releases + assets + metadata$( [[ $INCLUDE_LFS -eq 1 ]] && printf ' + LFS' )$( [[ $INCLUDE_FORKS -eq 1 ]] && printf ' + forks' )"
echo "  backup timer  : $TIMER_ON_CALENDAR"
backup_next=$(systemctl list-timers --no-legend --no-pager "$SERVICE_NAME.timer" 2>/dev/null | awk '{print $1, $2, $3}' | head -1)
echo "  next backup   : ${backup_next:-see: systemctl list-timers}"
echo "  verify timer  : $VERIFY_TIMER_ON_CALENDAR"
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
echo "  sudo systemctl start $SERVICE_NAME.service          # trigger backup now"
echo "  sudo systemctl start $VERIFY_SERVICE_NAME.service   # trigger verify now (needs ≥1 successful backup)"
echo "  sudo journalctl --namespace=$LOG_NAMESPACE -u $SERVICE_NAME.service -f"
echo "  sudo journalctl --namespace=$LOG_NAMESPACE -u $VERIFY_SERVICE_NAME.service -f"

# Fire a one-shot test notification on first-time-with-webhook installs.
if [[ -f "$WEBHOOK_FILE" ]] && [[ "$NOTIFY_ON" != "off" ]]; then
  log "sending test notification to Discord…"
  "$NOTIFY_BIN" test "setup script completed on $(hostname -f 2>/dev/null || hostname)" || warn "test notification failed (non-fatal)"
fi
