# Documentation Index

Navigate to comprehensive guides organized by category.

## 🚀 Getting Started

New to monobase-infra? Start here.

- **[CLUSTER-PROVISIONING.md](getting-started/CLUSTER-PROVISIONING.md)** - Provision Kubernetes clusters (AWS/Azure/GCP/DOKS/k3d)
- **[CLIENT-ONBOARDING.md](getting-started/CLIENT-ONBOARDING.md)** - Fork, configure, and deploy your first client
- **[DEPLOYMENT.md](getting-started/DEPLOYMENT.md)** - Complete step-by-step deployment guide
- **[TEMPLATE-USAGE.md](getting-started/TEMPLATE-USAGE.md)** - Template fork workflow and maintenance
- **[INFRASTRUCTURE-REQUIREMENTS.md](getting-started/INFRASTRUCTURE-REQUIREMENTS.md)** - Cluster specifications and prerequisites

## 🏗️ Architecture

Understand the system design and core components.

- **[ARCHITECTURE.md](architecture/ARCHITECTURE.md)** - System architecture, design decisions, component overview
- **[GITOPS-ARGOCD.md](architecture/GITOPS-ARGOCD.md)** - GitOps workflow with ArgoCD App-of-Apps pattern
- **[GATEWAY-API.md](architecture/GATEWAY-API.md)** - Envoy Gateway, HTTPRoutes, and traffic routing
- **[STORAGE.md](architecture/STORAGE.md)** - Storage providers (Longhorn, cloud CSI drivers)

## ⚙️ Operations

Day-to-day operations, monitoring, and incident response.

- **[CLUSTER-SIZING.md](operations/CLUSTER-SIZING.md)** - Multi-tenant cluster sizing and capacity planning
- **[BACKUP_DR.md](operations/BACKUP_DR.md)** - 3-tier backup strategy and restore procedures
- **[DISASTER_RECOVERY_RUNBOOKS.md](operations/DISASTER_RECOVERY_RUNBOOKS.md)** - DR scenarios and recovery procedures
- **[SCALING-GUIDE.md](operations/SCALING-GUIDE.md)** - Horizontal pod autoscaling, storage expansion
- **[MONITORING.md](operations/MONITORING.md)** - Prometheus, Grafana, alerting
- **[SECRETS-MANAGEMENT.md](operations/SECRETS-MANAGEMENT.md)** - External Secrets Operator, KMS integration
- **[TROUBLESHOOTING.md](operations/TROUBLESHOOTING.md)** - Common issues and solutions

## 🔐 Security

Security hardening, compliance, and policies.

- **[SECURITY-HARDENING.md](security/SECURITY-HARDENING.md)** - Security best practices and hardening guide
- **[SECURITY_COMPLIANCE.md](security/SECURITY_COMPLIANCE.md)** - HIPAA, SOC2, GDPR compliance

## 🧪 Development

Local development, testing, and validation.

- **[K3D-TESTING.md](development/K3D-TESTING.md)** - Local testing with k3d clusters
- **[K3D_TROUBLESHOOTING.md](development/K3D_TROUBLESHOOTING.md)** - k3d troubleshooting (Ubuntu 24.04 AppArmor fix)
- **[TESTING-RESULTS.md](development/TESTING-RESULTS.md)** - Validation test results
- **[ON-PREM-DEPLOYMENT.md](development/ON-PREM-DEPLOYMENT.md)** - Self-hosted cluster deployment

**Terraform/OpenTofu Module Development:**
- **[../terraform/CONTRIBUTING.md](../terraform/CONTRIBUTING.md)** - Build custom OpenTofu modules



## 📂 Reference Documentation

- **[VALUES-REFERENCE.md](reference/VALUES-REFERENCE.md)** - Complete configuration parameter reference
- **[STORAGE-PROVIDERS.md](reference/STORAGE-PROVIDERS.md)** - Storage provider configuration reference
- **[OPTIMIZATION-SUMMARY.md](reference/OPTIMIZATION-SUMMARY.md)** - Infrastructure simplification history
- **[TEMPLATE-USAGE.md](getting-started/TEMPLATE-USAGE.md)** - Template fork workflow and maintenance

---

## Quick Navigation by Task

### I want to...

**Provision a Kubernetes cluster:**
1. [CLUSTER-PROVISIONING.md](getting-started/CLUSTER-PROVISIONING.md)
2. [CLUSTER-SIZING.md](operations/CLUSTER-SIZING.md)

**Deploy a new client:**
1. [CLIENT-ONBOARDING.md](getting-started/CLIENT-ONBOARDING.md)
2. [DEPLOYMENT.md](getting-started/DEPLOYMENT.md)

**Understand the architecture:**
1. [ARCHITECTURE.md](architecture/ARCHITECTURE.md)
2. [GITOPS-ARGOCD.md](architecture/GITOPS-ARGOCD.md)

**Set up backups:**
1. [BACKUP_DR.md](operations/BACKUP_DR.md)

**Recover from an incident:**
1. [DISASTER_RECOVERY_RUNBOOKS.md](operations/DISASTER_RECOVERY_RUNBOOKS.md)
2. [TROUBLESHOOTING.md](operations/TROUBLESHOOTING.md)

**Secure the infrastructure:**
1. [SECURITY-HARDENING.md](security/SECURITY-HARDENING.md)
2. [SECURITY_COMPLIANCE.md](security/SECURITY_COMPLIANCE.md)

**Test locally:**
1. [K3D-TESTING.md](development/K3D-TESTING.md)
2. [K3D_TROUBLESHOOTING.md](development/K3D_TROUBLESHOOTING.md)

**Build custom Terraform modules:**
1. [MODULE-DEVELOPMENT.md](development/MODULE-DEVELOPMENT.md)

**Configure values:**
1. [VALUES-REFERENCE.md](reference/VALUES-REFERENCE.md)
2. [deployments/templates/README.md](../deployments/templates/README.md)

---

## Documentation Statistics

- **Total docs:** 21 files
- **Categories:** 6 (getting-started, architecture, operations, security, development, reference)
- **Lines:** ~5,750 total
- **Organization:** Categorized by purpose, easy navigation

## Contributing to Documentation

Found an issue? Want to improve docs?

1. Docs follow SCREAMING_SNAKE_CASE.md naming
2. Directories use kebab-case
3. Keep docs focused and well-organized
4. Update INDEX.md when adding new docs
5. Link to related docs (avoid duplication)

See [../README.md](../README.md) for contribution guidelines.
