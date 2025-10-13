# GCP GKE Module

Production-ready GKE cluster for multi-tenant LFH Infrastructure.

## Features

- ✅ Multi-tenant ready (3-20 node autoscaling)
- ✅ Workload Identity for External Secrets
- ✅ GCP Persistent Disk CSI
- ✅ VPC-native networking
- ✅ Network policy enabled
- ✅ Auto-scaling and auto-repair
- ✅ Regional HA cluster

## Usage

```hcl
module "gke_cluster" {
  source = "../../modules/gcp-gke"
  
  cluster_name       = "lfh-prod"
  project_id         = "my-project-123456"
  region             = "us-central1"
  kubernetes_version = "1.28"
  
  network_cidr = "10.0.0.0/16"
  
  node_pools = {
    general = {
      machine_type = "n2-standard-8"  # 8 vCPU, 32GB
      node_count   = 5
      min_count    = 3
      max_count    = 20
      disk_size_gb = 100
    }
  }
  
  enable_workload_identity = true
}
```

## Outputs

- `cluster_name`, `cluster_endpoint`
- `external_secrets_sa_email` - For External Secrets
- `velero_sa_email` - For Velero
- `cert_manager_sa_email` - For cert-manager

## Get Kubeconfig

```bash
gcloud container clusters get-credentials lfh-prod --region us-central1 --project my-project
kubectl get nodes
```

Complete multi-tenant GKE cluster ready for LFH deployments.
