# Certificate Management

Quick reference for managing TLS certificates in the Gateway.

---

## Overview

All certificates for the Gateway are centrally managed and stored in the `gateway-system` namespace.

**Certificate Types:**
- **HTTP-01 Auto:** `app.client.com` - auto-provisioned for client domains
- **Client-Provided:** Client uploads to GCP Secret Manager, ESO syncs

---

## Configuration File

**`infrastructure/certificates.yaml`**

All certificates declared in a single file for centralized management.

```yaml
certificates:
  # Client domain certificates (HTTP-01 auto-provisioned)
  - name: client1-domain
    domain: "app.client.com"
    issuer: letsencrypt-prod
    challengeType: http01
  
  # Client-provided certificates
  - name: client2-domain
    domain: "portal.client.com"
    certificateSource: provided
    externalSecret:
      gcpSecretName: client2-domain-cert
      gcpSecretKey: client2-domain-key
```

---

## Quick Operations

### Add New Client Domain

1. Client creates DNS: `app.client.com` → A → `<LoadBalancer-IP>`

2. Add to `infrastructure/certificates.yaml`:
   ```yaml
   - name: client-name-domain
     domain: "app.client.com"
     issuer: letsencrypt-prod
     challengeType: http01
   ```

3. Commit and push:
   ```bash
   git add infrastructure/certificates.yaml
   git commit -m "feat: Add certificate for app.client.com"
   git push
   ```

4. Verify (2-5 minutes):
   ```bash
   kubectl get certificate -n gateway-system
   ```

### Check Certificate Status

```bash
# List all certificates
kubectl get certificate -n gateway-system

# Check specific certificate
kubectl describe certificate client-name-domain-tls -n gateway-system

# Check expiry dates
kubectl get secret -n gateway-system -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls") | 
    .metadata.name + ": expires " + 
    (.data["tls.crt"] | @base64d | 
    capture("Not After : (?<date>[^\n]+)") | .date)'
```

### Troubleshoot Certificate Issues

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check Certificate events
kubectl describe certificate <name> -n gateway-system

# Check ACME challenges
kubectl get challenge -n gateway-system
kubectl describe challenge <name> -n gateway-system
```

---

## File Structure

```
infrastructure/
├── certificates/
│   ├── README.md                    # This file
│   └── certificates.yaml            # Certificate declarations (to be created)
│
├── tls/
│   └── README.md                    # TLS infrastructure documentation
│
└── gateway/
    ├── shared-gateway.yaml          # Gateway resource with certificateRefs
    └── envoy-gatewayclass.yaml      # GatewayClass configuration

charts/cert-manager-issuers/         # ClusterIssuer Helm chart
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── clusterissuer.yaml           # Multi-provider ClusterIssuer template
│   └── _helpers.tpl
└── README.md
```

---

## Certificate Lifecycle

1. **Declaration:** Added to `infrastructure/certificates.yaml`
2. **Provisioning:** cert-manager or ESO creates Secret in `gateway-system`
3. **Gateway:** Automatically references certificate (via certificateRefs)
4. **Usage:** HTTPRoutes use domain, traffic flows through Gateway
5. **Renewal:** Automatic (cert-manager) or manual (client-provided)

---

## ClusterIssuers

ClusterIssuers are now managed via the `cert-manager-issuers` Helm chart.

**Configuration:** `argocd/infrastructure/values.yaml` → `certManagerIssuers.issuers`  
**Chart:** `charts/cert-manager-issuers/`

### letsencrypt-prod (HTTP-01)

- **Default for client domains**
- For single-domain certificates
- No DNS API access needed
- Client only needs to create A record

### letsencrypt-staging (HTTP-01)

- Testing HTTP-01 certificate provisioning
- Avoids Let's Encrypt rate limits
- Certificates NOT trusted by browsers

---

## Gateway Configuration

**File:** `infrastructure/gateway/shared-gateway.yaml`

Gateway references all certificates:

```yaml
spec:
  listeners:
    - name: https
      hostname: "*"  # Accept all domains
      tls:
        certificateRefs:
          - name: client1-domain-tls
          - name: client2-domain-tls
          # ... auto-generated from certificates.yaml
```

---

## Naming Conventions

**Certificate Names:**
- Format: `{client}-{purpose}`
- Examples:
  - `client-acme-main`
  - `client-globex-portal`

**Secret Names:**
- Automatically generated: `{certificate-name}-tls`
- Examples:
  - `client-acme-main-tls`
  - `client-globex-portal-tls`

**ClusterIssuer Names:**
- `letsencrypt-prod` - HTTP-01 production (default for client domains)
- `letsencrypt-staging` - HTTP-01 staging

---

## Common Issues

### Certificate Not Issuing

**Check:**
```bash
kubectl describe certificate <name> -n gateway-system
kubectl get challenge -n gateway-system
kubectl logs -n cert-manager -l app=cert-manager
```

**Common causes:**
- DNS not pointing to LoadBalancer IP
- Port 80 blocked (for HTTP-01)
- Let's Encrypt rate limit exceeded
- Invalid domain format

### Gateway Not Routing

**Check:**
```bash
kubectl get httproute -n <namespace>
kubectl describe httproute <name> -n <namespace>
kubectl get gateway shared-gateway -n gateway-system -o yaml
```

**Common causes:**
- HTTPRoute hostname doesn't match certificate domain
- HTTPRoute not attached to Gateway
- Certificate not in Gateway certificateRefs list

---

## Documentation

**Full Documentation:**
- [Multi-Domain Gateway Architecture](../../docs/architecture/MULTI-DOMAIN-GATEWAY.md)
- [Certificate Management Operations Guide](../../docs/operations/CERTIFICATE-MANAGEMENT.md)
- [Client Onboarding Guide](../../docs/getting-started/CLIENT-ONBOARDING.md)

**External Resources:**
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)

---

## Support

For issues or questions:
1. Check [Certificate Management Operations Guide](../../docs/operations/CERTIFICATE-MANAGEMENT.md)
2. Review cert-manager logs
3. Check Gateway status
4. Contact platform team
