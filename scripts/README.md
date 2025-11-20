# Scripts Directory

This directory contains operational scripts for managing the mono-infra project.

## Structure

```
scripts/
├── *.ts                    # TypeScript scripts (Bun runtime)
├── *.sh                    # Bash scripts (legacy, being migrated)
├── lib/                    # Shared utilities for ALL scripts
│   ├── k8s.ts             # Kubernetes client
│   ├── prompts.ts         # CLI prompts (@clack/prompts)
│   ├── yaml.ts            # YAML parsing/writing
│   └── utils.ts           # General utilities
└── {feature}/             # Feature-specific modules
    ├── types.ts           # Feature types
    ├── parser.ts          # Feature parsers
    ├── providers/         # Provider implementations
    └── generators/        # Resource generators
```

## TypeScript Scripts (Bun)

### Prerequisites

```bash
# Install tools via mise
mise install

# Install dependencies
bun install
```

### Secrets Management

**Status:** ✅ Complete (Phase 3: Infrastructure Bootstrapping)

Provider-agnostic secrets management with centralized `secrets.yaml` configuration and full infrastructure bootstrapping.

**Files:**
- `scripts/secrets.ts` - Main CLI ✅
- `scripts/secrets/` - Secrets-specific modules
  - `types.ts` - Provider-agnostic schema ✅
  - `parser.ts` - Parse secrets.yaml ✅
  - `providers/base.ts` - Provider interface ✅
  - `providers/gcp.ts` - GCP implementation ✅
  - `generators/clustersecretstore.ts` - Generate ClusterSecretStore ✅
  - `generators/externalsecret.ts` - Generate ExternalSecret ✅
  - `gcp-setup.ts` - GCP service account, IAM, API setup ✅
  - `k8s-setup.ts` - Kubernetes namespace, gcpsm-secret setup ✅
  - `tls-setup.ts` - TLS ClusterIssuer generation ✅
  - `validate-cluster.ts` - Cluster state validation ✅

**Configuration:**
- `infrastructure/secrets.yaml` - Infrastructure-level secrets ✅
- `deployments/mycure-staging/secrets.yaml` - Staging secrets ✅
- `deployments/mycure-production/secrets.yaml` - Production secrets ✅

**Auto-Detection Features:**
- **GCP Project**: Detects from existing `gcp-secretstore.yaml` → `gcloud config` → prompts
- **Provider**: Detects from existing `*-secretstore.yaml` files → defaults to `gcp`
- **Kubeconfig**: Discovers all files in `~/.kube/` → shows interactive selection menu
- **Context Display**: Shows current `kubectl context` when kubeconfig is configured

**Priority Order:**
```
Project ID:   CLI flag > env var > gcp-secretstore.yaml > gcloud config > prompt
Provider:     CLI flag > existing *-secretstore.yaml > default (gcp)
Kubeconfig:   CLI flag > env var > ~/.kube/ discovery + selection > prompt
```

**Usage:**
```bash
# Auto-detect everything (idempotent, no flags needed!)
bun scripts/secrets.ts generate
bun scripts/secrets.ts validate-cluster

# Quick setup (secrets only, auto-detects project)
bun scripts/secrets.ts setup

# Full infrastructure setup (auto-detects project + kubeconfig)
bun scripts/secrets.ts setup --full

# Explicit values (overrides auto-detection)
bun scripts/secrets.ts setup --project mc-v4-prod
bun scripts/secrets.ts setup --full --project mc-v4-prod --kubeconfig ~/.kube/mycure-doks-main

# Validate secrets.yaml files
bun scripts/secrets.ts validate

# Validate cluster state (auto-discovers kubeconfig, shows context)
bun scripts/secrets.ts validate-cluster

# Dry-run mode
bun scripts/secrets.ts generate --dry-run

# Using environment variables
export GCP_PROJECT_ID=mc-v4-prod
export KUBECONFIG=/path/to/kubeconfig
bun scripts/secrets.ts setup

# Via mise tasks
mise run secrets setup --project mc-v4-prod
mise run secrets:generate
mise run secrets:validate
```

**Full Setup (`--full` flag) includes:**
1. **GCP Infrastructure:**
   - Enable Secret Manager API
   - Create `external-secrets` service account
   - Grant `roles/secretmanager.secretAccessor` IAM role
   - Generate service account key to `~/.gcp/external-secrets-{PROJECT}.json`

2. **Kubernetes Infrastructure:**
   - Create `external-secrets-system` namespace
   - Create `gcpsm-secret` with service account credentials

3. **TLS Setup:**
   - Generate Let's Encrypt ClusterIssuer manifests (staging + production)
   - HTTP-01 challenge configuration

4. **Secrets Setup:**
   - Create/update GCP Secret Manager secrets
   - Generate ExternalSecret manifests

**Schema Example:**
```yaml
secrets:
  - name: postgresql              # K8s secret name
    remoteRef: staging-postgresql # Provider reference (abstract)
    targetNamespace: mycure-staging  # Optional, inferred from location
    keys:
      - key: postgres-password    # K8s secret key
        remoteKey: staging-postgresql-password  # Provider key
        generate: true            # Auto-generate value
```

**Implementation Complete:**

**Phase 1 & 2:**
- ✅ package.json, tsconfig.json setup
- ✅ mise.toml updated (bun added)
- ✅ Provider-agnostic secrets.yaml files created
- ✅ Shared library (scripts/lib/) implemented
- ✅ Types and parser implemented
- ✅ GCP provider implementation
- ✅ Manifest generators
- ✅ CLI implementation (setup, generate, validate commands)
- ✅ Bash scripts removed

**Phase 3 (Infrastructure Bootstrapping):**
- ✅ GCP service account creation with idempotency
- ✅ IAM permission granting with retry logic
- ✅ Service account key generation
- ✅ Secret Manager API enablement
- ✅ Kubernetes namespace creation
- ✅ K8s gcpsm-secret creation
- ✅ TLS ClusterIssuer generation (Let's Encrypt + Cloudflare)
- ✅ Environment variable support (GCP_PROJECT_ID, KUBECONFIG)
- ✅ Cluster state validation (validate-cluster command)
- ✅ Full infrastructure setup mode (--full flag)

**Phase 4 (Auto-Detection & Idempotency):**
- ✅ GCP project auto-detection from existing gcp-secretstore.yaml
- ✅ GCP project fallback to gcloud config
- ✅ Provider auto-detection from existing *-secretstore.yaml files
- ✅ Kubeconfig auto-discovery from ~/.kube/ directory
- ✅ Interactive kubeconfig selection menu
- ✅ Current kubectl context display
- ✅ Priority-based configuration resolution
- ✅ Fully idempotent re-runs (no manual re-entry needed)

## Bash Scripts (Legacy)

### Other Scripts (To Be Migrated Later)

- `scripts/bootstrap.sh` - Bootstrap cluster with ArgoCD
- `scripts/provision.sh` - Provision cluster with Terraform
- `scripts/admin-access.sh` - Port-forward to admin UIs
- `scripts/validate.sh` - Validate infrastructure templates
- `scripts/resize-statefulset-storage.sh` - Resize PVCs
- `scripts/teardown.sh` - Destroy cluster
- `scripts/unbootstrap.sh` - Remove ArgoCD

## Development

### Running TypeScript Scripts

```bash
# Direct execution
bun scripts/secrets.ts

# Via mise tasks
mise run secrets

# With arguments
bun scripts/secrets.ts setup --provider gcp
```

### Adding New Scripts

1. Create `scripts/{name}.ts` for CLI entry point
2. Create `scripts/{name}/` for feature-specific modules
3. Use `scripts/lib/` for shared utilities
4. Update `mise.toml` if adding tasks
5. Update this README

### Import Aliases

```typescript
import { loadKubeConfig } from "@/lib/k8s";
import { parseSecretsFile } from "@/secrets/parser";
```

Configured in `tsconfig.json`:
```json
{
  "paths": {
    "@/lib/*": ["scripts/lib/*"],
    "@/secrets/*": ["scripts/secrets/*"]
  }
}
```

## Migration Status

| Script | Status | Notes |
|--------|--------|-------|
| secrets.sh | ✅ Complete | Migrated to TypeScript |
| secrets-gcp.sh | ✅ Complete | Migrated to TypeScript |
| validate-secrets.sh | ✅ Complete | Migrated to TypeScript |
| bootstrap.sh | ⏳ Pending | Future migration |
| provision.sh | ⏳ Pending | Future migration |
| admin-access.sh | ⏳ Pending | Future migration |
| validate.sh | ⏳ Pending | Future migration |
| resize-statefulset-storage.sh | ⏳ Pending | Future migration |
| teardown.sh | ⏳ Pending | Future migration |
| unbootstrap.sh | ⏳ Pending | Future migration |
