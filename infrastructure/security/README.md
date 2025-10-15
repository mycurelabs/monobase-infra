# Security Hardening Layer

Production-grade security controls for HIPAA compliance and best practices.

## Components

### 1. Network Policies
- **Default Deny All** - Block all traffic by default
- **Allow-Specific** - Explicit allow rules for required traffic
- **Namespace Isolation** - Prevent cross-namespace communication
- **Egress Control** - Control outbound traffic

### 2. Pod Security Standards (PSS)
- **Restricted Profile** - Highest security level enforced
- **Non-root Users** - All containers run as non-root
- **No Privilege Escalation** - Disabled
- **Read-only Root Filesystem** - Where possible
- **Drop ALL Capabilities** - Minimal Linux capabilities

### 3. Encryption
- **At Rest** - Longhorn volume encryption, PostgreSQL encryption
- **In Transit** - TLS everywhere via cert-manager
- **Backup Encryption** - Velero backups encrypted in S3

### 4. RBAC
- **Least Privilege** - Minimal permissions per service account
- **No Default SA** - Explicit service accounts
- **Namespace-scoped** - Roles limited to namespace

## Files Structure

```
security/
├── networkpolicies/
│   ├── default-deny-all.yaml
│   ├── allow-gateway-to-apps.yaml
│   ├── allow-apps-to-db.yaml
│   └── deny-cross-namespace.yaml
├── pod-security/
│   ├── namespace-pss.yaml.template
│   └── policy-exception.yaml
├── rbac/
│   ├── serviceaccount.yaml.template
│   ├── role.yaml.template
│   └── rolebinding.yaml.template
└── encryption/
    ├── postgresql-encryption.yaml
    └── backup-encryption.yaml
```

## HIPAA Compliance Checklist

- [x] Encryption at rest (Longhorn, PostgreSQL)
- [x] Encryption in transit (TLS via cert-manager)
- [x] Network segmentation (NetworkPolicies)
- [x] Access controls (RBAC, Pod Security)
- [x] Audit logging (enabled)
- [x] Backup encryption (Velero + S3 KMS)
- [ ] BAA with cloud provider (client responsibility)
- [ ] Security assessments (periodic)

## Implementation

### GitOps Deployment (Recommended)

Security baseline is deployed via ArgoCD along with all other infrastructure. **No manual installation required.**

Security baseline is **always enabled** for all environments.

#### Deployment Flow

1. **Render templates:**
   ```bash
   helm template myclient charts/monobase \
     -f config/yourclient/values-production.yaml \
     --output-dir rendered/myclient-prod
   ```

2. **Deploy via ArgoCD:**
   ```bash
   kubectl apply -f rendered/myclient-prod/monobase/templates/root-app.yaml
   ```

3. **Verify deployment:**
   ```bash
   # Check NetworkPolicies
   kubectl get networkpolicies -n myclient-prod

   # Check Pod Security Standards labels
   kubectl get namespace myclient-prod --show-labels

   # Check RBAC
   kubectl get serviceaccounts,roles,rolebindings -n myclient-prod
   ```

#### Sync Waves

Security baseline deploys early in the sequence:

- **Wave -1:** Namespace creation with Pod Security Standards labels
- **Wave 0:** NetworkPolicies and RBAC

ArgoCD ensures security is configured before applications deploy.

### What Gets Deployed

**NetworkPolicies** (from `infrastructure/security/networkpolicies/`):
- `default-deny-all.yaml` - Block all traffic by default
- `allow-gateway-to-apps.yaml` - Allow traffic from Gateway API
- `allow-apps-to-db.yaml` - Allow API to database connections
- `deny-cross-namespace.yaml` - Block cross-namespace traffic

**Pod Security Standards** (from namespace labels):
- Enforces `restricted` profile on all pods
- Configured in `argocd/infrastructure/namespace.yaml.template`

**RBAC** (from `infrastructure/security/rbac/`):
- Service accounts with least-privilege permissions
- Roles limited to namespace scope
- No cluster-wide permissions

## Phase 3 Implementation

Full implementation includes:
- Complete NetworkPolicy set
- Pod Security Standards configuration
- RBAC templates for all services
- Encryption configuration for all data stores
- Security scanning integration
- HIPAA compliance documentation
