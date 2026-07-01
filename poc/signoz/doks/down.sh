#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export KUBECONFIG="${KUBECONFIG:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.kube/config}"
helm uninstall signoz-k8s-infra -n signoz-poc >/dev/null 2>&1 || true
kubectl delete -f signoz-egress.yaml >/dev/null 2>&1 || true
kubectl delete namespace signoz-poc >/dev/null 2>&1 || true
echo ">> DOKS-side PoC removed (egress + collector + signoz-poc ns)."
