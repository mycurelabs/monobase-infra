# Skills & Agents — Infra Operations

Codebase: `~/Projects/mycure/infra`

## Kubeconfig Resolution (All Skills)

All kubectl/helm/argocd commands use this priority order:
1. Explicit `--kubeconfig` flag
2. `KUBECONFIG` environment variable
3. **Default:** `~/.kube/mycure-doks-main` (if exists)
4. Interactive selection (if multiple configs in `~/.kube/`)
5. Fall back to `~/.kube/config`

---

## Skills (4 skills, 22 operations)

### ArgoCD (`/argocd`)

GitOps deployment management with ApplicationSet auto-discovery.

| Operation | Command | Destructive |
|-----------|---------|-------------|
| `sync` | Force sync application | No |
| `diff` | Preview pending changes | No |
| `status` | Check sync/health status | No |
| `rollback` | Rollback to revision | Yes |
| `pause` | Pause/resume auto-sync | No |
| `refresh` | Hard refresh from Git | No |

### Kubernetes (`/k8s`)

Kubernetes operations, debugging, resource management.

| Operation | Command | Destructive |
|-----------|---------|-------------|
| `logs` | Stream pod logs | No |
| `restart` | Rolling restart deployment | Yes |
| `debug` | Troubleshoot pod (describe+logs+events) | No |
| `exec` | Shell into pod | No |
| `events` | Show namespace events | No |
| `scale` | Scale deployment | Yes (if 0) |
| `db-shell` | PostgreSQL/MongoDB CLI | No |
| `secrets-sync` | Force external secret refresh | No |
| `secrets-status` | Check sync status | No |
| `cluster-health` | Overall health check | No |
| `cluster-nodes` | Node status & capacity | No |

### Helm (`/helm`)

Helm chart management for 21 charts.

| Operation | Command | Destructive |
|-----------|---------|-------------|
| `diff` | Compare local vs deployed | No |
| `values` | Get deployed values | No |
| `template` | Render templates locally | No |
| `lint` | Validate chart structure | No |
| `history` | View release history | No |

### IaC (`/iac`)

Terraform/OpenTofu modules for 6 providers.

| Operation | Command | Destructive |
|-----------|---------|-------------|
| `plan` | Preview infrastructure changes | No |
| `apply` | Apply infrastructure changes | Yes |
| `state` | Inspect current state | No |
| `destroy` | Destroy infrastructure | Yes |
| `init` | Initialize module | No |

---

## Agents (1)

### SRE Expert (`sre-expert`)

**Scope:** Cluster operations, monitoring, incident response

**Embedded Knowledge:**
- Envoy Gateway / Gateway API (HTTPRoute configuration, multi-domain support)
- External Secrets Operator (AWS/Azure/GCP KMS sync)
- Velero (3-tier backup strategy: hourly/daily/weekly)
- Prometheus + Grafana (ServiceMonitors, dashboards)
- Kyverno + Falco (policy engine, runtime security)
- cert-manager (Let's Encrypt, Cloudflare DNS-01)

**Includes 8 Runbooks:**
1. Pod Not Starting
2. App Unreachable
3. Secrets Not Syncing
4. ArgoCD Sync Failure
5. Backup & Restore
6. Certificate Renewal
7. Complete Outage Response
8. Storage/PVC Issues

---

## Destructive Operations

Before executing any destructive operation, the agent/skill will:
1. **Explain** what will happen
2. **Ask for explicit confirmation**
3. **Only proceed** after user confirms

Destructive operations:
- `kubectl rollout restart` — causes rolling restart
- `kubectl scale --replicas=0` — stops service
- `argocd app rollback` — reverts to previous state
- `tofu apply` — modifies cloud infrastructure
- `tofu destroy` — destroys infrastructure

---

## File Locations

| File | Purpose |
|------|---------|
| `.claude/skills/argocd/SKILL.md` | ArgoCD skill definition |
| `.claude/skills/k8s/SKILL.md` | Kubernetes skill definition |
| `.claude/skills/helm/SKILL.md` | Helm skill definition |
| `.claude/skills/iac/SKILL.md` | IaC skill definition |
| `.claude/agents/sre-expert.md` | SRE Expert agent definition |
