#!/bin/bash
# render-templates.sh
# Renders Helm templates and YAML templates with client-specific values

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage
usage() {
    echo "Usage: $0 --values <values-file> --output <output-dir> [--namespace <namespace>]"
    echo ""
    echo "Renders all Helm charts and infrastructure templates with client values."
    echo ""
    echo "Options:"
    echo "  --values <file>     Path to client values file (required)"
    echo "  --output <dir>      Output directory for rendered files (required)"
    echo "  --namespace <name>  Override namespace (optional)"
    echo "  --environment <env> Override environment (optional)"
    echo ""
    echo "Example:"
    echo "  $0 --values config/myclient/values-production.yaml --output rendered/myclient"
    echo ""
    exit 1
}

# Parse arguments
VALUES_FILE=""
OUTPUT_DIR=""
NAMESPACE_OVERRIDE=""
ENVIRONMENT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --values)
            VALUES_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE_OVERRIDE="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$VALUES_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    usage
fi

# Check values file exists
if [ ! -f "$VALUES_FILE" ]; then
    echo -e "${RED}Error: Values file not found: $VALUES_FILE${NC}"
    exit 1
fi

# Check helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed${NC}"
    echo "Install helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Extract values from YAML (requires yq)
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}Warning: yq not installed. Using default values for templates.${NC}"
    echo "For full functionality, install yq: brew install yq"
    DOMAIN="example.com"
    NAMESPACE="example-prod"
    ENVIRONMENT="production"
else
    DOMAIN=$(yq eval '.global.domain' "$VALUES_FILE")
    NAMESPACE=$(yq eval '.global.namespace' "$VALUES_FILE")
    ENVIRONMENT=$(yq eval '.global.environment' "$VALUES_FILE")
fi

# Override if specified
if [ -n "$NAMESPACE_OVERRIDE" ]; then
    NAMESPACE="$NAMESPACE_OVERRIDE"
fi
if [ -n "$ENVIRONMENT_OVERRIDE" ]; then
    ENVIRONMENT="$ENVIRONMENT_OVERRIDE"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Template Rendering${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Values File:  ${GREEN}$VALUES_FILE${NC}"
echo -e "Output Dir:   ${GREEN}$OUTPUT_DIR${NC}"
echo -e "Domain:       ${GREEN}$DOMAIN${NC}"
echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "Environment:  ${GREEN}$ENVIRONMENT${NC}"
echo ""

# Create output directories
mkdir -p "$OUTPUT_DIR/charts"
mkdir -p "$OUTPUT_DIR/infrastructure"
mkdir -p "$OUTPUT_DIR/argocd"

echo -e "${BLUE}[1/3] Rendering Helm charts...${NC}"

# Render HapiHub chart
echo -n "  - HapiHub... "
helm template hapihub charts/hapihub \\
    -f "$VALUES_FILE" \\
    --namespace "$NAMESPACE" \\
    --output-dir "$OUTPUT_DIR/charts" \\
    > /dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Render Syncd chart
echo -n "  - Syncd... "
helm template syncd charts/syncd \\
    -f "$VALUES_FILE" \\
    --namespace "$NAMESPACE" \\
    --output-dir "$OUTPUT_DIR/charts" \\
    > /dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Render MyCureApp chart
echo -n "  - MyCureApp... "
helm template mycureapp charts/mycureapp \\
    -f "$VALUES_FILE" \\
    --namespace "$NAMESPACE" \\
    --output-dir "$OUTPUT_DIR/charts" \\
    > /dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo ""
echo -e "${BLUE}[2/3] Rendering infrastructure templates...${NC}"

# Function to render template file
render_template() {
    local template_file=$1
    local output_file=$2
    
    # Simple sed-based replacement (works without yq)
    sed -e "s/{{ \.Values\.global\.domain }}/$DOMAIN/g" \\
        -e "s/{{ \.Values\.global\.namespace }}/$NAMESPACE/g" \\
        -e "s/{{ \.Values\.global\.environment }}/$ENVIRONMENT/g" \\
        "$template_file" > "$output_file"
}

# Render Gateway template
echo -n "  - Gateway... "
render_template \\
    "infrastructure/envoy-gateway/gateway.yaml.template" \\
    "$OUTPUT_DIR/infrastructure/gateway.yaml"
echo -e "${GREEN}✓${NC}"

# Render ArgoCD HTTPRoute
echo -n "  - ArgoCD HTTPRoute... "
render_template \\
    "infrastructure/argocd/httproute.yaml.template" \\
    "$OUTPUT_DIR/infrastructure/argocd-httproute.yaml"
echo -e "${GREEN}✓${NC}"

# Render Monitoring HTTPRoute
echo -n "  - Monitoring HTTPRoute... "
render_template \\
    "infrastructure/monitoring/httproute.yaml.template" \\
    "$OUTPUT_DIR/infrastructure/monitoring-httproute.yaml"
echo -e "${GREEN}✓${NC}"

# Render namespace
echo -n "  - Namespace... "
render_template \\
    "infrastructure/namespaces/namespace.yaml.template" \\
    "$OUTPUT_DIR/infrastructure/namespace.yaml"
echo -e "${GREEN}✓${NC}"

# Render SecretStore (detect provider from values)
echo -n "  - SecretStore... "
if grep -q "provider: aws" "$VALUES_FILE"; then
    render_template \\
        "infrastructure/external-secrets-operator/secretstore/aws-secretsmanager.yaml.template" \\
        "$OUTPUT_DIR/infrastructure/secretstore.yaml"
elif grep -q "provider: azure" "$VALUES_FILE"; then
    render_template \\
        "infrastructure/external-secrets-operator/secretstore/azure-keyvault.yaml.template" \\
        "$OUTPUT_DIR/infrastructure/secretstore.yaml"
elif grep -q "provider: gcp" "$VALUES_FILE"; then
    render_template \\
        "infrastructure/external-secrets-operator/secretstore/gcp-secretmanager.yaml.template" \\
        "$OUTPUT_DIR/infrastructure/secretstore.yaml"
else
    echo -e "${YELLOW}⚠ (provider not detected)${NC}"
fi
echo -e "${GREEN}✓${NC}"

# Render cert-manager ClusterIssuer
echo -n "  - ClusterIssuer... "
render_template \\
    "infrastructure/cert-manager/clusterissuer.yaml.template" \\
    "$OUTPUT_DIR/infrastructure/clusterissuer.yaml"
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${BLUE}[3/3] Rendering ArgoCD applications...${NC}"

# Render root app
echo -n "  - Root App... "
render_template \\
    "argocd/bootstrap/root-app.yaml.template" \\
    "$OUTPUT_DIR/argocd/root-app.yaml"
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Templates rendered successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Output directory:${NC}"
echo -e "  $OUTPUT_DIR/"
echo ""
echo -e "${YELLOW}Rendered files:${NC}"
tree -L 2 "$OUTPUT_DIR" 2>/dev/null || find "$OUTPUT_DIR" -type f | head -20
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "1. Review rendered files:"
echo -e "   ${BLUE}ls -R $OUTPUT_DIR/${NC}"
echo ""
echo -e "2. Deploy infrastructure:"
echo -e "   ${BLUE}kubectl apply -f $OUTPUT_DIR/infrastructure/${NC}"
echo ""
echo -e "3. Deploy applications:"
echo -e "   ${BLUE}kubectl apply -f $OUTPUT_DIR/charts/${NC}"
echo ""
echo -e "4. Or use ArgoCD:"
echo -e "   ${BLUE}kubectl apply -f $OUTPUT_DIR/argocd/root-app.yaml${NC}"
echo ""
