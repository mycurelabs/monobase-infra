# k3d Local Testing Guide

Test Monobase Infrastructure locally using k3d (K3s in Docker).

## Prerequisites

```bash
# Install k3d
brew install k3d  # macOS
# Or: https://k3d.io

# Install kubectl and helm
brew install kubectl helm
```

## Quick Start

### 1. Create k3d Cluster

```bash
# Create 3-node cluster with port mappings
k3d cluster create monobase-test \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --volume /tmp/k3d-storage:/var/lib/rancher/k3s/storage@all

# Verify
kubectl cluster-info
kubectl get nodes
```

### 2. Deploy Monobase Template

```bash
# Use k3d configuration
helm install hapihub charts/hapihub \
  -f config/k3d-local/values-development.yaml \
  -n monobase-dev \
  --create-namespace

# Watch deployment
kubectl get pods -n monobase-dev --watch
```

### 3. Access Services

```bash
# Add to /etc/hosts
echo "127.0.0.1 api.local.test app.local.test" | sudo tee -a /etc/hosts

# Test HapiHub
curl http://api.local.test/health

# Test MyCureApp
open http://app.local.test
```

## What to Test Locally

✅ **Good for local testing:**
- Helm chart rendering
- Template validation
- Gateway routing (HTTPRoutes)
- NetworkPolicies
- Pod Security Standards
- Application functionality
- Configuration changes

❌ **Not realistic for local:**
- High availability (single node limits)
- Real load testing (resource constrained)
- Distributed storage (Longhorn)
- Full monitoring stack (too heavy)

## Resource Requirements

**Minimum:**
- 4 CPU cores
- 8GB RAM
- 20GB disk space

**Recommended:**
- 8 CPU cores
- 16GB RAM
- 50GB disk space

## Cleanup

```bash
# Delete cluster
k3d cluster delete monobase-test

# Remove hosts entries
sudo sed -i.bak '/local.test/d' /etc/hosts
```

## Tips

1. **Use local-path storage** - It's fast and simple
2. **Disable monitoring** - Saves RAM
3. **Use standalone MongoDB** - Not replicaset
4. **Skip MinIO** - Too resource intensive
5. **Test one client at a time** - Multiple namespaces drain resources

Perfect for validating template changes before cloud deployment!
