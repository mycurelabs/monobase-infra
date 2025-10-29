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

**Status:** ⚠️ Partial implementation - Phase 1 complete

Provider-agnostic secrets management with centralized `secrets.yaml` configuration.

**Files:**
- `scripts/secrets.ts` - Main CLI (stub)
- `scripts/secrets/` - Secrets-specific modules
  - `types.ts` - Provider-agnostic schema ✅
  - `parser.ts` - Parse secrets.yaml ✅
  - `providers/base.ts` - Provider interface ✅
  - `providers/gcp.ts` - GCP implementation 🚧
  - `generators/clustersecretstore.ts` - Generate ClusterSecretStore 🚧
  - `generators/externalsecret.ts` - Generate ExternalSecret 🚧

**Configuration:**
- `infrastructure/secrets.yaml` - Infrastructure-level secrets ✅
- `deployments/mycure-staging/secrets.yaml` - Staging secrets ✅
- `deployments/mycure-production/secrets.yaml` - Production secrets ✅

**Usage:**
```bash
# Full setup (not yet implemented)
bun scripts/secrets.ts setup

# Generate manifests only (not yet implemented)
bun scripts/secrets.ts generate

# Validate secrets.yaml (not yet implemented)
bun scripts/secrets.ts validate
```

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

**Phase 1 Complete:**
- ✅ package.json, tsconfig.json setup
- ✅ mise.toml updated (bun added)
- ✅ Provider-agnostic secrets.yaml files created
- ✅ Shared library (scripts/lib/) implemented
- ✅ Types and parser implemented

**Phase 2 (Next):**
- 🚧 GCP provider implementation
- 🚧 Manifest generators
- 🚧 CLI implementation (setup, generate, validate commands)
- 🚧 Testing and validation

## Bash Scripts (Legacy)

### Secrets Management (To Be Removed)

These bash scripts will be removed once TypeScript implementation is complete:
- `scripts/secrets.sh` - Main entry point ❌
- `scripts/secrets-gcp.sh` - GCP provider ❌
- `scripts/secrets-aws.sh` - AWS placeholder ❌
- `scripts/secrets-azure.sh` - Azure placeholder ❌
- `scripts/validate-secrets.sh` - Validation ❌

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
| secrets.sh | 🚧 In Progress | Phase 1 complete, Phase 2 pending |
| bootstrap.sh | ⏳ Pending | Future migration |
| provision.sh | ⏳ Pending | Future migration |
| admin-access.sh | ⏳ Pending | Future migration |
| validate.sh | ⏳ Pending | Future migration |
| resize-statefulset-storage.sh | ⏳ Pending | Future migration |
| teardown.sh | ⏳ Pending | Future migration |
| unbootstrap.sh | ⏳ Pending | Future migration |
