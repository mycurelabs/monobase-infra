# Skills & Agents — Infra Automation Plan

Codebase: `~/Projects/mycure/mono-infra`

## Infra

### Skills (4)

| # | Skill | Description |
|---|-------|-------------|
| 1 | Helm | 22 production-ready Helm charts (healthcare apps, core services, infrastructure) |
| 2 | ArgoCD | GitOps with ApplicationSet auto-discovery from `values/deployments/*.yaml` |
| 3 | IaC | Terraform/OpenTofu modules for 6 providers: AWS EKS, Azure AKS, GCP GKE, DigitalOcean DOKS, on-prem K3s, local k3d |
| 4 | K8s Expert (kubectl) | Kubernetes operations, debugging, resource management |

### Agents (1)

| Agent | Scope |
|-------|-------|
| SRE Expert | Cluster operations, monitoring, incident response |

---

## Recommendations

### Infra — SRE Expert scope expansion

The mono-infra repo includes tooling beyond Helm/ArgoCD/IaC/K8s that the SRE Expert agent should cover as embedded knowledge (not separate skills):

| Component | Why |
|-----------|-----|
| Envoy Gateway / Gateway API | Actual ingress layer — HTTPRoute configuration per client, multi-domain support |
| External Secrets Operator | Secrets sync across AWS/Azure/GCP KMS — no self-hosted Vault |
| Velero | Backup/DR with 3-tier strategy (hourly/daily/weekly) — required for healthcare compliance |
| Prometheus + Grafana | Monitoring and dashboards via ServiceMonitors |
| Kyverno + Falco | Policy engine + runtime security |
| cert-manager | TLS certificate automation (Let's Encrypt) |

---

## Tasks

| # | Task | Section |
|---|------|---------|
| 1 | Create Helm Skill | Infra |
| 2 | Create ArgoCD Skill | Infra |
| 3 | Create IaC Skill | Infra |
| 4 | Create K8s Expert (kubectl) Skill | Infra |
| 5 | Create SRE Expert Agent | Infra |

See also: [monobase Tasks](../monobase/SKILLS_AND_AGENTS.md#tasks)
