#!/usr/bin/env sh
# Self-check for the maestroapp promote Job script (mono#4095, PR #417 review round 2).
#
# The promote logic lives inside charts/maestroapp/templates/promote-job.yaml as
# a POSIX-sh script in the Job's args. There is no framework here on purpose:
# this one runnable check renders the chart, extracts the exact script, and runs
# it against a STUB `mc` on PATH that simulates a MinIO store on the local
# filesystem (alias/stat/cat/cp) and records every root-pointer write. It fails
# (non-zero) if either invariant breaks:
#
#   (a) missing-middle  — Darwin valid, Linux MISSING, Windows valid  =>
#                         NO platform-root latest.json is written (atomic:
#                         validate-all-before-any-write), Job exits non-zero.
#   (b) drift-reconcile — all v<PIN> manifests valid, one root pointer drifted
#                         to an old version => that root is pulled back to PIN.
#
# Run:  sh charts/maestroapp/tests/promote-selfcheck.sh
# Needs: helm, sh, sed, mkdir/cat (coreutils). No cluster, no real mc/MinIO.
set -eu

PIN=2.1.109
# Order matters for the falsifier: the MISSING platform (linux) sits in the
# MIDDLE, after a valid one (darwin). A non-atomic promoter would already have
# written darwin's root before hitting the missing linux — so a partial write
# is observable here. The atomic design writes nothing.
PLATFORMS="darwin_aarch64 linux_x86_64 windows_x86_64"
BUCKET=artifacts

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chart_dir=$(CDPATH= cd -- "$here/.." && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- extract the real script from the rendered chart -------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

script="$work/promote.sh"
helm template "$chart_dir" --set version="$PIN" --set global.nodePool=prod-apps >"$work/rendered.yaml" 2>"$work/helm.err" \
  || { cat "$work/helm.err" >&2; fail "helm template failed"; }
# Grab the Job container's inline script (between `- |` and the next `env:` key).
sed -n '/            - |/,/          env:/p' "$work/rendered.yaml" \
  | sed '1d;$d' | sed 's/^              //' >"$script"
[ -s "$script" ] || fail "could not extract promote script from rendered chart"
sh -n "$script" || fail "extracted script is not valid POSIX sh"

# --- stub `mc` + `sleep` on PATH ---------------------------------------------
# The stub maps `store/<bucket>/<path>` onto $STORE_ROOT/<bucket>/<path> on disk.
# `sleep` is a no-op so the script's bounded retry loop runs instantly.
bin="$work/bin"
mkdir -p "$bin"

cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF

cat >"$bin/mc" <<'EOF'
#!/usr/bin/env sh
# Minimal MinIO client stub. Store root comes from $STORE_ROOT.
# Path form used by the script: store/<bucket>/<key>
set -eu
sub=$1; shift
resolve() { printf '%s/%s\n' "$STORE_ROOT" "${1#store/}"; }
case "$sub" in
  alias)  exit 0 ;;                                  # alias set store ...
  stat)   p=$(resolve "$1"); [ -f "$p" ] ;;          # exit 1 if absent
  cat)    p=$(resolve "$1"); cat "$p" ;;             # errors if absent (real mc does too)
  cp)     s=$(resolve "$1"); d=$(resolve "$2")
          mkdir -p "$(dirname "$d")"; cp "$s" "$d"
          # record the write for the harness to assert on
          echo "$2" >>"$WRITES_LOG" ;;
  *)      echo "stub mc: unsupported subcommand '$sub'" >&2; exit 2 ;;
esac
EOF
chmod +x "$bin/mc" "$bin/sleep"

# seed a versioned + root manifest on disk
seed_manifest() { # <path-under-store> <version>
  p="$STORE/$1"; mkdir -p "$(dirname "$p")"
  printf '{"version":"%s"}\n' "$2" >"$p"
}
root_version() { # <platform>  -> prints version in the platform-root latest.json (empty if absent)
  f="$STORE/$BUCKET/maestroapp/desktop/$1/latest.json"
  [ -f "$f" ] && sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n1 || true
}

run_script() { # runs the extracted script in a fresh store env; sets rc
  set +e
  env PATH="$bin:$PATH" \
      MC_CONFIG_DIR="$work/.mc" \
      STORE_ROOT="$STORE" WRITES_LOG="$WRITES_LOG" \
      PIN="$PIN" PLATFORMS="$PLATFORMS" BUCKET="$BUCKET" \
      STORE_ENDPOINT="http://stub:9000" STORE_USER="u" STORE_PASSWORD="p" \
      sh "$script" >"$work/out.log" 2>&1
  rc=$?
  set -e
}

# ============================================================================
# (a) missing-middle: linux MISSING => atomic abort, ZERO root writes
# ============================================================================
STORE="$work/store_a"; WRITES_LOG="$work/writes_a"; : >"$WRITES_LOG"; mkdir -p "$STORE"
seed_manifest "$BUCKET/maestroapp/desktop/darwin_aarch64/v$PIN/latest.json"  "$PIN"
# linux_x86_64 v$PIN intentionally NOT published (the missing MIDDLE platform)
seed_manifest "$BUCKET/maestroapp/desktop/windows_x86_64/v$PIN/latest.json" "$PIN"
# pre-existing root pointers on an OLD version — must stay untouched
seed_manifest "$BUCKET/maestroapp/desktop/darwin_aarch64/latest.json"  "2.1.108"
seed_manifest "$BUCKET/maestroapp/desktop/linux_x86_64/latest.json"    "2.1.108"
seed_manifest "$BUCKET/maestroapp/desktop/windows_x86_64/latest.json"  "2.1.108"

run_script
[ "$rc" -ne 0 ] || { cat "$work/out.log"; fail "(a) expected non-zero exit on missing platform, got 0"; }
if [ -s "$WRITES_LOG" ]; then
  echo "--- writes recorded ---"; cat "$WRITES_LOG"
  fail "(a) PARTIAL PROMOTION: root pointer(s) written despite a missing platform"
fi
for p in $PLATFORMS; do
  v=$(root_version "$p")
  [ "$v" = "2.1.108" ] || fail "(a) root pointer for $p changed to '$v' (expected untouched 2.1.108)"
done
echo "PASS (a) missing-middle: 0 root writes, all roots still 2.1.108, exit $rc"

# ============================================================================
# (b) drift-reconcile: all valid, one root drifted => pulled back to PIN
# ============================================================================
STORE="$work/store_b"; WRITES_LOG="$work/writes_b"; : >"$WRITES_LOG"; mkdir -p "$STORE"
for p in $PLATFORMS; do
  seed_manifest "$BUCKET/maestroapp/desktop/$p/v$PIN/latest.json" "$PIN"
  seed_manifest "$BUCKET/maestroapp/desktop/$p/latest.json"       "$PIN"   # already at pin
done
# now DRIFT one root pointer away from the pin
seed_manifest "$BUCKET/maestroapp/desktop/windows_x86_64/latest.json" "2.0.999"

run_script
[ "$rc" -eq 0 ] || { cat "$work/out.log"; fail "(b) expected clean exit, got $rc"; }
for p in $PLATFORMS; do
  v=$(root_version "$p")
  [ "$v" = "$PIN" ] || fail "(b) root pointer for $p is '$v' after reconcile (expected $PIN)"
done
grep -q "windows_x86_64/latest.json" "$WRITES_LOG" \
  || fail "(b) drifted windows root was not re-written"
echo "PASS (b) drift-reconcile: windows root pulled 2.0.999 -> $PIN, all roots at $PIN, exit $rc"

echo "ALL CHECKS PASSED"
