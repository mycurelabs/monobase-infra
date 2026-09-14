#!/usr/bin/env bash
# Guard the argocd-applications app registry (see charts/argocd-applications/
# templates/generic-app.yaml). Two failure modes this catches that a plain
# `helm template` (rc=0) does NOT:
#
#   (a) appRegistry re-declared in an OVERLAY. Helm REPLACES arrays and, for the
#       registry MAP, an overlay key silently overrides the base entry — a wrong
#       `key`/`chart` (or a `null`) there drops a single Application even though
#       the base is correct. The registry must live ONLY in the base file so it
#       stays a single source of truth. (The template guard can't see which file
#       a value came from — hence this lint.)
#
#   (b) An Application DISAPPEARS between the committed base set and the render.
#       We render every overlay and fail if the set of generic-app Applications
#       shrinks below the expected baseline (a dropped/renamed registry entry, a
#       flipped enabled, etc.). This is the render-diff gate.
#
# Runs offline (dummy argocd.repoURL/targetRevision). Wired into `mise run
# lint-helm`. NOTE: security.yml CI only covers PRs into main, so on a
# cluster-branch PR this runs locally / via `mise run lint` only.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CHART=charts/argocd-applications
BASE=values/deployments/base.yaml
OVERLAYS=(mycure-production mycure-staging mycure-preprod)
HELM_FLAGS=(--set argocd.repoURL=lint --set argocd.targetRevision=lint)

fail=0

# ---- (a) appRegistry must appear ONLY in the base values file --------------
echo "[app-registry] check (a): appRegistry declared only in base.yaml"
offenders=$(grep -rl '^appRegistry:' values/deployments/ | grep -v "^${BASE}$" || true)
if [[ -n "${offenders}" ]]; then
  echo "  ✗ appRegistry re-declared outside base.yaml:" >&2
  echo "${offenders}" | sed 's/^/    - /' >&2
  echo "    The registry is the single source of truth in ${BASE}; an overlay" >&2
  echo "    copy silently overrides entries and can drop an Application." >&2
  fail=1
else
  echo "  ✓ appRegistry only in ${BASE}"
fi

# ---- (b) per-overlay render-diff gate: no generic-app Application vanishes --
# Baseline = the generic-app Application names each overlay renders on the
# committed tree. Any FUTURE change that renders fewer of them fails here.
# (Bespoke templates — postgresql/valkey/etc — are not asserted; only the
# registry-driven set, matched by sync-wave "3".)
apps_for() {
  helm template x "${CHART}" -f "${BASE}" -f "values/deployments/$1.yaml" \
    "${HELM_FLAGS[@]}" 2>/dev/null \
    | awk '/^kind: Application$/{a=1} a&&/^  name:/{print $2; a=0}' \
    | sort -u
}

declare -A BASELINE=(
  [mycure-production]="mycure-production-cadence mycure-production-cadence-relay mycure-production-hapihub-docs mycure-production-mycure mycure-production-mycure-dashboard mycure-production-mycure-myaccount mycure-production-mycure-pxp mycure-production-mycurelocal"
  [mycure-staging]="mycure-staging-cadence mycure-staging-cadence-relay mycure-staging-medgemma-worker mycure-staging-medleyapp mycure-staging-mycure mycure-staging-mycure-dashboard mycure-staging-mycure-pxp mycure-staging-openmed"
  [mycure-preprod]="mycure-preprod-cadence mycure-preprod-cadence-relay mycure-preprod-hapihub-docs mycure-preprod-medley mycure-preprod-mycure mycure-preprod-mycure-dashboard mycure-preprod-mycure-myaccount mycure-preprod-mycure-pxp mycure-preprod-mycurelocal"
)

echo "[app-registry] check (b): no generic-app Application disappears per overlay"
for ov in "${OVERLAYS[@]}"; do
  rendered=$(apps_for "${ov}")
  missing=""
  for expected in ${BASELINE[$ov]}; do
    grep -qx "${expected}" <<<"${rendered}" || missing+=" ${expected}"
  done
  if [[ -n "${missing}" ]]; then
    echo "  ✗ ${ov}: expected generic-app Application(s) missing:${missing}" >&2
    fail=1
  else
    echo "  ✓ ${ov}: all baseline generic-app Applications present"
  fi
done

if [[ "${fail}" -ne 0 ]]; then
  echo "[app-registry] FAILED" >&2
  exit 1
fi
echo "[app-registry] OK"
