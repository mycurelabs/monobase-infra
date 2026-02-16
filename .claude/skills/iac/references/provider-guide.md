# Provider-Specific Guide

## Authentication Requirements

| Provider | Auth Method | CLI Tool | Setup Command |
|----------|------------|----------|---------------|
| AWS EKS | IAM credentials / SSO | `aws` | `aws configure` or `aws sso login` |
| Azure AKS | Service principal / CLI login | `az` | `az login` |
| GCP GKE | Service account / gcloud auth | `gcloud` | `gcloud auth login` |
| DO DOKS | API token | `doctl` | `doctl auth init` |
| On-prem K3s | SSH keys | SSH client | N/A |
| Local k3d | Local Docker | `docker`, `k3d` | N/A |

## CLI Prerequisites

```bash
# All tools managed via mise
mise install

# Verify tools
kubectl version --client
helm version
terraform version
```

### Per-Provider CLI
```bash
# AWS
aws --version
aws sts get-caller-identity

# Azure
az version
az account show

# GCP
gcloud version
gcloud config get-value project

# DigitalOcean
doctl version
doctl account get
```

## Static IP Setup

Each cloud provider requires static IPs for the Envoy Gateway LoadBalancer.

### AWS EKS
- **Method**: Elastic IPs (one per subnet/AZ, typically 3)
- **Config**: `envoyProxyConfig.aws.eipAllocations: "eipalloc-xxx,eipalloc-yyy,eipalloc-zzz"`
- **Guide**: `docs/infrastructure/static-ip-aws.md`
- **Commands**:
  ```bash
  aws ec2 allocate-address --domain vpc --region us-east-1
  aws ec2 describe-addresses --allocation-ids eipalloc-xxx
  ```

### Azure AKS
- **Method**: Static Public IP in node resource group (MC_*)
- **Config**: `envoyProxyConfig.azure.publicIpName`, `envoyProxyConfig.azure.resourceGroup`, `envoyProxyConfig.azure.ipv4Address`
- **Guide**: `docs/infrastructure/static-ip-azure.md`
- **Commands**:
  ```bash
  NODE_RG=$(az aks show --resource-group $RG --name $CLUSTER --query nodeResourceGroup -o tsv)
  az network public-ip create --resource-group $NODE_RG --name production-gateway-ip --sku Standard --allocation-method Static
  ```

### GCP GKE
- **Method**: Regional static IP
- **Config**: `envoyProxyConfig.gcp.staticIpAddress: "35.x.x.x"`
- **Guide**: `docs/infrastructure/static-ip-gcp.md`
- **Commands**:
  ```bash
  gcloud compute addresses create production-gateway-ip --region=us-central1 --network-tier=PREMIUM
  gcloud compute addresses describe production-gateway-ip --region=us-central1 --format="get(address)"
  ```

### DigitalOcean DOKS
- **Method**: LoadBalancer name (or FLIPOP operator for true static IP)
- **Config**: `envoyProxyConfig.digitalocean.loadBalancerName`, optionally `loadBalancerId`
- **Guide**: `docs/infrastructure/static-ip-digitalocean.md`
- **Commands**:
  ```bash
  doctl compute load-balancer list --format ID,Name,IP,Status
  ```

## Storage Provider Mapping

| Provider | Default StorageClass | Block Storage | Object Storage |
|----------|---------------------|---------------|----------------|
| AWS EKS | `gp3` (EBS CSI) | EBS volumes | S3 |
| Azure AKS | `managed-premium` | Azure Disks | Azure Blob |
| GCP GKE | `pd-ssd` | Persistent Disks | Cloud Storage |
| DO DOKS | `do-block-storage` | DO Volumes | Spaces (S3-compat) |
| On-prem K3s | `longhorn` | Longhorn | MinIO |
| Local k3d | `local-path` | Local volumes | MinIO |

## Backup Provider Mapping (Velero)

| Provider | Backup Storage | Snapshot Provider | Auth |
|----------|---------------|-------------------|------|
| AWS | S3 bucket | EBS snapshots | IRSA |
| Azure | Blob container | Managed Disk snapshots | Workload Identity |
| GCP | GCS bucket | PD snapshots | Workload Identity |
| DigitalOcean | Spaces bucket | DO volume snapshots | API credentials |
| On-prem | MinIO bucket | Longhorn snapshots | Static credentials |
| Local | MinIO bucket | N/A | Static credentials |

## Secrets Provider Mapping (External Secrets)

| Provider | Secret Store | Auth | Config Key |
|----------|-------------|------|------------|
| AWS | AWS Secrets Manager | IRSA | `externalSecrets.aws.*` |
| Azure | Azure Key Vault | Workload Identity | `externalSecrets.azure.*` |
| GCP | GCP Secret Manager | Service Account Key | `externalSecrets.gcp.*` |
| DigitalOcean | GCP Secret Manager* | Service Account Key | `externalSecrets.gcp.*` |
| On-prem | GCP Secret Manager* | Service Account Key | `externalSecrets.gcp.*` |
| Local | GCP Secret Manager* | Service Account Key | `externalSecrets.gcp.*` |

*Currently all environments use GCP Secret Manager (project: mc-v4-prod) via ClusterSecretStore `gcp-secretstore`.

## DNS Provider

All environments use **Cloudflare** for DNS management:
- External DNS automatically creates/updates DNS records from HTTPRoutes
- cert-manager uses Cloudflare DNS-01 challenge for wildcard certificates
- Cloudflare API token stored via External Secrets
