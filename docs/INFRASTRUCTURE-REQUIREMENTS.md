# Infrastructure Requirements

Cluster specifications and sizing guide for LFH Infrastructure.

## Minimum Requirements (Core Stack)

**For single client with core components only:**

**Nodes:** 3 worker nodes
**CPU:** 4 cores per node (12 total)
**Memory:** 16GB per node (48GB total)
**Storage:** 100GB per node (for system + Longhorn)

**Workload:**
- HapiHub (2 replicas)
- MyCureApp (2 replicas)
- MongoDB (3 replicas)
- Longhorn, Gateway, ArgoCD, External Secrets

**Total Resource Usage:**
- ~7 CPU cores
- ~23Gi memory
- ~100Gi storage (MongoDB PVC)

## Recommended (Full Stack)

**For single client with all optional components:**

**Nodes:** 5 worker nodes
**CPU:** 8 cores per node (40 total)
**Memory:** 32GB per node (160GB total)
**Storage:** 500GB per node (for Longhorn pool)

**Workload:**
- All core components
- Syncd (2 replicas)
- MinIO (6 replicas)
- Typesense (3 replicas)
- Monitoring stack

**Total Resource Usage:**
- ~22 CPU cores
- ~53Gi memory
- ~1.15TB storage

## Multi-Tenant Sizing

**For multiple clients on same cluster:**

**Formula:**
- Base infrastructure: 3 CPU, 7Gi memory (shared)
- Per client (core): +7 CPU, +23Gi memory, +100Gi storage
- Per client (full): +22 CPU, +53Gi memory, +1.15TB storage

**Example (5 clients, core stack):**
- Infrastructure: 3 CPU, 7Gi
- 5 × clients: 35 CPU, 115Gi, 500Gi
- **Total: 38 CPU, 122Gi, 500Gi**
- **Cluster: 10 nodes × 4 CPU × 16GB**

## Kubernetes Version

**Minimum:** 1.25+
**Recommended:** 1.27+
**Features required:**
- Gateway API support (1.25+)
- Pod Security Standards (1.25+)
- CSI volume expansion (1.24+)

## Cloud Provider Recommendations

### AWS EKS
- **Node Type:** m6i.xlarge (4 vCPU, 16GB)
- **Storage:** gp3 EBS volumes
- **Networking:** VPC with 3 AZs
- **IAM:** IRSA for pod permissions
- **Addons:** EBS CSI driver, VPC CNI

### Azure AKS
- **Node Type:** Standard_D4s_v3 (4 vCPU, 16GB)
- **Storage:** Premium SSD
- **Networking:** Azure CNI
- **Identity:** Workload Identity
- **Features:** Azure Monitor integration

### GCP GKE
- **Node Type:** n2-standard-4 (4 vCPU, 16GB)
- **Storage:** pd-ssd
- **Networking:** VPC-native
- **Identity:** Workload Identity
- **Features:** GKE Autopilot (optional)

## Storage Requirements

### Longhorn Pool
- **Minimum:** 100GB per node
- **Recommended:** 500GB per node
- **Type:** SSD preferred
- **Replicas:** 3x replication (3 nodes minimum)

### Database Storage (MongoDB)
- **Small:** 20-50Gi (<10k patients)
- **Medium:** 50-200Gi (10k-100k patients)
- **Large:** 200Gi-1Ti (100k+ patients)
- **Growth:** Plan for 2x per year

### Object Storage (MinIO)
- **1TB usable:** 6 nodes × 250Gi = 1.5TB raw (EC:2)
- **2TB usable:** 6 nodes × 500Gi = 3TB raw (EC:2)
- **Or use external S3** for >1TB

## Network Requirements

**Bandwidth:**
- Minimum: 1 Gbps between nodes
- Recommended: 10 Gbps for production
- Internet: 100 Mbps minimum

**Latency:**
- Between nodes: <10ms (same AZ preferred)
- To internet: <100ms

**Ports:**
- 443 (HTTPS) - LoadBalancer
- 6443 (K8s API) - Control plane
- Internal cluster networking

## Compliance Requirements (HIPAA)

### Infrastructure
- [ ] Dedicated VPC/VNet (isolated network)
- [ ] Encryption at rest (EBS/disk encryption)
- [ ] Encryption in transit (TLS)
- [ ] Audit logging enabled
- [ ] BAA with cloud provider
- [ ] Access controls (IAM/RBAC)

### Cluster Configuration
- [ ] Private nodes (no public IPs)
- [ ] Bastion host for access
- [ ] Network policies enabled
- [ ] Pod Security Standards enforced
- [ ] Secrets in KMS

For more details, see [HIPAA-COMPLIANCE.md](HIPAA-COMPLIANCE.md).
