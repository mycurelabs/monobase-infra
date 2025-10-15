# Storage Provider Guide

Choosing and configuring storage for Monobase Infrastructure.

## Quick Recommendation

**Use `cloud-default`** for most deployments - it's simpler and uses your cluster's native storage.

## Configuration

```yaml
# config/myclient/values-production.yaml
global:
  storage:
    provider: cloud-default  # Recommended for cloud deployments
    className: ""  # Empty = use cluster default
```

## Provider Options

### 1. cloud-default (Recommended for Cloud)

**Uses cluster's default StorageClass:**
- AWS EKS → EBS CSI (gp2/gp3)
- Azure AKS → Azure Disk CSI  
- GCP GKE → GCP Persistent Disk
- No additional components to deploy!

**Pros:** Simple, managed, native integration
**Cons:** Cloud-specific, not portable

### 2. longhorn (Recommended for On-Prem)

**Deploys Longhorn distributed storage.**

**Pros:** Cloud-agnostic, advanced features, on-prem support
**Cons:** Requires management, resource overhead

**Use when:** On-premises, multi-cloud, need full control

### 3. local-path (For k3d/kind Testing)

**Uses local-path-provisioner.**

**Pros:** Simple, built-in to k3d/kind, perfect for testing
**Cons:** Not HA, not for production

**Use when:** Local development, CI/CD testing

## Quick Comparison

| Provider | Best For | Complexity | Cost |
|----------|----------|------------|------|
| cloud-default | Cloud (EKS/AKS/GKE) | Low | Low |
| longhorn | On-prem, multi-cloud | Medium | Medium |
| local-path | k3d/kind testing | Low | Free |

See: `infrastructure/longhorn/README.md` for Longhorn details.
