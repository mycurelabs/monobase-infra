# Monobase Infrastructure (mono-infra)

Multi-tenant Kubernetes infrastructure for healthcare SaaS (MyCure, HapiHub).
GitOps-driven with ArgoCD, Helm charts, and Terraform/OpenTofu for 6 cloud providers.
The live DOKS cluster is OpenTofu-managed from values/cluster (mise run cluster-plan|cluster-apply).

## Repository Structure

```
charts/               # Everything deployable is a chart
  argocd-bootstrap/       # Infrastructure root + auto-discover ApplicationSet
  argocd-applications/    # Per-deployment Application factory + dedicated templates
  argocd-infrastructure/  # Cluster-wide infrastructure apps
  app/                    # Generic frontend/service chart (consolidates clones)
  <bespoke charts>        # hapihub, cadence, security-baseline, *-resources, ...
terraform/            # IaC modules for 6 providers
  modules/                # aws-eks, azure-aks, gcp-gke, do-doks, on-prem-k3s, local-k3d
values/               # ALL real configuration
  cluster/                # OpenTofu root for the live DOKS cluster (imported state)
  deployments/            # <product>-<env>.yaml overlays + _base/<product>.yaml
  infrastructure/         # Cluster-wide infra config (main.yaml) + secrets registry
scripts/              # Operational scripts (bootstrap, provision, secrets, admin)
docs/                 # Architecture, operations, security documentation
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
- **Chart names**: lowercase, hyphenated (e.g., `mycure-myaccount`, `mycure-dashboard`)
- **Infrastructure namespaces**: `nginx-gateway-system`, `argocd`, `monitoring`, `velero`, `cert-manager`, `external-secrets-system`, `external-dns`, `tailscale`
- **Node pools** (DOKS): `prod-db`, `prod-apps`, `infra`, `nonprod` — tainted `node-pool=<name>:NoSchedule` except nonprod; see docs/operations/SCALING-GUIDE.md

## Key Patterns

- **Gateway API** (not Ingress) via NGINX Gateway Fabric — `nginx-shared-gateway` in `nginx-gateway-system`
- **External Secrets Operator** syncs from GCP Secret Manager — never commit secrets
- **ArgoCD auto-sync** — changes to `values/` trigger automatic deployment
- **Multi-domain gateway** — supports `*.mycureapp.com`, `*.localfirsthealth.com`, `*.stg.localfirsthealth.com`, `*.mycure.md`
- **Global values** pattern: `global.domain`, `global.namespace`, `global.gateway`, `global.storage`
- **Bitnami legacy images** for databases/caches (PostgreSQL, Valkey, MinIO)

## Git Conventions

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`
- Never commit secrets, credentials, or `.env` files
- Fork-based workflow for external contributors
- **Worktrees live under `.claude/worktrees/<branch>`** (gitignored) — NOT a sibling
  `../infra-worktrees/`. Branch development never happens in the main checkout (it's
  shared across concurrent sessions); create the worktree with the `EnterWorktree` tool,
  or `git worktree add .claude/worktrees/<branch> origin/main`. The main dir stays on
  `main`. Deploy/values/docs commits straight to `main` from the main dir are fine — the
  rule is about branch work.

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
