# External Secrets Configuration

This directory contains SecretStore and ClusterSecretStore configurations for External Secrets Operator (ESO).

## Current Setup

- **SOPS Secrets**: Managed via KSOPS in GitOps workflow (see `infrastructure/tls/`)
- **Cloud KMS**: Add SecretStores here for client-specific cloud providers

## Architecture

```
Secrets Management Strategy:
├── SOPS (via KSOPS)
│   └── For: Infrastructure secrets (TLS, bootstrap)
│   └── Managed by: ArgoCD + KSOPS plugin
│   └── Encrypted in: Git repository
│
└── External Secrets Operator
    ├── AWS Secrets Manager (for client use)
    ├── Azure Key Vault (for client use)
    └── GCP Secret Manager (for client use)
    └── Managed by: ESO + ClusterSecretStores
```

## Adding Cloud Provider SecretStores

### AWS Secrets Manager Example

```yaml
# aws-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
  labels:
    app.kubernetes.io/name: aws-secretstore
    app.kubernetes.io/component: external-secrets
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
```

Then create ExternalSecrets to sync from AWS:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
  namespace: my-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
    creationPolicy: Owner
  data:
    - secretKey: database-password
      remoteRef:
        key: prod/my-app/database
        property: password
```

### Azure Key Vault Example

```yaml
# azure-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
  labels:
    app.kubernetes.io/name: azure-secretstore
    app.kubernetes.io/component: external-secrets
spec:
  provider:
    azurekv:
      vaultUrl: https://my-vault.vault.azure.net
      authSecretRef:
        clientId:
          name: azure-creds
          namespace: external-secrets-system
          key: client-id
        clientSecret:
          name: azure-creds
          namespace: external-secrets-system
          key: client-secret
      tenantId: your-tenant-id
```

### GCP Secret Manager Example

```yaml
# gcp-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcpsm
  labels:
    app.kubernetes.io/name: gcp-secretstore
    app.kubernetes.io/component: external-secrets
spec:
  provider:
    gcpsm:
      projectID: my-project-id
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: my-cluster
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
```

## Usage

1. Add your SecretStore YAML file to this directory
2. Commit and push to Git
3. ArgoCD will automatically sync the SecretStore
4. Create ExternalSecrets in your application namespaces to reference the SecretStore

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Secrets Manager Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [Azure Key Vault Provider](https://external-secrets.io/latest/provider/azure-key-vault/)
- [GCP Secret Manager Provider](https://external-secrets.io/latest/provider/google-secrets-manager/)
