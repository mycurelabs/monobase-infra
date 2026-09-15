#!/usr/bin/env sh
# Self-check for the maestroapp promote Job script (mono#4095, PR #417).
#
# The promote logic lives in charts/maestroapp/templates/_helpers.tpl
# (maestroapp.promoteScript), rendered verbatim into the Job's args. There is no
# framework here on purpose: this one runnable check renders the chart, extracts
# the exact script from the rendered Job, and runs it against a STUB `mc` on PATH
# that simulates a MinIO store on the local filesystem (alias/stat/cat/cp) and
# records every root-pointer write. It fails (non-zero) if any invariant breaks:
#
#   (a) missing-middle    — darwin valid, linux MISSING, windows valid =>
#                           NO platform-root latest.json is written
#                           (validate-all-before-any-write), exit non-zero.
#   (b) drift-reconcile   — all v<PIN> valid, one root points at an OLD version
#                           => that root is pulled back to PIN.
#   (c) malformed-json    — a v<PIN>/latest.json that is NOT valid JSON but
#                           CONTAINS the "version":"<PIN>" substring is REJECTED
#                           (structural jq parse, not a substring grep): no root
#                           written, exit non-zero. Guards against publishing a
#                           corrupt manifest that a substring check would pass.
#   (d) content-drift     — a root whose version string == PIN but whose BYTES
#                           differ from the pinned v<PIN> manifest is reconciled
#                           (hash compare, not version-string compare).
#   (e) partial-recover   — a copy fails mid-phase => the script still reconciles
#                           the OTHER platforms and exits non-zero, and a SECOND
#                           run (failure cleared) completes the straggler. Proves
#                           a partial failure is recoverable, never wedged.
#   (f) prod-render       — EFFECTIVE-RENDER assertion (not the script, the wiring):
#                           render the PROD deployment overlay through the real
#                           argocd-applications factory + charts/maestroapp and
#                           assert prod actually renders the reconcile CronJob with
#                           the intended schedule ALONGSIDE the promote Job. Guards
#                           against the drift guard being INERT in prod because the
#                           overlay forgot to flip reconcile.enabled (round-4 fix).
#
# Run:  sh charts/maestroapp/tests/promote-selfcheck.sh
# Needs: helm, sh, jq, sha256sum, mktemp, mkdir/cat. No cluster, no real mc/MinIO.
set -eu

PIN=2.1.109
# Order matters for (a)/(e): the MISSING/failing platform (linux) sits in the
# MIDDLE, after a valid one (darwin). A non-atomic-validate promoter would have
# written darwin's root before hitting linux — a partial write is observable.
PLATFORMS="darwin_aarch64 linux_x86_64 windows_x86_64"
BUCKET=artifacts

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chart_dir=$(CDPATH= cd -- "$here/.." && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }

for t in helm jq sha256sum mktemp; do
  command -v "$t" >/dev/null 2>&1 || fail "missing required tool: $t"
done

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
# MC_FAIL_CP_FOR (optional): a platform dir name whose `cp` must FAIL exactly
# once per process, so we can simulate a mid-phase copy failure (falsifier e).
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
          # Inject a one-shot copy failure for a chosen platform (falsifier e).
          if [ -n "${MC_FAIL_CP_FOR:-}" ] && [ ! -f "$STORE_ROOT/.cp_failed" ] \
             && printf '%s' "$2" | grep -q "/${MC_FAIL_CP_FOR}/latest.json$"; then
            : >"$STORE_ROOT/.cp_failed"          # remember we already failed once
            echo "stub mc: injected cp failure for $MC_FAIL_CP_FOR" >&2
            exit 1
          fi
          mkdir -p "$(dirname "$d")"; cp "$s" "$d"
          # record the write for the harness to assert on
          echo "$2" >>"$WRITES_LOG" ;;
  *)      echo "stub mc: unsupported subcommand '$sub'" >&2; exit 2 ;;
esac
EOF
chmod +x "$bin/mc" "$bin/sleep"

# seed a manifest with a given version and OPTIONAL extra content marker so two
# manifests can share a version but differ byte-for-byte. NOTE: uses `_p` (not
# `p`) so it never clobbers a caller's `$p` loop variable (POSIX sh has no
# function-local scope).
seed_manifest() { # <path-under-store> <version> [marker]
  _p="$STORE/$1"; mkdir -p "$(dirname "$_p")"
  if [ "${3:-}" = "" ]; then
    printf '{"version":"%s"}\n' "$2" >"$_p"
  else
    printf '{"version":"%s","content":"%s"}\n' "$2" "$3" >"$_p"
  fi
}
# seed a deliberately MALFORMED manifest that nonetheless CONTAINS the
# "version":"<PIN>" substring (what the old floating-substring check keyed on).
seed_malformed() { # <path-under-store> <version>
  _p="$STORE/$1"; mkdir -p "$(dirname "$_p")"
  # trailing garbage + unclosed brace => not valid JSON; substring present.
  printf '{"version":"%s" GARBAGE not json\n' "$2" >"$_p"
}
root_version() { # <platform> -> version string in the platform-root latest.json
  f="$STORE/$BUCKET/maestroapp/desktop/$1/latest.json"
  [ -f "$f" ] && sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n1 || true
}
root_hash() { # <platform> -> sha256 of the platform-root latest.json (empty if absent)
  f="$STORE/$BUCKET/maestroapp/desktop/$1/latest.json"
  [ -f "$f" ] && sha256sum "$f" | cut -d' ' -f1 || true
}
ver_hash() { # <platform> -> sha256 of the v<PIN>/latest.json
  sha256sum "$STORE/$BUCKET/maestroapp/desktop/$1/v$PIN/latest.json" | cut -d' ' -f1
}

run_script() { # runs the extracted script in a fresh store env; sets rc. arg1=MC_FAIL_CP_FOR
  set +e
  env PATH="$bin:$PATH" \
      MC_CONFIG_DIR="$work/.mc" \
      STORE_ROOT="$STORE" WRITES_LOG="$WRITES_LOG" \
      MC_FAIL_CP_FOR="${1:-}" \
      PIN="$PIN" PLATFORMS="$PLATFORMS" BUCKET="$BUCKET" \
      STORE_ENDPOINT="http://stub:9000" STORE_USER="u" STORE_PASSWORD="p" \
      sh "$script" >"$work/out.log" 2>&1
  rc=$?
  set -e
}

# ============================================================================
# (a) missing-middle: linux MISSING => validate-all abort, ZERO root writes
# ============================================================================
STORE="$work/store_a"; WRITES_LOG="$work/writes_a"; : >"$WRITES_LOG"; mkdir -p "$STORE"
seed_manifest "$BUCKET/maestroapp/desktop/darwin_aarch64/v$PIN/latest.json"  "$PIN"
# linux_x86_64 v$PIN intentionally NOT published (the missing MIDDLE platform)
seed_manifest "$BUCKET/maestroapp/desktop/windows_x86_64/v$PIN/latest.json" "$PIN"
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
# (b) drift-reconcile: all valid, one root drifted to an old version => PIN
# ============================================================================
STORE="$work/store_b"; WRITES_LOG="$work/writes_b"; : >"$WRITES_LOG"; mkdir -p "$STORE"
for p in $PLATFORMS; do
  seed_manifest "$BUCKET/maestroapp/desktop/$p/v$PIN/latest.json" "$PIN"
  seed_manifest "$BUCKET/maestroapp/desktop/$p/latest.json"       "$PIN"   # already at pin
done
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

# ============================================================================
# (c) malformed-json: v<PIN> manifest is NOT JSON but CONTAINS "version":"PIN"
#     => structurally rejected, NO root written, non-zero exit.
# ============================================================================
STORE="$work/store_c"; WRITES_LOG="$work/writes_c"; : >"$WRITES_LOG"; mkdir -p "$STORE"
seed_manifest "$BUCKET/maestroapp/desktop/darwin_aarch64/v$PIN/latest.json"  "$PIN"
# linux's v<PIN> is malformed JSON but contains the version substring:
seed_malformed "$BUCKET/maestroapp/desktop/linux_x86_64/v$PIN/latest.json"   "$PIN"
seed_manifest "$BUCKET/maestroapp/desktop/windows_x86_64/v$PIN/latest.json" "$PIN"
for p in $PLATFORMS; do
  seed_manifest "$BUCKET/maestroapp/desktop/$p/latest.json" "2.1.108"
done
# sanity: the malformed file really does contain the substring the old check used
grep -q '"version":"'"$PIN"'"' "$STORE/$BUCKET/maestroapp/desktop/linux_x86_64/v$PIN/latest.json" \
  || fail "(c) test bug: malformed manifest lacks the version substring"

run_script
[ "$rc" -ne 0 ] || { cat "$work/out.log"; fail "(c) malformed manifest was ACCEPTED (exit 0) — substring passed structural check"; }
if [ -s "$WRITES_LOG" ]; then
  echo "--- writes recorded ---"; cat "$WRITES_LOG"
  fail "(c) root pointer written despite a malformed v<PIN> manifest"
fi
for p in $PLATFORMS; do
  v=$(root_version "$p")
  [ "$v" = "2.1.108" ] || fail "(c) root for $p changed to '$v' (expected untouched 2.1.108)"
done
echo "PASS (c) malformed-json: rejected, 0 root writes, roots untouched, exit $rc"

# ============================================================================
# (d) content-drift: root version == PIN but BYTES differ => reconciled
# ============================================================================
STORE="$work/store_d"; WRITES_LOG="$work/writes_d"; : >"$WRITES_LOG"; mkdir -p "$STORE"
for p in $PLATFORMS; do
  # pinned manifest carries a content marker "good"
  seed_manifest "$BUCKET/maestroapp/desktop/$p/v$PIN/latest.json" "$PIN" "good"
  # roots start byte-identical to pinned
  seed_manifest "$BUCKET/maestroapp/desktop/$p/latest.json"       "$PIN" "good"
done
# windows root: SAME version PIN, but STALE/wrong content bytes
seed_manifest "$BUCKET/maestroapp/desktop/windows_x86_64/latest.json" "$PIN" "STALE"
before_h=$(root_hash windows_x86_64)
want_h=$(ver_hash windows_x86_64)
[ "$before_h" != "$want_h" ] || fail "(d) test bug: drifted root already matches pinned bytes"

run_script
[ "$rc" -eq 0 ] || { cat "$work/out.log"; fail "(d) expected clean exit, got $rc"; }
after_h=$(root_hash windows_x86_64)
[ "$after_h" = "$want_h" ] || fail "(d) same-version content drift NOT reconciled (root bytes still differ)"
grep -q "windows_x86_64/latest.json" "$WRITES_LOG" \
  || fail "(d) windows root was not re-written despite content drift"
# the byte-identical darwin/linux roots must NOT have been re-copied (no-op)
grep -q "darwin_aarch64/latest.json" "$WRITES_LOG" && fail "(d) identical darwin root re-copied (not a no-op)"
echo "PASS (d) content-drift: same-version wrong-bytes windows root reconciled, identical roots skipped, exit $rc"

# ============================================================================
# (e) partial-recover: a copy fails mid-phase => others reconciled + non-zero;
#     a SECOND run (failure cleared) completes the straggler.
# ============================================================================
STORE="$work/store_e"; WRITES_LOG="$work/writes_e"; : >"$WRITES_LOG"; mkdir -p "$STORE"
for p in $PLATFORMS; do
  seed_manifest "$BUCKET/maestroapp/desktop/$p/v$PIN/latest.json" "$PIN"
  seed_manifest "$BUCKET/maestroapp/desktop/$p/latest.json"       "2.1.108"  # all roots stale
done

# Run 1: force linux's copy to fail. darwin (before it) + windows (after it)
# must still be reconciled; script must exit non-zero; linux root stays stale.
run_script linux_x86_64
[ "$rc" -ne 0 ] || { cat "$work/out.log"; fail "(e) run1 expected non-zero exit on injected copy failure, got 0"; }
[ "$(root_version darwin_aarch64)" = "$PIN" ]  || fail "(e) run1 darwin not reconciled despite failing on a LATER platform"
[ "$(root_version windows_x86_64)" = "$PIN" ]  || fail "(e) run1 windows (after the failure) not reconciled"
[ "$(root_version linux_x86_64)"  = "2.1.108" ] || fail "(e) run1 linux root changed despite its copy failing"
echo "PASS (e) run1: darwin+windows reconciled, linux left stale, exit $rc (recoverable state)"

# Run 2: same store, no injected failure => the straggler (linux) completes.
: >"$WRITES_LOG"
run_script
[ "$rc" -eq 0 ] || { cat "$work/out.log"; fail "(e) run2 expected clean exit after failure cleared, got $rc"; }
for p in $PLATFORMS; do
  v=$(root_version "$p")
  [ "$v" = "$PIN" ] || fail "(e) run2 root for $p is '$v' (expected $PIN — straggler not completed)"
done
grep -q "linux_x86_64/latest.json" "$WRITES_LOG" || fail "(e) run2 did not complete the linux straggler"
# darwin/windows already at PIN from run1 => byte-identical => must be no-op skips
grep -q "darwin_aarch64/latest.json" "$WRITES_LOG" && fail "(e) run2 re-copied already-reconciled darwin (not idempotent)"
echo "PASS (e) run2: straggler linux completed, already-done platforms skipped, exit $rc"

# ============================================================================
# (f) prod-render: the PROD overlay must actually ENABLE the reconcile CronJob.
#     Renders the real argocd-applications factory with base + mycure-production
#     values (exactly as `mise run lint-helm` does), extracts the maestroapp
#     Application's valuesObject, feeds it back into charts/maestroapp, and
#     asserts BOTH the promote Job AND the reconcile CronJob render — the CronJob
#     with the schedule the overlay set. A drift guard that defaults off is inert
#     unless the prod overlay flips it; this asserts the effective render, not the
#     chart's capability.
# ============================================================================
repo_root=$(CDPATH= cd -- "$chart_dir/../.." && pwd)
base_vals="$repo_root/values/deployments/base.yaml"
prod_vals="$repo_root/values/deployments/mycure-production.yaml"
[ -f "$base_vals" ] || fail "(f) missing $base_vals"
[ -f "$prod_vals" ] || fail "(f) missing $prod_vals"

# 1) render the app-of-apps and pull the maestroapp Application's valuesObject.
apps="$work/apps.yaml"
helm template lint "$repo_root/charts/argocd-applications" \
  -f "$base_vals" -f "$prod_vals" \
  --set argocd.repoURL=lint --set argocd.targetRevision=lint \
  >"$apps" 2>"$work/apps.err" \
  || { cat "$work/apps.err" >&2; fail "(f) argocd-applications prod render failed"; }

# Extract the valuesObject block under the mycure-production-maestroapp Application.
# It sits between `valuesObject:` and the next same-or-lower-indent key
# (`  destination:`), inside that one Application document.
prod_vo="$work/prod_valuesobject.yaml"
awk '
  /name: mycure-production-maestroapp/ { inapp=1 }
  inapp && /^      valuesObject:/       { invo=1; next }
  invo && /^  destination:/            { invo=0; inapp=0 }
  invo                                 { sub(/^        /, ""); print }
' "$apps" >"$prod_vo"
[ -s "$prod_vo" ] || fail "(f) could not extract maestroapp valuesObject from prod render"
grep -q '^reconcile:' "$prod_vo" \
  || fail "(f) prod overlay does NOT set maestroapp.reconcile — CronJob would be inert in prod"

# 2) feed that effective valuesObject into charts/maestroapp and render.
prod_render="$work/prod_maestroapp.yaml"
helm template maestroapp "$chart_dir" -f "$prod_vo" \
  >"$prod_render" 2>"$work/render.err" \
  || { cat "$work/render.err" >&2; fail "(f) charts/maestroapp prod render failed"; }

# 3) assert BOTH workloads render, and the CronJob carries the overlay's schedule.
grep -Eq '^kind: Job$'     "$prod_render" || fail "(f) prod render missing the promote Job"
grep -Eq '^kind: CronJob$' "$prod_render" || fail "(f) prod render missing the reconcile CronJob (drift guard inert in prod)"
grep -q 'name: maestroapp-reconcile' "$prod_render" \
  || fail "(f) reconcile CronJob not named as expected in prod render"

# schedule the CronJob renders with must equal the schedule the prod overlay set.
# strip only surrounding quotes (not inner spaces) so the cron expr stays readable.
unquote() { sed -e "s/^['\"]//" -e "s/['\"]$//"; }
want_sched=$(sed -n 's/^  schedule:[[:space:]]*//p' "$prod_vo"    | head -n1 | unquote)
[ -n "$want_sched" ] || fail "(f) prod overlay set reconcile.enabled but no reconcile.schedule"
got_sched=$(sed -n 's/^  schedule:[[:space:]]*//p' "$prod_render" | head -n1 | unquote)
[ "$got_sched" = "$want_sched" ] \
  || fail "(f) rendered CronJob schedule '$got_sched' != prod overlay schedule '$want_sched'"
echo "PASS (f) prod-render: promote Job + reconcile CronJob both present in prod, schedule='$got_sched'"

echo "ALL CHECKS PASSED"
