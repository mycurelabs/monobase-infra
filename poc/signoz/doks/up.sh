#!/usr/bin/env bash
# Deploy the DOKS-side PoC collector: tailscale egress to vanaheim + k8s-infra collector.
# Ships DOKS metrics + logs to the SigNoz on vanaheim. Idempotent. PoC for #2096.
set -euo pipefail
cd "$(dirname "$0")"
export KUBECONFIG="${KUBECONFIG:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.kube/config}"
helm repo add signoz https://charts.signoz.io >/dev/null 2>&1 || true
helm repo update signoz >/dev/null 2>&1 || true
kubectl apply -f signoz-egress.yaml
helm upgrade --install signoz-k8s-infra signoz/k8s-infra \
  -n signoz-poc --create-namespace -f k8s-infra-values.yaml
echo ">> deployed. tail collector: kubectl logs -n signoz-poc -l app.kubernetes.io/component=otel-agent -f"
