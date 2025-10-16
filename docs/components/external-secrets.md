# External Secrets Operator

External Secrets Operator synchronizes secrets from external KMS to Kubernetes secrets.

## Supported Providers

- **AWS Secrets Manager** - Recommended for AWS EKS
- **Azure Key Vault** - Recommended for Azure AKS
- **GCP Secret Manager** - Recommended for GCP GKE
- **SOPS** - For encrypted files in Git

## Automatic GitOps Deployment

When `externalSecrets.enabled: true` in `argocd/infrastructure/values.yaml`, the bootstrap process automatically deploys:

1. **External Secrets Operator** (sync wave 0) - Core operator
2. **SecretStore/ClusterSecretStore** (sync wave 1) - Provider-specific store

**Configuration:** Set provider in `argocd/infrastructure/values.yaml`:

```yaml
externalSecrets:
  enabled: true
  provider: aws  # Options: aws, azure, gcp, sops
  
  aws:
    region: us-east-1
    roleArn: "arn:aws:iam::123456789012:role/external-secrets-role"
```

**What gets created:**
- ✅ External Secrets Operator in `external-secrets-system` namespace
- ✅ ServiceAccount with IRSA/Workload Identity annotations
- ✅ ClusterSecretStore for the selected provider
- ✅ Applications can now reference the SecretStore

**Configuration files:**
- Operator: `argocd/infrastructure/templates/external-secrets.yaml`
- SecretStores: `infrastructure/external-secrets/secretstores.yaml` (GitOps-managed)

## Manual Installation (if not using GitOps)

```bash
# Install External Secrets Operator manually
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \\
  --namespace external-secrets-system \\
  --create-namespace \\
  --values helm-values.yaml
```

## Files

- `helm-values.yaml` - External Secrets Operator configuration
- `secretstore/aws-secretsmanager.yaml.template` - AWS SecretStore
- `secretstore/azure-keyvault.yaml.template` - Azure SecretStore
- `secretstore/gcp-secretmanager.yaml.template` - GCP SecretStore
- `secretstore/sops.yaml.template` - SOPS SecretStore

## Usage Pattern

1. **Store secrets in KMS** (AWS/Azure/GCP)
2. **Create SecretStore** (per namespace or cluster-wide)
3. **Create ExternalSecret** (maps KMS → K8s Secret)
4. **ESO syncs automatically** (watches KMS for changes)

## Example ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgresql-credentials
spec:
  secretStoreRef:
    name: aws-secretstore
    kind: SecretStore
  target:
    name: postgresql-credentials
  data:
    - secretKey: root-password
      remoteRef:
        key: client/prod/postgresql/root-password
```

## Supported Providers

All providers are configured automatically based on `externalSecrets.provider`:

### AWS Secrets Manager
- **Uses**: IRSA (IAM Roles for Service Accounts)
- **Required**: `roleArn` in configuration
- **SecretStore**: `aws-secretstore` (ClusterSecretStore)

### Azure Key Vault
- **Uses**: Workload Identity
- **Required**: `vaultUrl` and `identityId` in configuration
- **SecretStore**: `azure-secretstore` (ClusterSecretStore)

### GCP Secret Manager
- **Uses**: Workload Identity
- **Required**: `projectId`, `serviceAccountEmail` in configuration
- **SecretStore**: `gcp-secretstore` (ClusterSecretStore)

### SOPS (Git-Encrypted Secrets)
- **Uses**: Age or PGP encryption
- **Required**: SOPS age key in secret
- **SecretStore**: `sops-secretstore` (ClusterSecretStore)

## Provider Setup Requirements

### AWS (IRSA)
1. Create IAM role with trust relationship to EKS OIDC provider
2. Attach Secrets Manager read policy
3. Set `roleArn` in values.yaml
4. Bootstrap deploys ServiceAccount with annotation

### Azure (Workload Identity)
1. Create Managed Identity with Key Vault read permissions
2. Federate identity with AKS
3. Set `vaultUrl` and `identityId` in values.yaml
4. Bootstrap deploys ServiceAccount with annotation

### GCP (Workload Identity)
1. Create GCP Service Account with Secret Manager access
2. Bind to Kubernetes ServiceAccount
3. Set `projectId` and `serviceAccountEmail` in values.yaml
4. Bootstrap deploys ServiceAccount with annotation
