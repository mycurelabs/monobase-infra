# Architecture Documentation

Technical architecture of the Monobase Infrastructure template.

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Gateway Architecture](#gateway-architecture)
4. [Storage Architecture](#storage-architecture)
5. [Security Architecture](#security-architecture)
6. [Backup Architecture](#backup-architecture)
7. [Monitoring Architecture](#monitoring-architecture)

---

## Overview

### Design Principles

1. **No Overengineering** - Simple, proven technologies for <500 users
2. **Security by Default** - Zero-trust, encryption everywhere
3. **Fork-Based Workflow** - Reusable template, client-specific configuration
4. **Cloud-Native** - Kubernetes-native, CNCF projects preferred
5. **Cost-Effective** - Shared infrastructure, optional components

### High-Level System Architecture

```mermaid
graph TB
    subgraph "Internet"
        Users[👥 Users/Clients]
    end
    
    subgraph "Kubernetes Cluster"
        subgraph "gateway-system namespace"
            Gateway[🌐 Envoy Gateway<br/>shared-gateway<br/>2 replicas]
        end
        
        subgraph "client-a-prod namespace"
            Monobase API1[⚕️ Monobase API<br/>3 replicas]
            Monobase Account1[📱 Monobase Account<br/>2 replicas]
            API Worker1[🔄 API Worker<br/>2 replicas]
            PostgreSQL1[(🗄️ PostgreSQL<br/>3-node replica)]
            MinIO1[(📦 MinIO<br/>6-node distributed)]
        end
        
        subgraph "client-b-prod namespace"
            Monobase API2[⚕️ Monobase API]
            Apps2[📱 Apps...]
        end
        
        subgraph "Infrastructure"
            Longhorn[💾 Longhorn Storage]
            ArgoCD[🔄 ArgoCD GitOps]
            ExtSecrets[🔐 External Secrets]
            CertMgr[🔒 cert-manager]
            Velero[💼 Velero Backups]
        end
    end
    
    subgraph "Cloud Provider KMS"
        KMS[🔑 AWS Secrets Manager<br/>Azure Key Vault<br/>GCP Secret Manager]
    end
    
    Users -->|HTTPS| Gateway
    Gateway -->|HTTPRoute| Monobase API1
    Gateway -->|HTTPRoute| Monobase Account1
    Gateway -->|HTTPRoute| Monobase API2
    Monobase API1 --> PostgreSQL1
    Monobase API1 --> MinIO1
    API Worker1 --> PostgreSQL1
    ArgoCD -.->|manages| Monobase API1
    ArgoCD -.->|manages| Monobase Account1
    ExtSecrets -->|fetches| KMS
    ExtSecrets -.->|injects| Monobase API1
    Velero -.->|backups| PostgreSQL1
    Longhorn -.->|provides storage| PostgreSQL1
```

### Technology Stack

**Core (Always Deployed):**
- Kubernetes 1.27+ (EKS, AKS, GKE, or self-hosted)
- Envoy Gateway (Gateway API)
- Longhorn (distributed storage)
- ArgoCD (GitOps)
- External Secrets Operator (KMS integration)
- cert-manager (TLS automation)

**Applications:**
- Monobase API (API backend)
- Monobase Account (Vue.js frontend)
- PostgreSQL 7.x (primary database)

**Optional:**
- API Worker (real-time sync)
- MinIO (self-hosted S3)
- Valkey (Redis-compatible cache)
- Velero (Kubernetes backups)
- Prometheus + Grafana (monitoring)

**NOT Included (Deliberately):**
- ❌ Service Mesh (Istio/Linkerd) - Overkill for 3 services
- ❌ Self-hosted Vault - Use cloud KMS instead
- ❌ Rook-Ceph - Longhorn + MinIO simpler

---

## System Architecture

### Request Flow Diagram

```mermaid
sequenceDiagram
    participant U as 👤 User
    participant DNS as 🌐 DNS
    participant LB as ⚖️ LoadBalancer
    participant GW as 🚪 Envoy Gateway
    participant API as ⚕️ Monobase API
    participant DB as 🗄️ PostgreSQL
    participant S3 as 📦 MinIO/S3
    
    U->>DNS: api.client-a.com
    DNS-->>U: LoadBalancer IP
    U->>LB: HTTPS Request
    LB->>GW: Forward to Gateway
    Note over GW: Rate Limiting<br/>Security Headers<br/>TLS Termination
    GW->>GW: Match HTTPRoute<br/>(api.client-a.com)
    GW->>API: Route to Monobase API<br/>(client-a-prod ns)
    API->>DB: Query Data
    DB-->>API: Response
    API->>S3: Fetch File
    S3-->>API: File Data
    API-->>GW: JSON Response
    GW-->>LB: Response
    LB-->>U: HTTPS Response
```

### Multi-Tenant Architecture

```mermaid
graph TB
    subgraph "Single Kubernetes Cluster"
        subgraph "Shared Gateway"
            GW[Envoy Gateway<br/>LoadBalancer IP: X.X.X.X]
        end
        
        subgraph "client-a-prod namespace"
            R1[HTTPRoute<br/>api.client-a.com]
            H1[Monobase API-A]
            DB1[(PostgreSQL-A)]
        end
        
        subgraph "client-b-prod namespace"
            R2[HTTPRoute<br/>api.client-b.com]
            H2[Monobase API-B]
            DB2[(PostgreSQL-B)]
        end
        
        subgraph "client-c-staging namespace"
            R3[HTTPRoute<br/>api.client-c-staging.com]
            H3[Monobase API-C]
            DB3[(PostgreSQL-C)]
        end
        
        subgraph "Infrastructure (Shared)"
            NP[NetworkPolicies<br/>Namespace Isolation]
            Storage[Longhorn<br/>Distributed Storage]
        end
    end
    
    GW --> R1
    GW --> R2
    GW --> R3
    R1 --> H1
    R2 --> H2
    R3 --> H3
    H1 --> DB1
    H2 --> DB2
    H3 --> DB3
    NP -.->|isolates| client-a-prod
    NP -.->|isolates| client-b-prod
    NP -.->|isolates| client-c-staging
    Storage -.->|provides PVCs| DB1
    Storage -.->|provides PVCs| DB2
    Storage -.->|provides PVCs| DB3
```

### Component Diagram

```
                    Internet / DNS
                          |
                   [LoadBalancer IP]
                          |
        ┌─────────────────┴─────────────────┐
        │    gateway-system namespace       │
        │  ┌──────────────────────────────┐ │
        │  │   Shared Envoy Gateway       │ │
        │  │   - HTTPS listener (443)     │ │
        │  │   - HA: 2 replicas           │ │
        │  │   - Rate limiting            │ │
        │  │   - Security headers         │ │
        │  └──────────────────────────────┘ │
        └────────────────┬──────────────────┘
                         │
        ┌────────────────┴──────────────────┐
        │   myclient-prod namespace         │
        │                                   │
        │  ┌────────────────────────────┐  │
        │  │ HTTPRoutes (per service)   │  │
        │  │ - api.myclient.com         │  │
        │  │ - app.myclient.com         │  │
        │  │ - sync.myclient.com        │  │
        │  └─────┬──────────────────────┘  │
        │        │                          │
        │  ┌─────┴──────┬────────┬────────┐│
        │  │            │        │        ││
        │ ┌▼──────┐ ┌──▼────┐ ┌▼──────┐ ││
        │ │Monobase API│ │ API Worker │ │Account│ ││
        │ │ App   │ │       │ │ App   │ ││
        │ │2-3 rep│ │2 rep  │ │2 rep  │ ││
        │ └───┬───┘ └───┬───┘ └───────┘ ││
        │     │         │                ││
        │  ┌──┴─────────┴──┐             ││
        │  │               │             ││
        │ ┌▼────────────┐ ┌▼─────────┐  ││
        │ │  PostgreSQL    │ │  MinIO   │  ││
        │ │  Replica Set│ │ Distrib. │  ││
        │ │  3 nodes    │ │ 6 nodes  │  ││
        │ └──────┬──────┘ └────┬─────┘  ││
        │        │             │         ││
        │  ┌─────┴─────────────┴──────┐ ││
        │  │   Longhorn Storage       │ ││
        │  │   - 3x replication       │ ││
        │  │   - Snapshots            │ ││
        │  │   - Encryption           │ ││
        │  └──────────────────────────┘ ││
        └────────────────────────────────┘
```

### Data Flow

**1. User Request → Monobase API:**
```
Browser → DNS → LoadBalancer → Gateway (443) 
  → HTTPRoute (api.myclient.com) → Monobase API Service (7500) 
  → Monobase API Pod → PostgreSQL (5432)
```

**2. User Request → Frontend:**
```
Browser → DNS → LoadBalancer → Gateway (443)
  → HTTPRoute (app.myclient.com) → Monobase Account Service (80)
  → Monobase Account Pod (nginx serving static files)
```

**3. File Upload Flow:**
```
Client → Monobase API → MinIO S3 API (9000)
  → Longhorn PVC → Distributed storage across nodes
```

**4. File Download Flow:**
```
Client → Monobase API (generates presigned URL)
  → Client downloads directly from MinIO via Gateway
  → HTTPRoute (storage.myclient.com) → MinIO (9000)
```

---

## Gateway Architecture

### Shared Gateway Strategy

**Key Decision: 1 Gateway + Dynamic HTTPRoutes**

```
┌─────────────────────────────────────┐
│  gateway-system namespace (shared) │
│                                     │
│  ┌───────────────────────────────┐ │
│  │   Shared Gateway              │ │
│  │   - Single HTTPS listener     │ │
│  │   - Wildcard: *.myclient.com  │ │
│  │   - HA: 2 Envoy replicas      │ │
│  │   - Single LoadBalancer IP    │ │
│  └───────────────────────────────┘ │
└──────────────┬──────────────────────┘
               │ References
    ┌──────────┼──────────┐
    │          │          │
┌───▼────┐ ┌──▼─────┐ ┌─▼──────┐
│Client A│ │Client B│ │Client C│
│HTTPRtes│ │HTTPRtes│ │HTTPRtes│
└────────┘ └────────┘ └────────┘
```

**Benefits:**
- ✅ **Zero-downtime client onboarding** - HTTPRoutes added dynamically
- ✅ **Single LoadBalancer IP** - Cost-effective
- ✅ **Independent routing** - Each client controls their routes
- ✅ **Flexible hostnames** - Any domain per service

**HTTPRoute Pattern:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  parentRefs:
    - name: shared-gateway  # References shared Gateway
      namespace: gateway-system
  hostnames:
    - api.client.com       # Client-specific domain
  rules:
    - backendRefs:
        - name: api
          port: 7500
```

---

## Storage Architecture

### Longhorn Distributed Block Storage

```
┌─────────────────────────────────────────┐
│         Longhorn Storage Cluster        │
│                                         │
│  ┌────────┐  ┌────────┐  ┌────────┐   │
│  │ Node 1 │  │ Node 2 │  │ Node 3 │   │
│  │        │  │        │  │        │   │
│  │ Replica│  │ Replica│  │ Replica│   │
│  │   A    │  │   A    │  │   A    │   │
│  │ Replica│  │ Replica│  │ Replica│   │
│  │   B    │  │   B    │  │   B    │   │
│  └────────┘  └────────┘  └────────┘   │
│                                         │
│  Data replicated 3x across nodes       │
│  Can lose 2 nodes without data loss    │
└─────────────────────────────────────────┘
         ▲
         │ iSCSI / NVMe
         │
┌────────┴─────────┐
│  StatefulSets    │
│  - PostgreSQL       │
│  - MinIO         │
│  - Valkey     │
└──────────────────┘
```

**Features:**
- **3-way replication** - Data on 3 nodes
- **Automatic failover** - Rebuilds replicas on node failure
- **Snapshots** - Hourly local snapshots
- **Backups** - Daily S3 backups
- **Encryption** - dm-crypt volume encryption
- **Expansion** - Online volume resize

### MinIO Distributed Storage (Optional)

```
┌─────────────────────────────────────────┐
│     MinIO Erasure Coding (EC:2)         │
│                                          │
│  6 Nodes × 250Gi = 1.5TB raw            │
│  4 data + 2 parity = ~1TB usable (66%)  │
│                                          │
│  ┌──────┐ ┌──────┐ ┌──────┐            │
│  │Data 1│ │Data 2│ │Data 3│            │
│  │250Gi │ │250Gi │ │250Gi │            │
│  └──────┘ └──────┘ └──────┘            │
│  ┌──────┐ ┌──────┐ ┌──────┐            │
│  │Data 4│ │Parity│ │Parity│            │
│  │250Gi │ │ 1    │ │  2   │            │
│  └──────┘ └──────┘ └──────┘            │
│                                          │
│  Can lose 2 nodes without data loss     │
└──────────────────────────────────────────┘
```

**Why MinIO:**
- S3-compatible API
- No egress fees (self-hosted)
- <1TB data (cost-effective)
- Full control

**Why External S3:**
- >1TB data (scale better)
- Global CDN integration
- Managed service
- Built-in redundancy

---

## Security Architecture

### Zero-Trust Network Model

```
Default: DENY ALL
    ↓
┌─────────────────────────────────┐
│  All traffic blocked by default │
└─────────────────────────────────┘
    ↓
Explicit ALLOW rules:
    ↓
┌─────────────────────────────────┐
│ ✅ Gateway → Apps               │
│ ✅ Apps → PostgreSQL               │
│ ✅ Apps → Storage               │
│ ✅ Apps → Internet (HTTPS)      │
│ ❌ Cross-namespace (blocked)    │
│ ❌ Direct pod access (blocked)  │
└─────────────────────────────────┘
```

### Defense in Depth

**Layer 1: Network (NetworkPolicies)**
- Default deny all traffic
- Explicit allow rules only
- Cross-namespace isolation
- DNS and K8s API allowed

**Layer 2: Pod (Pod Security Standards)**
- Non-root containers
- No privilege escalation
- Drop ALL capabilities
- Read-only root filesystem
- seccomp profile enforced

**Layer 3: Application (RBAC)**
- Dedicated service accounts
- Least-privilege roles
- No default SA usage
- Namespace-scoped permissions

**Layer 4: Data (Encryption)**
- At rest: Longhorn + PostgreSQL encryption
- In transit: TLS everywhere (cert-manager)
- Backups: S3 + KMS encryption

**Layer 5: Access (External Secrets)**
- Secrets never in Git
- KMS integration (AWS/Azure/GCP)
- Automatic rotation
- Audit logging

---

## Backup Architecture

### 3-Tier Backup Strategy

```
┌─────────────────────────────────────────┐
│  Tier 1: Hourly Snapshots (Fast)        │
│  - Storage: Local (Longhorn nodes)      │
│  - Retention: 72 hours                  │
│  - Recovery: ~5 minutes                 │
│  - Use: Quick rollback, recent issues   │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│  Tier 2: Daily Backups (Medium)         │
│  - Storage: S3 (off-cluster)            │
│  - Retention: 30 days                   │
│  - Recovery: ~1 hour                    │
│  - Use: Last month recovery             │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│  Tier 3: Weekly Archive (Long-term)     │
│  - Storage: S3 Glacier (cold)           │
│  - Retention: 90+ days (HIPAA)          │
│  - Recovery: ~4 hours                   │
│  - Use: Compliance, disaster recovery   │
└─────────────────────────────────────────┘
```

**Backup Methods:**

1. **Longhorn Snapshots** - Volume-level, COW snapshots
2. **Velero Backups** - Kubernetes-native, application-aware
3. **PostgreSQL dumps** - Application-level (optional)

**Recovery Time Objectives (RTO):**
- Tier 1: 5 minutes
- Tier 2: 1 hour
- Tier 3: 4 hours

**Recovery Point Objectives (RPO):**
- Tier 1: 1 hour (max data loss)
- Tier 2: 24 hours
- Tier 3: 1 week

---

## Monitoring Architecture

### Optional Monitoring Stack

```
┌─────────────────────────────────────────┐
│           Applications                  │
│  Monobase API, API Worker, Account             │
│  /metrics endpoints                     │
└──────────────┬──────────────────────────┘
               │ scrape
        ┌──────▼────────┐
        │  Prometheus   │
        │  - 15d retain │
        │  - 50Gi PVC   │
        │  - HA: 2 rep  │
        └───┬───────┬───┘
            │       │
    ┌───────▼──┐ ┌─▼────────────┐
    │ Grafana  │ │ Alertmanager │
    │Dashboard │ │ Slack/PagerD │
    └──────────┘ └──────────────┘
```

**When to Enable:**
- Production environments
- >100 active users
- After baseline established
- Business-critical services

**Resource Overhead:**
- ~3-5% additional CPU/memory
- ~60Gi additional storage
- Worth it for production visibility

---

## High Availability

### Component HA Strategy

| Component | Replicas | Strategy | Downtime on Failure |
|-----------|----------|----------|---------------------|
| Monobase API | 2-3 | Rolling update + PDB | 0s (other pods serve) |
| Monobase Account | 2 | Rolling update + PDB | 0s |
| API Worker | 2 | Rolling update + PDB | 0s |
| PostgreSQL | 3 | Replica set | <30s (auto-failover) |
| MinIO | 6 | Erasure coding | 0s (2 node tolerance) |
| Envoy Gateway | 2 | Anti-affinity | <1s (pod swap) |
| Longhorn | 3 | Volume replication | 0s (auto-rebuild) |

### Update Strategy

**Zero-Downtime Updates:**
1. Rolling update with `maxSurge: 1`, `maxUnavailable: 0`
2. PodDisruptionBudget ensures `minAvailable: 1`
3. Health checks prevent unhealthy pod traffic
4. Gateway routes to healthy pods only

**Example Update:**
```
Before: Pod A (v1), Pod B (v1)
Step 1: Pod A (v1), Pod B (v1), Pod C (v2) ← new pod
Step 2: Pod A terminating, Pod B (v1), Pod C (v2)
Step 3: Pod B (v1), Pod C (v2), Pod D (v2) ← new pod
Step 4: Pod B terminating, Pod C (v2), Pod D (v2)
After: Pod C (v2), Pod D (v2) ← 100% v2, zero downtime
```

---

## Namespace Architecture

### Per-Client + Per-Environment Isolation

```
Cluster
├── gateway-system (shared)
│   └── shared-gateway (1 Gateway, HA: 2 replicas)
│
├── longhorn-system (shared)
│   └── Longhorn components
│
├── external-secrets-system (shared)
│   └── External Secrets Operator
│
├── velero (shared)
│   └── Velero backup controller
│
├── argocd (shared)
│   └── ArgoCD components
│
├── monitoring (shared, optional)
│   └── Prometheus + Grafana
│
├── client-a-prod
│   ├── api, api-worker, account
│   ├── postgresql, minio, valkey
│   └── HTTPRoutes → shared-gateway
│
├── client-a-staging
│   ├── api, account
│   ├── postgresql
│   └── HTTPRoutes → shared-gateway
│
└── client-b-prod
    ├── api, api-worker, account
    ├── postgresql, minio
    └── HTTPRoutes → shared-gateway
```

**Benefits:**
- **Isolation** - Each client in separate namespace
- **Security** - NetworkPolicies prevent cross-namespace traffic
- **Resource Control** - ResourceQuotas per namespace
- **Independent Scaling** - Scale clients independently
- **Cost Allocation** - Track resources per client

---

## Security Zones

### Zone Model

```
┌─────────────────────────────────────────┐
│  DMZ (Public Internet)                  │
│  - Gateway LoadBalancer (public IP)     │
│  - TLS termination                      │
│  - Rate limiting                        │
│  - DDoS protection                      │
└──────────────┬──────────────────────────┘
               │ HTTPS only
┌──────────────▼──────────────────────────┐
│  Application Zone                       │
│  - Monobase API, API Worker, Account           │
│  - NetworkPolicy: allow from Gateway    │
│  - Pod Security: restricted             │
└──────────────┬──────────────────────────┘
               │ Authenticated connections
┌──────────────▼──────────────────────────┐
│  Data Zone                              │
│  - PostgreSQL (TLS + auth)                 │
│  - MinIO (IAM auth)                     │
│  - NetworkPolicy: allow from apps only  │
│  - Encryption at rest                   │
└─────────────────────────────────────────┘
```

---

## Disaster Recovery

### RTO/RPO Targets

| Scenario | RTO | RPO | Recovery Method |
|----------|-----|-----|-----------------|
| Pod failure | 0s | 0 | Auto-restart + HA |
| Node failure | <30s | 0 | Pod rescheduling |
| AZ failure | <5min | 1h | Longhorn snapshot restore |
| Database corruption | <1h | 24h | Velero daily backup |
| Cluster failure | <4h | 1w | Velero weekly + new cluster |
| Region failure | <8h | 1w | Cross-region backup restore |

### Failure Scenarios

**1. Single Pod Failure:**
- **Detection:** Health check fails
- **Action:** Kubernetes restarts pod automatically
- **Impact:** None (other replicas serve traffic)
- **RTO:** <30s

**2. Node Failure:**
- **Detection:** Node goes NotReady
- **Action:** Pods rescheduled to healthy nodes
- **Impact:** Brief degradation if node had replicas
- **RTO:** 1-5 minutes
- **Longhorn:** Rebuilds volume replicas automatically

**3. PostgreSQL Replica Failure:**
- **Detection:** Replica set monitoring
- **Action:** Automatic failover to secondary
- **Impact:** <30s connection interruption
- **RTO:** <30s

**4. Complete Cluster Failure:**
- **Detection:** All nodes down
- **Action:** Restore to new cluster from Velero backup
- **Impact:** Full outage during restore
- **RTO:** 2-4 hours
- **RPO:** Last successful backup (24h max)

---

## Scalability

### Horizontal Scaling

**Application Pods (via HPA):**
```
Traffic increases → CPU >70% → HPA adds pods
  → More replicas → CPU normalizes → Stable
```

**Storage (via Volume Expansion):**
```
Storage fills → Expand PVC → Longhorn expands volume
  → No downtime → More space available
```

### Scaling Limits (Current Architecture)

| Component | Max Replicas | Bottleneck |
|-----------|--------------|------------|
| Monobase API | 10 | PostgreSQL connections |
| Monobase Account | 20 | None (stateless) |
| API Worker | 5 | WebSocket connections |
| PostgreSQL | 5 | Replication overhead |
| MinIO | 16 | Erasure coding limit |

**For >500 users:**
- Add PostgreSQL sharding
- Add read replicas
- Consider external S3
- Add caching layer (Redis)

---

## Summary

The Monobase Infrastructure template provides:

✅ **Modern Architecture** - Gateway API, GitOps, cloud-native
✅ **High Availability** - Multi-replica, auto-failover, zero-downtime
✅ **Security** - Zero-trust, encryption everywhere
✅ **Disaster Recovery** - 3-tier backups, tested procedures
✅ **Scalability** - HPA, storage expansion, multi-tenant
✅ **Observability** - Metrics, logs, alerts, dashboards

**Target:** <500 users, <1TB data per client
**Architecture:** Simple, proven, production-ready

For detailed operational procedures, see:
- [DEPLOYMENT.md](../getting-started/DEPLOYMENT.md) - Deployment steps
- [STORAGE.md](../operations/STORAGE.md) - Storage operations
- [BACKUP_DR.md](../operations/BACKUP_DR.md) - DR procedures
- [SCALING-GUIDE.md](../operations/SCALING-GUIDE.md) - Scaling guide
