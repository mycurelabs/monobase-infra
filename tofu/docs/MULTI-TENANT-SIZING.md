# Multi-Tenant Cluster Sizing Guide

Comprehensive guide for sizing Kubernetes clusters to support multiple Monobase Infrastructure clients.

## Table of Contents

- [Overview](#overview)
- [Multi-Tenancy Architecture](#multi-tenancy-architecture)
- [Sizing Methodology](#sizing-methodology)
- [Resource Requirements](#resource-requirements)
- [Sizing Examples](#sizing-examples)
- [Scaling Strategies](#scaling-strategies)
- [Cost Analysis](#cost-analysis)
- [Monitoring & Right-Sizing](#monitoring--right-sizing)

---

## Overview

### What is Multi-Tenancy?

Multi-tenancy allows **multiple clients** (tenants) to share a single Kubernetes cluster while maintaining isolation and security.

**Monobase Infrastructure Multi-Tenant Model:**

```
Single Kubernetes Cluster
├── client-a-prod namespace
│   ├── HapiHub (1-2 pods)
│   ├── Syncd (1 pod)
│   └── MyCureApp (1-2 pods)
│
├── client-b-prod namespace
│   ├── HapiHub (1-2 pods)
│   ├── Syncd (1 pod)
│   └── MyCureApp (1-2 pods)
│
├── client-c-prod namespace
│   └── ... (same pattern)
│
├── gateway-system (shared)
│   └── Envoy Gateway (2-3 pods)
│
└── external-secrets (shared)
    └── External Secrets Operator (1 pod)
```

### Why Multi-Tenancy?

✅ **Benefits:**
- **Cost Efficient** - Shared infrastructure (control plane, networking, storage)
- **Easier Management** - One cluster to maintain vs. many
- **Better Utilization** - Resources shared across clients
- **Faster Provisioning** - Deploy new client in minutes, not hours
- **Simplified Monitoring** - Single pane of glass

⚠️ **Trade-offs:**
- Requires proper isolation (NetworkPolicies, ResourceQuotas)
- Noisy neighbor potential (need resource limits)
- Blast radius (one cluster failure affects all clients)
- Compliance complexity (PHI data isolation)

### When to Use Multi-Tenancy

✅ **Good Fit:**
- 5-30 small to medium clients
- Similar resource requirements
- Clients in same region
- Cost optimization priority

❌ **Not Recommended:**
- Very large clients (dedicated cluster better)
- Strict compliance isolation required
- Clients in different regions
- <5 clients (overhead not worth it)

---

## Multi-Tenancy Architecture

### Namespace Isolation

Each client gets a dedicated namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: client-a-prod
  labels:
    client: client-a
    environment: production
```

### Resource Quotas

Limit resources per namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: client-quota
  namespace: client-a-prod
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "16Gi"
    limits.cpu: "8"
    limits.memory: "32Gi"
    pods: "50"
```

### Network Policies

Isolate network traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: client-a-prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: client-a-prod
    - namespaceSelector:
        matchLabels:
          name: gateway-system
```

### Shared vs. Per-Client Resources

| Resource | Deployment Model | Reason |
|----------|------------------|--------|
| **HapiHub** | Per-client | Client-specific data |
| **Syncd** | Per-client | Client-specific sync logic |
| **MyCureApp** | Per-client | Client-specific branding |
| **Envoy Gateway** | Shared | Routing for all clients |
| **External Secrets** | Shared | Secret management |
| **Velero** | Shared | Backup all namespaces |
| **PostgreSQL** | Per-client | Data isolation |
| **Redis** | Per-client | Cache isolation |

---

## Sizing Methodology

### Step 1: Calculate Per-Client Resources

**Typical client resource usage:**

| Service | CPU Request | Memory Request | CPU Limit | Memory Limit | Replicas |
|---------|-------------|----------------|-----------|--------------|----------|
| HapiHub | 500m | 2Gi | 2000m | 4Gi | 2 |
| Syncd | 250m | 1Gi | 1000m | 2Gi | 1 |
| MyCureApp | 500m | 2Gi | 2000m | 4Gi | 2 |
| PostgreSQL | 500m | 2Gi | 2000m | 4Gi | 1 |
| Redis | 250m | 512Mi | 1000m | 1Gi | 1 |
| **Total per client** | **2000m (2 vCPU)** | **7.5Gi** | **8000m (8 vCPU)** | **15Gi** | **7 pods** |

### Step 2: Calculate Shared Resources

| Service | CPU Request | Memory Request | Replicas |
|---------|-------------|----------------|----------|
| Envoy Gateway | 500m | 1Gi | 3 |
| External Secrets | 100m | 256Mi | 1 |
| CoreDNS | 100m | 128Mi | 2 |
| Metrics Server | 100m | 256Mi | 1 |
| **Total shared** | **2100m (2.1 vCPU)** | **3.5Gi** | **7 pods** |

### Step 3: Add System Overhead

- **Kubernetes system pods**: ~1 vCPU, 2Gi per node
- **OS overhead**: ~0.5 vCPU, 1Gi per node
- **Buffer**: 20% for spikes


### Step 4: Calculate Total Cluster Size

**Formula:**
```
Total CPU = (Clients × Per-Client CPU) + Shared CPU + System Overhead
Total Memory = (Clients × Per-Client Memory) + Shared Memory + System Overhead
```

**Example for 10 clients:**
```
CPU = (10 × 2) + 2.1 + 5 (system) = ~27 vCPU
Memory = (10 × 7.5Gi) + 3.5Gi + 10Gi (system) = ~88Gi
```

**With 20% buffer:**
```
CPU = 27 × 1.2 = ~33 vCPU
Memory = 88 × 1.2 = ~106Gi
```

### Step 5: Choose Node Sizes

**AWS Example (m6i.2xlarge = 8 vCPU, 32Gi):**
```
Nodes needed: 
  CPU: 33 / 8 = 4.1 → 5 nodes
  Memory: 106 / 32 = 3.3 → 4 nodes
  Choose: 5 nodes (CPU is limiting factor)
```

---

## Resource Requirements

### Per-Client Baseline

**Small Client (< 1000 users):**
- CPU: 1.5 vCPU (requests), 6 vCPU (limits)
- Memory: 5Gi (requests), 12Gi (limits)
- Pods: ~5-7

**Medium Client (1000-5000 users):**
- CPU: 2 vCPU (requests), 8 vCPU (limits)
- Memory: 7.5Gi (requests), 15Gi (limits)
- Pods: ~7-10

**Large Client (5000+ users):**
- CPU: 4 vCPU (requests), 12 vCPU (limits)
- Memory: 12Gi (requests), 24Gi (limits)
- Pods: ~10-15
- Consider: Dedicated cluster

### Instance Type Recommendations

#### AWS (EKS)

| Client Count | Instance Type | vCPU | Memory | Nodes | Total vCPU | Total Memory |
|--------------|---------------|------|--------|-------|------------|--------------|
| 5-10 | m6i.xlarge | 4 | 16Gi | 5-8 | 20-32 | 80-128Gi |
| 10-15 | m6i.2xlarge | 8 | 32Gi | 4-6 | 32-48 | 128-192Gi |
| 15-25 | m6i.2xlarge | 8 | 32Gi | 6-10 | 48-80 | 192-320Gi |
| 25-30 | m6i.4xlarge | 16 | 64Gi | 5-8 | 80-128 | 320-512Gi |


#### Azure (AKS)

| Client Count | Instance Type | vCPU | Memory | Nodes | Total vCPU | Total Memory |
|--------------|---------------|------|--------|-------|------------|--------------|
| 5-10 | Standard_D4s_v5 | 4 | 16Gi | 5-8 | 20-32 | 80-128Gi |
| 10-15 | Standard_D8s_v5 | 8 | 32Gi | 4-6 | 32-48 | 128-192Gi |
| 15-25 | Standard_D8s_v5 | 8 | 32Gi | 6-10 | 48-80 | 192-320Gi |
| 25-30 | Standard_D16s_v5 | 16 | 64Gi | 5-8 | 80-128 | 320-512Gi |

#### GCP (GKE)

| Client Count | Instance Type | vCPU | Memory | Nodes | Total vCPU | Total Memory |
|--------------|---------------|------|--------|-------|------------|--------------|
| 5-10 | n2-standard-4 | 4 | 16Gi | 5-8 | 20-32 | 80-128Gi |
| 10-15 | n2-standard-8 | 8 | 32Gi | 4-6 | 32-48 | 128-192Gi |
| 15-25 | n2-standard-8 | 8 | 32Gi | 6-10 | 48-80 | 192-320Gi |
| 25-30 | n2-standard-16 | 16 | 64Gi | 5-8 | 80-128 | 320-512Gi |

### Why These Instance Types?

✅ **m6i/Standard_D/n2-standard (General Purpose)**
- Balanced CPU:Memory ratio (1:4)
- Good for mixed workloads
- Cost-effective
- Healthcare application fit

❌ **Avoid:**
- Compute-optimized (c-series): Low memory
- Memory-optimized (r-series): Expensive
- Burstable (t-series): Unreliable performance

---

## Sizing Examples

### Example 1: Small Deployment (5 Clients)

**Requirements:**
- 5 clients
- Small usage per client
- Cost-conscious

**Configuration (AWS EKS):**
```hcl
# terraform.tfvars

node_groups = {
  general = {
    instance_types = ["m6i.xlarge"]  # 4 vCPU, 16Gi
    desired_size   = 3  # Start small
    max_size       = 8  # Room to grow
    min_size       = 3  # HA minimum
  }
}
```

**Capacity:**
- Total: 12 vCPU, 48Gi (3 nodes)
- Per-client: ~2 vCPU, 7.5Gi
- Supports: 5 clients comfortably
- Can scale to: 8-10 clients (autoscale to 8 nodes)

**Monthly Cost:** ~$200-250

### Example 2: Medium Deployment (15 Clients)

**Requirements:**
- 15 clients
- Medium usage
- Production reliability

**Configuration (AWS EKS):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]  # 8 vCPU, 32Gi
    desired_size   = 5   # Good starting point
    max_size       = 12  # Scale headroom
    min_size       = 3   # HA minimum
  }
}
```

**Capacity:**
- Total: 40 vCPU, 160Gi (5 nodes)
- Per-client: ~2 vCPU, 7.5Gi
- Supports: 15 clients comfortably
- Can scale to: 20-22 clients (autoscale to 12 nodes)

**Monthly Cost:** ~$600-800

### Example 3: Large Deployment (25 Clients)

**Requirements:**
- 25 clients
- High availability
- Room for growth

**Configuration (AWS EKS):**
```hcl
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]  # 8 vCPU, 32Gi
    desired_size   = 8    # Start larger
    max_size       = 20   # Significant headroom
    min_size       = 5    # Higher minimum
  }
}
```

**Capacity:**
- Total: 64 vCPU, 256Gi (8 nodes)
- Per-client: ~2 vCPU, 7.5Gi
- Supports: 25 clients comfortably
- Can scale to: 30-35 clients (autoscale to 20 nodes)

**Monthly Cost:** ~$1000-1400

### Example 4: Mixed Workload (10 small + 3 large clients)

**Requirements:**
- 10 small clients (1.5 vCPU each)
- 3 large clients (4 vCPU each)
- Resource isolation

**Configuration (AWS EKS):**
```hcl
node_groups = {
  # General purpose pool
  general = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 4
    max_size       = 10
    min_size       = 3
  }
  
  # Large client pool (with taints)
  large_clients = {
    instance_types = ["m6i.4xlarge"]  # 16 vCPU, 64Gi
    desired_size   = 2
    max_size       = 5
    min_size       = 2
    taints = [{
      key    = "workload"
      value  = "large-client"
      effect = "NoSchedule"
    }]
  }
}
```

**Capacity:**
- General: 32 vCPU, 128Gi (4 nodes) → 10 small clients
- Large: 32 vCPU, 128Gi (2 nodes) → 3 large clients
- Total: 64 vCPU, 256Gi

**Monthly Cost:** ~$900-1200

---

## Scaling Strategies

### Horizontal Pod Autoscaling (HPA)

Scale pods based on CPU/memory:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hapihub-hpa
  namespace: client-a-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hapihub
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Cluster Autoscaling

Automatically add/remove nodes:

**How it works:**
1. Pod can't be scheduled (insufficient resources)
2. Cluster Autoscaler detects unschedulable pods
3. New node added to cluster
4. Pod scheduled on new node

**Configuration (already in modules):**
```hcl
# Already enabled in aws-eks, azure-aks, gcp-gke modules
enable_cluster_autoscaler = true

node_groups = {
  general = {
    min_size = 3   # Never go below
    max_size = 20  # Never go above
  }
}
```

### Vertical Pod Autoscaling (VPA)

Automatically adjust pod resource requests:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hapihub-vpa
  namespace: client-a-prod
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hapihub
  updatePolicy:
    updateMode: "Auto"  # Or "Recreate", "Initial"
```

### Scaling Best Practices

✅ **DO:**
- Start with conservative sizing (can scale up)
- Use HPA for application scaling
- Use Cluster Autoscaler for infrastructure
- Set appropriate min/max bounds
- Monitor utilization continuously
- Right-size after initial deployment

❌ **DON'T:**
- Over-provision initially (waste money)
- Set max too low (can't handle growth)
- Set min too high (waste money)
- Scale without monitoring

---

## Cost Analysis

### AWS EKS Cost Breakdown

**Control Plane:**
- $0.10/hour = ~$73/month (per cluster)

**Worker Nodes (m6i.2xlarge, us-east-1):**
- On-Demand: $0.384/hour = ~$280/month per node
- Spot: $0.115/hour = ~$84/month per node (70% savings!)

**Storage (gp3):**
- $0.08/GB-month

**Data Transfer:**
- Egress: $0.09/GB (first 10TB)

**Example Total (5 nodes on-demand):**
```
Control Plane: $73
Nodes: 5 × $280 = $1,400
Storage: 500GB × $0.08 = $40
Data Transfer: ~$50
Total: ~$1,563/month
```

**With Spot instances (5 nodes):**
```
Control Plane: $73
Nodes: 5 × $84 = $420
Storage: $40
Data Transfer: $50
Total: ~$583/month (63% savings!)
```

### Cost Per Client

| Clients | Nodes | Instance | Monthly Cost | Cost/Client |
|---------|-------|----------|--------------|-------------|
| 5 | 3 | m6i.xlarge | $300 | $60 |
| 10 | 5 | m6i.xlarge | $500 | $50 |
| 15 | 5 | m6i.2xlarge | $800 | $53 |
| 20 | 7 | m6i.2xlarge | $1,100 | $55 |
| 25 | 8 | m6i.2xlarge | $1,400 | $56 |
| 30 | 10 | m6i.2xlarge | $1,750 | $58 |

**Economies of Scale:**
- Cost per client decreases with more clients
- Shared infrastructure amortized
- Better resource utilization

### Cost Optimization Tips

✅ **Immediate Savings:**
1. **Use Spot Instances** (60-70% savings)
   - For non-production
   - Or mix: 50% spot, 50% on-demand

2. **Right-size instances**
   - Use latest generation (m6i vs m5)
   - Avoid over-provisioning

3. **Use gp3 volumes** (cheaper than gp2)
   ```hcl
   disk_size = 100  # Default in modules
   disk_type = "gp3"
   ```

4. **Enable Cluster Autoscaler**
   - Scale down during off-hours
   - Match demand dynamically

5. **Use VPC Endpoints** (AWS)
   - Reduce data transfer costs
   - Already configured in aws-eks module

✅ **Long-term Savings:**
1. **Reserved Instances** (1-3 year commit)
   - 30-60% discount
   - Once cluster size stabilizes

2. **Savings Plans** (AWS)
   - Flexible compute commitment
   - 20-40% discount

---

## Monitoring & Right-Sizing

### Key Metrics to Monitor

#### Cluster-Level Metrics

```bash
# CPU utilization
kubectl top nodes

# Memory utilization
kubectl top nodes

# Pod count per node
kubectl get pods -A -o wide | awk '{print $7}' | sort | uniq -c
```

**Target Utilization:**
- CPU: 50-70% average (allows burst headroom)
- Memory: 60-80% average
- Pods per node: <100

#### Namespace-Level Metrics

```bash
# Resource usage per namespace
kubectl top pods -n client-a-prod

# Quota usage
kubectl describe resourcequota -n client-a-prod
```

### Right-Sizing Process

#### Step 1: Collect Data (2-4 weeks)

```bash
# Install metrics-server (if not already)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Monitor continuously
kubectl top nodes > node-usage.log
kubectl top pods -A >> pod-usage.log
```

#### Step 2: Analyze Usage

**Questions to answer:**
- What's average CPU utilization? (target: 50-70%)
- What's average memory utilization? (target: 60-80%)
- Are there consistent under-utilized nodes?
- Are pods frequently OOMKilled?
- Is cluster autoscaler adding/removing nodes?

#### Step 3: Adjust

**If under-utilized (< 50% CPU):**
```hcl
# Reduce node count or downsize instances
node_groups = {
  general = {
    instance_types = ["m6i.xlarge"]  # Down from 2xlarge
    desired_size   = 4  # Down from 6
  }
}
```

**If over-utilized (> 80% CPU):**
```hcl
# Increase node count or upsize instances
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]  # Up from xlarge
    desired_size   = 8  # Up from 5
  }
}
```

**If memory-constrained:**
```hcl
# Switch to memory-optimized
node_groups = {
  general = {
    instance_types = ["r6i.xlarge"]  # 4 vCPU, 32Gi (1:8 ratio)
  }
}
```

### Monitoring Tools

**Built-in:**
- `kubectl top` - Basic metrics
- Cloud provider metrics (CloudWatch, Azure Monitor)

**Advanced:**
- **Prometheus + Grafana** - Industry standard
- **Datadog** - Commercial APM
- **New Relic** - Commercial APM
- **Kubecost** - Cost monitoring and optimization

---

## Sizing Decision Tree

```
Start: How many clients?

├─ < 5 clients
│  └─ Use: 3x m6i.xlarge (4 vCPU, 16Gi)
│     Cost: ~$300/month
│     Scale to: 8-10 clients
│
├─ 5-10 clients
│  └─ Use: 5x m6i.xlarge (4 vCPU, 16Gi)
│     Cost: ~$500/month
│     Scale to: 10-12 clients
│
├─ 10-15 clients
│  └─ Use: 5x m6i.2xlarge (8 vCPU, 32Gi)
│     Cost: ~$800/month
│     Scale to: 18-20 clients
│
├─ 15-25 clients
│  └─ Use: 7x m6i.2xlarge (8 vCPU, 32Gi)
│     Cost: ~$1,200/month
│     Scale to: 25-28 clients
│
├─ 25-30 clients
│  └─ Use: 10x m6i.2xlarge (8 vCPU, 32Gi)
│     Cost: ~$1,750/month
│
└─ > 30 clients
   └─ Consider: Multiple clusters or larger instances
      Regional split or dedicated clusters
```

---

## Quick Reference Tables

### Node Size Quick Reference

| Instance Type | vCPU | Memory | Clients Supported | Monthly Cost (AWS) |
|---------------|------|--------|-------------------|---------------------|
| m6i.xlarge | 4 | 16Gi | 1-2 | $100 |
| m6i.2xlarge | 8 | 32Gi | 3-4 | $280 |
| m6i.4xlarge | 16 | 64Gi | 7-8 | $560 |

### Cluster Configuration Quick Reference

| Clients | Min Nodes | Desired Nodes | Max Nodes | Instance Type | Monthly Cost |
|---------|-----------|---------------|-----------|---------------|--------------|
| 5 | 3 | 3 | 8 | m6i.xlarge | $300 |
| 10 | 3 | 5 | 10 | m6i.xlarge | $500 |
| 15 | 3 | 5 | 12 | m6i.2xlarge | $800 |
| 20 | 3 | 7 | 15 | m6i.2xlarge | $1,100 |
| 25 | 5 | 8 | 18 | m6i.2xlarge | $1,400 |
| 30 | 5 | 10 | 20 | m6i.2xlarge | $1,750 |

### Resource Quota Per Client

```yaml
# Recommended per-client quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: client-quota
spec:
  hard:
    # Small client
    requests.cpu: "2"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    
    # Medium client (adjust as needed)
    # requests.cpu: "3"
    # requests.memory: "12Gi"
    # limits.cpu: "12"
    # limits.memory: "24Gi"
    
    # Limits
    pods: "50"
    services: "20"
    persistentvolumeclaims: "10"
```

---

## Common Scenarios & Solutions

### Scenario 1: Rapid Client Growth

**Problem:** Adding 5 new clients per month

**Solution:**
```hcl
# Start with headroom
node_groups = {
  general = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 8   # Current need
    max_size       = 20  # Allow 2.5x growth
    min_size       = 5   # Higher floor for stability
  }
}

# Enable aggressive autoscaling
enable_cluster_autoscaler = true
```

**Monitor:** Weekly utilization, adjust max_size quarterly

### Scenario 2: Uneven Client Sizes

**Problem:** 20 small clients + 3 large clients

**Solution:** Multiple node pools
```hcl
node_groups = {
  # Small clients (default)
  small = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 6
    max_size       = 15
    min_size       = 3
  }
  
  # Large clients (dedicated)
  large = {
    instance_types = ["m6i.4xlarge"]
    desired_size   = 2
    max_size       = 5
    min_size       = 2
    labels = {
      workload = "large-client"
    }
    taints = [{
      key    = "workload"
      value  = "large-client"
      effect = "NoSchedule"
    }]
  }
}
```

### Scenario 3: Cost Reduction Priority

**Problem:** Need to cut costs by 30%

**Solutions:**
1. **Use Spot Instances** (60-70% savings)
   ```hcl
   capacity_type = "SPOT"  # AWS
   ```

2. **Right-size based on actual usage**
   - Monitor for 2 weeks
   - Downsize if < 50% utilized

3. **Reduce minimum node count**
   ```hcl
   min_size = 2  # Down from 3 (accept brief unavailability)
   ```

4. **Use Cluster Autoscaler aggressively**
   - Scale down unused nodes faster

### Scenario 4: Performance Priority

**Problem:** Users complaining about slow response

**Solutions:**
1. **Increase node sizes**
   ```hcl
   instance_types = ["m6i.4xlarge"]  # Up from 2xlarge
   ```

2. **Increase minimum nodes**
   ```hcl
   min_size = 8  # Higher floor, always capacity
   ```

3. **Use performance-optimized instances**
   ```hcl
   instance_types = ["c6i.2xlarge"]  # Compute-optimized
   ```

4. **Add HPA to applications**
   - Scale pods faster
   - Better resource distribution

---

## Validation Checklist

Before finalizing cluster size:

### Capacity Planning
- [ ] Calculated per-client resources (CPU, memory)
- [ ] Added shared infrastructure overhead
- [ ] Included 20% buffer for spikes
- [ ] Verified node sizes match requirements
- [ ] Planned for growth (max_size > current need)

### Cost Optimization
- [ ] Compared instance type options
- [ ] Considered spot instances
- [ ] Enabled cluster autoscaler
- [ ] Reviewed storage class (gp3 vs gp2)
- [ ] Planned for reserved instances (long-term)

### High Availability
- [ ] Minimum 3 nodes configured
- [ ] Multiple availability zones
- [ ] Node anti-affinity for critical pods
- [ ] Appropriate resource quotas per namespace

### Security & Isolation
- [ ] ResourceQuotas defined per namespace
- [ ] NetworkPolicies configured
- [ ] PodSecurityPolicies/Standards applied
- [ ] Separate node pools for workload isolation (if needed)


### Monitoring Setup
- [ ] Metrics server installed
- [ ] CloudWatch/Azure Monitor/Cloud Monitoring configured
- [ ] Alerts configured for high utilization
- [ ] Cost monitoring enabled (Kubecost or native)
- [ ] Scheduled reviews planned (monthly)

---

## Additional Resources

- **Cluster Provisioning**: [CLUSTER-PROVISIONING.md](./CLUSTER-PROVISIONING.md)
- **Module Development**: [MODULE-DEVELOPMENT.md](./MODULE-DEVELOPMENT.md)
- **Architecture**: [../PLAN.md](../PLAN.md)
- **Main README**: [../README.md](../README.md)

### External Resources

- **Kubernetes Resource Management**: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- **AWS EKS Best Practices**: https://aws.github.io/aws-eks-best-practices/
- **Azure AKS Best Practices**: https://learn.microsoft.com/en-us/azure/aks/best-practices
- **GCP GKE Best Practices**: https://cloud.google.com/kubernetes-engine/docs/best-practices

---

## Summary

**Key Takeaways:**

1. **Per-Client Baseline**: ~2 vCPU, 7.5Gi memory
2. **Recommended Instance Type**: m6i.2xlarge (8 vCPU, 32Gi)
3. **Starting Configuration**: 3-5 nodes, scale to 20
4. **Cost Per Client**: $50-60/month (at scale)
5. **Monitor & Adjust**: Review monthly, right-size quarterly

**Formula to Remember:**
```
Total CPU = (Clients × 2 vCPU) + 5 vCPU (overhead) × 1.2 (buffer)
Total Memory = (Clients × 7.5Gi) + 10Gi (overhead) × 1.2 (buffer)

Nodes = Total CPU / Instance vCPU (round up)
```

**Example for 10 clients:**
```
CPU = (10 × 2) + 5 = 25 × 1.2 = 30 vCPU
Memory = (10 × 7.5) + 10 = 85 × 1.2 = 102Gi

With m6i.2xlarge (8 vCPU, 32Gi):
  CPU: 30 / 8 = 3.75 → 4 nodes
  Memory: 102 / 32 = 3.2 → 4 nodes
  
Result: 4-5 nodes (start with 5 for headroom)
```

**Start Conservative, Scale Smart!**

---

**Need help sizing your cluster? Use the decision tree and quick reference tables above!**
