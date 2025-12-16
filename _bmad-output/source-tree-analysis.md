# Source Tree Analysis - monobase-infra

## Overview

This document provides a comprehensive analysis of the monobase-infra repository structure, designed to help newcomers understand how the codebase is organized and where to find specific functionality.

## Complete Directory Tree

```
monobase-infra/
│
├── terraform/                    # [LEVEL 3] Infrastructure as Code
│   ├── modules/                  #   Reusable Terraform modules
│   │   ├── aws-eks/              #   ★ AWS Elastic Kubernetes Service
│   │   │   ├── main.tf           #     EKS cluster, node groups, add-ons
│   │   │   ├── vpc.tf            #     VPC, subnets, NAT gateways
│   │   │   ├── iam.tf            #     IAM roles and policies
│   │   │   ├── security-groups.tf#     Security group rules
│   │   │   ├── variables.tf      #     Input variables
│   │   │   ├── outputs.tf        #     Output values
│   │   │   └── versions.tf       #     Provider versions
│   │   ├── azure-aks/            #   ★ Azure Kubernetes Service
│   │   ├── gcp-gke/              #   ★ Google Kubernetes Engine
│   │   ├── do-doks/              #   ★ DigitalOcean Kubernetes
│   │   ├── on-prem-k3s/          #   ★ On-premises K3s
│   │   └── local-k3d/            #   ★ Local development (k3d)
│   └── examples/                 #   Example configurations
│       ├── aws-eks/              #     AWS example
│       ├── do-doks/              #     DigitalOcean example
│       └── k3d/                  #     Local k3d example
│
├── charts/                       # [LEVEL 2] Helm Charts
│   ├── api/                      #   ★ API backend chart
│   │   ├── Chart.yaml            #     Chart metadata
│   │   ├── values.yaml           #     Default values
│   │   └── templates/            #     K8s manifest templates
│   │       ├── deployment.yaml   #       Pod deployment
│   │       ├── service.yaml      #       Service exposure
│   │       ├── httproute.yaml    #       Gateway API routing
│   │       ├── configmap.yaml    #       Configuration
│   │       ├── hpa.yaml          #       Horizontal Pod Autoscaler
│   │       ├── pdb.yaml          #       Pod Disruption Budget
│   │       ├── networkpolicy.yaml#       Network isolation
│   │       └── servicemonitor.yaml#      Prometheus metrics
│   ├── account/                  #   ★ Frontend application chart
│   ├── gateway/                  #   ★ Envoy Gateway configuration
│   ├── namespace/                #   Namespace creation chart
│   ├── cert-manager-issuers/     #   TLS certificate issuers
│   ├── database-secrets/         #   External secrets for DBs
│   ├── external-dns/             #   DNS record automation
│   ├── grafana/                  #   Monitoring dashboards
│   ├── security-baseline/        #   Security policies
│   └── [app-specific]/           #   Application charts (hapihub, mycure, etc.)
│
├── argocd/                       # [LEVEL 4] GitOps Configuration
│   ├── bootstrap/                #   ★ ENTRY POINT - One-time setup
│   │   ├── infrastructure-root.yaml    # Deploys cluster infrastructure
│   │   └── applicationset-auto-discover.yaml # Auto-discovers deployments
│   ├── infrastructure/           #   Infrastructure app definitions
│   │   ├── Chart.yaml            #     Helm chart for infra apps
│   │   └── templates/            #     ArgoCD Application templates
│   │       ├── cert-manager.yaml #       Certificate management
│   │       ├── envoy-gateway.yaml#       API Gateway
│   │       ├── external-secrets.yaml#    Secrets from cloud KMS
│   │       ├── monitoring.yaml   #       Prometheus + Grafana
│   │       ├── velero.yaml       #       Backup solution
│   │       ├── kyverno.yaml      #       Policy engine
│   │       └── falco.yaml        #       Runtime security
│   └── applications/             #   Application definitions
│       ├── Chart.yaml
│       └── templates/            #     Per-application ArgoCD apps
│
├── infrastructure/               # [LEVEL 5] K8s Infrastructure Manifests
│   ├── monitoring/               #   Prometheus rules, ServiceMonitors
│   ├── security/                 #   ★ Security configurations
│   │   ├── networkpolicies/      #     Zero-trust network rules
│   │   │   ├── default-deny-all.yaml
│   │   │   ├── allow-gateway-to-apps.yaml
│   │   │   └── allow-apps-to-db.yaml
│   │   ├── kyverno/              #     Policy definitions
│   │   │   └── policies/         #       Pod security, labels, registries
│   │   └── falco/                #     Runtime threat detection
│   ├── storage/                  #   StorageClass definitions
│   ├── tls/                      #   TLS certificates
│   ├── velero/                   #   Backup schedules and locations
│   └── external-secrets/         #   Secret store configurations
│
├── deployments/                  # [LEVEL 4] Client/Environment Configs
│   ├── example-prod/             #   ★ Production reference
│   │   ├── values.yaml           #     Complete production config
│   │   └── README.md             #     Production deployment guide
│   ├── example-staging/          #   ★ Staging reference
│   └── example-k3d/              #   ★ Local development reference
│
├── values/                       # Configuration values
│   ├── infrastructure/           #   Infrastructure values
│   │   └── main.yaml             #     Central infrastructure config
│   └── deployments/              #   Per-deployment values (gitignored)
│
├── scripts/                      # [LEVEL 2] Automation Scripts
│   ├── bootstrap.ts              #   ★ ENTRY POINT - Cluster bootstrap
│   ├── provision.ts              #   Terraform cluster provisioning
│   ├── secrets.ts                #   Secrets configuration
│   ├── admin.ts                  #   Admin UI port-forwarding
│   ├── resize.ts                 #   Storage resize operations
│   └── validate.ts               #   Template validation
│
├── docs/                         # Documentation
│   ├── architecture/             #   System architecture docs
│   ├── getting-started/          #   Onboarding guides
│   ├── infrastructure/           #   Cloud-specific guides
│   ├── operations/               #   Operational runbooks
│   └── security/                 #   Security documentation
│
└── Configuration Files
    ├── mise.toml                 #   Tool versions & tasks
    ├── package.json              #   Bun dependencies
    ├── .tflint.hcl               #   Terraform linting rules
    └── .yamllint                 #   YAML linting rules
```

## Critical Entry Points

| Entry Point | Purpose | When to Use |
|-------------|---------|-------------|
| `scripts/bootstrap.ts` | Initialize GitOps on cluster | First-time cluster setup |
| `scripts/provision.ts` | Create Kubernetes cluster | Need new cluster |
| `argocd/bootstrap/*.yaml` | GitOps root applications | After ArgoCD installed |
| `deployments/example-*/` | Client configuration templates | Adding new deployment |

## Learning Path by Directory

### Level 1: Kubernetes Fundamentals
Start by understanding what gets deployed:
- `charts/*/templates/*.yaml` - See actual K8s resources
- `infrastructure/security/networkpolicies/` - Understand pod networking

### Level 2: Helm & Package Management
Learn how configurations are parameterized:
- `charts/*/Chart.yaml` - Chart metadata
- `charts/*/values.yaml` - Default configurations
- `charts/*/templates/` - Go templating

### Level 3: Infrastructure as Code
Understand cluster provisioning:
- `terraform/modules/local-k3d/` - Start simple
- `terraform/modules/aws-eks/` - Production complexity
- `terraform/examples/` - Usage patterns

### Level 4: GitOps & ArgoCD
Learn declarative deployments:
- `argocd/bootstrap/` - App-of-Apps pattern
- `argocd/infrastructure/` - Infrastructure apps
- `argocd/applications/` - Application apps
- `deployments/` - Configuration management

### Level 5: Production Operations
Master production concerns:
- `infrastructure/security/` - Zero-trust networking
- `infrastructure/velero/` - Backup strategies
- `infrastructure/monitoring/` - Observability
- `docs/operations/` - Runbooks

## File Naming Conventions

| Pattern | Meaning | Example |
|---------|---------|---------|
| `*.tf` | Terraform configuration | `main.tf`, `variables.tf` |
| `Chart.yaml` | Helm chart definition | Required in every chart |
| `values.yaml` | Default Helm values | Configurable parameters |
| `*-root.yaml` | ArgoCD root application | `infrastructure-root.yaml` |
| `example-*` | Reference configuration | `example-prod/` |

## Integration Points

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Git Repository                                │
│                     (Single Source of Truth)                         │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         ArgoCD                                       │
│   [argocd/bootstrap/]  ──────────────────────────────────────────── │
│         │                                                            │
│         ├── infrastructure-root.yaml ───► [argocd/infrastructure/]   │
│         │         │                                                  │
│         │         └──► cert-manager, gateway, monitoring, velero...  │
│         │                                                            │
│         └── applicationset-auto-discover.yaml ───► [deployments/]    │
│                   │                                                  │
│                   └──► Per-client applications (api, account, etc.)  │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                               │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│   │ gateway-    │  │ monitoring  │  │ client-prod │                │
│   │ system      │  │             │  │             │                │
│   │             │  │ Prometheus  │  │ API         │                │
│   │ Envoy GW    │  │ Grafana     │  │ Account     │                │
│   │ Certs       │  │ Alerting    │  │ PostgreSQL  │                │
│   └─────────────┘  └─────────────┘  └─────────────┘                │
└─────────────────────────────────────────────────────────────────────┘
```

## Next Steps

1. **Start Local**: Use `terraform/modules/local-k3d/` to create a local cluster
2. **Bootstrap**: Run `scripts/bootstrap.ts` to set up GitOps
3. **Deploy Example**: Copy `deployments/example-k3d/` and customize
4. **Explore ArgoCD**: Access the UI to see applications syncing
5. **Read Docs**: Follow `docs/getting-started/` for detailed guides
