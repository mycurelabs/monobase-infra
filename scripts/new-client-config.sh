#!/bin/bash
# new-client-config.sh
# Bootstrap script to create new client configuration from example.com reference

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 <client-name> <client-domain>"
    echo ""
    echo "Creates a new client configuration from the example.com reference."
    echo ""
    echo "Arguments:"
    echo "  client-name    Client identifier (lowercase, no spaces)"
    echo "  client-domain  Client's domain (e.g., myclient.com)"
    echo ""
    echo "Example:"
    echo "  $0 myclient myclient.com"
    echo ""
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    usage
fi

CLIENT_NAME=$1
CLIENT_DOMAIN=$2

# Validate client name (lowercase, alphanumeric, hyphens only)
if ! [[ "$CLIENT_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "${RED}Error: Client name must be lowercase alphanumeric with hyphens only${NC}"
    exit 1
fi

# Validate domain format
if ! [[ "$CLIENT_DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
    echo -e "${RED}Error: Invalid domain format${NC}"
    exit 1
fi

# Check if config directory already exists
if [ -d "config/$CLIENT_NAME" ]; then
    echo -e "${RED}Error: Configuration for '$CLIENT_NAME' already exists${NC}"
    echo "Directory: config/$CLIENT_NAME"
    exit 1
fi

# Check if we're in the repository root
if [ ! -f "README.md" ] || [ ! -d "config/example.com" ]; then
    echo -e "${RED}Error: Must run from repository root${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  LFH Infrastructure - Client Bootstrap${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Client Name:   ${GREEN}$CLIENT_NAME${NC}"
echo -e "Client Domain: ${GREEN}$CLIENT_DOMAIN${NC}"
echo ""

# Confirm before proceeding
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}[1/4] Copying reference configuration...${NC}"

# Copy example.com to client directory
cp -r config/example.com config/$CLIENT_NAME

echo -e "${GREEN}✓ Copied config/example.com → config/$CLIENT_NAME${NC}"

echo ""
echo -e "${BLUE}[2/4] Replacing placeholders...${NC}"

# Replace placeholders in all files
# Using sed -i.bak for cross-platform compatibility (macOS and Linux)
find config/$CLIENT_NAME -type f -exec sed -i.bak \
    -e "s/example\.com/$CLIENT_DOMAIN/g" \
    -e "s/example-prod/$CLIENT_NAME-prod/g" \
    -e "s/example-staging/$CLIENT_NAME-staging/g" \
    -e "s/example/$CLIENT_NAME/g" \
    {} \;

# Clean up backup files
find config/$CLIENT_NAME -type f -name "*.bak" -delete

echo -e "${GREEN}✓ Replaced example.com → $CLIENT_DOMAIN${NC}"
echo -e "${GREEN}✓ Replaced example → $CLIENT_NAME${NC}"

echo ""
echo -e "${BLUE}[3/4] Updating README...${NC}"

# Update the README in client config
cat > config/$CLIENT_NAME/README.md << EOF
# Configuration for $CLIENT_NAME

Client: **$CLIENT_NAME**  
Domain: **$CLIENT_DOMAIN**

## Files

- \`values-staging.yaml\` - Staging environment configuration
- \`values-production.yaml\` - Production environment configuration
- \`secrets-mapping.yaml\` - KMS secret path mappings

## Next Steps

1. **Review and customize configuration:**
   \`\`\`bash
   vim config/$CLIENT_NAME/values-production.yaml
   \`\`\`

2. **Key items to configure:**
   - Image tags (replace "latest" with specific versions)
   - Resource limits (CPU, memory)
   - Storage sizes (MongoDB, MinIO)
   - Replica counts
   - Optional components (syncd, minio, typesense)

3. **Configure secrets management:**
   \`\`\`bash
   vim config/$CLIENT_NAME/secrets-mapping.yaml
   \`\`\`
   Update with your KMS paths (AWS, Azure, GCP, or SOPS)

4. **Create secrets in your KMS:**
   - MongoDB credentials
   - HapiHub secrets (JWT, database URL, S3, SMTP)
   - MinIO credentials (if self-hosted)
   - TLS certificates (if not using cert-manager)

5. **Commit configuration:**
   \`\`\`bash
   git add config/$CLIENT_NAME/
   git commit -m "Add $CLIENT_NAME configuration"
   git push origin main
   \`\`\`

6. **Deploy infrastructure:**
   See [CLIENT-ONBOARDING.md](../../docs/CLIENT-ONBOARDING.md) for deployment steps.

## Support

- Documentation: [docs/](../../docs/)
- Issues: [GitHub Issues](https://github.com/mycurelabs/lfh-infra/issues)
EOF

echo -e "${GREEN}✓ Created custom README${NC}"

echo ""
echo -e "${BLUE}[4/4] Creating directory structure...${NC}"

# Create rendered output directory (for template rendering)
mkdir -p rendered/$CLIENT_NAME

echo -e "${GREEN}✓ Created rendered/$CLIENT_NAME/${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Client configuration created successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "1. Customize your configuration:"
echo -e "   ${BLUE}vim config/$CLIENT_NAME/values-production.yaml${NC}"
echo ""
echo -e "2. Update secrets mapping:"
echo -e "   ${BLUE}vim config/$CLIENT_NAME/secrets-mapping.yaml${NC}"
echo ""
echo -e "3. Create secrets in your KMS"
echo ""
echo -e "4. Commit your configuration:"
echo -e "   ${BLUE}git add config/$CLIENT_NAME/${NC}"
echo -e "   ${BLUE}git commit -m \"Add $CLIENT_NAME configuration\"${NC}"
echo -e "   ${BLUE}git push origin main${NC}"
echo ""
echo -e "5. Deploy infrastructure:"
echo -e "   See ${BLUE}docs/CLIENT-ONBOARDING.md${NC} for deployment steps"
echo ""
