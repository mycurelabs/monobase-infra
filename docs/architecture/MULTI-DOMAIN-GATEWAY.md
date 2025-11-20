# Multi-Domain Gateway Architecture

Comprehensive guide to the centralized certificate management architecture for supporting client-owned domains.

---

## Overview

The mono-infra Gateway supports **two types of domains**:

1. **Platform Subdomains** (`*.example.com`)
   - Covered by wildcard certificate
   - Automatic for all deployments
   
2. **Client Custom Domains** (`app.client.com`)
   - Per-domain certificates
   - Client provides domain, platform manages certificate

**Key Principle:** All certificates stored centrally in `gateway-system` namespace, not distributed per client namespace.

---

## Architecture Diagram

```
┌─────────────┐
│   Client    │
│  DNS Config │  1. Creates A record: app.client.com → LoadBalancer-IP
└──────┬──────┘
       │
       ↓ DNS Query
┌──────────────────────────────────────────────────────────────┐
│                       Internet                                 │
└──────┬───────────────────────────────────────────────────────┘
       │
       ↓ HTTPS Request (SNI: app.client.com)
┌──────────────────────────────────────────────────────────────┐
│  LoadBalancer (203.0.113.42)                                   │
│  - Single IP for all domains                                   │
└──────┬───────────────────────────────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────────────────────────────┐
│  Gateway (gateway-system namespace)                            │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ TLS Termination:                                           ││
│  │ - SNI-based certificate selection                          ││
│  │ - Certificates: wildcard-tls, client1-tls, client2-tls    ││
│  └──────────────────────────────────────────────────────────┘│
│  ┌──────────────────────────────────────────────────────────┐│
│  │ Routing Logic:                                             ││
│  │ - Match Host header against HTTPRoutes                     ││
│  │ - Route to appropriate backend service                     ││
│  └──────────────────────────────────────────────────────────┘│
└──────┬───────────────────────────────────────────────────────┘
       │
       ↓ Routed based on hostname
┌──────────────────────────────────────────────────────────────┐
│  HTTPRoute (client namespace)                                  │
│  - hostname: app.client.com                                    │
│  - backendRef: client-api-service:8080                         │
└──────┬───────────────────────────────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────────────────────────────┐
│  Service → Pod                                                 │
│  Application responds                                          │
└──────────────────────────────────────────────────────────────┘
```

---

## Why Centralized Certificate Management?

### 1. Security Advantages

**Centralized (Recommended):**
- ✅ All certificates in one highly-controlled namespace (`gateway-system`)
- ✅ No cross-namespace secret access needed
- ✅ No ReferenceGrants required (eliminates attack surface)
- ✅ Simpler RBAC = fewer misconfiguration risks
- ✅ If Gateway compromised: Attacker only accesses gateway-system secrets

**Distributed (Not Recommended):**
- ❌ Certificates scattered across N client namespaces
- ❌ Requires ReferenceGrant for each namespace (cross-namespace access)
- ❌ If Gateway compromised: Attacker accesses ALL client namespaces via ReferenceGrants
- ❌ Complex RBAC across multiple namespaces

**Conclusion:** Centralized is more secure.

### 2. Operational Simplicity

**Centralized:**
```
gateway-system/
  ├── wildcard-example-tls (Secret)
  ├── client1-domain-tls (Secret)
  ├── client2-domain-tls (Secret)
  └── client3-domain-tls (Secret)

Operations:
- Add client: Create ONE Certificate in gateway-system
- Debug: Check ONE namespace
- RBAC: ONE namespace needs cert-manager permissions
```

**Distributed:**
```
gateway-system/
  └── wildcard-example-tls

client1/
  ├── client1-domain-tls
  └── client1-referencegrant

client2/
  ├── client2-domain-tls
  └── client2-referencegrant

Operations:
- Add client: Create Certificate + ReferenceGrant in client namespace
- Debug: Search N namespaces
- RBAC: N namespaces need permissions OR cert-manager needs ClusterRole
```

**Conclusion:** Centralized is 10x simpler.

### 3. Industry Best Practices

| System | Certificate Storage | Pattern |
|--------|---------------------|---------|
| **Istio Gateway** | istio-system namespace | Centralized |
| **NGINX Ingress** | ingress-nginx namespace | Centralized |
| **Kong Gateway** | kong namespace | Centralized |
| **Traefik** | traefik namespace | Centralized |
| **AWS ALB** | AWS Certificate Manager | Centralized |
| **GKE Ingress** | Ingress namespace | Centralized |

**cert-manager documentation** explicitly recommends:
> "For multi-tenant scenarios with shared ingress, store certificates in the ingress namespace."

**Conclusion:** Industry standard is centralized.

---

## Certificate Types

### 1. HTTP-01 Auto-Provisioned (Client Domains)

**Purpose:** Auto-provision certificates for client-owned domains

**Example:**
- Domain: `app.client.com`
- Certificate: Single domain (no wildcard support with HTTP-01)
- Type: HTTP-01 challenge (no DNS API access needed)
- Issuer: `letsencrypt-prod` ClusterIssuer

**When to Use:**
- Client owns domain
- Client can create DNS A record
- Client does NOT have DNS provider API access
- Most common scenario

**Requirements:**
1. Client creates DNS: `app.client.com` → A → `<LoadBalancer-IP>`
2. Port 80 accessible for ACME challenge
3. Let's Encrypt can reach domain via HTTP

**Process:**
1. Certificate declared in `infrastructure/certificates.yaml`
2. cert-manager creates temporary HTTPRoute for `/.well-known/acme-challenge/`
3. Let's Encrypt validates via HTTP request
4. Certificate issued (2-5 minutes)
5. Secret stored in `gateway-system` namespace

**Configuration:**
```yaml
# infrastructure/certificates.yaml
certificates:
  - name: client1-domain
    domain: "app.client.com"
    issuer: letsencrypt-prod
    challengeType: http01
```

**Limitations:**
- ❌ No wildcard support (HTTP-01 limitation)
- ❌ Domain must be publicly accessible
- ⚠️ Rate limits: 50 certificates/week per domain

---

### 2. Client-Provided Certificates

**Purpose:** Client provides their own certificate

**Example:**
- Domain: `portal.client.com`
- Certificate: Client uploads to GCP Secret Manager
- Type: External Secrets Operator syncs to Kubernetes
- Renewal: Client manages certificate lifecycle

**When to Use:**
- Client has existing certificate
- Client wants to manage certificate lifecycle
- Client uses internal CA
- Regulatory requirements for specific certificate authority

**Process:**
1. Client uploads cert/key to GCP Secret Manager
2. Configuration added to `infrastructure/certificates.yaml`
3. External Secrets Operator syncs to `gateway-system` namespace
4. Gateway references certificate

**Configuration:**
```yaml
# infrastructure/certificates.yaml
certificates:
  - name: client2-domain
    domain: "portal.client.com"
    certificateSource: provided
    externalSecret:
      gcpSecretName: client2-domain-cert
      gcpSecretKey: client2-domain-key
```

**Certificate Format Requirements:**
- PEM-encoded X.509 certificate
- Include full certificate chain (intermediate CAs)
- PEM-encoded private key (RSA 2048+ or ECDSA P-256+)
- No password-protected keys

---

## Gateway Configuration

### Listener Configuration

**Key Change:** Gateway listener hostname set to `"*"` (accept all domains)

```yaml
# Gateway in gateway-system namespace
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "*"  # ← Accept ALL domains (not just "*.example.com")
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          # Client domain certificates
          - name: client1-domain-tls
            kind: Secret
          - name: client2-domain-tls
            kind: Secret
```

**How it works:**
1. Client connects with SNI: `app.client.com`
2. Gateway matches SNI against available certificates
3. Gateway presents `client1-domain-tls` certificate
4. TLS handshake completes
5. Gateway reads HTTP Host header: `app.client.com`
6. Gateway finds HTTPRoute with matching hostname
7. Gateway routes to backend service

---

### HTTP to HTTPS Redirect

**Challenge:** HTTP-01 ACME challenges need port 80 access, but redirect sends everything to HTTPS

**Solution:** cert-manager's HTTPRoute for challenges is more specific than redirect

```yaml
# Existing redirect HTTPRoute (no changes needed)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-to-https-redirect
  namespace: gateway-system
spec:
  parentRefs:
    - name: shared-gateway
      sectionName: http
  hostnames:
    - "*"
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

**Why it works:**
- cert-manager creates: `path: /.well-known/acme-challenge/TOKEN` (exact path)
- Redirect HTTPRoute: `path: /` (prefix)
- Gateway API routing: More specific path wins
- ACME challenges route to cert-manager, others get redirected

---

## Certificate Lifecycle

### 1. Declaration

Platform team adds to `infrastructure/certificates.yaml`:

```yaml
certificates:
  - name: client1-domain
    domain: "app.client.com"
    issuer: letsencrypt-prod
    challengeType: http01
```

### 2. Provisioning

**For HTTP-01:**
1. ArgoCD syncs, creates Certificate resource in `gateway-system`
2. cert-manager sees new Certificate
3. cert-manager creates Order, Challenge resources
4. cert-manager creates temporary HTTPRoute for ACME challenge
5. Let's Encrypt makes HTTP request: `http://app.client.com/.well-known/acme-challenge/TOKEN`
6. cert-manager solver responds with challenge answer
7. Let's Encrypt validates, issues certificate
8. cert-manager stores certificate in Secret: `client1-domain-tls`
9. cert-manager deletes temporary HTTPRoute
10. Gateway automatically picks up new certificate

**Time:** 2-5 minutes

**For Client-Provided:**
1. ArgoCD syncs, creates ExternalSecret in `gateway-system`
2. External Secrets Operator sees new ExternalSecret
3. ESO fetches certificate from GCP Secret Manager
4. ESO creates Secret: `client2-domain-tls` in `gateway-system`
5. Gateway automatically picks up new certificate

**Time:** 10-30 seconds

### 3. Usage

HTTPRoute in client namespace references domain:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: client1-api
  namespace: client1
spec:
  parentRefs:
    - name: shared-gateway
      namespace: gateway-system
      sectionName: https
  hostnames:
    - app.client.com
  rules:
    - backendRefs:
        - name: api
          port: 8080
```

### 4. Renewal

**For HTTP-01 (Automatic):**
- cert-manager renews automatically 30 days before expiry
- Zero-downtime renewal (new secret created, Gateway picks up seamlessly)
- No manual intervention needed

**For Client-Provided (Manual):**
- Client manages renewal
- Client uploads new certificate to GCP Secret Manager
- ESO syncs automatically (refresh interval: 1 hour default)
- Gateway picks up new certificate seamlessly

### 5. Monitoring

**Certificate Status:**
```bash
# Check all certificates
kubectl get certificate -n gateway-system

# Check specific certificate
kubectl describe certificate client1-domain-tls -n gateway-system

# Check expiry dates
kubectl get secret -n gateway-system -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name + ": " + (.data["tls.crt"] | @base64d | capture("notAfter=(?<date>[^\n]+)") | .date)'
```

**Recommendations:**
- Monitor cert-manager logs for provisioning failures
- Alert on certificates expiring in < 14 days
- Alert on cert-manager Certificate resources with Ready=False

---

## Comparison with Alternatives

### Alternative 1: Per-Namespace Certificates (Not Recommended)

**Architecture:**
```
client1/
  ├── client1-domain-tls (Secret)
  └── client1-referencegrant (ReferenceGrant)

gateway-system/
  └── shared-gateway (references client1/client1-domain-tls)
```

**Pros:**
- Certificates in client namespaces (logical isolation)

**Cons:**
- ❌ Requires ReferenceGrant for each namespace
- ❌ Cross-namespace secret access (security risk)
- ❌ Complex RBAC (N namespaces need permissions)
- ❌ Harder to debug (search across namespaces)
- ❌ Not industry standard

**Verdict:** Less secure, more complex, non-standard. Avoid.

---

### Alternative 2: Dedicated Gateway per Client

**Architecture:**
```
client1/
  ├── client1-gateway (Gateway with own LoadBalancer)
  ├── client1-domain-tls (Secret)
  └── client1-httproute (references local Gateway)
```

**Pros:**
- ✅ Complete isolation per client
- ✅ No shared infrastructure concerns
- ✅ Client-specific Gateway configuration

**Cons:**
- ❌ Expensive: N × LoadBalancer cost ($15-30/month each)
- ❌ N LoadBalancer IPs to manage
- ❌ Client needs to point DNS to their specific IP
- ❌ Wasteful for small clients

**When to Use:**
- Client pays for their own infrastructure
- Strict network isolation required
- >50 client domains (shared Gateway becomes unwieldy)
- Client-specific Gateway features needed

**Verdict:** Use only when budget/requirements justify the cost.

---

### Alternative 3: TLS Passthrough (No Termination at Gateway)

**Architecture:**
```
Gateway (TLS passthrough mode)
  ↓ (encrypted traffic)
Backend Pod (terminates TLS)
```

**Pros:**
- Gateway doesn't handle certificates
- Backend fully controls TLS

**Cons:**
- ❌ No L7 routing (can't route based on HTTP headers/path)
- ❌ Can't do HTTP to HTTPS redirect
- ❌ Can't inspect/modify requests
- ❌ Each backend needs certificate management
- ❌ No centralized certificate handling

**Verdict:** Only for specific use cases (gRPC, raw TCP). Not suitable for HTTP applications.

---

## Security Considerations

### 1. Certificate Private Keys

- Stored in Kubernetes Secrets (encrypted at rest if cluster has encryption enabled)
- Access controlled by RBAC (only gateway-system ServiceAccounts)
- Gateway pods read via mounted secrets (not environment variables)

**Best Practice:** Enable encryption at rest for Secrets
```bash
# For managed Kubernetes (EKS, GKE, AKS): Usually enabled by default
# Verify encryption provider configured
```

### 2. Let's Encrypt Rate Limits

- 50 certificates per registered domain per week
- 5 duplicate certificates per week
- If hit: Wait until rate limit window resets OR use staging for testing

**Mitigation:**
- Use `letsencrypt-staging` ClusterIssuer for testing
- Plan certificate additions (batch if adding many clients)
- Monitor rate limit usage

### 3. ACME Challenge Security

**HTTP-01 Challenges:**
- Temporary HTTPRoute created by cert-manager
- Only routes `/.well-known/acme-challenge/*` to solver
- Deleted immediately after validation
- No security risk (challenge tokens are single-use)

### 4. Client-Provided Certificates

**Validation:**
- Verify certificate matches domain
- Check certificate chain completeness
- Verify not expired
- Test in staging first

**Storage:**
- Store in GCP Secret Manager (encrypted)
- IAM controls access
- ESO syncs to Kubernetes (also encrypted if cluster encryption enabled)

---

## Operational Best Practices

### 1. Certificate Naming Convention

```yaml
certificates:
  - name: wildcard-platform  # Platform wildcard
  - name: client-{client-name}-{purpose}  # Client certificates
    # Examples:
    # - name: client-acme-main
    # - name: client-globex-portal
```

### 2. Certificate Monitoring

**Metrics to Track:**
- Certificate expiry dates (alert < 14 days)
- Certificate provisioning failures
- ACME challenge failures
- Rate limit violations

**Tools:**
- cert-manager Prometheus metrics
- Alertmanager rules for expiry
- cert-manager status dashboard

### 3. Documentation

**For Each Client:**
- Document domain in `infrastructure/certificates.yaml` comments
- Note certificate type (auto-provisioned vs client-provided)
- Record renewal process (if client-managed)

### 4. Testing

**Before Production:**
1. Use `letsencrypt-staging` ClusterIssuer
2. Verify certificate issued successfully
3. Test TLS handshake
4. Verify HTTP routing works
5. Switch to production issuer: `letsencrypt-prod`

---

## Troubleshooting

### Certificate Not Issuing

**Symptoms:**
```bash
kubectl get certificate client1-domain-tls -n gateway-system
# Status: Ready=False
```

**Debug:**
```bash
# Check Certificate status
kubectl describe certificate client1-domain-tls -n gateway-system

# Check Order status
kubectl get order -n gateway-system

# Check Challenge status
kubectl get challenge -n gateway-system

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

**Common Issues:**
- DNS not pointing to LoadBalancer IP → Verify with `dig domain.com`
- Port 80 not accessible → Check NetworkPolicies, Security Groups
- Rate limit hit → Use staging issuer for testing

---

### Gateway Not Routing

**Symptoms:**
- TLS handshake succeeds but 404/503 errors

**Debug:**
```bash
# Check HTTPRoute exists
kubectl get httproute -n client-namespace

# Check HTTPRoute status
kubectl describe httproute client-api -n client-namespace

# Check Gateway attached routes
kubectl get gateway shared-gateway -n gateway-system -o yaml

# Check Envoy config
kubectl exec -n gateway-system deploy/envoy-shared-gateway-xxxxx -- \
  curl -s localhost:19000/config_dump
```

**Common Issues:**
- HTTPRoute hostname doesn't match certificate domain
- HTTPRoute not attached to Gateway (check parentRefs)
- Backend service not reachable

---

## References

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [External Secrets Operator](https://external-secrets.io/)

---

## Next Steps

- See [Certificate Management Operations Guide](../operations/CERTIFICATE-MANAGEMENT.md)
- See [Client Onboarding Guide](../getting-started/CLIENT-ONBOARDING.md)
- See [Gateway API Architecture](GATEWAY-API.md)
