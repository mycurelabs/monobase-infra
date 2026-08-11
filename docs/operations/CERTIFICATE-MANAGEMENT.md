# Certificate Management Operations Guide

Practical guide for managing TLS certificates in the multi-domain gateway architecture.

---

## Quick Reference

**Add Client Domain:**
1. Edit `values/infrastructure/main.yaml` (under `nginxGatewayResources.tls.certificates`)
2. Commit and push
3. Wait 2-5 minutes for certificate provisioning
4. Verify with `kubectl get certificate -n nginx-gateway-system`

**Check Certificate Status:**
```bash
kubectl get certificate -n nginx-gateway-system
```

**Troubleshoot Issues:**
```bash
kubectl describe certificate <name> -n nginx-gateway-system
kubectl logs -n cert-manager -l app=cert-manager
```

---

## Certificate Configuration Reference

### File: values/infrastructure/main.yaml

All certificates are declared under `nginxGatewayResources.tls.certificates` for centralized management. The `charts/nginx-gateway` chart renders these into cert-manager `Certificate` resources.

**Schema:**
```yaml
nginxGatewayResources:
  tls:
    certificates:
      - secretName: string        # TLS Secret name (e.g. nginx-gateway-tls-prod)
        clusterIssuer: string     # ClusterIssuer name
        dnsNames:                 # One or more fully qualified domain names
          - string
```

---

## Certificate Types

### 1. HTTP-01 Auto-Provisioned Certificate

**Purpose:** Automatically provision certificates for client-owned domains

**Example:**
```yaml
nginxGatewayResources:
  tls:
    certificates:
      - secretName: nginx-gateway-tls-client1
        clusterIssuer: letsencrypt-nginx-http01
        dnsNames:
          - "app.client.com"
```

**Requirements:**
- Client creates DNS A record: `app.client.com` → LoadBalancer IP
- Domain publicly accessible on port 80
- Let's Encrypt can reach domain via HTTP

**Use Cases:**
- Client-owned domains
- Client has DNS access but no API access
- Most common scenario

**Limitations:**
- ❌ No wildcard support (HTTP-01 limitation)
- ❌ Domain must be publicly accessible
- ⚠️ Rate limits: 50 certificates/week per registered domain

**Process:**
1. Client creates DNS record
2. Platform adds certificate declaration
3. cert-manager creates temporary HTTPRoute for ACME challenge
4. Let's Encrypt validates via HTTP
5. Certificate issued and stored in `nginx-gateway-system` namespace
6. Gateway automatically uses certificate

**Time:** 2-5 minutes

---

### 2. Client-Provided Certificate

**Purpose:** Client provides their own TLS certificate

**Example:**
Client-provided certificates are synced from GCP Secret Manager into a TLS Secret in `nginx-gateway-system` via an ExternalSecret, then referenced by the gateway listener. The TLS Secret follows the `nginx-gateway-tls-*` naming scheme (e.g. `nginx-gateway-tls-client2`).

**Requirements:**
- Client uploads certificate and private key to GCP Secret Manager
- External Secrets Operator configured
- Certificate must be valid for the domain

**Use Cases:**
- Client has existing certificate
- Client wants to manage certificate lifecycle
- Client uses internal Certificate Authority
- Regulatory requirements for specific CA

**Certificate Format:**
- PEM-encoded X.509 certificate
- Include full chain (intermediate CAs)
- PEM-encoded private key (RSA 2048+ or ECDSA P-256+)
- No password-protected keys

**Process:**
1. Client uploads cert to GCP Secret Manager:
   ```bash
   gcloud secrets create client2-domain-cert \
     --data-file=certificate.pem \
     --project=<project-id>
   
   gcloud secrets create client2-domain-key \
     --data-file=private-key.pem \
     --project=<project-id>
   ```

2. Platform adds ExternalSecret configuration
3. ESO syncs certificate to Kubernetes Secret
4. Gateway automatically uses certificate

**Time:** 10-30 seconds (ESO refresh interval)

---

## Operations

### Adding a New Client Domain

#### Step 1: Get LoadBalancer IP

```bash
kubectl get gateway nginx-shared-gateway -n nginx-gateway-system \
  -o jsonpath='{.status.addresses[0].value}'

# Example output: 203.0.113.42
```

#### Step 2: Client Creates DNS Record

Client must create A record pointing to LoadBalancer IP:

```
app.client.com    A    203.0.113.42
```

**Verify DNS propagation:**
```bash
dig app.client.com +short
# Should return LoadBalancer IP
```

#### Step 3: Add Certificate Declaration

Edit `values/infrastructure/main.yaml` under `nginxGatewayResources.tls.certificates`:

```yaml
nginxGatewayResources:
  tls:
    certificates:
      # Existing certificates...

      # New client certificate
      - secretName: nginx-gateway-tls-client1
        clusterIssuer: letsencrypt-nginx-http01
        dnsNames:
          - "app.client.com"
```

**Naming Convention:**
- Use lowercase, hyphens for spaces
- Format: `nginx-gateway-tls-{name}`
- Examples: `nginx-gateway-tls-acme`, `nginx-gateway-tls-globex`

#### Step 4: Commit and Deploy

```bash
git add values/infrastructure/main.yaml
git commit -m "feat: Add certificate for app.client.com"
git push
```

ArgoCD syncs automatically (check ArgoCD UI for status).

#### Step 5: Verify Certificate Provisioned

```bash
# Check certificate status
kubectl get certificate nginx-gateway-tls-client1 -n nginx-gateway-system

# Expected output:
# NAME                        READY   SECRET                      AGE
# nginx-gateway-tls-client1   True    nginx-gateway-tls-client1   2m

# If not Ready, check details:
kubectl describe certificate nginx-gateway-tls-client1 -n nginx-gateway-system
```

**Common statuses during provisioning:**
- `Issuing`: cert-manager creating ACME order
- `Ready=False, Reason=Pending`: Waiting for challenge validation
- `Ready=True`: Certificate successfully issued

#### Step 6: Verify Gateway References Certificate

```bash
kubectl get gateway nginx-shared-gateway -n nginx-gateway-system -o yaml | grep -A 5 certificateRefs

# Should show:
# certificateRefs:
#   - name: nginx-gateway-tls-prod  # Platform certificate
#   - name: nginx-gateway-tls-client1  # ← New certificate
```

#### Step 7: Test TLS Handshake

```bash
# Test TLS connection
openssl s_client -connect app.client.com:443 -servername app.client.com

# Verify:
# - Certificate CN/SAN matches domain
# - Certificate issuer is Let's Encrypt
# - No certificate errors
```

#### Step 8: Test HTTP Routing

Once deployment is configured with HTTPRoute:

```bash
curl -v https://app.client.com

# Should return:
# - 200 OK (or appropriate application response)
# - TLS handshake successful
# - Certificate valid
```

---

### Monitoring Certificates

#### Check All Certificates

```bash
kubectl get certificate -n nginx-gateway-system

# Example output:
# NAME                        READY   SECRET                      AGE
# nginx-gateway-tls-prod      True    nginx-gateway-tls-prod      30d
# nginx-gateway-tls-client1   True    nginx-gateway-tls-client1   5d
# nginx-gateway-tls-client2   True    nginx-gateway-tls-client2   2d
```

#### Check Certificate Expiry

```bash
# Get expiry dates for all TLS secrets
kubectl get secret -n nginx-gateway-system -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls") | 
    .metadata.name + ": " + 
    (.data["tls.crt"] | @base64d | 
    capture("Not After : (?<date>[^\n]+)") | .date)'

# Example output:
# nginx-gateway-tls-prod: Jan 15 12:00:00 2025 GMT
# nginx-gateway-tls-client1: Feb 20 15:30:00 2025 GMT
```

#### Monitor cert-manager Logs

```bash
# Watch cert-manager logs for errors
kubectl logs -n cert-manager -l app=cert-manager --tail=50 -f

# Look for:
# - Certificate issuance events
# - Challenge failures
# - Rate limit errors
```

#### Prometheus Metrics

cert-manager exposes metrics for monitoring:

```promql
# Certificate expiry (days remaining)
certmanager_certificate_expiration_timestamp_seconds{namespace="nginx-gateway-system"}

# Certificate renewal status
certmanager_certificate_renewal_total{namespace="nginx-gateway-system"}

# Challenge failures
certmanager_acme_orders_total{namespace="nginx-gateway-system", status="invalid"}
```

**Recommended Alerts:**
- Certificate expires in < 14 days
- Certificate Ready=False for > 10 minutes
- ACME challenge failures

---

### Certificate Renewal

#### Automatic Renewal (HTTP-01)

cert-manager automatically renews certificates:

- **When:** 30 days before expiry
- **Process:** 
  1. cert-manager creates new Certificate order
  2. ACME challenge completed
  3. New certificate issued
  4. Secret updated with new certificate
  5. Gateway picks up new certificate (zero downtime)
- **No action needed:** Fully automatic

#### Manual Renewal (Force)

If needed, force renewal before automatic window:

```bash
# Trigger renewal by deleting Secret
kubectl delete secret nginx-gateway-tls-client1 -n nginx-gateway-system

# cert-manager recreates immediately
kubectl get certificate nginx-gateway-tls-client1 -n nginx-gateway-system -w
```

**When to force renewal:**
- Certificate compromised
- Testing renewal process
- Troubleshooting renewal issues

#### Client-Provided Certificate Renewal

Client must manually update certificate in GCP Secret Manager:

```bash
# Client uploads new certificate
gcloud secrets versions add client2-domain-cert \
  --data-file=new-certificate.pem

gcloud secrets versions add client2-domain-key \
  --data-file=new-private-key.pem
```

External Secrets Operator syncs automatically (default: 1 hour refresh interval).

**Force immediate sync:**
```bash
# Delete Secret to trigger ESO re-sync
kubectl delete secret nginx-gateway-tls-client2 -n nginx-gateway-system

# ESO recreates within seconds
```

---

### Removing a Client Domain

#### Step 1: Remove Certificate Declaration

Edit `values/infrastructure/main.yaml` and remove the certificate entry from `nginxGatewayResources.tls.certificates`:

```yaml
nginxGatewayResources:
  tls:
    certificates:
      # Remove this:
      # - secretName: nginx-gateway-tls-client1
      #   clusterIssuer: letsencrypt-nginx-http01
      #   dnsNames:
      #     - "app.client.com"
```

#### Step 2: Commit and Deploy

```bash
git add values/infrastructure/main.yaml
git commit -m "chore: Remove client1 certificate"
git push
```

#### Step 3: Verify Cleanup

```bash
# Certificate resource should be deleted
kubectl get certificate nginx-gateway-tls-client1 -n nginx-gateway-system
# Error: NotFound (expected)

# Secret should be deleted
kubectl get secret nginx-gateway-tls-client1 -n nginx-gateway-system
# Error: NotFound (expected)
```

---

## Troubleshooting

### Certificate Not Issuing

**Symptoms:**
```bash
kubectl get certificate nginx-gateway-tls-client1 -n nginx-gateway-system
# STATUS: Ready=False
```

**Debug Steps:**

1. **Check Certificate status:**
   ```bash
   kubectl describe certificate nginx-gateway-tls-client1 -n nginx-gateway-system
   
   # Look for:
   # - Status conditions
   # - Recent events
   # - Error messages
   ```

2. **Check Order status:**
   ```bash
   kubectl get order -n nginx-gateway-system
   kubectl describe order <order-name> -n nginx-gateway-system
   
   # Look for:
   # - Order state (pending, valid, invalid)
   # - Authorization failures
   ```

3. **Check Challenge status:**
   ```bash
   kubectl get challenge -n nginx-gateway-system
   kubectl describe challenge <challenge-name> -n nginx-gateway-system

   # Look for:
   # - Challenge type (http-01)
   # - Challenge state (pending, valid, invalid)
   # - Failure reasons
   ```

4. **Check cert-manager logs:**
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager --tail=100
   
   # Look for:
   # - ACME errors
   # - Challenge failures
   # - Rate limit messages
   ```

**Common Issues:**

| Issue | Cause | Solution |
|-------|-------|----------|
| DNS not resolving | DNS not propagated yet | Wait 5-10 minutes, verify with `dig` |
| HTTP-01 challenge failed | Port 80 not accessible | Check NetworkPolicies, Security Groups |
| Rate limit exceeded | Too many cert requests | Validate DNS/routing before re-requesting; space out additions |
| Invalid domain | Domain doesn't match DNS | Verify domain spelling in config |
| Certificate already exists | Duplicate request | Check existing certificates |

---

### ACME Challenge Failures

**HTTP-01 Challenge Failed:**

```bash
# Check challenge details
kubectl describe challenge <name> -n nginx-gateway-system

# Common errors:
# - "Connection refused" → Port 80 blocked
# - "404 Not Found" → HTTPRoute not created
# - "Timeout" → Firewall blocking traffic
```

**Debug:**
```bash
# Verify HTTPRoute created by cert-manager
kubectl get httproute -n nginx-gateway-system | grep acme

# Test challenge endpoint directly
curl -v http://app.client.com/.well-known/acme-challenge/test

# Should return:
# - 404 (if no active challenge) = OK
# - OR challenge response (if active challenge)
# - NOT redirect to HTTPS
```

---

### Gateway Not Routing to Domain

**Symptoms:**
- TLS handshake succeeds
- But 404/503 errors returned

**Debug:**

1. **Check HTTPRoute exists:**
   ```bash
   kubectl get httproute -n <client-namespace>
   ```

2. **Check HTTPRoute attached to Gateway:**
   ```bash
   kubectl describe httproute <name> -n <client-namespace>
   
   # Look for:
   # - parentRefs pointing to nginx-shared-gateway
   # - hostname matching certificate domain
   # - Status showing attached
   ```

3. **Check Gateway certificate list:**
   ```bash
   kubectl get gateway nginx-shared-gateway -n nginx-gateway-system -o yaml | \
     grep -A 10 certificateRefs
   
   # Verify certificate for domain is listed
   ```

4. **Test TLS SNI:**
   ```bash
   openssl s_client -connect <LoadBalancer-IP>:443 \
     -servername app.client.com
   
   # Verify correct certificate presented
   ```

---

### Certificate Expired or Expiring Soon

**Check expiry:**
```bash
# Check specific certificate
kubectl get secret nginx-gateway-tls-client1 -n nginx-gateway-system -o json | \
  jq -r '.data["tls.crt"] | @base64d' | \
  openssl x509 -noout -dates

# Output:
# notBefore=Jan 1 00:00:00 2025 GMT
# notAfter=Apr 1 00:00:00 2025 GMT
```

**If expired or expiring soon:**

1. **Check cert-manager renewing:**
   ```bash
   kubectl get certificate nginx-gateway-tls-client1 -n nginx-gateway-system -o yaml
   
   # Look for:
   # - renewalTime (should be 30 days before expiry)
   # - Recent events showing renewal attempts
   ```

2. **Force renewal:**
   ```bash
   # Delete certificate secret
   kubectl delete secret nginx-gateway-tls-client1 -n nginx-gateway-system
   
   # cert-manager recreates immediately
   ```

3. **Check for renewal failures:**
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager | grep renewal
   ```

---

### Let's Encrypt Rate Limits

**Rate Limits:**
- 50 certificates per registered domain per week
- 5 duplicate certificates per week
- 300 pending authorizations per account

**Check if hit:**
```bash
# Look for rate limit errors in cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager | grep -i "rate limit"

# Example error:
# "too many certificates already issued for exact set of domains"
```

**Solutions:**

1. **Validate before requesting:**
   - Confirm DNS resolves to the LoadBalancer IP (`dig`) and port 80 is reachable before adding the certificate, so each request succeeds on the first attempt.

2. **Wait for rate limit window:**
   - Limits reset weekly (rolling window)
   - Check Let's Encrypt status page for details

3. **Batch certificate additions:**
   - Plan certificate additions to avoid sudden spikes
   - Space out additions if adding many clients

---

## Best Practices

### 1. Choosing a ClusterIssuer

Match the issuer to the challenge type the domain requires:

```yaml
nginxGatewayResources:
  tls:
    certificates:
      # HTTP-01 (single hostnames routed through the NGINX gateway)
      - secretName: nginx-gateway-tls-client1
        clusterIssuer: letsencrypt-nginx-http01
        dnsNames:
          - "app.client.com"

      # DNS-01 via Cloudflare (wildcards / multi-level subdomains)
      - secretName: nginx-gateway-tls-client1-wild
        clusterIssuer: letsencrypt-mycure-cloudflare-prod
        dnsNames:
          - "*.client.com"
```

**Verify:**
1. Certificate issues successfully
2. TLS handshake works
3. HTTP routing works
4. No errors in logs

### 2. Certificate Naming

**Consistent naming convention:**
- Format: `nginx-gateway-tls-{name}`
- Examples:
  - `nginx-gateway-tls-acme`
  - `nginx-gateway-tls-globex`
  - `nginx-gateway-tls-initech`
  - `nginx-gateway-tls-prod`

**Benefits:**
- Easy to identify certificate purpose
- Consistent sorting in listings
- Clear ownership

### 3. Documentation

**For each client certificate:**
- Add comment in `values/infrastructure/main.yaml`
- Document client contact information
- Note special requirements (renewal process, etc.)

**Example:**
```yaml
nginxGatewayResources:
  tls:
    certificates:
      # ACME Corp - Main Application
      # Contact: john@acme.com
      # Renewal: Auto (HTTP-01)
      - secretName: nginx-gateway-tls-acme
        clusterIssuer: letsencrypt-nginx-http01
        dnsNames:
          - "app.acme.com"
```

### 4. Monitoring and Alerts

**Set up alerts for:**
- Certificate expiring in < 14 days
- Certificate Ready=False for > 10 minutes
- ACME challenge failures
- cert-manager pod failures

**Example Prometheus alert:**
```yaml
- alert: CertificateExpiringSoon
  expr: |
    certmanager_certificate_expiration_timestamp_seconds{namespace="nginx-gateway-system"} - time() < (14 * 24 * 3600)
  labels:
    severity: warning
  annotations:
    summary: "Certificate {{ $labels.name }} expires in < 14 days"
```

### 5. Security

**Certificate Storage:**
- Enable Kubernetes Secret encryption at rest
- Limit RBAC access to nginx-gateway-system namespace
- Audit certificate access regularly

**Client-Provided Certificates:**
- Validate certificate format before accepting
- Verify certificate matches domain
- Check certificate chain completeness
- Test in staging environment first

---

## References

- [Multi-Domain Gateway Architecture](../architecture/MULTI-DOMAIN-GATEWAY.md)
- [Client Onboarding Guide](../getting-started/CLIENT-ONBOARDING.md)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Check cert-manager logs
3. Review [Multi-Domain Gateway Architecture](../architecture/MULTI-DOMAIN-GATEWAY.md)
4. Contact platform team
