#!/usr/bin/env bash
# Upgrade the shared Gateway API CRDs to the bundle pinned by our NGF release.
#
# The gateway.networking.k8s.io CRDs are cluster-scoped and shared; they are
# deliberately NOT managed by any ArgoCD Application (the Envoy Gateway
# teardown, 2026-08-01, showed why: an app-level skipCrds/prune cascade can
# delete them out from under every HTTPRoute in the cluster). They carry
# argocd.argoproj.io/sync-options=Prune=false + helm.sh/resource-policy=keep
# and are upgraded only by running this script on purpose.
#
# Keep NGF_REF in lockstep with nginxGateway.version in
# values/infrastructure/main.yaml — NGF pins the Gateway API bundle it is
# tested against (v2.6.7 -> Gateway API v1.5.1, experimental channel; the
# experimental channel is required for UDPRoute/TCPRoute on NGF <= 2.6).
#
# Last run: 2026-08-06 — v1.2.0/v1.2.1 mixed -> v1.5.1 experimental.
# --force-conflicts is intentional: field ownership is reclaimed from stale
# managers (the deleted Envoy Gateway ArgoCD app, old manual applies).
set -euo pipefail

NGF_REF="${NGF_REF:-v2.6.7}"
BUNDLE_URL="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=${NGF_REF}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

kubectl kustomize "$BUNDLE_URL" > "$tmp/bundle.yaml"
yq 'select(.kind == "CustomResourceDefinition")' "$tmp/bundle.yaml" > "$tmp/crds.yaml"
yq 'select(.kind != "CustomResourceDefinition")' "$tmp/bundle.yaml" > "$tmp/policies.yaml"

echo "--- dry-run"
kubectl apply --server-side --force-conflicts --dry-run=server -f "$tmp/crds.yaml"

read -rp "Apply for real? [y/N] " ok
[[ "$ok" == y* ]] || exit 1

# CRDs first, then the safe-upgrades ValidatingAdmissionPolicy — installing the
# policy first would block channel/version changes made by this very run.
kubectl apply --server-side --force-conflicts -f "$tmp/crds.yaml"
kubectl apply --server-side -f "$tmp/policies.yaml"

# Prune-protection on every gateway CRD, including ones new in this bundle.
kubectl get crd -o name | grep 'gateway\.networking' | xargs -r kubectl annotate \
  'argocd.argoproj.io/sync-options=Prune=false' 'helm.sh/resource-policy=keep' --overwrite

kubectl get crd -o custom-columns='NAME:.metadata.name,VERSION:.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version,CHANNEL:.metadata.annotations.gateway\.networking\.k8s\.io/channel' | grep -E 'NAME|gateway'
