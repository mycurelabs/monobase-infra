# Azure AKS Static IP Configuration

## Overview

This guide provides step-by-step instructions for creating and configuring static public IP addresses for Azure Kubernetes Service (AKS) clusters.

## Prerequisites

- Azure CLI installed and configured
- Access to Azure subscription with appropriate permissions
- AKS cluster already deployed
- Permissions to create resources in the node resource group

## Important Concepts

### Node Resource Group

When you create an AKS cluster, Azure automatically creates a second resource group called the "node resource group" (starts with `MC_`). This resource group contains all the infrastructure resources for your cluster, including:
- Virtual machines (nodes)
- Virtual network
- Load balancers
- **Public IP addresses**

**Critical**: Static IPs for AKS LoadBalancer services **must** be created in the node resource group, not your main resource group.

## Method 1: Create New Static IP (Recommended)

### Step 1: Get Node Resource Group Name

```bash
# Replace with your actual resource group and cluster name
RESOURCE_GROUP="your-aks-resource-group"
CLUSTER_NAME="your-aks-cluster-name"

# Get the node resource group
NODE_RG=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query nodeResourceGroup \
  --output tsv)

echo "Node Resource Group: $NODE_RG"
```

**Example output:** `MC_example-rg_example-aks_eastus`

### Step 2: Create Static Public IP

```bash
# Choose a descriptive name for your IP
IP_NAME="production-gateway-ip"  # Or "staging-gateway-ip"

# Get the region from your cluster
REGION=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query location \
  --output tsv)

# Create the static public IP
az network public-ip create \
  --resource-group $NODE_RG \
  --name $IP_NAME \
  --sku Standard \
  --allocation-method Static \
  --location $REGION \
  --tags "Environment=Production" "Service=Gateway"

echo "Static IP created successfully!"
```

### Step 3: Get the IP Address

```bash
# Retrieve the assigned IP address
IP_ADDRESS=$(az network public-ip show \
  --resource-group $NODE_RG \
  --name $IP_NAME \
  --query ipAddress \
  --output tsv)

echo "Static IP Address: $IP_ADDRESS"
```

### Step 4: Save Configuration Values

Save these values for your infrastructure configuration:

```yaml
# Configuration values to provide to DevOps team:
cloudProvider: azure
azure:
  publicIpName: "production-gateway-ip"  # From Step 2
  resourceGroup: "MC_example-rg_example-aks_eastus"  # From Step 1
  # Note: The IP address ($IP_ADDRESS) will be automatically assigned
```

## Method 2: Preserve Existing IP

If you want to keep your current IP address instead of creating a new one:

### Step 1: Find Existing IP

```bash
# Get node resource group (same as Method 1, Step 1)
NODE_RG=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME \
  --query nodeResourceGroup \
  --output tsv)

# Find the public IP with your current address
CURRENT_IP="135.171.153.160"  # Replace with your actual current IP

az network public-ip list \
  --resource-group $NODE_RG \
  --query "[?ipAddress=='$CURRENT_IP'].{Name:name, IP:ipAddress, Allocation:publicIPAllocationMethod, SKU:sku.name}" \
  --output table
```

### Step 2: Check Current Allocation Method

```bash
# Get the IP name from Step 1 output
IP_NAME="kubernetes-xxx-yyy-zzz"  # Replace with actual name from Step 1

# Check if it's already static
az network public-ip show \
  --resource-group $NODE_RG \
  --name $IP_NAME \
  --query "{Name:name, IP:ipAddress, Allocation:publicIPAllocationMethod, SKU:sku.name}" \
  --output table
```

### Step 3: Promote to Static (if Dynamic)

```bash
# If allocation method is "Dynamic", promote to Static
az network public-ip update \
  --resource-group $NODE_RG \
  --name $IP_NAME \
  --allocation-method Static

echo "IP promoted to Static successfully!"
```

### Step 4: Save Configuration Values

```yaml
# Configuration values:
cloudProvider: azure
azure:
  publicIpName: "kubernetes-xxx-yyy-zzz"  # Actual name from Step 1
  resourceGroup: "MC_example-rg_example-aks_eastus"  # Node RG from Step 1
```

## Method 3: Using Direct IP Address (Alternative)

Instead of using the Public IP name, you can configure using the IP address directly:

```yaml
cloudProvider: azure
azure:
  ipv4Address: "135.171.153.160"  # Your static IP address
  resourceGroup: "MC_example-rg_example-aks_eastus"  # Node resource group
```

**Note**: Using `publicIpName` (Methods 1 & 2) is recommended over `ipv4Address` as it's more explicit and maintainable.

## Verification

After creating or promoting the static IP:

```bash
# Verify the IP exists and is static
az network public-ip show \
  --resource-group $NODE_RG \
  --name $IP_NAME \
  --query "{Name:name, IP:ipAddress, Allocation:publicIPAllocationMethod, SKU:sku.name, Location:location}" \
  --output table
```

Expected output:
```
Name                          IP               Allocation  SKU       Location
----------------------------  ---------------  ----------  --------  ----------
production-gateway-ip         135.171.153.160  Static      Standard  eastus
```

## Important Notes

### SKU Requirements
- **Must use `Standard` SKU** for AKS LoadBalancer services
- `Basic` SKU is not supported with AKS
- Standard SKU IPs are zone-redundant by default

### Location Requirements
- Public IP **must** be in the same region as your AKS cluster
- Cross-region IPs will not work

### Costs
- Static Public IPs incur a small hourly charge (~$0.004/hour or ~$3/month)
- Charged whether in use or not once created
- See [Azure Pricing](https://azure.microsoft.com/en-us/pricing/details/ip-addresses/) for current rates

### Permissions Required
- `Microsoft.Network/publicIPAddresses/write` on node resource group
- `Microsoft.ContainerService/managedClusters/read` on AKS resource group

## Multiple Environments

For multiple environments (production, staging, etc.), create separate static IPs:

```bash
# Production
az network public-ip create \
  --resource-group $NODE_RG_PROD \
  --name production-gateway-ip \
  --sku Standard \
  --allocation-method Static \
  --location $REGION

# Staging
az network public-ip create \
  --resource-group $NODE_RG_STAGING \
  --name staging-gateway-ip \
  --sku Standard \
  --allocation-method Static \
  --location $REGION
```

## Troubleshooting

### Error: Public IP not found
- Verify you're using the **node resource group** (starts with `MC_`), not your main resource group
- Check the IP name spelling

### Error: Cannot create IP - quota exceeded
- Check your Azure subscription's public IP quota
- Request quota increase if needed

### IP not assigning to LoadBalancer
- Verify the IP is in the same region as the cluster
- Check that SKU is `Standard`, not `Basic`
- Ensure the IP is in the correct resource group (node RG)
- Verify infrastructure configuration has correct `publicIpName` and `resourceGroup`

### Load Balancer still gets dynamic IP
- Confirm ArgoCD has synced the infrastructure changes
- Check EnvoyProxy resource annotations: `kubectl get envoyproxy -n envoy-gateway-system custom-proxy-config -o yaml`
- Verify LoadBalancer service annotations: `kubectl get svc -n envoy-gateway-system -o yaml`

## Next Steps

1. ✅ Static IP created and configured
2. Provide configuration values to DevOps team
3. DevOps team updates infrastructure configuration
4. ArgoCD deploys changes
5. Update DNS records to point to static IP
6. Verify gateway connectivity

## Additional Resources

- [Azure Public IP documentation](https://docs.microsoft.com/en-us/azure/virtual-network/public-ip-addresses)
- [AKS Network Concepts](https://docs.microsoft.com/en-us/azure/aks/concepts-network)
- [Azure Load Balancer with AKS](https://docs.microsoft.com/en-us/azure/aks/load-balancer-standard)
