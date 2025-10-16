# k3d Module

Creates k3d cluster for local testing and CI/CD.

## Features

- ✅ **Fast** - Cluster ready in <1 minute
- ✅ **CI/CD ready** - Terraform provider for automation
- ✅ **Port mappings** - Access via localhost:80, localhost:443
- ✅ **Gateway API** - Optionally installs CRDs
- ✅ **Multi-node** - 1 server + 2 agents by default

## Usage

```hcl
module "k3d_test" {
  source = "../../modules/local-k3d"
  
  cluster_name        = "monobase-test"
  servers             = 1
  agents              = 2
  disable_traefik     = true  # Use Envoy Gateway
  install_gateway_api = true
}
```

## After Provisioning

### Get kubeconfig

```bash
# Via Terraform output
export KUBECONFIG=$(tofu output -raw kubeconfig_file)

# Or use file path
export KUBECONFIG=$(tofu output -raw kubeconfig_file)

# Verify
kubectl get nodes
```

### Deploy Monobase Application Stack

```bash
# Use existing Monobase workflow
cd ../../..
./scripts/new-client-config.sh client-a client-a.local

# Deploy via Helm
helm install api charts/api -f config/client-a/values-development.yaml
```

## CI/CD Example (GitHub Actions)

```yaml
- name: Create k3d cluster
  run: |
    cd tofu/modules/local-k3d
    tofu init
    tofu apply -auto-approve

- name: Deploy and test
  run: |
    export KUBECONFIG=$(tofu output -raw kubeconfig_file)
    helm install api charts/api -f config/k3d-local/values-development.yaml
    kubectl wait --for=condition=ready pod -l app=api --timeout=300s

- name: Cleanup
  if: always()
  run: |
    cd tofu/modules/local-k3d
    tofu destroy -auto-approve
```

## Outputs

- `cluster_name` - Cluster name
- `kubeconfig_file` - Path to kubeconfig
- `kubeconfig` - Kubeconfig content
- `cluster_endpoint` - API endpoint

## Requirements

- Docker running
- k3d installed (`brew install k3d`)
- OpenTofu >= 1.6

## Cleanup

```bash
tofu destroy
# Or: k3d cluster delete monobase-test
```
