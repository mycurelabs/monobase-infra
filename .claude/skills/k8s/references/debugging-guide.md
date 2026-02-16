# Kubernetes Debugging Guide

## Pod Lifecycle Debugging

### Pending State
Pod is waiting to be scheduled.

**Common causes:**
- Insufficient CPU/memory on nodes
- PVC not bound (StorageClass missing or no available PV)
- Node selector or affinity mismatch (e.g., `nodePool` label doesn't match)
- Resource quotas exceeded

**Diagnostics:**
```bash
kubectl describe pod {pod} -n {namespace}
# Look at Events section for scheduling failures
kubectl get events -n {namespace} --field-selector reason=FailedScheduling
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
```

### CrashLoopBackOff
Container starts but crashes repeatedly.

**Common causes:**
- Missing environment variables or secrets
- Database connection failure (wrong URI, auth failure, network policy blocking)
- Application startup error (bad config, missing dependency)
- OOM kill (memory limit too low)

**Diagnostics:**
```bash
kubectl logs {pod} -n {namespace} --previous  # Logs from crashed container
kubectl describe pod {pod} -n {namespace}      # Check exit code and OOM events
kubectl get events -n {namespace} --field-selector involvedObject.name={pod}
```

**Exit codes:**
- `0`: Normal exit
- `1`: Application error
- `137`: OOM killed (SIGKILL) — increase memory limits
- `143`: Graceful termination (SIGTERM)

### ImagePullBackOff
Container image cannot be pulled.

**Common causes:**
- Wrong image name or tag
- Private registry without imagePullSecrets
- Registry rate limiting (Docker Hub)

**Diagnostics:**
```bash
kubectl describe pod {pod} -n {namespace}  # Check Events for pull error
kubectl get events -n {namespace} --field-selector reason=Failed
```

### OOMKilled
Container exceeded memory limit.

**Diagnostics:**
```bash
kubectl describe pod {pod} -n {namespace}  # Look for OOMKilled in lastState
kubectl top pod {pod} -n {namespace}       # Current memory usage
```

**Fix:** Increase `.resources.limits.memory` in deployment values.

## Service Connectivity Debugging

### App Unreachable via Gateway
```bash
# 1. Check Gateway is programmed
kubectl get gateway shared-gateway -n gateway-system
# STATUS should be "Programmed"

# 2. Check HTTPRoute exists and is accepted
kubectl get httproute -n {namespace}
kubectl describe httproute {name} -n {namespace}
# Conditions should show "Accepted" and "ResolvedRefs"

# 3. Check Service exists and has endpoints
kubectl get svc -n {namespace}
kubectl get endpoints {svc} -n {namespace}
# Endpoints should list pod IPs

# 4. Check Pod is running and ready
kubectl get pods -n {namespace} -l app.kubernetes.io/name={app}

# 5. Check certificates
kubectl get certificates -n gateway-system
kubectl describe certificate gateway-tls -n gateway-system
```

### DNS Not Resolving
```bash
# Check external-dns is running
kubectl get pods -n external-dns

# Check external-dns logs for the domain
kubectl logs -n external-dns deployment/external-dns --tail=50

# Verify HTTPRoute has correct hostname
kubectl get httproute -n {namespace} -o yaml | grep hostname
```

## Storage Debugging

### PVC Stuck Pending
```bash
kubectl describe pvc {name} -n {namespace}
# Check Events for provisioning errors

# Verify StorageClass exists
kubectl get storageclass

# Check if Longhorn is healthy (if using Longhorn)
kubectl get pods -n longhorn-system
```

### Volume Full
```bash
# Check PVC usage
kubectl exec {pod} -n {namespace} -- df -h

# For MongoDB
kubectl exec mongodb-0 -n {namespace} -- df -h /bitnami/mongodb

# Resize PVC (use script)
mise run resize-storage
```

## Gateway/Routing Debugging

### HTTP 431 (Request Header Fields Too Large)
The EnvoyPatchPolicy increases max headers to 96KB. If still hitting 431:
```bash
# Verify EnvoyPatchPolicy exists
kubectl get envoypatchpolicy -n gateway-system
kubectl describe envoypatchpolicy -n gateway-system
```

### Certificate Issues
```bash
# Check certificate status
kubectl get certificates -n gateway-system
kubectl describe certificate gateway-tls -n gateway-system

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --tail=50

# Check ACME challenges
kubectl get challenges -A
kubectl describe challenge {name} -n {namespace}

# Check ClusterIssuer
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-mycure-cloudflare-prod
```

### Route Not Matching
```bash
# Check HTTPRoute matches
kubectl get httproute -A -o wide

# Verify listener names match sectionName
kubectl get gateway shared-gateway -n gateway-system -o yaml | grep -A3 "listeners:"

# Common issue: sectionName mismatch
# Production *.localfirsthealth.com uses: sectionName: https-lfh
# Staging *.stg.localfirsthealth.com uses: sectionName: https-lfh-stg
```

## Secrets Debugging

### ExternalSecret Not Syncing
```bash
# Check ExternalSecret status
kubectl get externalsecrets -n {namespace}
# STATUS should be "SecretSynced"

# Describe for error details
kubectl describe externalsecret {name} -n {namespace}

# Check ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore gcp-secretstore

# Check ESO operator
kubectl get pods -n external-secrets-system
kubectl logs -n external-secrets-system deployment/external-secrets --tail=50

# Verify secret exists in GCP
# (requires gcloud access)
gcloud secrets list --project=mc-v4-prod --filter="name:{remote-key}"
```

## ArgoCD Sync Issues

### Application Out of Sync
```bash
# Check sync status
kubectl get application {name}-root -n argocd

# Force refresh
argocd app get {name}-root --hard-refresh

# Check diff
argocd app diff {name}-root

# Manual sync
argocd app sync {name}-root
```

### Sync Failed
```bash
# Check sync result
argocd app get {name}-root
# Look at "Sync Status" and "Health Status"

# Check controller logs
kubectl logs -n argocd deployment/argocd-application-controller --tail=100 | grep {name}

# Check repo server (Helm rendering errors)
kubectl logs -n argocd deployment/argocd-repo-server --tail=100
```
