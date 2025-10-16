# Envoy Gateway (Gateway API)

Envoy Gateway provides modern, Kubernetes-native ingress using the Gateway API standard.

## Architecture

**Shared Gateway Strategy:**
- **ONE Gateway** in `gateway-system` namespace (HA with 2 replicas)
- **HTTPRoutes** per client/service in their namespaces
- **Zero-downtime** when adding new clients (HTTPRoutes dynamically added)

## Benefits

✅ Single LoadBalancer IP (cost-effective)
✅ Zero-downtime client onboarding
✅ Clean namespace isolation
✅ Modern Gateway API standard (successor to Ingress)

## Installation

```bash
# Install Envoy Gateway
helm repo add envoy-gateway https://gateway.envoyproxy.io
helm repo update

helm install envoy-gateway envoy-gateway/gateway \\
  --namespace envoy-gateway-system \\
  --create-namespace \\
  --values helm-values.yaml

# Create shared Gateway
kubectl apply -f gateway.yaml
```

## Files

- `helm-values.yaml` - Envoy Gateway operator configuration
- `gateway-class.yaml` - GatewayClass resource
- `gateway.yaml.template` - Shared Gateway with single HTTPS listener
- `certificates.yaml.template` - TLS certificate configuration
- `rate-limit-policy.yaml` - Rate limiting for MinIO/public endpoints

## HTTPRoute Pattern

Each application creates its own HTTPRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api
  namespace: client-prod
spec:
  parentRefs:
    - name: shared-gateway
      namespace: gateway-system
  hostnames:
    - api.client.com
  rules:
    - backendRefs:
      - name: api
        port: 7500
```

## Phase 3 Implementation

Full implementation includes:
- Complete Helm values with HA configuration
- Shared Gateway with TLS
- Rate limiting policies
- Security headers
- DDoS protection
- Integration with cert-manager
