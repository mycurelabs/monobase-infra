# Security Tools (Optional)

Advanced security tools for production environments requiring enhanced protection.

## Overview

This directory contains **optional** security tools that complement the baseline security provided in `infrastructure/security/`:

| Tool | Type | Purpose | Deployment |
|------|------|---------|------------|
| **Kyverno** | Policy Engine | Admission control, policy enforcement | Cluster-wide |
| **Falco** | Runtime Security | Threat detection, anomaly detection | DaemonSet (per-node) |

## Baseline Security (Always Enabled)

The following security measures are **always active** via `infrastructure/security/`:

- NetworkPolicies (default-deny, explicit allow rules)
- Pod Security Standards (restricted profile)
- RBAC (least-privilege service accounts)
- Encryption at rest and in transit

**These are sufficient for most deployments.**

## When to Enable Security Tools

### Decision Matrix

| Deployment Scenario | Kyverno | Falco | Reasoning |
|---------------------|---------|-------|-----------|
| 100% GitOps, single team | ❌ | ✅ | IaC controls config, need runtime protection |
| 100% GitOps, multi-team | ✅ | ✅ | Teams may bypass GitOps |
| Ad-hoc kubectl allowed | ✅ | ✅ | Need both layers of protection |
| HIPAA compliance | ⚠️ | ✅ | Falco required, Kyverno for audit trail |
| Dev/staging | ❌ | ❌ | Overhead not justified |
| Production <100 users | ❌ | ⚠️ | Consider Falco only |
| Production >100 users | ⚠️ | ✅ | Falco recommended, Kyverno optional |
| Multi-tenant cluster | ✅ | ✅ | Both strongly recommended |

**Legend:**
- ✅ **Recommended** - Clear benefit for this scenario
- ⚠️ **Optional** - Consider based on requirements
- ❌ **Skip** - Not needed or overhead not justified

### Quick Decision Guide

**Enable Kyverno if you have:**
- Multiple teams with kubectl access
- Ad-hoc deployments outside GitOps
- Third-party Helm charts installed manually
- Compliance requirements for automated policy enforcement
- Multi-tenant clusters

**Enable Falco if you have:**
- Production environment
- HIPAA/SOC2/PCI compliance requirements
- Need runtime threat detection
- >100 active users
- Sensitive data (PHI, PII, financial)

## What Each Tool Does

### Kyverno - Admission Control

**Purpose:** Validates and mutates Kubernetes resources at admission time (before they're created).

**How it works:**
1. Intercepts all resource creation requests
2. Checks against defined policies
3. Blocks non-compliant resources OR mutates them to comply
4. Logs violations for audit

**Example:**
```bash
# Developer tries to create pod running as root
kubectl run test --image=nginx

# Kyverno intercepts request
# Checks policy: "Pods must set runAsNonRoot=true"
# BLOCKS creation ❌
# Returns error: "Policy violation: requires runAsNonRoot"
```

**What it protects against:**
- Developers bypassing GitOps with direct kubectl
- Third-party charts violating security standards
- Accidental misconfigurations
- Non-compliant resource definitions

**What it DOESN'T protect against:**
- Runtime attacks (use Falco for this)
- Drift in running resources (ArgoCD selfHeal handles this)
- Vulnerabilities in images (use Trivy for this)

### Falco - Runtime Threat Detection

**Purpose:** Monitors running containers for suspicious behavior and security threats.

**How it works:**
1. Uses eBPF to monitor system calls in real-time
2. Detects anomalous behavior patterns
3. Triggers alerts when rules match
4. Sends notifications to Slack/PagerDuty/Syslog

**Example:**
```bash
# Container gets compromised, attacker spawns shell
kubectl exec -it api-pod -- /bin/bash

# Falco detects system call pattern
# Matches rule: "Shell spawned in container"
# TRIGGERS ALERT 🚨
# Sends to Slack: "⚠️ Shell spawned in api-pod (myclient-prod)"
```

**What it protects against:**
- Compromised containers
- Privilege escalation attempts
- Unexpected network connections
- Sensitive file access (/etc/shadow, SSH keys)
- Cryptomining malware
- Data exfiltration

**What it DOESN'T protect against:**
- Non-compliant deployments (use Kyverno for this)
- Vulnerabilities before exploitation (use Trivy for this)
- Network-level attacks (use NetworkPolicies for this)

## Use Case Examples

### Kyverno Use Cases

#### Use Case 1: Block Root Containers
**Scenario:** Developer tries to bypass GitOps and deploy insecure pod.

```bash
# Developer attempts direct deployment
kubectl run debug --image=ubuntu --restart=Never

# Without Kyverno: ✅ Pod created (running as root - insecure!)
# With Kyverno: ❌ Blocked - "Policy violation: requires runAsNonRoot=true"
```

#### Use Case 2: Enforce Standard Labels
**Scenario:** All resources must have standard labels for tracking.

```bash
# Create deployment without required labels
kubectl create deployment test --image=nginx

# Without Kyverno: ✅ Created (missing labels)
# With Kyverno: ❌ Blocked - "Missing required labels: app, environment"
```

#### Use Case 3: Restrict Image Registries
**Scenario:** Only allow images from trusted registries.

```bash
# Try to use untrusted registry
kubectl run test --image=docker.io/malicious/image

# Without Kyverno: ✅ Created (potential security risk)
# With Kyverno: ❌ Blocked - "Image must be from ghcr.io or approved registry"
```

### Falco Use Cases

#### Use Case 1: Detect Shell in Container
**Scenario:** Attacker exploits vulnerability and spawns shell.

```bash
# Attacker gets shell access
kubectl exec -it api-pod -- /bin/bash

# Falco Alert:
# Rule: Shell spawned in container
# Container: api-pod
# User: root
# Command: /bin/bash
# Action: ALERT sent to Slack
```

#### Use Case 2: Detect Sensitive File Read
**Scenario:** Container tries to read sensitive files.

```bash
# Malicious process reads secrets
cat /etc/shadow
cat /root/.ssh/id_rsa

# Falco Alert:
# Rule: Read sensitive file
# File: /etc/shadow
# Process: cat
# Action: ALERT sent to PagerDuty
```

#### Use Case 3: Detect Unexpected Network Connection
**Scenario:** Cryptominer tries to connect to mining pool.

```bash
# Malicious process opens connection
curl http://mining-pool.com:3333

# Falco Alert:
# Rule: Unexpected outbound connection
# Destination: mining-pool.com:3333
# Process: curl
# Action: ALERT + Log to SIEM
```

## Resource Overhead

### Kyverno

| Resource | Cluster-wide | Per-Node | Total (3 nodes) |
|----------|--------------|----------|-----------------|
| CPU | 100m | - | 100m |
| Memory | 128Mi | - | 128Mi |
| Storage | 1Gi (logs) | - | 1Gi |

**Overhead:** ~0.5% of cluster resources

### Falco

| Resource | Cluster-wide | Per-Node | Total (3 nodes) |
|----------|--------------|----------|-----------------|
| CPU | - | 100m | 300m |
| Memory | - | 256Mi | 768Mi |
| Storage | - | 2Gi (logs) | 6Gi |

**Overhead:** ~1.5% of cluster resources

### Both Enabled

**Total overhead:** ~2-3% of cluster resources
- CPU: 400m (~2% of 20 vCPU cluster)
- Memory: ~1Gi (~1.5% of 64Gi cluster)
- Storage: ~7Gi

**Acceptable for production environments with >100 users.**

## Installation

### Prerequisites

```bash
# Add Helm repositories
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
```

### Install Kyverno

```bash
# Install Kyverno controller (cluster-wide)
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --values infrastructure/security-tools/kyverno/helm-values.yaml

# Wait for Kyverno to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyverno -n kyverno --timeout=120s

# Apply policies
kubectl apply -f infrastructure/security-tools/kyverno/policies/

# Verify policies are installed
kubectl get clusterpolicies
```

### Install Falco

```bash
# Install Falco DaemonSet (per-node)
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --values infrastructure/security-tools/falco/helm-values.yaml

# Verify Falco is running on all nodes
kubectl get pods -n falco -o wide

# Apply custom rules
kubectl apply -f infrastructure/security-tools/falco/rules/

# Check Falco logs
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
```

## Testing

### Test Kyverno

```bash
# Test 1: Try to create non-compliant pod (should be BLOCKED)
kubectl run test-root --image=nginx --restart=Never

# Expected: Error: admission webhook denied the request
# Policy violation: requires runAsNonRoot=true

# Test 2: Create compliant pod (should SUCCEED)
kubectl run test-nonroot --image=nginx --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000}}}'

# Expected: pod/test-nonroot created

# Clean up
kubectl delete pod test-nonroot
```

### Test Falco

```bash
# Test 1: Trigger shell detection
kubectl exec -it api-pod -- /bin/bash
# Check Falco logs for alert
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Shell spawned"

# Test 2: Trigger sensitive file read
kubectl exec -it api-pod -- cat /etc/shadow
# Check Falco logs for alert
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Sensitive file"
```

## Integration with Existing Security

Security tools work in **layers**:

```
Layer 1: Infrastructure Security (Always Active)
├── NetworkPolicies - Network segmentation
├── Pod Security Standards - Container security baseline
├── RBAC - Access control
└── Encryption - Data protection

Layer 2: Admission Control (Optional - Kyverno)
├── Policy enforcement at deployment time
├── Validates resource definitions
└── Blocks non-compliant resources

Layer 3: Runtime Protection (Optional - Falco)
├── Monitors running containers
├── Detects anomalous behavior
└── Alerts on security events

All layers are complementary, not redundant.
```

## Monitoring & Alerts

### Kyverno Metrics

```bash
# Policy violations (blocked requests)
kubectl get events -n kyverno

# Policy report (audit mode)
kubectl get policyreports -A
```

### Falco Alerts

Configure alert destinations in `falco/helm-values.yaml`:

- **Slack** - Real-time alerts to security channel
- **PagerDuty** - Critical alerts for on-call
- **Syslog** - Centralized logging (SIEM integration)
- **File** - Local logs for audit trail

## Troubleshooting

### Kyverno Blocking Legitimate Resources

```bash
# Check which policy is blocking
kubectl describe pod <pod-name>

# Temporarily disable policy (NOT recommended for production)
kubectl patch clusterpolicy <policy-name> -p '{"spec":{"validationFailureAction":"audit"}}'

# Fix the resource to comply with policy
# Then re-enable enforce mode
kubectl patch clusterpolicy <policy-name> -p '{"spec":{"validationFailureAction":"enforce"}}'
```

### Falco Too Noisy

```bash
# Check which rules are triggering
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -E "Notice|Warning|Error"

# Tune rules in falco/helm-values.yaml
# Adjust priority levels or disable specific rules
```

## See Also

- [Kyverno Documentation](kyverno/README.md) - Detailed Kyverno guide
- [Falco Documentation](falco/README.md) - Detailed Falco guide
- [Baseline Security](../security/README.md) - Manual NetworkPolicies and RBAC
- [Security Hardening Guide](../../docs/security/SECURITY-HARDENING.md) - Complete security overview
