# External Secrets Operator

External Secrets Operator synchronizes secrets from external KMS to Kubernetes secrets.

## Supported Providers

- **AWS Secrets Manager** - Recommended for AWS EKS
- **Azure Key Vault** - Recommended for Azure AKS
- **GCP Secret Manager** - Recommended for GCP GKE
- **SOPS** - For encrypted files in Git

## Installation

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \\
  --namespace external-secrets \\
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
  name: mongodb-credentials
spec:
  secretStoreRef:
    name: aws-secretstore
    kind: SecretStore
  target:
    name: mongodb-credentials
  data:
    - secretKey: root-password
      remoteRef:
        key: client/prod/mongodb/root-password
```

## Phase 3 Implementation

Full implementation includes:
- SecretStore templates for all providers
- Integration with IAM roles (IRSA, Workload Identity)
- Refresh intervals and rotation policies
- ClusterSecretStore for shared secrets
