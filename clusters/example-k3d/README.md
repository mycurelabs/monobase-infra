# Example k3d Local Development Cluster

Quick local Kubernetes cluster for development and testing.

## Prerequisites

- Docker Desktop or Docker Engine running
- k3d installed (`brew install k3d` or `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`)

## Quick Start

```bash
# Provision (recommended)
./scripts/provision.sh --cluster k3d-local

# OR manually:
cd clusters/example-k3d
terraform init && terraform apply
```

## Features

- ✅ 1 control plane + 3 workers (lightweight)
- ✅ Ports 80/443 exposed for LoadBalancer services
- ✅ Gateway API CRDs pre-installed
- ✅ Traefik disabled (uses Envoy Gateway)

## Cleanup

```bash
terraform destroy
# OR
k3d cluster delete k3d-local
```
