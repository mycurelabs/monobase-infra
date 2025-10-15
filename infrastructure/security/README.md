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

```bash
# Apply NetworkPolicies
kubectl apply -f networkpolicies/

# Enable Pod Security Standards
kubectl label namespace client-prod \\
  pod-security.kubernetes.io/enforce=restricted \\
  pod-security.kubernetes.io/audit=restricted \\
  pod-security.kubernetes.io/warn=restricted

# Apply RBAC
kubectl apply -f rbac/
```

## Phase 3 Implementation

Full implementation includes:
- Complete NetworkPolicy set
- Pod Security Standards configuration
- RBAC templates for all services
- Encryption configuration for all data stores
- Security scanning integration
- HIPAA compliance documentation
