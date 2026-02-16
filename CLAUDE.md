# Monobase Infrastructure (mono-infra)

Multi-tenant Kubernetes infrastructure for healthcare SaaS (MyCure, DentaLemon, HapiHub).
GitOps-driven with ArgoCD, Helm charts, and Terraform/OpenTofu for 6 cloud providers.

## Repository Structure

```
charts/           # 21 Helm charts (healthcare apps, core services, infrastructure)
argocd/           # ArgoCD bootstrap + application templates
  bootstrap/      # ApplicationSet auto-discover + infrastructure root
  applications/   # Per-deployment app-of-apps templates
  infrastructure/ # Cluster-wide infrastructure apps
terraform/        # IaC modules for 6 providers
  modules/        # aws-eks, azure-aks, gcp-gke, do-doks, on-prem-k3s, local-k3d
values/           # Configuration values
  deployments/    # Per-client deployment configs (e.g., mycure-production.yaml)
  infrastructure/ # Cluster-wide infra config (main.yaml)
infrastructure/   # Raw K8s manifests (monitoring, security, velero, secrets)
scripts/          # Operational scripts (bootstrap, provision, secrets, admin)
docs/             # Architecture, operations, security documentation
```

## Tool Management

This project uses **mise exclusively** for tool versions and task running.
- Install tools: `mise install`
- Run tasks: `mise run <task>` (e.g., `mise run lint`, `mise run bootstrap`)
- See all tasks: `mise tasks`

Key tasks: `lint`, `validate`, `check`, `fmt`, `bootstrap`, `provision`, `secrets`, `admin`

## Naming Conventions

- **Namespaces**: `{client}-{environment}` (e.g., `mycure-production`, `mycure-staging`)
- **Deployment files**: `values/deployments/{client}-{environment}.yaml`
- **Chart names**: lowercase, hyphenated (e.g., `mycure-myaccount`, `dentalemon-website`)
- **Infrastructure namespaces**: `gateway-system`, `envoy-gateway-system`, `argocd`, `monitoring`, `velero`, `cert-manager`, `external-secrets-system`, `external-dns`, `longhorn-system`

## Key Patterns

- **Gateway API** (not Ingress) via Envoy Gateway — shared-gateway in `gateway-system` namespace
- **External Secrets Operator** syncs from GCP Secret Manager — never commit secrets
- **ArgoCD auto-sync** — changes to `values/` trigger automatic deployment
- **Multi-domain gateway** — supports `*.mycureapp.com`, `*.localfirsthealth.com`, `*.stg.localfirsthealth.com`, `*.mycure.md`
- **Global values** pattern: `global.domain`, `global.namespace`, `global.gateway`, `global.storage`
- **Bitnami legacy images** for databases/caches (MongoDB, PostgreSQL, Valkey, MinIO)

## Git Conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`
- Never commit secrets, credentials, or `.env` files
- Fork-based workflow for external contributors

## Safety Rules

- **No destructive kubectl operations** without explicit user confirmation
- Changes to `values/deployments/*.yaml` trigger ArgoCD auto-sync to production
- Direct `kubectl` changes are reverted by ArgoCD self-heal
- Always use `helm template --dry-run` before applying chart changes
- Velero backup verification before any DR operation

## Available Skills

- `/helm` — Helm chart management for 21 charts
- `/argocd` — GitOps deployment management with ApplicationSet auto-discovery
- `/iac` — Terraform/OpenTofu modules for 6 providers
- `/k8s` — Kubernetes operations, debugging, resource management

## Available Agents

- `sre-expert` — Cluster operations, monitoring, incident response
