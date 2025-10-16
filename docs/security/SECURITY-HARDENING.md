# Security Hardening Guide

Production security hardening for compliant deployments.

## Security Checklist

### Network Security
- [ ] NetworkPolicies applied (default-deny + explicit allow)
- [ ] Cross-namespace traffic blocked
- [ ] Gateway rate limiting enabled
- [ ] DDoS protection configured
- [ ] Security headers enabled (HSTS, CSP, X-Frame-Options)
- [ ] TLS 1.3 enforced
- [ ] Weak ciphers disabled

### Pod Security
- [ ] Pod Security Standards enforced (restricted)
- [ ] All containers run as non-root
- [ ] No privilege escalation allowed
- [ ] ALL capabilities dropped
- [ ] seccomp profile applied
- [ ] Read-only root filesystem (where possible)

### Access Control
- [ ] RBAC configured (least privilege)
- [ ] Service accounts per application
- [ ] No default service accounts used
- [ ] Admin access restricted
- [ ] MFA enabled for admin accounts
- [ ] API keys rotated regularly

### Encryption
- [ ] Encryption at rest (Longhorn volumes)
- [ ] Encryption in transit (TLS everywhere)
- [ ] PostgreSQL encryption enabled
- [ ] Backup encryption enabled (S3 + KMS)
- [ ] Secrets in KMS (never in Git)
- [ ] TLS certificates from trusted CA

### Secrets Management
- [ ] External Secrets Operator deployed
- [ ] All secrets in KMS
- [ ] Secret rotation policy documented
- [ ] Audit logging enabled for secret access
- [ ] No secrets in ConfigMaps or environment variables
- [ ] Secrets refreshed automatically (1h interval)

### Monitoring & Audit
- [ ] Audit logging enabled for all components
- [ ] Security alerts configured
- [ ] Failed login attempts monitored
- [ ] Unusual network activity alerted
- [ ] Resource usage monitored
- [ ] Backup failures alerted

---

## Network Security Hardening

### 1. NetworkPolicies

**Apply Zero-Trust Model:**

```bash
# Step 1: Deny all traffic (foundation)
kubectl apply -f infrastructure/security/networkpolicies/default-deny-all.yaml

# Step 2: Allow specific patterns
kubectl apply -f infrastructure/security/networkpolicies/allow-gateway-to-apps.yaml
kubectl apply -f infrastructure/security/networkpolicies/allow-apps-to-db.yaml
kubectl apply -f infrastructure/security/networkpolicies/allow-apps-to-storage.yaml

# Step 3: Deny cross-namespace
kubectl apply -f infrastructure/security/networkpolicies/deny-cross-namespace.yaml

# Verify
kubectl get networkpolicy -n myclient-prod
```

**Test NetworkPolicies:**

```bash
# Should FAIL (blocked by default-deny):
kubectl run test --image=busybox -n myclient-prod -it --rm -- \\
  wget -O- http://api.other-namespace:7500

# Should SUCCEED (allowed by allow rules):
kubectl run test --image=busybox -n gateway-system -it --rm -- \\
  wget -O- http://api.myclient-prod:7500
```

### 2. Gateway Security

**Rate Limiting:**

```yaml
# Applied via BackendTrafficPolicy
# See: infrastructure/envoy-gateway/rate-limit-policy.yaml

# Per-IP limits:
# - 100 requests/second
# - 1000 requests/minute burst
```

**Security Headers:**

```yaml
# Automatically added by SecurityPolicy:
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000; includeSubDomains
Referrer-Policy: strict-origin-when-cross-origin
```

**CORS Configuration:**

```yaml
# Restrict allowed origins:
allowOrigins:
  - https://app.myclient.com
  - https://admin.myclient.com
# Deny all others
```

### 3. TLS Configuration

**Enforce TLS 1.3:**

```bash
# Via Gateway EnvoyProxy config
# Weak ciphers automatically disabled
# Only strong ciphers allowed:
# - TLS_AES_128_GCM_SHA256
# - TLS_AES_256_GCM_SHA384
# - TLS_CHACHA20_POLY1305_SHA256
```

**Certificate Management:**

```bash
# Wildcard certificate (recommended)
# Covers: *.myclient.com

# Automatic renewal (30 days before expiry)
# Let's Encrypt certificates valid 90 days

# Monitor certificate expiry
kubectl get certificate -A
```

---

## Pod Security Hardening

### 1. Pod Security Standards

**Restricted Profile Enforced:**

```bash
# Apply to namespace
kubectl label namespace myclient-prod \\
  pod-security.kubernetes.io/enforce=restricted \\
  pod-security.kubernetes.io/audit=restricted \\
  pod-security.kubernetes.io/warn=restricted

# Verify
kubectl get namespace myclient-prod -o yaml | grep pod-security
```

**All Pods Must:**
- ✅ Run as non-root user
- ✅ Drop ALL Linux capabilities
- ✅ Disable privilege escalation
- ✅ Use seccomp profile (RuntimeDefault)
- ✅ No host namespaces (network/PID/IPC)
- ✅ No privileged mode

**Our Helm charts already comply!**

### 2. Security Context Best Practices

**Container Security Context:**

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000         # Non-root UID
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL              # Drop all capabilities
  readOnlyRootFilesystem: true  # Where possible
  seccompProfile:
    type: RuntimeDefault
```

**Pod Security Context:**

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

### 3. Image Security

**Image Best Practices:**

```bash
# 1. Pin specific versions (never "latest")
image:
  tag: "5.215.2"  # ✅ GOOD
  # tag: "latest"   # ❌ BAD

# 2. Use minimal base images
# - distroless (Google)
# - alpine (minimal)
# - scratch (static binaries)

# 3. Scan images for vulnerabilities
trivy image ghcr.io/YOUR-ORG/api:5.215.2

# 4. Sign images (optional)
cosign sign ghcr.io/YOUR-ORG/api:5.215.2

# 5. Verify signatures
cosign verify ghcr.io/YOUR-ORG/api:5.215.2
```

---

## Access Control Hardening

### 1. RBAC

**Least Privilege Principle:**

```bash
# Each app has minimal permissions
# See: infrastructure/security/rbac/

# Verify permissions
kubectl auth can-i get secrets \\
  --as=system:serviceaccount:myclient-prod:api \\
  -n myclient-prod
# yes (needs secrets)

kubectl auth can-i delete pods \\
  --as=system:serviceaccount:myclient-prod:api \\
  -n myclient-prod
# no (doesn't need to delete pods)
```

**Audit RBAC:**

```bash
# List all RoleBindings
kubectl get rolebindings -n myclient-prod

# Review permissions
kubectl describe role api -n myclient-prod
```

### 2. Admin Access

**Restrict Admin Access:**

```bash
# ArgoCD admin access via SSO (not password)
# Configure in infrastructure/argocd/helm-values.yaml

# kubectl access via RBAC
# Create read-only role for developers:

kubectl create clusterrole developer-readonly \\
  --verb=get,list,watch \\
  --resource=pods,services,deployments,logs

# Bind to developer group
kubectl create clusterrolebinding developers \\
  --clusterrole=developer-readonly \\
  --group=developers
```

**MFA for Production:**

```bash
# Require MFA for:
# - kubectl access (via OIDC provider)
# - ArgoCD UI (via SSO)
# - Cloud console access
# - KMS access
# - Bastion/jump host access
```

---

## Encryption Hardening

### 1. Encryption at Rest

**Longhorn Volume Encryption:**

```bash
# Enable encryption in StorageClass
# See: infrastructure/longhorn/storageclass.yaml

parameters:
  encrypted: "true"

# Create encryption passphrase
kubectl create secret generic longhorn-crypto \\
  --from-literal=CRYPTO_KEY_VALUE=$(openssl rand -base64 32) \\
  -n longhorn-system

# Or use External Secrets (recommended)
```

**PostgreSQL Encryption:**

```yaml
# Enable in deployments/*/values.yaml
postgresql:
  encryption:
    enabled: true
    existingSecret: postgresql-encryption-key

  tls:
    enabled: true
    mode: requireTLS
```

### 2. Encryption in Transit

**TLS Everywhere:**

```
✅ Client → Gateway: TLS 1.3
✅ Gateway → Apps: HTTP (internal, within cluster)
✅ Apps → PostgreSQL: TLS
✅ Apps → External APIs: HTTPS
✅ Backup → S3: HTTPS + encryption
```

**PostgreSQL TLS:**

```bash
# Generate certificates (or use cert-manager)
openssl req -x509 -newkey rsa:4096 \\
  -keyout postgresql.key \\
  -out postgresql.crt \\
  -days 365 \\
  -nodes \\
  -subj "/CN=postgresql.myclient-prod.svc.cluster.local"

# Create secret
kubectl create secret generic postgresql-tls \\
  --from-file=tls.crt=postgresql.crt \\
  --from-file=tls.key=postgresql.key \\
  -n myclient-prod
```

### 3. Secrets Management

**Never Commit Secrets:**

```bash
# ❌ NEVER do this:
kubectl create secret generic my-secret \\
  --from-literal=password=MyPassword123 \\
  --dry-run=client -o yaml > secret.yaml
git add secret.yaml  # ❌ DON'T COMMIT!

# ✅ ALWAYS use External Secrets:
# 1. Store in KMS
aws secretsmanager create-secret \\
  --name myclient/prod/password \\
  --secret-string "MyPassword123"

# 2. Create ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  secretStoreRef:
    name: myclient-prod-secretstore
  data:
    - secretKey: password
      remoteRef:
        key: myclient/prod/password
```

**Secret Rotation:**

```bash
# Rotate secrets every 90 days

# 1. Create new secret version in KMS
aws secretsmanager update-secret \\
  --secret-id myclient/prod/jwt-secret \\
  --secret-string "$(openssl rand -base64 64)"

# 2. External Secrets auto-syncs (within 1h)
# 3. Restart pods to use new secret
kubectl rollout restart deployment api -n myclient-prod
```

---

## Hardening Checklist

### Pre-Production

- [ ] All NetworkPolicies tested
- [ ] Pod Security Standards enforced
- [ ] RBAC audited (no excessive permissions)
- [ ] Secrets migrated to KMS
- [ ] TLS certificates valid and trusted
- [ ] Encryption at rest enabled
- [ ] Backup encryption enabled
- [ ] Monitoring and alerting configured

### Production Hardening

- [ ] Admin access via MFA only
- [ ] SSH disabled on nodes
- [ ] Audit logging enabled
- [ ] Security scanning automated (Trivy, Snyk)
- [ ] Vulnerability patching SLA defined
- [ ] Incident response plan documented
- [ ] Security training completed
- [ ] Penetration testing scheduled

### Compliance-Specific (HIPAA, SOC 2, etc.)

- [ ] Appropriate agreements signed with cloud provider (BAA for HIPAA, DPA for GDPR, etc.)
- [ ] Encryption documented in System Security Plan
- [ ] Access controls documented
- [ ] Audit logs retention configured (as per compliance requirements)
- [ ] Breach notification procedures documented
- [ ] Annual risk assessment scheduled
- [ ] Security incident log maintained

---

## Security Monitoring

### 1. Enable Audit Logging

**Kubernetes Audit Logs:**

```yaml
# Enable on cluster (EKS example)
# In cluster config:
logging:
  clusterLogging:
    - types:
        - audit
        - authenticator
      enabled: true
```

**PostgreSQL Audit Logs:**

```yaml
# In postgresql configuration:
auditLog:
  destination: file
  format: JSON
  path: /var/log/postgresql/audit.json
```

### 2. Security Alerts

**Configure in Prometheus:**

```yaml
# See: infrastructure/monitoring/prometheus-rules.yaml

# Alerts for:
- Failed authentication attempts
- Privilege escalation attempts
- NetworkPolicy violations
- Secret access anomalies
- Unusual network patterns
- Failed backup attempts
```

### 3. Log Aggregation

**Forward logs to SIEM:**

```bash
# Options:
# - Fluent Bit → CloudWatch / Elasticsearch
# - Promtail → Loki
# - Vector → Datadog / Splunk

# Example: Install Fluent Bit
helm install fluent-bit fluent/fluent-bit \\
  --namespace logging \\
  --create-namespace
```

---

## Compliance Hardening

### HIPAA Requirements

**Technical Safeguards (§164.312):**

1. **Access Control (§164.312(a))**
   - ✅ Unique user identification (RBAC)
   - ✅ Automatic logoff (session timeouts)
   - ✅ Encryption and decryption (at rest + transit)

2. **Audit Controls (§164.312(b))**
   - ✅ Audit logs enabled
   - ✅ 7-year retention configured
   - ✅ Log integrity protected

3. **Integrity (§164.312(c))**
   - ✅ Data integrity (checksums, encryption)
   - ✅ Unauthorized modification detection

4. **Transmission Security (§164.312(e))**
   - ✅ TLS encryption for all transmissions
   - ✅ Integrity controls (TLS validation)

### SOC 2 Considerations

**Control Objectives:**

1. **Security** - Encryption, access controls, monitoring
2. **Availability** - HA, backups, disaster recovery
3. **Processing Integrity** - Checksums, validation
4. **Confidentiality** - Encryption, access controls
5. **Privacy** - Data retention, deletion procedures

---

## Incident Response

### Security Incident Procedure

**1. Detection:**
- Monitor alerts in Alertmanager
- Review audit logs daily
- Automated security scanning

**2. Containment:**

```bash
# Isolate compromised pod
kubectl label pod suspicious-pod-xyz quarantine=true -n myclient-prod

# Block network access
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-suspicious-pod
  namespace: myclient-prod
spec:
  podSelector:
    matchLabels:
      quarantine: "true"
  policyTypes:
    - Ingress
    - Egress
  # No ingress/egress rules = total isolation
EOF

# Collect forensics
kubectl logs suspicious-pod-xyz -n myclient-prod > evidence.log
kubectl describe pod suspicious-pod-xyz -n myclient-prod > pod-details.txt
```

**3. Eradication:**

```bash
# Delete compromised resources
kubectl delete pod suspicious-pod-xyz -n myclient-prod

# Rotate all secrets
# See: Secret Rotation procedure above

# Patch vulnerabilities
kubectl set image deployment/api \\
  api=ghcr.io/YOUR-ORG/api:5.215.3-patched \\
  -n myclient-prod
```

**4. Recovery:**

```bash
# Restore from known-good backup if needed
velero restore create incident-recovery \\
  --from-backup daily-full-20250114020000

# Verify integrity
# Run security scans
# Monitor for reinfection
```

**5. Post-Incident:**
- Document incident
- Update security controls
- Notify affected parties (as required by compliance, e.g., HIPAA breach notification if PHI accessed)
- Conduct lessons learned

---

## Vulnerability Management

### 1. Image Scanning

**Automated Scanning:**

```bash
# Scan container images
trivy image ghcr.io/YOUR-ORG/api:5.215.2

# Scan Helm charts
trivy config charts/api

# Scan Kubernetes manifests
trivy kubernetes --namespace myclient-prod

# CI/CD integration
# Add to GitHub Actions / GitLab CI
```

### 2. Dependency Scanning

```bash
# Scan npm dependencies (in application repos)
npm audit
npm audit fix

# Scan Helm dependencies
helm dependency list charts/api
# Check for outdated charts
```

### 3. Patching SLA

**Severity Levels:**

| Severity | Patch Within | Example |
|----------|--------------|---------|
| Critical | 24 hours | Remote code execution |
| High | 7 days | Privilege escalation |
| Medium | 30 days | Information disclosure |
| Low | 90 days | Minor issues |

---

## Security Testing

### 1. Penetration Testing

**Schedule:**
- Annual external penetration test
- Quarterly internal security review
- After major infrastructure changes

**Scope:**
- External attack surface (Gateway, APIs)
- Internal lateral movement
- Privilege escalation
- Data exfiltration

### 2. Compliance Audits

**HIPAA Audit:**
- Annual risk assessment
- Review access controls
- Verify encryption
- Test backup/recovery
- Review audit logs

### 3. Automated Security Scanning

```bash
# Run weekly security scans

# 1. Image vulnerabilities
trivy image --severity HIGH,CRITICAL <image>

# 2. Misconfigurations
kubesec scan deployment.yaml

# 3. RBAC analysis
kubectl rbac-lookup --kind user --name developer

# 4. Network policy validation
kubectl get networkpolicy -A
```

---

## Hardening for Specific Threats

### 1. Credential Stuffing

**Mitigation:**
- Rate limiting (100 req/min)
- Account lockout after 5 failed attempts
- MFA for all accounts
- Monitor failed login attempts

### 2. SQL Injection

**Mitigation:**
- Parameterized queries in Monobase API (already done)
- Input validation
- WAF rules (if using external WAF)
- Regular code reviews

### 3. DDoS Attacks

**Mitigation:**
- Gateway rate limiting (per IP)
- CloudFlare / AWS Shield (optional)
- Auto-scaling (HPA)
- Resource quotas per namespace

### 4. Data Exfiltration

**Mitigation:**
- Egress NetworkPolicies
- Monitor large data transfers
- S3 bucket policies (restrict IPs)
- Alert on unusual API usage

### 5. Container Escape

**Mitigation:**
- Pod Security Standards (restricted)
- seccomp profile
- AppArmor / SELinux
- No privileged containers
- Regular kernel updates

---

## Security Best Practices

### 1. Least Privilege

✅ Service accounts with minimal permissions
✅ NetworkPolicies block by default
✅ No cluster-admin access in production
✅ RBAC audited regularly

### 2. Defense in Depth

✅ Multiple security layers
✅ Network + Pod + Application + Data
✅ No single point of failure
✅ Assume breach mentality

### 3. Security by Default

✅ Security controls in template
✅ Clients get security automatically
✅ Secure defaults, opt-in to relax
✅ Regular security updates

### 4. Auditability

✅ All actions logged
✅ Logs immutable (S3 Object Lock)
✅ 7-year retention (HIPAA)
✅ Regular log reviews

---

## Security Resources

### Internal
- [HIPAA-COMPLIANCE.md](HIPAA-COMPLIANCE.md) - Compliance checklist
- [BACKUP-RECOVERY.md](BACKUP-RECOVERY.md) - DR procedures
- infrastructure/security/ - Security policy files

### External
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Top 10](https://owasp.org/www-project-kubernetes-top-ten/)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/)

---

## Security Incident Contacts

**Internal:**
- Security Team: security@example.com
- On-Call: See PagerDuty rotation

**External:**
- Cloud Provider Support
- Compliance-specific notifications (e.g., HIPAA Breach Notification: HHS OCR)
- Legal Team (for breach notification)

**Report Security Issues:**
- Email: security@example.com
- PGP Key: [link]
- Response SLA: 24 hours
