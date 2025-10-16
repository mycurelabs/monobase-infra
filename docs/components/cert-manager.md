# cert-manager (TLS Certificate Management)

Automated TLS certificate provisioning and renewal using Let's Encrypt or other CAs.

## Features

- **Automatic issuance** - Certificates requested and issued automatically
- **Automatic renewal** - Renews certificates before expiry
- **Multiple issuers** - Let's Encrypt, self-signed, CA, Vault
- **Gateway API integration** - Works seamlessly with Gateway annotations
- **Wildcard certificates** - Single cert for *.example.com

## Installation

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

## Files

- `clusterissuer.yaml.template` - Let's Encrypt ClusterIssuer configuration

## ClusterIssuer Types

**1. Let's Encrypt Production (Recommended)**
- Trusted certificates
- Rate limited (50 certs/week per domain)
- Use for production

**2. Let's Encrypt Staging**
- For testing
- Not trusted by browsers
- Higher rate limits

**3. Self-Signed**
- For development
- Not trusted
- No external dependencies

## Usage

```bash
# Apply ClusterIssuer
kubectl apply -f clusterissuer.yaml

# Request certificate via Gateway annotation
# (See infrastructure/envoy-gateway/gateway.yaml.template)

# Or request certificate via Certificate resource
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-example-com
  namespace: gateway-system
spec:
  secretName: wildcard-tls-example-com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: "*.example.com"
  dnsNames:
    - "example.com"
    - "*.example.com"
EOF
```

## Verification

```bash
# Check certificate status
kubectl get certificate -n gateway-system

# Check certificate details
kubectl describe certificate wildcard-example-com -n gateway-system

# View issued certificate
kubectl get secret wildcard-tls-example-com -n gateway-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Phase 4 Status

✅ README complete
🔄 ClusterIssuer template in progress
