# Terraform Module Inventory

## aws-eks

**Provider**: `hashicorp/aws ~> 5.0`, `hashicorp/tls ~> 4.0`
**Terraform**: >= 1.6

### Key Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | (required) | EKS cluster name |
| `region` | string | (required) | AWS region |
| `kubernetes_version` | string | `"1.28"` | K8s version |
| `vpc_cidr` | string | `"10.0.0.0/16"` | VPC CIDR block |
| `availability_zones` | list(string) | `[]` (auto) | AZs |
| `enable_public_endpoint` | bool | `true` | Public API endpoint |
| `api_access_cidrs` | list(string) | `["0.0.0.0/0"]` | API access restriction |
| `deployment_profile` | string | `"small"` | Size preset (small/medium/large) |

### Deployment Profiles
- **small**: m6i.xlarge (4 vCPU, 16GB), 3-10 nodes
- **medium**: m6i.xlarge (4 vCPU, 16GB), 5-15 nodes
- **large**: m6i.2xlarge (8 vCPU, 32GB), 5-20 nodes

### Key Outputs
- `cluster_id`, `cluster_name`, `cluster_endpoint`, `cluster_version`
- `cluster_arn`, `cluster_certificate_authority_data`
- `cluster_security_group_id`, `oidc_provider_arn`
- `configure_kubectl` command

---

## azure-aks

**Provider**: `hashicorp/azurerm ~> 3.0`, `hashicorp/azuread ~> 2.0`
**Terraform**: >= 1.6

### Key Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | (required) | AKS cluster name |
| `resource_group_name` | string | (required) | Azure resource group |
| `location` | string | `"eastus"` | Azure region |
| `kubernetes_version` | string | `"1.28"` | K8s version |
| `vnet_cidr` | string | `"10.0.0.0/16"` | VNet CIDR |
| `node_pools` | map(object) | Standard_D8s_v3 x5 | Node pool configs |
| `enable_workload_identity` | bool | `true` | Workload Identity for ESO |
| `tags` | map(string) | `{}` | Resource tags |

### Key Outputs
- `cluster_name`, `cluster_id`, `cluster_endpoint`
- `kubeconfig` (sensitive), `configure_kubectl` command
- `oidc_issuer_url`, `external_secrets_identity_client_id`
- `velero_identity_client_id`

---

## gcp-gke

**Provider**: `hashicorp/google ~> 5.0`
**Terraform**: >= 1.6

### Key Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | (required) | GKE cluster name |
| `project_id` | string | (required) | GCP project ID |
| `region` | string | `"us-central1"` | GCP region |
| `kubernetes_version` | string | `"1.28"` | K8s version |
| `network_cidr` | string | `"10.0.0.0/16"` | VPC CIDR |
| `node_pools` | map(object) | n2-standard-8 x5 | Node pool configs |
| `enable_workload_identity` | bool | `true` | Workload Identity |
| `tags` | map(string) | `{}` | Resource labels |

### Key Outputs
- `cluster_name`, `cluster_id`, `cluster_endpoint`
- `cluster_ca_certificate` (sensitive), `configure_kubectl` command
- `external_secrets_sa_email`, `velero_sa_email`, `cert_manager_sa_email`

---

## do-doks

**Provider**: `digitalocean/digitalocean ~> 2.0`
**Terraform**: >= 1.6

### Key Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | (required) | DOKS cluster name |
| `region` | string | `"nyc3"` | DO region |
| `kubernetes_version` | string | `"1.28.2-do.0"` | K8s version |
| `deployment_profile` | string | `"small"` | Size preset |
| `node_size` | string | `""` | Custom droplet size (overrides profile) |
| `node_count` | number | `0` | Custom count (overrides profile) |
| `min_nodes` | number | `0` | Min autoscale (overrides profile) |

### Deployment Profiles
- **small**: s-2vcpu-4gb (2 vCPU, 4GB), 3-10 nodes
- **medium**: s-4vcpu-8gb (4 vCPU, 8GB), 5-15 nodes
- **large**: s-8vcpu-16gb (8 vCPU, 16GB), 5-20 nodes

### Key Outputs
- `cluster_id`, `cluster_name`, `cluster_endpoint`, `cluster_version`
- `cluster_urn`, `cluster_ipv4_address`, `cluster_status`
- `vpc_id`, `configure_kubectl` command

---

## on-prem-k3s

**Provider**: `hashicorp/null ~> 3.0`
**Terraform**: >= 1.6

### Key Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | (required) | Cluster name |
| `server_ips` | list(string) | (required) | Control plane IPs |
| `agent_ips` | list(string) | `[]` | Worker node IPs |
| `k3s_version` | string | `"v1.28.3+k3s1"` | K3s version |
| `k3s_token` | string | (required, sensitive) | Cluster join token |
| `ssh_user` | string | `"ubuntu"` | SSH user |
| `ssh_private_key_path` | string | (required) | SSH key path |
| `enable_ha` | bool | `true` | HA mode (3+ servers) |
| `install_longhorn` | bool | `true` | Install Longhorn storage |
| `install_metallb` | bool | `true` | Install MetalLB LB |
| `metallb_ip_range` | string | `""` | MetalLB IP range |

### Key Outputs
- `cluster_name`, `server_ips`, `agent_ips`
- `api_endpoint`, `kubeconfig_path`, `configure_kubectl`
- `metallb_ip_range`

---

## local-k3d

**Provider**: `pvotal-tech/k3d ~> 0.0.7`, `hashicorp/null ~> 3.0`
**Terraform**: >= 1.6

### Key Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | string | `"monobase-test"` | k3d cluster name |
| `k3s_version` | string | `"v1.28.3-k3s1"` | K3s version |
| `servers` | number | `1` | Server nodes |
| `agents` | number | `2` | Agent nodes |
| `http_port` | number | `8080` | Host HTTP port |
| `https_port` | number | `8443` | Host HTTPS port |
| `disable_traefik` | bool | `true` | Disable Traefik |
| `install_gateway_api` | bool | `true` | Install Gateway API CRDs |

### Key Outputs
- `cluster_name`, `kubeconfig_file`, `kubeconfig` (sensitive)
- `cluster_endpoint`, `configure_kubectl`
