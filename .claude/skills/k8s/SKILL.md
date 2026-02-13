---
name: k8s
description: Kubernetes operations, debugging, resource management
allowed-tools: Bash, Read, Grep, Glob
---

# Kubernetes Operations Skill

## Current Context

```
!kubectl config current-context
```

```
!kubectl get ns --no-headers | sort
```

## Namespace Conventions

- Tenant namespaces: `{client}-{environment}` (e.g., `mycure-production`, `mycure-staging`)
- Infrastructure namespaces: `gateway-system`, `argocd`, `monitoring`, `velero`, `cert-manager`, `external-secrets-system`, `envoy-gateway-system`, `external-dns`, `kyverno`, `falco`, `longhorn-system`

## Gateway Architecture

- Shared gateway: `shared-gateway` in `gateway-system` namespace
- Gateway class: `envoy-gateway` (Envoy Gateway implementation)
- Multi-domain listeners: `*.mycureapp.com`, `*.localfirsthealth.com`, `*.stg.localfirsthealth.com`, `*.mycure.md`
- HTTPRoutes in each tenant namespace reference the shared gateway via `parentRefs`
- EnvoyPatchPolicy increases max request headers to 96KB (prevents HTTP 431 errors)

## Common Operations

### Status & Inspection
```bash
# Namespace overview
kubectl get all -n {namespace}

# Pod status with wide output
kubectl get pods -n {namespace} -o wide

# Recent events (sorted)
kubectl get events -n {namespace} --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top pods -n {namespace}
kubectl top nodes
```

### Logs & Debugging
```bash
# Application logs
kubectl logs -n {namespace} deployment/{app} --tail=100
kubectl logs -n {namespace} deployment/{app} -f  # follow
kubectl logs -n {namespace} deployment/{app} --previous  # crashed container

# Describe for events and conditions
kubectl describe pod {pod} -n {namespace}
kubectl describe deployment {app} -n {namespace}

# Exec into pod
kubectl exec -it {pod} -n {namespace} -- sh
```

### Scaling & Restarts
```bash
# Restart deployment (rolling)
kubectl rollout restart deployment/{app} -n {namespace}

# Scale
kubectl scale deployment/{app} --replicas=3 -n {namespace}

# Check rollout status
kubectl rollout status deployment/{app} -n {namespace}
```

### Gateway & Networking
```bash
# Check gateway status
kubectl get gateway -n gateway-system
kubectl describe gateway shared-gateway -n gateway-system

# List all HTTPRoutes
kubectl get httproute -A

# Check specific route
kubectl describe httproute {name} -n {namespace}

# Check certificates
kubectl get certificates -A
kubectl describe certificate {name} -n {namespace}
```

### Secrets & ExternalSecrets
```bash
# Check ExternalSecret sync status
kubectl get externalsecrets -n {namespace}
kubectl describe externalsecret {name} -n {namespace}

# Check ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore gcp-secretstore
```

### Port Forwarding
```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward svc/grafana -n monitoring 3000:3000

# Prometheus
kubectl port-forward svc/kube-prometheus-prometheus -n monitoring 9090:9090
```

## Debugging Flowchart

1. **Pod not starting?** → `kubectl describe pod` → check Events section
   - Pending: resource constraints, PVC not bound, node selector mismatch
   - ImagePullBackOff: wrong image name/tag, registry auth
   - CrashLoopBackOff: check logs, env vars, secrets

2. **App unreachable?** → Check outside-in:
   - Gateway: `kubectl get gateway -n gateway-system`
   - HTTPRoute: `kubectl get httproute -n {namespace}`
   - Service: `kubectl get svc -n {namespace}`
   - Pod: `kubectl get pods -n {namespace}`
   - Certificates: `kubectl get certificates -A`

3. **Secrets not syncing?** → Check ExternalSecret:
   - `kubectl get externalsecrets -n {namespace}`
   - Verify ClusterSecretStore exists
   - Check GCP Secret Manager permissions
   - Verify ESO operator is running

## Important Reminders

- ArgoCD **reverts direct kubectl changes** — use Git for persistent changes
- Changes to `values/deployments/*.yaml` auto-sync via ArgoCD
- Use `mise run admin` for port-forwarding to admin UIs
- Always check ArgoCD sync status after making changes
