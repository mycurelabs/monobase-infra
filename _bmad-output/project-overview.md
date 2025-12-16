# Project Overview - monobase-infra

## Executive Summary

**monobase-infra** is a production-ready, reusable Kubernetes infrastructure template that enables organizations to deploy and manage applications on Kubernetes clusters across multiple cloud providers using GitOps principles.

## Purpose

This repository serves as:
1. **Infrastructure Template** - Fork and customize for your organization
2. **Multi-Cloud Platform** - Deploy to AWS, Azure, GCP, DigitalOcean, or on-premises
3. **GitOps Foundation** - True GitOps workflow with ArgoCD
4. **Learning Resource** - Comprehensive example of modern Kubernetes infrastructure

## Quick Reference

| Attribute | Value |
|-----------|-------|
| **Project Type** | Infrastructure-as-Code (IaC) |
| **Primary Technologies** | Kubernetes, Terraform, Helm, ArgoCD |
| **Cloud Support** | AWS EKS, Azure AKS, GCP GKE, DO DOKS, K3s, k3d |
| **Architecture Pattern** | GitOps with App-of-Apps |
| **Target Scale** | <500 users, <1TB data per client |

## Technology Stack Summary

### Core Platform
| Component | Technology | Purpose |
|-----------|------------|---------|
| Container Orchestration | Kubernetes 1.31+ | Workload management |
| Package Management | Helm 3.16 | K8s application packaging |
| Infrastructure as Code | Terraform 1.9 | Cloud resource provisioning |
| GitOps Engine | ArgoCD | Declarative deployments |

### Infrastructure Components
| Component | Technology | Purpose |
|-----------|------------|---------|
| API Gateway | Envoy Gateway | Traffic routing (Gateway API) |
| TLS Management | cert-manager | Automated certificates |
| Secrets | External Secrets Operator | Cloud KMS integration |
| Storage | Longhorn / Cloud CSI | Persistent volumes |
| Monitoring | Prometheus + Grafana | Metrics and dashboards |
| Backup | Velero | Kubernetes-native backups |
| Security | Kyverno + Falco | Policy & threat detection |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ENVOY GATEWAY (Shared)                        │
│              Gateway API + TLS Termination                       │
│                   *.example.com → HTTPRoutes                     │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ client-a-prod │     │ client-b-prod │     │ client-c-stag │
│   Namespace   │     │   Namespace   │     │   Namespace   │
│               │     │               │     │               │
│  ┌─────────┐  │     │  ┌─────────┐  │     │  ┌─────────┐  │
│  │   API   │  │     │  │   API   │  │     │  │   API   │  │
│  └────┬────┘  │     │  └────┬────┘  │     │  └────┬────┘  │
│       │       │     │       │       │     │       │       │
│  ┌────▼────┐  │     │  ┌────▼────┐  │     │  ┌────▼────┐  │
│  │PostgreSQL│ │     │  │PostgreSQL│ │     │  │PostgreSQL│ │
│  └─────────┘  │     │  └─────────┘  │     │  └─────────┘  │
└───────────────┘     └───────────────┘     └───────────────┘
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Shared Gateway** | Single LoadBalancer IP, cost-effective, zero-downtime onboarding |
| **Namespace Isolation** | Each client/environment isolated, NetworkPolicies enforced |
| **GitOps with ArgoCD** | Declarative, auditable, self-healing deployments |
| **External Secrets** | No secrets in Git, cloud KMS integration |
| **App-of-Apps Pattern** | Scalable ArgoCD management, auto-discovery |

## Repository Structure

```
monobase-infra/
├── terraform/        # Cluster provisioning (multi-cloud)
├── charts/           # Helm charts (applications + infrastructure)
├── argocd/           # GitOps configuration (App-of-Apps)
├── infrastructure/   # K8s manifests (security, monitoring)
├── deployments/      # Client/environment configurations
├── scripts/          # Automation (bootstrap, provision)
└── docs/             # Documentation
```

## Getting Started

### Prerequisites
- Kubernetes cluster (or use Terraform to create one)
- kubectl configured
- Helm 3.x installed
- Git repository access

### Quick Start (5 minutes)
```bash
# 1. Clone and bootstrap
git clone https://github.com/your-org/monobase-infra.git
cd monobase-infra
./scripts/bootstrap.sh

# 2. Create deployment
cp -r deployments/example-prod deployments/myapp-prod
# Edit deployments/myapp-prod/values.yaml

# 3. Deploy via GitOps
git add deployments/myapp-prod
git commit -m "Add myapp-prod"
git push
# ArgoCD auto-deploys!
```

## Links to Detailed Documentation

- [Source Tree Analysis](./source-tree-analysis.md) - Directory structure guide
- [Learning Path](./learning-path.md) - Beginner to advanced progression
- [Architecture](./architecture.md) - Detailed system design
- [Development Guide](./development-guide.md) - Local development setup

## Existing Documentation Index

The repository includes extensive documentation in `docs/`:

### Architecture
- [System Architecture](../docs/architecture/ARCHITECTURE.md)
- [Gateway API](../docs/architecture/GATEWAY-API.md)
- [GitOps with ArgoCD](../docs/architecture/GITOPS-ARGOCD.md)

### Getting Started
- [Client Onboarding](../docs/getting-started/CLIENT-ONBOARDING.md)
- [Cluster Provisioning](../docs/getting-started/CLUSTER-PROVISIONING.md)
- [Deployment Guide](../docs/getting-started/DEPLOYMENT.md)

### Operations
- [Backup & DR](../docs/operations/BACKUP_DR.md)
- [Monitoring](../docs/operations/MONITORING.md)
- [Troubleshooting](../docs/operations/TROUBLESHOOTING.md)

### Security
- [Security Hardening](../docs/security/SECURITY-HARDENING.md)
- [Compliance](../docs/security/SECURITY_COMPLIANCE.md)
