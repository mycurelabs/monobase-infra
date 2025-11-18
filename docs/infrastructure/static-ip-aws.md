# AWS EKS Static IP Configuration

## Overview

AWS EKS uses Elastic IPs (EIPs) with Network Load Balancers (NLB) to provide static IP addresses for LoadBalancer services.

## Prerequisites

- AWS CLI installed and configured
- EKS cluster deployed
- Know your VPC subnet IDs (typically 3 subnets across 3 AZs)
- IAM permissions to allocate EIPs

## Key Concepts

### High Availability Requirements
- AWS NLB requires **one Elastic IP per subnet** where your cluster runs
- Typical setup: 3 subnets = 3 Elastic IPs needed
- All 3 IPs are active; first IP is typically used for DNS

### Network Load Balancer (NLB)
- Required for static IP support (Classic LB doesn't support EIPs)
- Operates at Layer 4 (TCP/UDP)
- Zone-aware and highly available

## Step-by-Step Instructions

### Step 1: Identify Your Subnets

```bash
# Get your cluster's VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name your-cluster-name \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

# List subnets in your VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}' \
  --output table
```

### Step 2: Allocate Elastic IPs

Allocate one EIP per subnet (typically 3):

```bash
REGION="us-east-1"
ENV="production"

# Allocate EIP 1
EIP1=$(aws ec2 allocate-address \
  --region $REGION \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${ENV}-gateway-eip-1},{Key=Environment,Value=${ENV}},{Key=Service,Value=gateway}]" \
  --query 'AllocationId' \
  --output text)

echo "EIP 1 Allocation ID: $EIP1"

# Allocate EIP 2
EIP2=$(aws ec2 allocate-address \
  --region $REGION \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${ENV}-gateway-eip-2},{Key=Environment,Value=${ENV}},{Key=Service,Value=gateway}]" \
  --query 'AllocationId' \
  --output text)

echo "EIP 2 Allocation ID: $EIP2"

# Allocate EIP 3
EIP3=$(aws ec2 allocate-address \
  --region $REGION \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${ENV}-gateway-eip-3},{Key=Environment,Value=${ENV}},{Key=Service,Value=gateway}]" \
  --query 'AllocationId' \
  --output text)

echo "EIP 3 Allocation ID: $EIP3"
```

### Step 3: Get IP Addresses

```bash
# List all allocated EIPs with their addresses
aws ec2 describe-addresses \
  --region $REGION \
  --filters "Name=tag:Environment,Values=${ENV}" "Name=tag:Service,Values=gateway" \
  --query 'Addresses[*].{IP:PublicIp,AllocationID:AllocationId,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output table
```

**Example output:**
```
---------------------------------------------------------------------
|                         DescribeAddresses                          |
+-------------------------+-------------------+------------------------+
|      AllocationID       |        IP         |          Name          |
+-------------------------+-------------------+------------------------+
|  eipalloc-0abc123def... |  52.123.45.67     |  production-gateway-eip-1 |
|  eipalloc-0def456ghi... |  52.123.45.68     |  production-gateway-eip-2 |
|  eipalloc-0ghi789jkl... |  52.123.45.69     |  production-gateway-eip-3 |
+-------------------------+-------------------+------------------------+
```

### Step 4: Format Configuration Values

Create comma-separated list of allocation IDs:

```bash
# Format for configuration
echo "eipAllocations: \"$EIP1,$EIP2,$EIP3\""
```

## Configuration

Provide these values to your DevOps team:

```yaml
cloudProvider: aws
aws:
  eipAllocations: "eipalloc-0abc123,eipalloc-0def456,eipalloc-0ghi789"
```

**For DNS:** Use the first IP address in your list (52.123.45.67 in the example above).

## Verification

After allocation:

```bash
# Verify all EIPs are allocated and unassigned
aws ec2 describe-addresses \
  --allocation-ids $EIP1 $EIP2 $EIP3 \
  --query 'Addresses[*].{AllocationId:AllocationId,IP:PublicIp,Status:AssociationId}' \
  --output table
```

Status should show `None` until the LoadBalancer is created.

## Important Notes

### Cost
- EIPs are **free when in use** (associated with running resources)
- **$0.005/hour (~$3.60/month)** per EIP when **not in use**
- Once LoadBalancer is running, no additional charge

### Subnet Requirements
- Must have one EIP per subnet where NLB will be deployed
- Typically 3 subnets across 3 availability zones
- All subnets must be in the same region

### Permissions Required
```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:AllocateAddress",
    "ec2:DescribeAddresses",
    "ec2:CreateTags"
  ],
  "Resource": "*"
}
```

## Troubleshooting

### Error: Cannot allocate more addresses
- Check your EIP quota: `aws service-quotas get-service-quota --service-code ec2 --quota-code L-0263D0A3`
- Request quota increase if needed

### LoadBalancer not using EIPs
- Verify `aws-load-balancer-type` annotation is set to `external` or `nlb`
- Check that allocation IDs are correct and comma-separated
- Ensure EIPs are in the same region as cluster

### Only one IP responding
- This is normal - AWS distributes traffic across all IPs
- All IPs are active but DNS typically points to first IP
- Use all 3 IPs for high availability across AZs

## Cleanup (if needed)

To release EIPs (will stop charges):

```bash
# Release EIPs (only if not in use!)
aws ec2 release-address --allocation-id $EIP1
aws ec2 release-address --allocation-id $EIP2
aws ec2 release-address --allocation-id $EIP3
```

**Warning:** Only release EIPs if they're not associated with any resources.

## Additional Resources

- [AWS EIP Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html)
- [EKS Load Balancing](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
