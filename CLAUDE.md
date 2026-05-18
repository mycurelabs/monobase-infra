# Monobase Infrastructure (mono-infra)

Multi-tenant Kubernetes infrastructure for healthcare SaaS (MyCure, DentaLemon, HapiHub).
GitOps-driven with ArgoCD, Helm charts, and Terraform/OpenTofu for 6 cloud providers.

## Repository Structure

```
charts/                            # All Helm charts (apps + infrastructure + argocd glue)
  argocd-bootstrap/                # Templated infrastructure-root + ApplicationSet
  argocd-applications/             # Per-app ArgoCD Application templates (one per chart)
  argocd-infrastructure/           # Cluster-wide infra Application templates
  {api,account,hapihub,mycure,…}/  # Application charts
  cert-manager-issuers/, external-dns/, external-secrets-stores/,
  gateway/, nginx-gateway/, security-baseline/, namespace/,
  monitoring-resources/, falco-resources/, kyverno-resources/,
  velero-resources/, storage-resources/, minio-httproute/
terraform/
  modules/                         # aws-eks, azure-aks, gcp-gke, do-doks, on-prem-k3s, local-k3d
values/
  cluster/                         # Terraform module call for the production cluster (DOKS)
  deployments/                     # Per-client deployment configs (mycure-production.yaml, etc.)
  infrastructure/                  # Cluster-wide infra config (single-file main.yaml)
scripts/                           # Bun/TypeScript ops scripts (bootstrap, provision, secrets, admin,
                                   # monitor-migration, render-parity, seed, onprem-backup-*)
docs/                              # Architecture, operations, security docs
  history/                         # Point-in-time records (DIFF.md, MIGRATION.md, FIXME.md, SKILLS_AND_AGENTS.md)
```

The previous top-level `argocd/` and `infrastructure/` directories were removed
in commit ███ (the medicard-shape migration); their contents now live under
`charts/argocd-*/` and `charts/*-resources/`.

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
