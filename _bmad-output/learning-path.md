# Learning Path - From Kubernetes Beginner to Infrastructure Expert

## Introduction

This learning path is designed to help you understand the monobase-infra repository from the ground up. Each level builds on the previous one, taking you from Kubernetes fundamentals to advanced GitOps and production operations.

**Estimated Total Time:** 40-60 hours of study and hands-on practice

---

## Level 1: Kubernetes Fundamentals

**Goal:** Understand what Kubernetes is and core concepts

**Time:** 8-10 hours

### What You'll Learn
- Containers and why we need orchestration
- Kubernetes architecture (control plane, nodes, kubelet)
- Core resources: Pods, Services, Deployments, ConfigMaps, Secrets

### Prerequisites
- Basic Linux command line
- Understanding of containers (Docker basics)

### Study Resources
1. **Kubernetes Official Docs** - [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
2. **Video Course** - "Kubernetes for Beginners" on YouTube (TechWorld with Nana)

### Hands-On in This Repo
```bash
# Look at a simple deployment template
cat charts/api/templates/deployment.yaml

# Key concepts to identify:
# - apiVersion, kind, metadata, spec (standard K8s structure)
# - containers, ports, resources
# - labels and selectors
```

### Key Files to Study
| File | What It Teaches |
|------|-----------------|
| `charts/api/templates/deployment.yaml` | Deployment structure, pod spec |
| `charts/api/templates/service.yaml` | Service exposure, port mapping |
| `charts/api/templates/configmap.yaml` | Configuration injection |

### Checkpoint Questions
- [ ] What is a Pod and why is it the smallest deployable unit?
- [ ] How does a Deployment manage Pods?
- [ ] What's the difference between ClusterIP and LoadBalancer services?
- [ ] How do labels and selectors work together?

---

## Level 2: Helm - Kubernetes Package Manager

**Goal:** Understand how Helm templating and charts work

**Time:** 6-8 hours

### What You'll Learn
- What Helm solves (configuration management, reusability)
- Chart structure (Chart.yaml, values.yaml, templates/)
- Go templating basics ({{ }}, if/else, range)
- Values and overrides

### Prerequisites
- Completed Level 1

### Study Resources
1. **Helm Official Docs** - [Getting Started](https://helm.sh/docs/intro/quickstart/)
2. **Helm Chart Development Guide**

### Hands-On in This Repo
```bash
# Explore a chart structure
ls -la charts/api/

# Key files:
# - Chart.yaml: Metadata (name, version, description)
# - values.yaml: Default configuration
# - templates/: Kubernetes manifests with Go templating

# See how templating works
cat charts/api/templates/deployment.yaml | head -50

# Notice patterns like:
# {{ include "api.fullname" . }}  - Helper functions
# {{ .Values.replicaCount }}      - Value references
# {{- if .Values.enabled }}       - Conditionals
```

### Key Files to Study
| File | What It Teaches |
|------|-----------------|
| `charts/api/Chart.yaml` | Chart metadata, dependencies |
| `charts/api/values.yaml` | Default values, configuration options |
| `charts/api/templates/_helpers.tpl` | Template helper functions |
| `charts/gateway/templates/gateway.yaml` | Complex templating |

### Checkpoint Questions
- [ ] What's the purpose of Chart.yaml vs values.yaml?
- [ ] How do you override default values?
- [ ] What does `{{ include "chart.name" . }}` do?
- [ ] How do conditionals work in Helm templates?

---

## Level 3: Terraform - Infrastructure as Code

**Goal:** Understand how cloud infrastructure is provisioned

**Time:** 8-10 hours

### What You'll Learn
- Infrastructure as Code concepts
- Terraform basics (providers, resources, variables, outputs)
- Modules for reusability
- State management

### Prerequisites
- Completed Level 2
- Basic cloud concepts (VPC, IAM)

### Study Resources
1. **HashiCorp Learn** - [Terraform Fundamentals](https://learn.hashicorp.com/terraform)
2. **Video Course** - "Terraform for Beginners" on YouTube

### Hands-On in This Repo

**Start Simple - Local k3d:**
```bash
# The simplest module - local Kubernetes cluster
cat terraform/modules/local-k3d/main.tf

# Key concepts:
# - resource "k3d_cluster" - Creates a local K8s cluster
# - var.cluster_name - Input variables
# - Port mappings for LoadBalancer
```

**Progress to Cloud - AWS EKS:**
```bash
# Production-grade complexity
ls terraform/modules/aws-eks/

# Files breakdown:
# - main.tf: EKS cluster, node groups
# - vpc.tf: Networking infrastructure
# - iam.tf: Security roles and policies
# - security-groups.tf: Network rules
# - variables.tf: Configurable inputs
# - outputs.tf: Values to export
```

### Key Files to Study
| File | What It Teaches | Complexity |
|------|-----------------|------------|
| `terraform/modules/local-k3d/main.tf` | Basic Terraform, k3d provider | Beginner |
| `terraform/modules/aws-eks/variables.tf` | Variable definitions, types | Beginner |
| `terraform/modules/aws-eks/main.tf` | EKS cluster, node groups | Intermediate |
| `terraform/modules/aws-eks/vpc.tf` | AWS VPC, subnets, NAT | Advanced |
| `terraform/modules/aws-eks/iam.tf` | AWS IAM for Kubernetes | Advanced |

### Learning Progression
1. `local-k3d/` - Start here, understand basic Terraform
2. `do-doks/` - Simple cloud provider
3. `aws-eks/` - Production complexity
4. `azure-aks/` or `gcp-gke/` - Compare cloud implementations

### Checkpoint Questions
- [ ] What is Terraform state and why is it important?
- [ ] How do modules promote reusability?
- [ ] What's the difference between variables and outputs?
- [ ] How does the AWS EKS module create a VPC?

---

## Level 4: ArgoCD - GitOps and Continuous Delivery

**Goal:** Master GitOps principles and ArgoCD patterns

**Time:** 8-10 hours

### What You'll Learn
- GitOps philosophy (Git as source of truth)
- ArgoCD concepts (Applications, Projects, Sync)
- App-of-Apps pattern
- ApplicationSets for dynamic generation

### Prerequisites
- Completed Levels 1-3
- Understanding of Git workflows

### Study Resources
1. **ArgoCD Official Docs** - [Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
2. **GitOps Guide** - Weaveworks GitOps principles

### Hands-On in This Repo

**Bootstrap Architecture:**
```bash
# CRITICAL: Understand the bootstrap process
cat argocd/bootstrap/infrastructure-root.yaml

# This single file deploys ALL infrastructure:
# - Creates an ArgoCD Application
# - Points to argocd/infrastructure/
# - ArgoCD syncs everything automatically

cat argocd/bootstrap/applicationset-auto-discover.yaml

# This auto-discovers client configurations:
# - Scans values/deployments/*.yaml
# - Creates Application for each file
# - True GitOps: add file → auto-deploy
```

**App-of-Apps Pattern:**
```
Bootstrap Layer (one-time apply)
    │
    ├── infrastructure-root.yaml
    │         │
    │         └──► argocd/infrastructure/ (ArgoCD Applications)
    │                    │
    │                    ├──► cert-manager (Helm chart)
    │                    ├──► envoy-gateway (Helm chart)
    │                    ├──► monitoring (Helm chart)
    │                    └──► ... more components
    │
    └── applicationset-auto-discover.yaml
              │
              └──► values/deployments/*.yaml ──► argocd/applications/
                                                        │
                                                        ├──► api (Helm)
                                                        ├──► account (Helm)
                                                        └──► databases
```

### Key Files to Study
| File | What It Teaches |
|------|-----------------|
| `argocd/bootstrap/infrastructure-root.yaml` | Root Application pattern |
| `argocd/bootstrap/applicationset-auto-discover.yaml` | Dynamic app generation |
| `argocd/infrastructure/Chart.yaml` | Infrastructure as Helm chart |
| `argocd/infrastructure/templates/cert-manager.yaml` | Nested Applications |
| `argocd/applications/templates/api.yaml` | Application definitions |

### Checkpoint Questions
- [ ] What is the App-of-Apps pattern and why use it?
- [ ] How does ApplicationSet auto-discover deployments?
- [ ] What's the difference between sync and refresh in ArgoCD?
- [ ] How does ArgoCD handle drift (manual changes)?

---

## Level 5: Gateway API and Certificate Management

**Goal:** Understand modern Kubernetes networking and TLS

**Time:** 6-8 hours

### What You'll Learn
- Gateway API vs Ingress (the evolution)
- Envoy Gateway implementation
- Certificate automation with cert-manager
- External DNS for automatic DNS records

### Prerequisites
- Completed Level 4
- Basic networking concepts (DNS, TLS)

### Study Resources
1. **Gateway API Docs** - [Introduction](https://gateway-api.sigs.k8s.io/)
2. **cert-manager Docs** - [Getting Started](https://cert-manager.io/docs/)

### Hands-On in This Repo
```bash
# Gateway API resources
cat charts/gateway/templates/gateway.yaml
cat charts/gateway/templates/gatewayclass.yaml

# Key concepts:
# - GatewayClass: Implementation (Envoy)
# - Gateway: Listener configuration
# - HTTPRoute: Traffic routing rules

# Certificate automation
cat charts/gateway/templates/certificate.yaml
cat charts/cert-manager-issuers/templates/clusterissuer.yaml

# Flow:
# ClusterIssuer → Certificate → Secret → Gateway TLS
```

### Architecture Flow
```
Internet Traffic
       │
       ▼
┌─────────────────────────────────────┐
│          GatewayClass               │
│    (Envoy Gateway Controller)       │
└─────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│            Gateway                  │
│  - HTTPS listener (*.example.com)  │
│  - TLS certificate reference       │
│  - allowedRoutes: All namespaces   │
└─────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│          HTTPRoute (per app)        │
│  - hostname: api.example.com       │
│  - rules: / → api-service:7213     │
└─────────────────────────────────────┘
```

### Key Files to Study
| File | What It Teaches |
|------|-----------------|
| `charts/gateway/templates/gatewayclass.yaml` | Gateway implementation |
| `charts/gateway/templates/gateway.yaml` | Listener configuration |
| `charts/api/templates/httproute.yaml` | Route definitions |
| `charts/cert-manager-issuers/` | TLS certificate automation |
| `charts/external-dns/` | DNS record automation |

### Checkpoint Questions
- [ ] What's the difference between Gateway API and Ingress?
- [ ] How does cert-manager automate certificate issuance?
- [ ] What role does External DNS play?
- [ ] How do HTTPRoutes from different namespaces share a Gateway?

---

## Level 6: Security, Monitoring, and Operations

**Goal:** Master production-grade Kubernetes operations

**Time:** 10-12 hours

### What You'll Learn
- Zero-trust networking with NetworkPolicies
- Policy enforcement with Kyverno
- Runtime security with Falco
- Monitoring with Prometheus/Grafana
- Backup and disaster recovery with Velero

### Prerequisites
- Completed Levels 1-5
- Understanding of security principles

### Hands-On in This Repo

**Network Security (Zero Trust):**
```bash
# Default deny - foundation of zero trust
cat infrastructure/security/networkpolicies/default-deny-all.yaml

# Allow specific traffic
cat infrastructure/security/networkpolicies/allow-gateway-to-apps.yaml
cat infrastructure/security/networkpolicies/allow-apps-to-db.yaml

# Pattern:
# 1. Deny all by default
# 2. Explicitly allow needed traffic
# 3. Document everything
```

**Policy Enforcement (Kyverno):**
```bash
cat infrastructure/security/kyverno/policies/pod-security.yaml
cat infrastructure/security/kyverno/policies/require-labels.yaml
cat infrastructure/security/kyverno/policies/restrict-registries.yaml

# Policies enforce:
# - Pod security standards
# - Required labels/annotations
# - Approved container registries
```

**Backup Strategy (Velero):**
```bash
cat infrastructure/velero/schedules.yaml
cat infrastructure/velero/backup-locations.yaml

# 3-tier backup strategy:
# - Tier 1: Hourly (24h retention)
# - Tier 2: Daily (30d retention)
# - Tier 3: Weekly (90d retention)
```

### Key Files to Study
| Category | Files | What It Teaches |
|----------|-------|-----------------|
| Network Security | `infrastructure/security/networkpolicies/` | Zero-trust networking |
| Policy | `infrastructure/security/kyverno/policies/` | Admission control |
| Runtime Security | `infrastructure/security/falco/rules/` | Threat detection |
| Monitoring | `infrastructure/monitoring/` | Prometheus rules |
| Backup | `infrastructure/velero/` | Disaster recovery |
| Operations | `docs/operations/` | Runbooks and guides |

### Checkpoint Questions
- [ ] Why start with default-deny NetworkPolicies?
- [ ] How does Kyverno differ from OPA/Gatekeeper?
- [ ] What does Falco detect at runtime?
- [ ] How would you restore from a Velero backup?

---

## Learning Checklist Summary

### Level 1: Kubernetes Fundamentals
- [ ] Understand Pods, Services, Deployments
- [ ] Can explain labels and selectors
- [ ] Can read and understand basic K8s YAML

### Level 2: Helm
- [ ] Understand chart structure
- [ ] Can read Go templates
- [ ] Know how to override values

### Level 3: Terraform
- [ ] Understand IaC concepts
- [ ] Can read Terraform modules
- [ ] Understand state management

### Level 4: ArgoCD
- [ ] Understand GitOps principles
- [ ] Can explain App-of-Apps pattern
- [ ] Understand ApplicationSets

### Level 5: Networking
- [ ] Understand Gateway API
- [ ] Know how cert-manager works
- [ ] Can trace traffic flow

### Level 6: Operations
- [ ] Understand zero-trust networking
- [ ] Know security policy patterns
- [ ] Can explain backup strategies

---

## Recommended Learning Order

```
Week 1-2: Level 1 (Kubernetes Fundamentals)
   │      └── Practice with local k3d cluster
   │
Week 3: Level 2 (Helm)
   │      └── Modify charts/api values, see changes
   │
Week 4: Level 3 (Terraform)
   │      └── Provision local k3d, then explore cloud modules
   │
Week 5-6: Level 4 (ArgoCD)
   │      └── Bootstrap local cluster, deploy apps via Git
   │
Week 7: Level 5 (Networking)
   │      └── Trace traffic from internet to pod
   │
Week 8: Level 6 (Operations)
         └── Implement and test security policies
```

## Next Steps After Completion

1. **Contribute** - Improve documentation or add features
2. **Customize** - Adapt the template for your organization
3. **Teach** - Help others learn from your experience
4. **Certify** - Consider CKA/CKAD certification
