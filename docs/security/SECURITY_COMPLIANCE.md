# Compliance Checklist

Compliance guide for Monobase Infrastructure deployments supporting healthcare and other regulated industries.

## Overview

This infrastructure template is designed to support compliant deployments for various regulatory frameworks (HIPAA, SOC 2, GDPR, etc.). However, **infrastructure alone does not guarantee compliance** - organizational policies, procedures, and appropriate agreements are also required.

## HIPAA Compliance (Healthcare)

If you're deploying healthcare applications handling Protected Health Information (PHI), this section provides HIPAA-specific guidance.

---

## Technical Safeguards (§164.312)

### Access Control (§164.312(a))

- [ ] **Unique User Identification (Required)**
  - ✅ RBAC with service accounts per application
  - ✅ No shared credentials
  - ✅ Audit logging of all access
  - Location: `infrastructure/security/rbac/`

- [ ] **Emergency Access Procedure (Required)**
  - ✅ Break-glass admin access documented
  - ✅ Emergency access logged and reviewed
  - Document: Emergency access procedure in security policy

- [ ] **Automatic Logoff (Addressable)**
  - ✅ Session timeouts in ArgoCD, Grafana
  - ✅ JWT token expiry in Monobase API
  - Configure: Application-level session management

- [ ] **Encryption and Decryption (Addressable)**
  - ✅ Encryption at rest (Longhorn, PostgreSQL)
  - ✅ Encryption in transit (TLS everywhere)
  - ✅ KMS for key management
  - Location: `infrastructure/security/encryption/`

### Audit Controls (§164.312(b))

- [ ] **Audit Logging (Required)**
  - ✅ Kubernetes audit logs enabled
  - ✅ PostgreSQL audit logs configured
  - ✅ Application access logs
  - ✅ 7-year retention (via S3 lifecycle)
  
  **Enable:**
  ```bash
  # Kubernetes audit (EKS example)
  # Enable in cluster logging configuration
  
  # PostgreSQL audit
  # Configured in postgresql-values.yaml
  auditLog:
    destination: file
    format: JSON
    path: /var/log/postgresql/audit.json
  ```

### Integrity (§164.312(c))

- [ ] **Mechanism to Authenticate ePHI (Addressable)**
  - ✅ Checksums for backups
  - ✅ Digital signatures (optional)
  - ✅ PostgreSQL integrity validation
  
  **Verify:**
  ```bash
  # Backup integrity via Velero
  velero backup describe <backup-name>
  # Check: Phase: Completed, Validation errors: 0
  ```

### Person or Entity Authentication (§164.312(d))

- [ ] **Authentication (Required)**
  - ✅ All APIs require authentication (JWT)
  - ✅ Admin UIs require login
  - ✅ MFA recommended for admin access
  
  **Verify:**
  ```bash
  # Test unauthenticated access (should fail)
  curl https://api.myclient.com/patients
  # Expected: 401 Unauthorized
  ```

### Transmission Security (§164.312(e))

- [ ] **Integrity Controls (Addressable)**
  - ✅ TLS 1.3 for all transmissions
  - ✅ Certificate validation
  - ✅ Checksum verification
  
  **Verify:**
  ```bash
  # Check TLS version
  openssl s_client -connect api.myclient.com:443 -tls1_3
  ```

- [ ] **Encryption (Addressable)**
  - ✅ TLS encryption for all PHI transmission
  - ✅ No unencrypted PHI transmission
  
  **Verify:**
  ```bash
  # All endpoints should use HTTPS
  curl -v https://api.myclient.com 2>&1 | grep "TLS"
  ```

---

## Administrative Safeguards (§164.308)

### Security Management Process (§164.308(a)(1))

- [ ] **Risk Analysis (Required)**
  - Action: Conduct annual risk assessment
  - Document: Risk assessment report
  - Review: Security controls vs identified risks

- [ ] **Risk Management (Required)**
  - Action: Implement security controls (done via template)
  - Document: Security control implementation
  - Monitor: Continuous security monitoring

- [ ] **Sanction Policy (Required)**
  - Action: Document sanction policy for violations
  - Include: Consequences for security violations

- [ ] **Information System Activity Review (Required)**
  - Action: Review audit logs weekly
  - Monitor: Security alerts, failed access, anomalies
  - Document: Log review findings

### Assigned Security Responsibility (§164.308(a)(2))

- [ ] **Security Official (Required)**
  - Action: Designate security officer
  - Responsibility: Overall security program

### Workforce Security (§164.308(a)(3))

- [ ] **Authorization/Supervision (Addressable)**
  - ✅ RBAC controls access
  - ✅ Least privilege principle
  - Document: Access control policies

- [ ] **Workforce Clearance (Addressable)**
  - Action: Background checks for PHI access
  - Document: Workforce clearance procedures

- [ ] **Termination Procedures (Addressable)**
  - Action: Revoke access immediately on termination
  - ✅ RBAC makes this easy (delete RoleBinding)

### Information Access Management (§164.308(a)(4))

- [ ] **Access Authorization (Addressable)**
  - ✅ Role-based access (RBAC)
  - ✅ Documented roles and permissions
  - Location: `infrastructure/security/rbac/`

- [ ] **Access Establishment and Modification (Addressable)**
  - ✅ Git-based access control changes
  - ✅ Auditable via Git history

### Security Awareness and Training (§164.308(a)(5))

- [ ] **Security Training (Addressable)**
  - Action: Annual HIPAA security training
  - Topics: PHI handling, encryption, incident response

### Contingency Plan (§164.308(a)(7))

- [ ] **Data Backup Plan (Required)**
  - ✅ 3-tier backup strategy implemented
  - ✅ Automated schedules
  - ✅ Monthly restore testing
  - Location: `infrastructure/velero/`, `infrastructure/longhorn/`

- [ ] **Disaster Recovery Plan (Required)**
  - ✅ DR procedures documented
  - ✅ RTO/RPO defined
  - ✅ Recovery scenarios tested
  - Document: [BACKUP-RECOVERY.md](BACKUP-RECOVERY.md)

- [ ] **Emergency Mode Operation Plan (Required)**
  - Action: Document degraded-mode operations
  - Example: Manual processes if system down

- [ ] **Testing and Revision (Addressable)**
  - Action: Annual DR test
  - Schedule: Test disaster recovery annually

### Business Associate Contracts (§164.308(b))

- [ ] **BAA with Cloud Provider (Required)**
  - AWS: Sign AWS BAA
  - Azure: Sign Microsoft BAA
  - GCP: Sign Google Cloud BAA
  - Document: Store executed BAAs

- [ ] **BAA with Subcontractors**
  - If using: Managed monitoring, external backup services
  - Ensure: All subcontractors handling PHI have BAAs

---

## Physical Safeguards (§164.310)

### Facility Access Controls (§164.310(a))

- [ ] **Cloud Provider Compliance**
  - ✅ AWS/Azure/GCP SOC 2 compliant
  - ✅ Physical security by cloud provider
  - ✅ Covered under BAA

### Workstation Security (§164.310(b))

- [ ] **Developer Workstations**
  - Action: Encrypt developer laptops
  - Require: MFA for kubectl access
  - Policy: Screen lock after 5 min

### Device and Media Controls (§164.310(d))

- [ ] **Disposal (Required)**
  - ✅ PVC deletion removes data
  - ✅ Longhorn secure erase supported
  - Document: Data disposal procedures

- [ ] **Media Re-use (Required)**
  - ✅ PVCs encrypted (prevents data recovery)
  - ✅ Secure erase before re-use

---

## HIPAA Compliance Checklist Summary

### Infrastructure (Template Provides)

- [x] Encryption at rest (Longhorn, PostgreSQL)
- [x] Encryption in transit (TLS everywhere)
- [x] Access controls (RBAC, NetworkPolicies)
- [x] Audit logging (enabled and configured)
- [x] Backup and recovery (3-tier, tested)
- [x] Disaster recovery procedures
- [x] Security monitoring (alerts configured)
- [x] Network segmentation (NetworkPolicies)
- [x] Pod security (PSS restricted)
- [x] Secrets management (KMS integration)

### Client Responsibilities

- [ ] Sign BAA with cloud provider
- [ ] Conduct annual risk assessment
- [ ] Document security policies and procedures
- [ ] Security awareness training for workforce
- [ ] Breach notification procedures
- [ ] Access control policies
- [ ] Incident response plan
- [ ] Business continuity plan
- [ ] Regular security audits
- [ ] Vendor management (BAAs with subcontractors)

---

## HIPAA Breach Notification

### When to Report

**Breach = Unauthorized access/disclosure of PHI**

Examples:
- Database exposed to internet
- Stolen laptop with PHI
- Ransomware accessing PHI
- Employee accessing unauthorized records

### Notification Timeline

**Individuals:** 60 days
**HHS OCR:** 60 days (if >500 individuals)
**Media:** Immediately (if >500 individuals in same state)

### Breach Response Procedure

```bash
# 1. Immediate containment
kubectl delete gateway shared-gateway -n gateway-system  # Stop all traffic

# 2. Assessment
# - What PHI was accessed?
# - How many individuals affected?
# - When did breach occur?

# 3. Documentation
# - Incident timeline
# - PHI accessed
# - Mitigation steps taken

# 4. Notification
# - Affected individuals (60 days)
# - HHS OCR (if >500 affected)
# - Media (if >500 in same state)
# - Law enforcement (if requested)

# 5. Remediation
# - Fix vulnerability
# - Update security controls
# - Additional monitoring

# 6. Prevention
# - Update policies
# - Additional training
# - Enhanced controls
```

---

## BAA Requirements

### What Must Be in BAA

1. **Permitted Uses** - Cloud provider may only use PHI for services
2. **Safeguards** - Provider must implement appropriate safeguards
3. **Reporting** - Provider must report breaches to you
4. **Subcontractors** - Provider ensures subcontractors also comply
5. **Access** - You can access/inspect provider's safeguards
6. **Termination** - Termination procedures if BAA violated

### Cloud Provider BAAs

**AWS:**
- Sign via AWS Artifact
- Covers: EC2, EKS, S3, Secrets Manager, KMS, CloudWatch

**Azure:**
- Sign via Microsoft Trust Center
- Covers: AKS, Azure Storage, Key Vault, Monitor

**GCP:**
- Sign via Google Cloud compliance page
- Covers: GKE, Cloud Storage, Secret Manager, Cloud Monitoring

---

## Compliance Audit Preparation

### Documentation Required

1. **System Security Plan**
   - Infrastructure architecture (this template)
   - Security controls implemented
   - Encryption methods
   - Access controls

2. **Policies and Procedures**
   - Security policy
   - Privacy policy
   - Breach notification policy
   - Incident response plan
   - Business continuity plan
   - Access control policy

3. **Evidence of Compliance**
   - BAA with cloud provider
   - Security training records
   - Risk assessment reports
   - Audit log samples
   - Backup test results
   - Penetration test reports

4. **Configuration Evidence**
   ```bash
   # Generate compliance report
   
   # 1. Encryption status
   kubectl get storageclass longhorn -o yaml | grep encrypted
   
   # 2. NetworkPolicy list
   kubectl get networkpolicy -A -o yaml
   
   # 3. Pod Security Standards
   kubectl get namespace myclient-prod -o yaml | grep pod-security
   
   # 4. Backup schedules
   velero schedule get -o yaml
   
   # 5. TLS certificates
   kubectl get certificate -A
   ```

---

## Annual Compliance Tasks

### Q1 (January-March)
- [ ] Annual risk assessment
- [ ] Security policy review
- [ ] BAA renewal (if needed)
- [ ] Penetration testing

### Q2 (April-June)
- [ ] Security awareness training
- [ ] Audit log review
- [ ] Backup restore testing
- [ ] DR plan testing

### Q3 (July-September)
- [ ] Mid-year risk review
- [ ] Security control testing
- [ ] Vendor assessment
- [ ] Incident response drill

### Q4 (October-December)
- [ ] Annual compliance audit
- [ ] Policy updates
- [ ] Next year planning
- [ ] Training updates

---

## Summary

**Compliance Status:**
- ✅ **Technical Safeguards:** Fully implemented
- ✅ **Encryption:** At rest + in transit
- ✅ **Access Controls:** RBAC + NetworkPolicies
- ✅ **Audit Logs:** Enabled with configurable retention
- ✅ **Backup/DR:** 3-tier, tested monthly
- ⚠️ **Administrative:** Organization must document policies
- ⚠️ **Physical:** Cloud provider responsibility (via agreements)
- ⚠️ **Agreements:** Organization must sign appropriate agreements (BAA for HIPAA, DPA for GDPR, etc.)

**This infrastructure provides the technical foundation for regulatory compliance. Organizations must complete organizational requirements (policies, training, appropriate agreements) for full compliance.**

**Note:** This guide focuses on HIPAA as an example. For other frameworks (SOC 2, GDPR, PCI-DSS), consult with your compliance team to map these controls to your specific requirements.

For security details, see [SECURITY-HARDENING.md](SECURITY-HARDENING.md).
