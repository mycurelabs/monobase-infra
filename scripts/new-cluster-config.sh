#!/bin/bash
# new-cluster-config.sh
# Bootstrap new cluster configuration from default-cluster reference

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <cluster-name> [region]"
    echo ""
    echo "Creates new cluster configuration from default-cluster reference."
    echo ""
    echo "Arguments:"
    echo "  cluster-name   Cluster identifier (e.g., myclient-prod)"
    echo "  region         AWS region (default: us-east-1)"
    echo ""
    echo "Example:"
    echo "  $0 myclient-prod us-east-1"
    echo ""
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

CLUSTER_NAME=$1
REGION=${2:-"us-east-1"}

if ! [[ "$CLUSTER_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "${RED}Error: Cluster name must be lowercase alphanumeric with hyphens${NC}"
    exit 1
fi

if [ -d "tofu/clusters/$CLUSTER_NAME" ]; then
    echo -e "${RED}Error: Cluster '$CLUSTER_NAME' already exists${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Cluster Configuration Bootstrap${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Cluster Name: ${GREEN}$CLUSTER_NAME${NC}"
echo -e "Region:       ${GREEN}$REGION${NC}"
echo ""

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}[1/3] Copying default-cluster...${NC}"
cp -r tofu/clusters/default-cluster tofu/clusters/$CLUSTER_NAME
echo -e "${GREEN}✓ Copied${NC}"

echo ""
echo -e "${BLUE}[2/3] Replacing placeholders...${NC}"
cd tofu/clusters/$CLUSTER_NAME

sed -i.bak "s/monobase-default-cluster/monobase-$CLUSTER_NAME/g" terraform.tfvars
sed -i.bak "s/us-east-1/$REGION/g" terraform.tfvars
find . -name "*.bak" -delete

echo -e "${GREEN}✓ Replaced placeholders${NC}"

echo ""
echo -e "${BLUE}[3/3] Creating backend config...${NC}"
cp backend.tf.example backend.tf
echo -e "${GREEN}✓ Created backend.tf${NC}"

cd ../../..

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Cluster configuration created!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "1. Customize cluster config:"
echo -e "   ${BLUE}vim tofu/clusters/$CLUSTER_NAME/terraform.tfvars${NC}"
echo ""
echo -e "2. Configure backend (S3 bucket):"
echo -e "   ${BLUE}vim tofu/clusters/$CLUSTER_NAME/backend.tf${NC}"
echo ""
echo -e "3. Provision cluster (idempotent - safe to re-run):"
echo -e "   ${BLUE}./scripts/provision.sh --cluster $CLUSTER_NAME${NC}"
echo ""
echo -e "4. Create client configuration:"
echo -e "   ${BLUE}./scripts/new-client-config.sh myclient myclient.com${NC}"
echo ""
echo -e "5. Bootstrap applications (one command!):"
echo -e "   ${BLUE}./scripts/bootstrap.sh --client myclient --env production${NC}"
echo ""
