# Kyverno - Kubernetes Policy Engine

Kyverno is a policy engine designed for Kubernetes that validates, mutates, and generates configurations using admission controls.

## What Kyverno Does

**Admission Controller:** Intercepts Kubernetes API requests BEFORE resources are created and validates them against policies.

**Three modes:**
1. **Validate** - Block non-compliant resources
2. **Mutate** - Automatically fix resources to comply
3. **Generate** - Auto-create related resources (e.g., NetworkPolicies)

## When to Use Kyverno

### ✅ Use Kyverno When:

**1. Multiple teams have kubectl access**
- Teams can bypass GitOps with direct `kubectl` commands
- Need to prevent ad-hoc deployments that violate security

**2. Third-party Helm charts are installed**
- Installing Bitnami, Prometheus, or other charts outside this repo
- Charts may not follow your security standards

**3. Compliance requires automated enforcement**
- Auditors want proof of automated policy enforcement
- Need audit trail of policy violations
- HIPAA/SOC2 requires documented controls

**4. Multi-tenant clusters**
- Multiple clients/teams share the same cluster
- Need namespace-level policy isolation
- Prevent cross-namespace access

### ❌ Skip Kyverno When:

**1. 100% GitOps with single team**
- All deployments via ArgoCD from this repo
- Helm templates already enforce security
- No direct kubectl access
- **Kyverno is redundant** - your IaC already controls config

**2. Small deployments (<100 users)**
- Overhead not justified for small scale
- Manual review is sufficient

**3. Dev/staging environments**
- Want flexibility for testing
- Don't need strict enforcement

## Use Cases with Examples

### Use Case 1: Block Root Containers

**Scenario:** Developer tries to deploy pod running as root.

**Without Kyverno:**
```bash
kubectl run test --image=nginx --restart=Never
# ✅ Pod created
# ❌ Running as root (security risk!)
```

**With Kyverno:**
```bash
kubectl run test --image=nginx --restart=Never
# ❌ Error: admission webhook denied the request
# Policy pod-security: validation error: Pod must set securityContext.runAsNonRoot=true
```

**Fix:**
```bash
kubectl run test --image=nginx --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000}}}'
# ✅ Pod created (complies with policy)
```

### Use Case 2: Enforce Required Labels

**Scenario:** All resources must have standard labels for tracking and billing.

**Policy:** Every deployment must have `app`, `environment`, and `client` labels.

**Without Kyverno:**
```bash
kubectl create deployment test --image=nginx -n myclient-prod
# ✅ Created
# ❌ Missing labels (can't track ownership/costs)
```

**With Kyverno:**
```bash
kubectl create deployment test --image=nginx -n myclient-prod
# ❌ Error: admission webhook denied the request
# Policy require-labels: validation error: Missing required labels: app, environment, client
```

**Fix:**
```bash
kubectl create deployment test --image=nginx -n myclient-prod \
  --labels app=test,environment=production,client=myclient
# ✅ Created (has required labels)
```

### Use Case 3: Restrict Image Registries

**Scenario:** Only allow images from trusted registries (prevent supply chain attacks).

**Policy:** Images must be from `ghcr.io/YOUR-ORG/*` or `bitnami/*`.

**Without Kyverno:**
```bash
kubectl run malicious --image=docker.io/attacker/backdoor
# ✅ Pod created
# ❌ Untrusted image (potential malware)
```

**With Kyverno:**
```bash
kubectl run malicious --image=docker.io/attacker/backdoor
# ❌ Error: admission webhook denied the request
# Policy restrict-registries: Image must be from approved registry: ghcr.io/YOUR-ORG, bitnami
```

**Allowed:**
```bash
kubectl run api --image=ghcr.io/YOUR-ORG/monobase-api:5.215.2
# ✅ Created (from trusted registry)
```

### Use Case 4: Auto-Generate NetworkPolicies

**Scenario:** Automatically create default-deny NetworkPolicy when namespace is created.

**Without Kyverno:**
```bash
kubectl create namespace test-client
# ✅ Namespace created
# ❌ No NetworkPolicy (all traffic allowed!)
```

**With Kyverno (generate policy):**
```bash
kubectl create namespace test-client
# ✅ Namespace created
# ✅ Kyverno auto-generates default-deny NetworkPolicy
```

Kyverno automatically creates:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: test-client
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Use Case 5: Prevent Privilege Escalation

**Scenario:** Block pods that allow privilege escalation.

**Without Kyverno:**
```yaml
# Deploy pod with allowPrivilegeEscalation=true
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
spec:
  containers:
  - name: app
    image: nginx
    securityContext:
      allowPrivilegeEscalation: true  # ❌ Security risk
```

```bash
kubectl apply -f privileged-pod.yaml
# ✅ Pod created
# ❌ Can escalate privileges (security risk)
```

**With Kyverno:**
```bash
kubectl apply -f privileged-pod.yaml
# ❌ Error: admission webhook denied the request
# Policy pod-security: containers must set allowPrivilegeEscalation=false
```

## Installation

### Step 1: Install Kyverno Controller

```bash
# Add Helm repository
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --values helm-values.yaml

# Wait for Kyverno to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=kyverno \
  -n kyverno \
  --timeout=120s
```

### Step 2: Apply Policies

```bash
# Apply all policies
kubectl apply -f policies/

# Verify policies are active
kubectl get clusterpolicies

# Check policy status
kubectl describe clusterpolicy pod-security
```

### Step 3: Test Policies

```bash
# Test blocking non-compliant pod
kubectl run test-root --image=nginx --restart=Never
# Should be BLOCKED

# Test allowing compliant pod
kubectl run test-nonroot --image=nginx --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000}}}'
# Should SUCCEED
```

## Included Policies

### 1. Pod Security Standards (pod-security.yaml)

Enforces Kubernetes Pod Security Standards (restricted profile):

- ✅ `runAsNonRoot: true` - All containers must run as non-root
- ✅ `allowPrivilegeEscalation: false` - No privilege escalation
- ✅ `capabilities.drop: [ALL]` - Drop all Linux capabilities
- ✅ `readOnlyRootFilesystem: true` - Root filesystem read-only (where possible)
- ✅ `seccompProfile.type: RuntimeDefault` - Seccomp profile required

**Audit mode:** Logs violations but allows resources
**Enforce mode:** Blocks non-compliant resources

### 2. Require Labels (require-labels.yaml)

All resources must have standard labels:

- `app` - Application name
- `environment` - Environment (production, staging, dev)
- `client` - Client identifier (namespace prefix)

**Benefits:**
- Cost tracking per client/environment
- Resource ownership clarity
- Easier troubleshooting

### 3. Restrict Image Registries (restrict-registries.yaml)

Only allow images from approved registries:

- `ghcr.io/YOUR-ORG/*` - Your organization's images
- `bitnami/*` - Trusted third-party charts
- `registry.k8s.io/*` - Kubernetes official images

**Prevents:**
- Supply chain attacks
- Malicious images
- Unvetted third-party software

## Configuration

### Audit vs. Enforce Mode

**Audit Mode** (default for testing):
```yaml
spec:
  validationFailureAction: audit  # Log violations, allow resource
```

- Violations logged to policy reports
- Resources still created
- Good for testing new policies

**Enforce Mode** (production):
```yaml
spec:
  validationFailureAction: enforce  # Block non-compliant resources
```

- Violations block resource creation
- Returns error to user
- Production-ready enforcement

### Per-Policy Configuration

```bash
# Check current mode
kubectl get clusterpolicy pod-security -o yaml | grep validationFailureAction

# Switch to audit mode (for testing)
kubectl patch clusterpolicy pod-security \
  -p '{"spec":{"validationFailureAction":"audit"}}'

# Switch to enforce mode (for production)
kubectl patch clusterpolicy pod-security \
  -p '{"spec":{"validationFailureAction":"enforce"}}'
```

## Monitoring & Auditing

### View Policy Reports

```bash
# List all policy reports
kubectl get policyreports -A

# View report for specific namespace
kubectl get policyreport -n myclient-prod -o yaml

# Count violations
kubectl get policyreports -A -o json | \
  jq '.items[].results[] | select(.result=="fail")' | wc -l
```

### View Policy Violations

```bash
# Recent violations (audit mode)
kubectl get events -n kyverno --sort-by='.lastTimestamp' | grep PolicyViolation

# Blocked requests (enforce mode)
kubectl get events -A | grep "denied the request"
```

### Kyverno Metrics

```bash
# Prometheus metrics endpoint
kubectl port-forward -n kyverno svc/kyverno-svc 8000:8000

# View metrics
curl http://localhost:8000/metrics | grep kyverno
```

**Key metrics:**
- `kyverno_policy_results_total` - Policy evaluation results
- `kyverno_admission_requests_total` - Total admission requests
- `kyverno_policy_execution_duration_seconds` - Policy execution time

## Troubleshooting

### Kyverno Blocking Legitimate Resources

**Problem:** Policy is too strict, blocking valid deployments.

**Solution 1: Use Audit Mode**
```bash
# Temporarily switch to audit mode
kubectl patch clusterpolicy <policy-name> \
  -p '{"spec":{"validationFailureAction":"audit"}}'

# Deploy resource
kubectl apply -f your-resource.yaml

# Review policy report
kubectl get policyreport -n <namespace>

# Fix policy or resource
# Switch back to enforce mode
```

**Solution 2: Add Exclusions**
```yaml
# Exclude specific namespaces from policy
spec:
  rules:
  - match:
      any:
      - resources:
          kinds:
          - Pod
          namespaces:
          - kube-system  # Exclude system namespace
          - longhorn-system  # Exclude storage
    exclude:
      resources:
        namespaces:
        - special-case-namespace  # Temporarily exclude
```

### Policy Not Applying

**Check 1: Verify policy is active**
```bash
kubectl get clusterpolicy <policy-name>
kubectl describe clusterpolicy <policy-name>
```

**Check 2: Check Kyverno webhook**
```bash
kubectl get validatingwebhookconfigurations | grep kyverno
kubectl get mutatingwebhookconfigurations | grep kyverno
```

**Check 3: Check Kyverno logs**
```bash
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno --tail=50
```

### High Latency / Slow Deployments

**Problem:** Kyverno adds latency to admission requests.

**Solution 1: Increase resources**
```yaml
# In helm-values.yaml
resources:
  requests:
    cpu: 200m  # Increase from 100m
    memory: 256Mi  # Increase from 128Mi
```

**Solution 2: Reduce policy scope**
```yaml
# Only apply to specific resource types
spec:
  rules:
  - match:
      any:
      - resources:
          kinds:
          - Pod  # Only pods, not all resources
```

## Best Practices

### 1. Start with Audit Mode
- Deploy policies in audit mode first
- Review policy reports for violations
- Fix resources or adjust policies
- Switch to enforce mode when ready

### 2. Use Namespace Exclusions
- Exclude system namespaces (kube-system, kyverno, etc.)
- System components may not comply with strict policies

### 3. Test Policies Thoroughly
- Test in dev/staging before production
- Validate common use cases
- Document exceptions

### 4. Monitor Policy Performance
- Track policy execution time
- Tune policies for performance
- Remove unused policies

### 5. Document Exceptions
- Document why exceptions are needed
- Review exceptions periodically
- Remove when no longer needed

## Integration with This IaC

Kyverno is **complementary** to this IaC's security:

| Security Layer | Tool | When Applied | What It Protects |
|----------------|------|--------------|------------------|
| **IaC Templates** | Helm | Deployment time | Enforces security in templates |
| **Admission Control** | Kyverno | Creation time | Blocks kubectl bypasses |
| **GitOps Sync** | ArgoCD | Continuous | Reverts manual changes |
| **Runtime** | Falco | Real-time | Detects runtime threats |

**All layers work together** - not redundant.

## Resources

- [Kyverno Documentation](https://kyverno.io/docs/)
- [Policy Library](https://kyverno.io/policies/)
- [Best Practices](https://kyverno.io/docs/writing-policies/best-practices/)

## See Also

- [Falco Runtime Security](../falco/README.md)
- [Baseline Security](../../security/README.md)
- [Security Tools Overview](../README.md)
