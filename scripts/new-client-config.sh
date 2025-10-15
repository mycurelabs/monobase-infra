#!/bin/bash
# new-client-config.sh
# Bootstrap script to create new client configuration from profile templates

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 <client-name> <client-domain> [--profile production|staging]"
    echo ""
    echo "Creates a new client configuration from base profile templates."
    echo ""
    echo "Arguments:"
    echo "  client-name    Client identifier (lowercase, no spaces)"
    echo "  client-domain  Client's domain (e.g., myclient.com)"
    echo ""
    echo "Options:"
    echo "  --profile      Base profile to use (default: production)"
    echo "                 - production: Full HA setup with backups"
    echo "                 - staging: Single replicas, Mailpit enabled"
    echo ""
    echo "Example:"
    echo "  $0 myclient myclient.com"
    echo "  $0 myclient myclient.com --profile staging"
    echo ""
    exit 1
}

# Parse arguments
CLIENT_NAME=""
CLIENT_DOMAIN=""
PROFILE="production"

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$CLIENT_NAME" ]; then
                CLIENT_NAME="$1"
                shift
            elif [ -z "$CLIENT_DOMAIN" ]; then
                CLIENT_DOMAIN="$1"
                shift
            else
                echo -e "${RED}Error: Unknown argument: $1${NC}"
                usage
            fi
            ;;
    esac
done

# Check required arguments
if [ -z "$CLIENT_NAME" ] || [ -z "$CLIENT_DOMAIN" ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    usage
fi

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

# Validate profile
if [[ "$PROFILE" != "production" && "$PROFILE" != "staging" ]]; then
    echo -e "${RED}Error: Invalid profile. Must be 'production' or 'staging'${NC}"
    exit 1
fi

# Check if we're in the repository root
if [ ! -f "README.md" ] || [ ! -d "config/profiles" ]; then
    echo -e "${RED}Error: Must run from repository root${NC}"
    exit 1
fi

# Check if profile exists
PROFILE_FILE="config/profiles/${PROFILE}-base.yaml"
if [ ! -f "$PROFILE_FILE" ]; then
    echo -e "${RED}Error: Profile not found: $PROFILE_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Monobase Infrastructure - Client Bootstrap${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Client Name:   ${GREEN}$CLIENT_NAME${NC}"
echo -e "Client Domain: ${GREEN}$CLIENT_DOMAIN${NC}"
echo -e "Base Profile:  ${GREEN}$PROFILE${NC}"
echo ""

# Confirm before proceeding
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}[1/3] Creating client configuration directory...${NC}"

# Create client directory
mkdir -p config/$CLIENT_NAME

echo -e "${GREEN}✓ Created config/$CLIENT_NAME/${NC}"

echo ""
echo -e "${BLUE}[2/3] Creating minimal configuration from profile...${NC}"

# Create production values file with minimal overrides
cat > config/$CLIENT_NAME/values-production.yaml << EOF
# $CLIENT_NAME Production Configuration
# Based on: $PROFILE-base.yaml profile
#
# This file contains ONLY client-specific overrides.
# All other settings are inherited from config/profiles/$PROFILE-base.yaml
#
# Keep this file minimal (~60 lines) by only overriding what's different.

global:
  domain: $CLIENT_DOMAIN
  namespace: $CLIENT_NAME-prod
  environment: production

# REQUIRED: Pin specific image versions (never use "latest" in production)
api:
  image:
    tag: "5.215.2"  # TODO: Update to your API version

account:
  image:
    tag: "1.0.0"  # TODO: Update to your Account version

# Optional: Override resource limits if needed
# api:
#   resources:
#     limits:
#       cpu: "2000m"
#       memory: "4Gi"

# Optional: Override storage sizes if needed
# postgresql:
#   persistence:
#     size: 200Gi  # Default: 50Gi

# Optional: Enable/disable components
# minio:
#   enabled: false  # Use cloud S3 instead
#
# mailpit:
#   enabled: false  # Production uses real SMTP
EOF

# Create staging values file if using staging profile
if [ "$PROFILE" == "staging" ]; then
    cat > config/$CLIENT_NAME/values-staging.yaml << EOF
# $CLIENT_NAME Staging Configuration
# Based on: staging-base.yaml profile

global:
  domain: staging.$CLIENT_DOMAIN
  namespace: $CLIENT_NAME-staging
  environment: staging

# Pin image versions
api:
  image:
    tag: "latest"  # OK for staging

account:
  image:
    tag: "latest"  # OK for staging
EOF
    echo -e "${GREEN}✓ Created values-staging.yaml${NC}"
fi

echo -e "${GREEN}✓ Created values-production.yaml (minimal overrides only)${NC}"

echo ""
echo -e "${BLUE}[3/3] Creating README...${NC}"

# Update the README in client config
cat > config/$CLIENT_NAME/README.md << EOF
# Configuration for $CLIENT_NAME

Client: **$CLIENT_NAME**
Domain: **$CLIENT_DOMAIN**
Base Profile: **$PROFILE**

## Files

- \`values-production.yaml\` - Production configuration (minimal overrides only)
- \`values-staging.yaml\` - Staging configuration (if applicable)

## Profile-Based Configuration

This configuration inherits from \`config/profiles/$PROFILE-base.yaml\`.

**Keep your configuration minimal!** Only override values that are different from the base profile:
- Domain and namespace (required)
- Image tags (required - pin specific versions)
- Resource limits (only if different from profile)
- Storage sizes (only if different from profile)

**Target:** ~60 lines instead of 430 lines

## Next Steps

1. **Review and customize minimal overrides:**
   \`\`\`bash
   vim config/$CLIENT_NAME/values-production.yaml
   \`\`\`

2. **Update image tags to specific versions:**
   - Replace TODO comments with actual version numbers
   - Never use "latest" in production

3. **Add overrides only if needed:**
   - Resource limits (if different from profile defaults)
   - Storage sizes (if different from profile defaults)
   - Component toggles (minio, mailpit, etc.)

4. **Commit configuration:**
   \`\`\`bash
   git add config/$CLIENT_NAME/
   git commit -m "Add $CLIENT_NAME configuration"
   git push origin main
   \`\`\`

5. **Bootstrap deployment (one command!):**
   \`\`\`bash
   ./scripts/bootstrap.sh --client $CLIENT_NAME --env production
   \`\`\`

## Support

- Documentation: [docs/](../../docs/)
- Profile Documentation: [config/profiles/README.md](../profiles/README.md)
EOF

echo -e "${GREEN}✓ Created custom README${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Client configuration created successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo -e "  Base Profile:  ${GREEN}$PROFILE-base.yaml${NC}"
echo -e "  Config File:   ${GREEN}config/$CLIENT_NAME/values-production.yaml${NC}"
echo -e "  Approach:      ${GREEN}Minimal overrides only (~60 lines)${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "1. Review and update image tags (REQUIRED):"
echo -e "   ${BLUE}vim config/$CLIENT_NAME/values-production.yaml${NC}"
echo -e "   ${YELLOW}→ Replace TODO comments with actual version numbers${NC}"
echo ""
echo -e "2. Add overrides only if needed (optional):"
echo -e "   - Resource limits (if different from profile)"
echo -e "   - Storage sizes (if different from profile)"
echo -e "   - Component toggles (minio, mailpit, etc.)"
echo ""
echo -e "3. Commit your configuration:"
echo -e "   ${BLUE}git add config/$CLIENT_NAME/${NC}"
echo -e "   ${BLUE}git commit -m \"Add $CLIENT_NAME configuration\"${NC}"
echo -e "   ${BLUE}git push origin main${NC}"
echo ""
echo -e "4. Bootstrap entire stack (one command!):"
echo -e "   ${BLUE}./scripts/bootstrap.sh --client $CLIENT_NAME --env production${NC}"
echo ""
echo -e "📖 See ${BLUE}config/profiles/README.md${NC} for profile-based configuration guide"
echo ""
