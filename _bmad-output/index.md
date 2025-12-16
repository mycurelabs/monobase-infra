# monobase-infra Documentation Index

> **Primary Entry Point for AI-Assisted Development and Learning**

## Project at a Glance

| Attribute | Value |
|-----------|-------|
| **Project** | monobase-infra |
| **Type** | Infrastructure-as-Code (Kubernetes) |
| **Primary Tech** | Terraform, Helm, ArgoCD, Kubernetes |
| **Cloud Support** | AWS, Azure, GCP, DigitalOcean, On-prem, Local |
| **Architecture** | GitOps with App-of-Apps pattern |

---

## Quick Navigation

### For Learning (Beginner → Advanced)

| Level | Topic | Start Here |
|-------|-------|------------|
| **Level 1** | Kubernetes Fundamentals | [Learning Path - Level 1](./learning-path.md#level-1-kubernetes-fundamentals) |
| **Level 2** | Helm Package Management | [Learning Path - Level 2](./learning-path.md#level-2-helm---kubernetes-package-manager) |
| **Level 3** | Terraform IaC | [Learning Path - Level 3](./learning-path.md#level-3-terraform---infrastructure-as-code) |
| **Level 4** | ArgoCD GitOps | [Learning Path - Level 4](./learning-path.md#level-4-argocd---gitops-and-continuous-delivery) |
| **Level 5** | Gateway & Certificates | [Learning Path - Level 5](./learning-path.md#level-5-gateway-api-and-certificate-management) |
| **Level 6** | Security & Operations | [Learning Path - Level 6](./learning-path.md#level-6-security-monitoring-and-operations) |

### For Development

| Task | Documentation |
|------|---------------|
| **Set up local environment** | [Development Guide](./development-guide.md) |
| **Understand the codebase** | [Source Tree Analysis](./source-tree-analysis.md) |
| **Learn the architecture** | [Project Overview](./project-overview.md) |

---

## Generated Documentation

| Document | Description |
|----------|-------------|
| [Project Overview](./project-overview.md) | Executive summary, tech stack, architecture |
| [Source Tree Analysis](./source-tree-analysis.md) | Directory structure, entry points, file purposes |
| [Learning Path](./learning-path.md) | **Ladderized learning program (Levels 1-6)** |
| [Development Guide](./development-guide.md) | Local setup, common tasks, troubleshooting |

---

## Existing Repository Documentation

### Architecture (`docs/architecture/`)
- [System Architecture](../docs/architecture/ARCHITECTURE.md) - Core design decisions
- [Gateway API](../docs/architecture/GATEWAY-API.md) - Envoy Gateway, HTTPRoutes
- [GitOps with ArgoCD](../docs/architecture/GITOPS-ARGOCD.md) - App-of-Apps pattern
- [Multi-Domain Gateway](../docs/architecture/MULTI-DOMAIN-GATEWAY.md) - Client domains, certs

### Getting Started (`docs/getting-started/`)
- [Client Onboarding](../docs/getting-started/CLIENT-ONBOARDING.md) - Fork and customize
- [Cluster Provisioning](../docs/getting-started/CLUSTER-PROVISIONING.md) - Terraform workflows
- [Clusters Guide](../docs/getting-started/CLUSTERS.md) - Supported platforms
- [Deployment Guide](../docs/getting-started/DEPLOYMENT.md) - Step-by-step deployment
- [Infrastructure Requirements](../docs/getting-started/INFRASTRUCTURE-REQUIREMENTS.md) - Minimum specs
- [Template Usage](../docs/getting-started/TEMPLATE-USAGE.md) - How to use the template

### Operations (`docs/operations/`)
- [Backup & DR](../docs/operations/BACKUP_DR.md) - Velero, 3-tier strategy
- [Certificate Management](../docs/operations/CERTIFICATE-MANAGEMENT.md) - TLS automation
- [Cluster Sizing](../docs/operations/CLUSTER-SIZING.md) - Resource planning
- [Disaster Recovery Runbooks](../docs/operations/DISASTER_RECOVERY_RUNBOOKS.md) - Recovery procedures
- [External DNS](../docs/operations/EXTERNAL-DNS.md) - Automatic DNS records
- [Monitoring](../docs/operations/MONITORING.md) - Prometheus + Grafana
- [Scaling Guide](../docs/operations/SCALING-GUIDE.md) - HPA, storage expansion
- [Secrets Management](../docs/operations/SECRETS-MANAGEMENT.md) - External Secrets
- [Storage](../docs/operations/STORAGE.md) - Longhorn, cloud CSI
- [Troubleshooting](../docs/operations/TROUBLESHOOTING.md) - Common issues

### Security (`docs/security/`)
- [Security Hardening](../docs/security/SECURITY-HARDENING.md) - Best practices
- [Security Compliance](../docs/security/SECURITY_COMPLIANCE.md) - HIPAA, SOC2, GDPR

### Infrastructure Guides (`docs/infrastructure/`)
- [Static IP - AWS](../docs/infrastructure/static-ip-aws.md)
- [Static IP - Azure](../docs/infrastructure/static-ip-azure.md)
- [Static IP - GCP](../docs/infrastructure/static-ip-gcp.md)
- [Static IP - DigitalOcean](../docs/infrastructure/static-ip-digitalocean.md)

---

## Component Documentation

### Helm Charts (`charts/`)
| Chart | README |
|-------|--------|
| API Backend | [charts/api/README.md](../charts/api/README.md) |
| Account Frontend | [charts/account/README.md](../charts/account/README.md) |
| External DNS | [charts/external-dns/README.md](../charts/external-dns/README.md) |
| Namespace | [charts/namespace/README.md](../charts/namespace/README.md) |

### Terraform Modules (`terraform/modules/`)
| Module | README |
|--------|--------|
| AWS EKS | [terraform/modules/aws-eks/README.md](../terraform/modules/aws-eks/README.md) |
| Azure AKS | [terraform/modules/azure-aks/README.md](../terraform/modules/azure-aks/README.md) |
| GCP GKE | [terraform/modules/gcp-gke/README.md](../terraform/modules/gcp-gke/README.md) |
| DigitalOcean DOKS | [terraform/modules/do-doks/README.md](../terraform/modules/do-doks/README.md) |
| On-prem K3s | [terraform/modules/on-prem-k3s/README.md](../terraform/modules/on-prem-k3s/README.md) |
| Local k3d | [terraform/modules/local-k3d/README.md](../terraform/modules/local-k3d/README.md) |

### Infrastructure Components
| Component | README |
|-----------|--------|
| External Secrets | [infrastructure/external-secrets/README.md](../infrastructure/external-secrets/README.md) |
| TLS Certificates | [infrastructure/tls/README.md](../infrastructure/tls/README.md) |
| Velero Backup | [infrastructure/velero/README.md](../infrastructure/velero/README.md) |

---

## Quick Commands

```bash
# Local Development
mise run provision -- --cluster k3d-local    # Create local cluster
mise run bootstrap                            # Bootstrap GitOps
mise run admin                                # Access admin UIs

# Validation
mise run check                                # Run all checks
mise run lint                                 # Run all linters
mise run validate                             # Validate configs

# Cleanup
mise run teardown                             # Destroy cluster
```

---

## Learning Roadmap Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR LEARNING JOURNEY                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Week 1-2: Kubernetes Fundamentals (Level 1)                   │
│     └── Pods, Services, Deployments, ConfigMaps                │
│                                                                 │
│  Week 3: Helm Package Management (Level 2)                     │
│     └── Charts, templates, values                              │
│                                                                 │
│  Week 4: Terraform IaC (Level 3)                               │
│     └── Modules, state, multi-cloud                            │
│                                                                 │
│  Week 5-6: ArgoCD GitOps (Level 4)                             │
│     └── App-of-Apps, ApplicationSets                           │
│                                                                 │
│  Week 7: Gateway & Certs (Level 5)                             │
│     └── Gateway API, cert-manager, DNS                         │
│                                                                 │
│  Week 8: Security & Ops (Level 6)                              │
│     └── NetworkPolicies, Kyverno, Velero                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Getting Help

- **Repository Issues**: [GitHub Issues](https://github.com/monobaselabs/monobase-infra/issues)
- **Documentation**: This index and linked documents
- **Contributing**: [CONTRIBUTING.md](../CONTRIBUTING.md)

---

*Generated by BMad Document Project Workflow on 2025-12-16*
