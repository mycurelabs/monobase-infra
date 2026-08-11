# DigitalOcean (DOKS) Static IP Configuration

## Overview

DigitalOcean Kubernetes (DOKS) has limited native support for static IPs. This guide covers two approaches:

- **Option 1**: LoadBalancer name annotation (simple, IP can still change)
- **Option 2**: FLIPOP Operator (true reserved IP support)

## Current Live Setup

The live cluster's public gateway (`nginx-shared-gateway`) uses **Option 1**: NGINX Gateway Fabric provisions the LoadBalancer Service in `nginx-gateway-system`, and the DO LB is type `REGIONAL_NETWORK` — listener/port changes update the existing LB in place, so the IP stays stable in practice. The internal gateway (`nginx-internal-gateway`) is ClusterIP-only and never provisions a DO LB.

**Gotcha**: if a Service round-trips ClusterIP → LoadBalancer, the DO cloud controller may leave a stale `kubernetes.digitalocean.com/load-balancer-id` annotation pointing at a deleted LB. Clear the annotation so a fresh LB gets provisioned.

## Important Note

Unlike other cloud providers, DOKS LoadBalancers don't have native static IP support via annotations alone. The IP can change if the LB is deleted and recreated.

## Option 1: LoadBalancer Name (Simple)

This provides consistency but doesn't guarantee the IP won't change.

### Step 1: Choose LoadBalancer Name

```bash
# Choose a unique, descriptive name
LB_NAME="production-gateway-lb"
```

### Step 2: Configuration

Set the annotation on the Gateway's provisioned Service via `infrastructure.annotations` in `values/infrastructure/main.yaml` (see [static-ip-prerequisites.md](./static-ip-prerequisites.md)):

```yaml
nginxGatewayResources:
  gateway:
    infrastructure:
      annotations:
        service.beta.kubernetes.io/do-loadbalancer-name: "production-gateway-lb"
```

### Step 3: Get LoadBalancer ID (After Deployment)

After the infrastructure is deployed:

```bash
# Get LoadBalancer ID from DigitalOcean
doctl compute load-balancer list --format ID,Name,IP,Status

# Or from Kubernetes
kubectl get svc -n nginx-gateway-system -o yaml | \
  grep "kubernetes.digitalocean.com/load-balancer-id"
```

## Option 2: FLIPOP Operator (Recommended for a true static IP)

FLIPOP (Floating IP Operator) provides true reserved IP support for DOKS.

### Prerequisites

- DOKS cluster deployed
- `doctl` CLI installed
- `kubectl` access to cluster

### Step 1: Reserve Floating IP

```bash
# Reserve a floating IP in your cluster's region
REGION="nyc3"  # Must match your DOKS cluster region

doctl compute floating-ip create \
  --region $REGION \
  --tag production-gateway

# Note the IP address from output
```

### Step 2: Install FLIPOP Operator

```bash
# Install FLIPOP operator
kubectl apply -f https://raw.githubusercontent.com/digitalocean/flipop/main/deploy/flipop.yaml

# Verify installation
kubectl get pods -n kube-system -l app=flipop
```

### Step 3: Create FloatingIPMapping

After infrastructure deployment, create the mapping:

```bash
# Get the LoadBalancer service name
LB_SERVICE=$(kubectl get svc -n nginx-gateway-system -o name | head -1)

# Get your floating IP
FLOATING_IP="142.93.xxx.xxx"  # From Step 1

# Create FloatingIPMapping
cat <<EOF | kubectl apply -f -
apiVersion: flipop.digitalocean.com/v1alpha1
kind: FloatingIPMapping
metadata:
  name: gateway-floating-ip
  namespace: nginx-gateway-system
spec:
  floatingIP: $FLOATING_IP
  service:
    name: ${LB_SERVICE#service/}
    namespace: nginx-gateway-system
EOF
```

### Step 4: Verify

```bash
# Check FloatingIPMapping status
kubectl get floatingipmapping gateway-floating-ip -n nginx-gateway-system

# Verify LoadBalancer IP
kubectl get svc -n nginx-gateway-system -o wide
```

## Comparison of Options

| Feature | Option 1 (Name Only) | Option 2 (FLIPOP) |
|---------|---------------------|-------------------|
| Setup Complexity | Simple | Moderate |
| True Static IP | No | Yes |
| IP Persistence | Stable while LB exists | Guaranteed |
| Additional Components | None | FLIPOP operator |
| Cost | LB only (~$12/month) | LB + Floating IP (~$16/month) |
| Recommended For | Most cases (current live setup) | Hard static-IP requirements |

## Important Notes

### Floating IP Costs

- **$6/month** per floating IP (includes 1TB transfer)
- **$12/month** for LoadBalancer
- Total: **~$18/month** per environment

### Regional Requirements

- Floating IP must be in same region as cluster
- Cannot move floating IPs between regions

### Permissions Required (doctl)

- `floating_ip:create`
- `floating_ip:read`
- `load_balancer:read`

### FLIPOP Limitations

- Requires operator running in cluster
- Adds dependency on third-party component
- DigitalOcean maintains but not officially supported

## Verification

### For Option 1

```bash
# Check LoadBalancer
doctl compute load-balancer list --format ID,Name,IP

# Check from Kubernetes
kubectl get svc -n nginx-gateway-system
```

### For Option 2

```bash
# Check floating IP assignment
doctl compute floating-ip list

# Check FLIPOP mapping
kubectl get floatingipmapping -n nginx-gateway-system

# Verify IP on service
kubectl get svc -n nginx-gateway-system -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

## Troubleshooting

### LoadBalancer not created

- Check DOKS cluster has available capacity
- Verify service type is LoadBalancer
- Check DigitalOcean quotas
- Clear a stale `kubernetes.digitalocean.com/load-balancer-id` annotation left from a previous LB (see Current Live Setup above)

### FLIPOP not assigning floating IP

- Verify FLIPOP operator is running: `kubectl get pods -n kube-system -l app=flipop`
- Check FloatingIPMapping resource: `kubectl describe floatingipmapping -n nginx-gateway-system`
- Ensure floating IP is in same region as cluster

### Floating IP shows as "unassigned"

- Check LoadBalancer is fully provisioned first
- Verify FloatingIPMapping references correct service
- Check FLIPOP operator logs: `kubectl logs -n kube-system -l app=flipop`

### IP changed after LB recreation

- This is expected with Option 1 (name only)
- Use Option 2 (FLIPOP) for guaranteed static IP
- Update DNS if IP changes

## Cleanup

### Option 1

```bash
# LoadBalancer will be deleted with service
# No additional cleanup needed
```

### Option 2

```bash
# Delete FloatingIPMapping
kubectl delete floatingipmapping gateway-floating-ip -n nginx-gateway-system

# Release floating IP (optional, stops charges)
doctl compute floating-ip delete $FLOATING_IP

# Uninstall FLIPOP (optional)
kubectl delete -f https://raw.githubusercontent.com/digitalocean/flipop/main/deploy/flipop.yaml
```

## Additional Resources

- [DOKS Load Balancers](https://docs.digitalocean.com/products/kubernetes/how-to/add-load-balancers/)
- [DigitalOcean Floating IPs](https://docs.digitalocean.com/products/networking/floating-ips/)
- [FLIPOP GitHub](https://github.com/digitalocean/flipop)
- [DOKS Networking](https://docs.digitalocean.com/products/kubernetes/details/networking/)
