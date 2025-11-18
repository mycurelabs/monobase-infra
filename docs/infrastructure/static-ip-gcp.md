# Google Cloud (GKE) Static IP Configuration

## Overview

Google Kubernetes Engine (GKE) uses regional static IP addresses for LoadBalancer services.

## Prerequisites

- `gcloud` CLI installed and configured
- GKE cluster deployed
- IAM permissions to reserve IP addresses
- Know your cluster's region

## Step-by-Step Instructions

### Step 1: Reserve Regional Static IP

```bash
# Set variables
PROJECT_ID="your-gcp-project-id"
REGION="us-central1"  # Must match your GKE cluster region
IP_NAME="production-gateway-ip"

# Set project
gcloud config set project $PROJECT_ID

# Reserve static IP
gcloud compute addresses create $IP_NAME \
  --region=$REGION \
  --network-tier=PREMIUM

echo "Static IP reserved successfully!"
```

### Step 2: Get IP Address

```bash
# Get the reserved IP address
IP_ADDRESS=$(gcloud compute addresses describe $IP_NAME \
  --region=$REGION \
  --format="get(address)")

echo "Reserved IP Address: $IP_ADDRESS"
```

### Step 3: Verify Reservation

```bash
# List and verify
gcloud compute addresses list \
  --filter="name=$IP_NAME" \
  --format="table(name,address,region,status,networkTier)"
```

**Example output:**
```
NAME                     ADDRESS         REGION       STATUS      NETWORK_TIER
production-gateway-ip    35.123.45.67   us-central1   RESERVED    PREMIUM
```

## Configuration

Provide these values to your DevOps team:

**Option 1 - Using IP Address (Recommended):**
```yaml
cloudProvider: gcp
gcp:
  staticIpAddress: "35.123.45.67"
```

**Option 2 - Using IP Name:**
```yaml
cloudProvider: gcp
gcp:
  staticIpAddress: "production-gateway-ip"
```

## Important Notes

### Regional vs Global
- Use **regional** addresses for GKE LoadBalancers
- Global addresses are for global load balancers only
- Region must match your GKE cluster's region

### Network Tier
- `PREMIUM` tier recommended for best performance
- `STANDARD` tier available for cost savings
- Cannot change tier after creation

### Cost
- **~$0.010/hour (~$7/month)** for reserved but unused IP
- **Free when in use** (attached to LoadBalancer)
- See [GCP Pricing](https://cloud.google.com/vpc/network-pricing#ipaddress) for current rates

### Permissions Required
```yaml
roles/compute.networkAdmin
# OR specific permissions:
compute.addresses.create
compute.addresses.get
compute.addresses.list
compute.addresses.use
```

## Verification

After reservation:

```bash
# Check IP details
gcloud compute addresses describe $IP_NAME \
  --region=$REGION \
  --format="yaml"
```

## Multiple Environments

For multiple environments:

```bash
# Production
gcloud compute addresses create production-gateway-ip \
  --region=$REGION \
  --network-tier=PREMIUM

# Staging
gcloud compute addresses create staging-gateway-ip \
  --region=$REGION \
  --network-tier=PREMIUM
```

## Troubleshooting

### Error: Quota exceeded
- Check quota: `gcloud compute project-info describe --project=$PROJECT_ID`
- Request increase via GCP Console

### IP not assigning to LoadBalancer
- Verify IP is in same region as cluster
- Check IP is regional (not global)
- Ensure correct staticIpAddress in configuration

### IP shows as "IN_USE" but not on LoadBalancer
- Check if IP is attached to different resource
- May need to release from old resource first

## Cleanup

To release IP (stops charges):

```bash
# Delete reserved IP (only if not in use!)
gcloud compute addresses delete $IP_NAME \
  --region=$REGION
```

**Warning:** Only delete if IP is not in use.

## Additional Resources

- [GCP Static IP Documentation](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address)
- [GKE Load Balancing](https://cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer)
- [GCP Network Tiers](https://cloud.google.com/network-tiers)
