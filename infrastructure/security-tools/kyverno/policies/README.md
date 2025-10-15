# Kyverno Policies

Pre-configured policies for monobase-infra deployments.

## Policy Catalog

| Policy | Mode | Purpose | Scope |
|--------|------|---------|-------|
| **pod-security** | Enforce | Pod Security Standards (restricted) | All namespaces |
| **require-labels** | Enforce | Require standard labels | Deployments, StatefulSets, Pods |
| **restrict-registries** | Audit | Only allow trusted registries | Pods |

## Policy Modes

**Enforce** - Blocks non-compliant resources (production)
**Audit** - Logs violations, allows resource (testing)

## Usage

### Apply All Policies

```bash
kubectl apply -f .
```

### Apply Specific Policy

```bash
kubectl apply -f pod-security.yaml
```

### Switch Between Modes

```bash
# Audit mode (for testing)
kubectl patch clusterpolicy pod-security \
  -p '{"spec":{"validationFailureAction":"audit"}}'

# Enforce mode (for production)
kubectl patch clusterpolicy pod-security \
  -p '{"spec":{"validationFailureAction":"enforce"}}'
```

## Policy Details

### 1. Pod Security Standards

**File:** `pod-security.yaml`
**Mode:** Enforce
**Applies to:** All Pods

**Requirements:**
- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- `seccompProfile.type: RuntimeDefault`

**Example violation:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
spec:
  containers:
  - name: app
    image: nginx
    # Missing: securityContext.runAsNonRoot=true
```

**Result:** ❌ Blocked - "Pod must set runAsNonRoot=true"

### 2. Require Labels

**File:** `require-labels.yaml`
**Mode:** Enforce
**Applies to:** Deployments, StatefulSets, Pods

**Required labels:**
- `app` - Application name
- `environment` - Environment (production/staging/dev)
- `client` - Client identifier

**Example violation:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  # Missing labels
spec:
  template:
    metadata:
      labels:
        # Missing: app, environment, client
```

**Result:** ❌ Blocked - "Missing required labels"

### 3. Restrict Image Registries

**File:** `restrict-registries.yaml`
**Mode:** Audit (warning only)
**Applies to:** Pods

**Allowed registries:**
- `ghcr.io/YOUR-ORG/*`
- `bitnami/*`
- `registry.k8s.io/*`

**Example violation:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: untrusted
spec:
  containers:
  - name: app
    image: docker.io/random/image  # Untrusted registry
```

**Result:** ⚠️ Warning logged (audit mode)

## Customizing Policies

### Add Namespace Exclusions

```yaml
spec:
  rules:
  - exclude:
      resources:
        namespaces:
        - special-namespace  # Exclude from policy
```

### Change Enforcement Mode

```yaml
spec:
  validationFailureAction: audit  # or "enforce"
```

### Add New Registry

Edit `restrict-registries.yaml`:
```yaml
- images:
    any:
    - "ghcr.io/YOUR-ORG/*"
    - "bitnami/*"
    - "registry.k8s.io/*"
    - "your-registry.com/*"  # Add here
```

## Monitoring

### View Policy Status

```bash
kubectl get clusterpolicies
```

### View Policy Reports

```bash
# All reports
kubectl get policyreports -A

# Specific namespace
kubectl get policyreport -n myclient-prod -o yaml
```

### Check Violations

```bash
# In enforce mode (blocked requests)
kubectl get events -A | grep "denied the request"

# In audit mode (violations logged)
kubectl get policyreports -A -o json | \
  jq '.items[].results[] | select(.result=="fail")'
```

## Troubleshooting

### Policy Not Working

```bash
# Check policy exists
kubectl get clusterpolicy <policy-name>

# Check policy status
kubectl describe clusterpolicy <policy-name>

# Check Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
```

### Too Many Violations

If a policy is too strict:

1. Switch to audit mode
2. Review violations
3. Adjust policy or fix resources
4. Switch back to enforce

```bash
# Audit mode
kubectl patch clusterpolicy <name> -p '{"spec":{"validationFailureAction":"audit"}}'

# Review
kubectl get policyreports -A

# Enforce mode
kubectl patch clusterpolicy <name> -p '{"spec":{"validationFailureAction":"enforce"}}'
```
