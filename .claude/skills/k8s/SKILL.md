---
name: k8s
description: Kubernetes operations, debugging, resource management
allowed-tools: Bash, Read, Grep, Glob
---

# Kubernetes Operations Skill

## Kubeconfig Resolution

All kubectl commands use this priority order:
1. Explicit `--kubeconfig` flag (if provided)
2. `KUBECONFIG` environment variable
3. **Default:** `~/.kube/mycure-doks-main` (if exists)
4. Interactive selection (if multiple configs in `~/.kube/`)
5. Fall back to `~/.kube/config`

Set kubeconfig before running commands:
```bash
export KUBECONFIG=~/.kube/mycure-doks-main
```

---

## Quick Operations

### logs — Stream pod logs (handles multi-pod deployments)
```bash
# Stream logs from deployment (all pods)
kubectl logs -f -n {namespace} deployment/{name} --all-containers --prefix

# Stream logs with label selector
kubectl logs -f -n {namespace} -l app.kubernetes.io/name={name} --all-containers --prefix

# Last 100 lines from deployment
kubectl logs -n {namespace} deployment/{name} --tail=100

# Previous container logs (for crash debugging)
kubectl logs -n {namespace} deployment/{name} --previous

# Examples:
kubectl logs -f -n mycure-staging deployment/api --all-containers --prefix
kubectl logs -n mycure-production deployment/hapihub --tail=100
```

### restart — Rolling restart deployment/statefulset ⚠️ DESTRUCTIVE
```bash
# ⚠️ CONFIRM BEFORE EXECUTING - causes brief downtime during rollout

# Restart deployment
kubectl rollout restart deployment/{name} -n {namespace}

# Restart statefulset
kubectl rollout restart statefulset/{name} -n {namespace}

# Watch rollout progress
kubectl rollout status deployment/{name} -n {namespace}

# Examples:
kubectl rollout restart deployment/api -n mycure-staging
kubectl rollout status deployment/api -n mycure-staging
```

### debug — Combined troubleshooting (describe + logs + events)
```bash
# Full debug sequence for a pod/deployment:

# 1. Describe pod for status, conditions, events
kubectl describe pod {pod} -n {namespace}
# or for deployment:
kubectl describe deployment {name} -n {namespace}

# 2. Recent logs
kubectl logs {pod} -n {namespace} --tail=100

# 3. Related events
kubectl get events -n {namespace} --sort-by=.lastTimestamp | grep {name}

# Examples:
kubectl describe pod api-7d8f9b6c4-x2k3l -n mycure-staging
kubectl logs api-7d8f9b6c4-x2k3l -n mycure-staging --tail=100
kubectl get events -n mycure-staging --sort-by=.lastTimestamp | grep api
```

### exec — Shell into pod
```bash
# Interactive shell
kubectl exec -it {pod} -n {namespace} -- /bin/sh

# Run specific command
kubectl exec {pod} -n {namespace} -- {command}

# Examples:
kubectl exec -it api-7d8f9b6c4-x2k3l -n mycure-staging -- /bin/sh
kubectl exec api-7d8f9b6c4-x2k3l -n mycure-staging -- env
```

### events — Show recent events for namespace
```bash
# All events sorted by time
kubectl get events -n {namespace} --sort-by=.lastTimestamp

# Last 20 events
kubectl get events -n {namespace} --sort-by=.lastTimestamp | tail -20

# Warning events only
kubectl get events -n {namespace} --field-selector type=Warning

# All namespaces
kubectl get events -A --sort-by=.lastTimestamp | head -50

# Examples:
kubectl get events -n mycure-staging --sort-by=.lastTimestamp
kubectl get events -A --field-selector type=Warning
```

### scale — Scale deployment/statefulset replicas ⚠️ DESTRUCTIVE if scaling to 0
```bash
# ⚠️ CONFIRM if scaling to 0 - this stops all pods

# Scale deployment
kubectl scale deployment/{name} -n {namespace} --replicas={n}

# Scale statefulset
kubectl scale statefulset/{name} -n {namespace} --replicas={n}

# Examples:
kubectl scale deployment/api -n mycure-staging --replicas=3
kubectl scale deployment/hapihub -n mycure-staging --replicas=0  # ⚠️ STOPS SERVICE
```

---

## Database Operations

### db-shell — Quick database CLI access
```bash
# PostgreSQL shell
kubectl exec -it -n {namespace} postgresql-0 -- psql -U postgres

# PostgreSQL with specific database
kubectl exec -it -n {namespace} postgresql-0 -- psql -U postgres -d {database}

# MongoDB shell (mongosh)
kubectl exec -it -n {namespace} mongodb-0 -- mongosh

# MongoDB with auth (get password from secret)
MONGO_PASS=$(kubectl get secret -n {namespace} mongodb -o jsonpath='{.data.mongodb-root-password}' | base64 -d)
kubectl exec -it -n {namespace} mongodb-0 -- mongosh -u root -p "$MONGO_PASS"

# Examples:
kubectl exec -it -n mycure-staging postgresql-0 -- psql -U postgres
kubectl exec -it -n mycure-production mongodb-0 -- mongosh
```

---

## Secrets Operations

### secrets-sync — Force External Secrets to refresh
```bash
# Force sync by updating annotation (triggers immediate refresh)
kubectl annotate externalsecret {name} -n {namespace} force-sync=$(date +%s) --overwrite

# Force sync all external secrets in namespace
kubectl get externalsecret -n {namespace} -o name | xargs -I {} kubectl annotate {} -n {namespace} force-sync=$(date +%s) --overwrite

# Examples:
kubectl annotate externalsecret api-secrets -n mycure-staging force-sync=$(date +%s) --overwrite
```

### secrets-status — Check External Secret sync status
```bash
# List all external secrets with status
kubectl get externalsecret -n {namespace} -o wide

# All namespaces
kubectl get externalsecret -A -o wide

# Detailed status for specific secret
kubectl describe externalsecret {name} -n {namespace}

# Check ClusterSecretStore health
kubectl get clustersecretstore
kubectl describe clustersecretstore gcp-secretstore

# Examples:
kubectl get externalsecret -n mycure-staging -o wide
kubectl describe externalsecret api-secrets -n mycure-staging
```

---

## Cluster Operations

### cluster-health — Overall cluster health check
```bash
# Node status
kubectl get nodes -o wide

# Unhealthy pods across all namespaces
kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded

# Unbound PVCs
kubectl get pvc -A --field-selector status.phase!=Bound

# Recent events (warnings)
kubectl get events -A --sort-by=.lastTimestamp --field-selector type=Warning | head -30

# Node resource usage
kubectl top nodes

# Quick health summary:
echo "=== Nodes ===" && kubectl get nodes -o wide
echo "=== Unhealthy Pods ===" && kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded 2>/dev/null || echo "All pods healthy"
echo "=== Unbound PVCs ===" && kubectl get pvc -A --field-selector status.phase!=Bound 2>/dev/null || echo "All PVCs bound"
echo "=== Recent Warnings ===" && kubectl get events -A --sort-by=.lastTimestamp --field-selector type=Warning | head -10
```

### cluster-nodes — Node status and resource capacity
```bash
# Node overview
kubectl get nodes -o wide

# Resource usage per node
kubectl top nodes

# Detailed node info (allocated resources)
kubectl describe nodes | grep -A 10 "Allocated resources"

# Node conditions
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"\n"}{end}'

# Examples - full node report:
kubectl get nodes -o wide && kubectl top nodes
```

---

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
