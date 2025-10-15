# Monobase Infrastructure

**Reusable Kubernetes Infrastructure Template**

This repository provides production-ready, template-based Kubernetes infrastructure that can be easily customized and deployed to any cluster using modern best practices.

## 🎯 Key Features

- **Fork-Based Workflow** - Clients fork this template and add their configuration
- **100% Parameterized** - No hardcoded client-specific values in base template
- **Security by Default** - NetworkPolicies, Pod Security Standards, encryption
- **Compliance Ready** - Built-in security controls and compliance features
- **Modern Stack** - Gateway API, ArgoCD GitOps, External Secrets, Velero backups
- **Scalable** - Designed for <500 users, <1TB data per client (scales further if needed)

## 📦 Scope & Repository Structure

This repository contains **complete infrastructure** for deploying applications on Kubernetes.

### Repository Structure

```
monobase-infra/
├── tofu/                    # ← OPTIONAL: Cluster provisioning (OpenTofu/Terraform)
│   ├── modules/             #    - AWS EKS, Azure AKS, GCP GKE
│   │   ├── aws-eks/         #    - K3s on-premises, k3d local
│   │   ├── azure-aks/       #    Only needed if provisioning clusters
│   │   ├── gcp-gke/         #    Can skip if cluster already exists
│   │   ├── on-prem-k3s/
│   │   └── k3d-local/
│   └── clusters/            #    Example cluster configurations
├── charts/                  # ← CORE: Helm charts for applications
│   ├── api/
│   ├── api-worker/
│   └── account/
├── config/                  # ← CORE: Client configurations
│   ├── profiles/            #    Pre-configured size profiles
│   └── example.com/         #    Example client config
├── infrastructure/          # ← CORE: K8s infrastructure components
│   ├── envoy-gateway/
│   ├── argocd/
│   ├── longhorn/
│   └── ...
├── argocd/                  # ← CORE: GitOps configuration
├── scripts/                 # ← CORE: Automation scripts
└── docs/                    # ← CORE: Documentation
```

### What's Included ✅
- **Cluster Provisioning (Optional)**: OpenTofu modules for AWS/Azure/GCP/on-prem/local
- **Application Deployments**: Monobase API, API Worker, Monobase Account Helm charts
- **Storage Infrastructure**: Longhorn distributed block storage
- **Networking & Routing**: Envoy Gateway with Gateway API
- **Security Layer**: NetworkPolicies, Pod Security Standards, RBAC, encryption
- **Backup & Disaster Recovery**: Velero 3-tier backups
- **Monitoring Stack**: Prometheus + Grafana (optional)
- **GitOps**: ArgoCD with App-of-Apps pattern
- **Secrets Management**: External Secrets Operator + Cloud KMS
- **Configuration Profiles**: Pre-configured small/medium/large deployments

### Prerequisites

**Required:**
- ✅ Existing Kubernetes cluster (EKS, AKS, GKE, or self-hosted)
- ✅ kubectl configured and authenticated
- ✅ Helm 3.x installed
- ✅ Cluster meets [minimum requirements](docs/getting-started/INFRASTRUCTURE-REQUIREMENTS.md)

**Minimum Cluster Specs:**
- 3 worker nodes
- 4 CPU cores per node (12 total)
- 16GB RAM per node (48GB total)
- 100GB storage per node

### Optional: Cluster Provisioning

If you need to create Kubernetes clusters, use these tools **before** deploying this template:

**Infrastructure as Code (Recommended for Production):**
- **OpenTofu/Terraform** - Full infrastructure control
  - [AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws)
  - [Azure AKS Module](https://registry.terraform.io/modules/Azure/aks/azurerm)
  - [GCP GKE Module](https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google)
- **Terragrunt** - DRY Terraform wrapper for multi-environment setups
- **Pulumi** - Modern IaC with programming languages

**Quick Setup (Good for Testing):**
- **eksctl** - `eksctl create cluster --name myclient --nodes 3 --node-type m6i.xlarge`
- **az cli** - `az aks create --resource-group rg --name myclient --node-count 3`
- **gcloud** - `gcloud container clusters create myclient --num-nodes=3`

**Complementary Framework:**
- [k8s-iac-framework](https://github.com/malayh/k8s-iac-framework) - Full-stack IaC with OpenTofu + Terragrunt + apps

**This template works with ANY Kubernetes cluster regardless of how it was provisioned.**

## 🚀 Quick Start

### Choose Your Path

#### **Track 1: I Already Have a Kubernetes Cluster** ✅ (Most Common)

If you already have an EKS/AKS/GKE/K3s cluster:

```bash
# 1. Fork and clone
git clone https://github.com/YOUR-ORG/monobase-infra.git
cd monobase-infra

# 2. Create client configuration from base profile
cp config/profiles/production-base.yaml config/myclient/values-production.yaml

# 3. Edit configuration (minimal overrides only)
vim config/myclient/values-production.yaml
# Required changes:
#   - global.domain: myclient.com
#   - global.namespace: myclient-prod
#   - api.image.tag: "5.215.2" (pin version)
#   - account.image.tag: "1.0.0" (pin version)
# Optional: Adjust resources, storage sizes, enable components
# Keep it minimal! (~60 lines vs 430 lines)

# 5. Deploy infrastructure
kubectl apply -f infrastructure/

# 6. Deploy applications  
helm install myclient-prod charts/api \
  --values config/myclient/values-production.yaml \
  --namespace myclient-prod --create-namespace
```

**You can skip the `tofu/` directory entirely!**

---

#### **Track 2: I Need to Provision a Cluster** 🏗️ (Optional)

If you need to create a Kubernetes cluster first:

```bash
# 1. Fork and clone (same as above)
git clone https://github.com/YOUR-ORG/monobase-infra.git
cd monobase-infra

# 2. Provision cluster using OpenTofu
cd tofu/clusters/
cp -r default-cluster myclient-cluster
cd myclient-cluster

# 3. Configure cluster
vim terraform.tfvars
# Set: cluster_name, region, deployment_profile (small/medium/large)

# 4. Create cluster
tofu init
tofu plan
tofu apply

# 5. Get kubeconfig
tofu output -raw kubeconfig > ~/.kube/myclient
export KUBECONFIG=~/.kube/myclient

# 6. Now follow Track 1 steps 2-6
cd ../../../
./scripts/new-client-config.sh myclient myclient.com
# - global.namespace: myclient-prod
# - global.storage.provider: cloud-default (EKS/AKS/GKE) or longhorn (on-prem)
# - Image tags (replace "latest" with specific versions)
# - Resource limits (CPU, memory)
# - Storage sizes (PostgreSQL, MinIO, etc.)
# - Hostnames for each service
```

### 4. Configure Secrets Management

```bash
vim config/myclient/secrets-mapping.yaml

# Map your KMS secret paths:
# - AWS Secrets Manager
# - Azure Key Vault
# - GCP Secret Manager
# - SOPS encrypted files
```

### 5. Commit Your Configuration

```bash
git add config/myclient/
git commit -m "Add MyClient production configuration"
git push origin main
```

### 6. Deploy Infrastructure (One-Time Setup)

```bash
# Deploy core infrastructure to your cluster
kubectl apply -f infrastructure/longhorn/
kubectl apply -f infrastructure/envoy-gateway/
kubectl apply -f infrastructure/external-secrets-operator/
kubectl apply -f infrastructure/argocd/
```

### 7. Deploy Applications via ArgoCD

```bash
# Render templates with your config
./scripts/render-templates.sh \\
  --values config/myclient/values-production.yaml \\
  --output rendered/myclient/

# Deploy ArgoCD root application
kubectl apply -f rendered/myclient/argocd/root-app.yaml

# Watch deployment progress
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open https://localhost:8080
```

## ⚙️ Configuration Approach

### Profile-Based Configuration (Recommended)

This template uses a **profile-based configuration** system to minimize boilerplate and maximize maintainability:

**Base Profiles:**
- `config/profiles/production-base.yaml` - Production defaults (HA, backups, security)
- `config/profiles/staging-base.yaml` - Staging defaults (single replicas, Mailpit enabled)
- `config/profiles/production-{small|medium|large}.yaml` - Sized profiles

**Your Client Config:**
1. Copy a base profile to `config/yourclient/values-{env}.yaml`
2. Change only required values (domain, namespace, image tags)
3. Override only what's different from the base
4. Keep your config minimal (~60 lines instead of 430 lines)

**Example:**
```yaml
# config/myclient/values-production.yaml (60 lines)
global:
  domain: myclient.com
  namespace: myclient-prod

api:
  image:
    tag: "5.215.2"  # Pin version

postgresql:
  persistence:
    size: 200Gi  # Override default of 50Gi

# Everything else inherits from production-base.yaml
```

See `config/profiles/README.md` for detailed workflow and examples.

## 📋 What's Included

### Required Core Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Gateway | Envoy Gateway | Shared Gateway API routing, zero-downtime updates |
| API Backend | Monobase API | Core API service |
| Frontend | Monobase Account | React/Vite frontend application |
| Database | PostgreSQL 16.x | Primary datastore with replication |
| Storage | Cloud-native or Longhorn | Persistent storage for databases |
| GitOps | ArgoCD | Declarative deployments with web UI |
| Secrets | External Secrets Operator | KMS integration (AWS/Azure/GCP/SOPS) |

### Storage Provider Options

The infrastructure **automatically selects** the appropriate storage provider based on `global.storage.provider`:

| Provider | Use When | StorageClass | Auto-Deploy Longhorn? |
|----------|----------|--------------|----------------------|
| `ebs-csi` | **AWS EKS** | `gp3` | ❌ No (uses native EBS) |
| `azure-disk` | **Azure AKS** | `managed-premium` | ❌ No (uses Azure Disk) |
| `gcp-pd` | **GCP GKE** | `pd-ssd` | ❌ No (uses GCP PD) |
| `longhorn` | **On-prem/Bare-metal** | `longhorn` | ✅ Yes (self-hosted storage) |
| `local-path` | **k3d/k3s dev** | `local-path` | ❌ No (local development) |
| `cloud-default` | **Any cloud** | (cluster default) | ❌ No (uses provider default) |

**Recommendation:**
- **Cloud deployments** (EKS/AKS/GKE): Use native CSI drivers (`ebs-csi`, `azure-disk`, `gcp-pd`)
- **On-premises/bare-metal**: Use `longhorn` for distributed block storage
- **Development**: Use `local-path` for simplicity

### Optional Add-On Components

| Component | Enable When | Purpose |
|-----------|-------------|---------|
| API Worker | Offline/mobile sync needed | Real-time data synchronization |
| Valkey | Search features needed | Full-text search engine |
| MinIO | Self-hosted S3 needed | Object storage (files, images) |
| Monitoring | Production visibility needed | Prometheus + Grafana metrics |
| Velero | Backup/DR required | Kubernetes-native backups |
| Mailpit | Dev/staging only | Email testing (SMTP capture) |

## 🏗️ Architecture

```
Internet → Envoy Gateway (shared, HA) → HTTPRoutes (per client/env) → Applications
                                                                      ↓
                                                            PostgreSQL + Longhorn Storage
                                                            MinIO (optional)
                                                            Valkey (optional)
```

**Key Design Decisions:**
- **Shared Gateway** - One Gateway in `gateway-system`, HTTPRoutes per client (zero-downtime)
- **Namespace Isolation** - Each client/environment gets separate namespace (`{client}-{env}`)
- **No Overengineering** - No service mesh, no self-hosted Vault (use cloud KMS)
- **Security First** - NetworkPolicies, PSS, encryption, compliance features built-in

## 📁 Template Structure

```
monobase-infra/                   # Base template repository
├── charts/                       # Custom Helm charts
│   ├── api/                  # Monobase API application chart
│   ├── api-worker/                    # API Worker application chart
│   └── account/                # Monobase Account frontend chart
│
├── helm-dependencies/            # Bitnami/community chart configurations
│   ├── postgresql-values.yaml       # PostgreSQL configuration
│   ├── minio-values.yaml         # MinIO configuration
│   └── valkey-values.yaml    # Valkey configuration
│
├── infrastructure/               # Infrastructure templates
│   ├── longhorn/                 # Block storage
│   ├── envoy-gateway/            # Gateway API
│   ├── argocd/                   # GitOps
│   ├── external-secrets-operator/ # Secrets management
│   ├── cert-manager/             # TLS certificates
│   ├── velero/                   # Backup solution
│   ├── security/                 # NetworkPolicies, PSS, encryption
│   └── monitoring/               # Optional Prometheus + Grafana
│
├── argocd/                       # ArgoCD application definitions
│   ├── bootstrap/                # App-of-Apps root
│   ├── infrastructure/           # Infrastructure apps
│   └── applications/             # Application apps
│
├── config/                       # Configuration directory
│   ├── profiles/                 # Base configuration profiles
│   │   ├── production-base.yaml  # Production defaults (copy this!)
│   │   ├── staging-base.yaml     # Staging defaults
│   │   └── README.md             # Configuration guide
│   ├── example.com/              # Example configurations
│   │   ├── values-production.yaml           # Full reference (430 lines)
│   │   ├── values-production-minimal.yaml   # Minimal example (60 lines) ⭐
│   │   └── values-staging-minimal.yaml      # Staging minimal (40 lines) ⭐
│   └── [your-client]/            # Your client config goes here
│
├── docs/                         # Documentation
└── scripts/                      # Automation scripts
```

## 📚 Documentation

**See [docs/INDEX.md](docs/INDEX.md) for complete documentation index.**

### Quick Links

**🚀 Getting Started:**
- [Client Onboarding](docs/getting-started/CLIENT-ONBOARDING.md) - Fork, configure, deploy
- [Deployment Guide](docs/getting-started/DEPLOYMENT.md) - Step-by-step deployment
- [Configuration Profiles](config/profiles/README.md) - Profile-based config workflow

**🏗️ Architecture:**
- [System Architecture](docs/architecture/ARCHITECTURE.md) - Design decisions, components
- [GitOps with ArgoCD](docs/architecture/GITOPS-ARGOCD.md) - App-of-Apps pattern
- [Gateway API](docs/architecture/GATEWAY-API.md) - Envoy Gateway, HTTPRoutes
- [Storage](docs/architecture/STORAGE.md) - Longhorn, cloud CSI drivers

**⚙️ Operations:**
- [Backup & DR](docs/operations/BACKUP_DR.md) - 3-tier backup, disaster recovery
- [Scaling Guide](docs/operations/SCALING-GUIDE.md) - HPA, storage expansion
- [Troubleshooting](docs/operations/TROUBLESHOOTING.md) - Common issues

**🔐 Security:**
- [Security Hardening](docs/security/SECURITY-HARDENING.md) - Best practices
- [Compliance](docs/security/SECURITY_COMPLIANCE.md) - HIPAA, SOC2, GDPR

**📖 Reference:**
- [Values Reference](docs/reference/VALUES-REFERENCE.md) - All configuration parameters
- [Optimization Summary](docs/reference/OPTIMIZATION-SUMMARY.md) - Simplification history

## 🔄 Syncing Upstream Changes

Clients can pull template updates from the base repository:

```bash
# In your forked repo (one-time setup)
git remote add upstream https://github.com/YOUR-ORG/monobase-infra.git

# Pull latest template updates
git fetch upstream
git merge upstream/main

# Resolve any conflicts (usually keep your config/, accept upstream changes)
git push origin main
```

## 🔐 Security & Compliance

- **NetworkPolicies** - Default-deny, allow-specific traffic patterns
- **Pod Security Standards** - Restricted security profile enforced
- **Encryption at Rest** - PostgreSQL encryption, Longhorn volume encryption
- **Encryption in Transit** - TLS everywhere via cert-manager
- **RBAC** - Least-privilege service accounts
- **Secrets Management** - Never commit secrets, use External Secrets + KMS
- **Compliance** - See compliance documentation in [docs/](docs/)

## ⚙️ Resource Requirements

### Minimum (Core Only)
- **3 nodes** × 4 CPU × 16GB RAM
- **~7 CPU, ~23Gi memory**
- **~100Gi storage** (PostgreSQL)

### Full Stack (All Optional Components)
- **3-5 nodes** × 8 CPU × 32GB RAM
- **~22 CPU, ~53Gi memory**
- **~1.15TB storage** (PostgreSQL + MinIO)

## 🤝 Contributing

Improvements to the base template are welcome! If you implement a useful feature or fix:

1. Make changes in your fork
2. Test thoroughly
3. Submit a pull request to the base template repository
4. Your contribution helps all clients!

## 📞 Support

- **Issues**: GitHub Issues
- **Documentation**: [docs/](docs/)

## 📄 License

[Add your license here]
