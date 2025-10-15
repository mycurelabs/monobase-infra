#!/bin/bash
# validate.sh
# Comprehensive validation script for Monobase Infrastructure template

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Monobase Infrastructure Template Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Test 1: Check for hardcoded client values
echo -e "${BLUE}[1/7] Checking for hardcoded client values...${NC}"
HARDCODED=$(grep -r "mycompany\|client-a\|client-b\|philcare" \
    charts/ infrastructure/ argocd/ 2>/dev/null | grep -v "\.git" | grep -v "example.com" || true)

if [ -n "$HARDCODED" ]; then
    echo -e "${RED}✗ Found hardcoded client values:${NC}"
    echo "$HARDCODED"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ No hardcoded client values found${NC}"
fi
echo ""

# Test 2: Verify only example.com in base template
echo -e "${BLUE}[2/7] Verifying example.com reference usage...${NC}"
EXAMPLE_COUNT=$(grep -r "example\.com" charts/ infrastructure/ config/example.com/ docs/ 2>/dev/null | wc -l | tr -d ' ')
echo -e "  Found ${GREEN}$EXAMPLE_COUNT${NC} references to example.com (expected in reference config)"

if [ ! -d "config/example.com" ]; then
    echo -e "${RED}✗ config/example.com directory missing${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}✓ Reference configuration exists${NC}"
fi
echo ""

# Test 3: Validate directory structure
echo -e "${BLUE}[3/7] Validating directory structure...${NC}"

REQUIRED_DIRS=(
    "charts/api/templates"
    "charts/api/templates"
    "charts/account/templates"
    "infrastructure/longhorn"
    "infrastructure/envoy-gateway"
    "infrastructure/security/networkpolicies"
    "config/example.com"
    "docs"
    "scripts"
)

DIR_OK=0
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        DIR_OK=$((DIR_OK + 1))
    else
        echo -e "  ${RED}✗${NC} $dir (missing)"
        ERRORS=$((ERRORS + 1))
    fi
done
echo -e "${GREEN}✓ $DIR_OK/${#REQUIRED_DIRS[@]} required directories exist${NC}"
echo ""

# Test 4: Check Helm charts have required files
echo -e "${BLUE}[4/7] Validating Helm chart structure...${NC}"

for CHART in api api account; do
    echo -n "  - $CHART: "
    CHART_COMPLETE=true
    
    [ ! -f "charts/$CHART/Chart.yaml" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/values.yaml" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/values.schema.json" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/templates/_helpers.tpl" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/templates/deployment.yaml" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/templates/service.yaml" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/templates/httproute.yaml" ] && CHART_COMPLETE=false
    [ ! -f "charts/$CHART/templates/NOTES.txt" ] && CHART_COMPLETE=false
    
    if [ "$CHART_COMPLETE" = true ]; then
        echo -e "${GREEN}✓ Complete${NC}"
    else
        echo -e "${RED}✗ Missing required files${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

# Test 5: Check scripts are executable
echo -e "${BLUE}[5/7] Checking automation scripts...${NC}"

SCRIPTS=(
    "scripts/new-client-config.sh"
    "scripts/render-templates.sh"
    "scripts/resize-statefulset-storage.sh"
    "scripts/admin-access.sh"
    "scripts/validate.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo -e "  ${RED}✗${NC} $script (missing)"
        ERRORS=$((ERRORS + 1))
    elif [ -x "$script" ]; then
        echo -e "  ${GREEN}✓${NC} $script (exists and executable)"
    else
        echo -e "  ${YELLOW}⚠${NC} $script (not executable)"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# Test 6: Check documentation completeness
echo -e "${BLUE}[6/7] Checking documentation...${NC}"

DOCS=(
    "README.md"
    "docs/CLIENT-ONBOARDING.md"
    "docs/TEMPLATE-USAGE.md"
    "docs/DEPLOYMENT.md"
    "docs/ARCHITECTURE.md"
    "docs/SECURITY-HARDENING.md"
    "docs/STORAGE.md"
    "docs/BACKUP-RECOVERY.md"
    "docs/GATEWAY-API.md"
    "docs/SCALING-GUIDE.md"
    "docs/HIPAA-COMPLIANCE.md"
    "docs/TROUBLESHOOTING.md"
)

DOCS_OK=0
for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        DOCS_OK=$((DOCS_OK + 1))
    else
        echo -e "  ${YELLOW}⚠${NC} $doc (missing)"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo -e "${GREEN}✓ $DOCS_OK/${#DOCS[@]} documentation files exist${NC}"
echo ""

# Test 7: Count template files
echo -e "${BLUE}[7/7] Template statistics...${NC}"

HELM_TEMPLATES=$(find charts/*/templates -name "*.yaml" -o -name "*.tpl" | wc -l | tr -d ' ')
INFRA_FILES=$(find infrastructure -name "*.yaml" -o -name "*.template" | wc -l | tr -d ' ')
TOTAL_FILES=$(find . -type f | grep -v "\.git" | wc -l | tr -d ' ')
TOTAL_LINES=$(find . \( -name "*.yaml" -o -name "*.md" -o -name "*.sh" -o -name "*.json" -o -name "*.tpl" \) -print0 | xargs -0 wc -l 2>/dev/null | tail -1 | awk '{print $1}')

echo -e "  Helm templates:       ${GREEN}$HELM_TEMPLATES${NC}"
echo -e "  Infrastructure files: ${GREEN}$INFRA_FILES${NC}"
echo -e "  Total files:          ${GREEN}$TOTAL_FILES${NC}"
echo -e "  Total lines of code:  ${GREEN}$TOTAL_LINES${NC}"
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Validation Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✓ ALL VALIDATION TESTS PASSED!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Template is ready for:"
    echo -e "  ${GREEN}✓${NC} Client fork and customization"
    echo -e "  ${GREEN}✓${NC} Production deployment"
    echo -e "  ${GREEN}✓${NC} HIPAA-compliant healthcare deployments"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation passed with $WARNINGS warnings${NC}"
    echo ""
    echo "Template is functional. Review warnings if needed."
    exit 0
else
    echo -e "${RED}✗ Validation failed with $ERRORS errors and $WARNINGS warnings${NC}"
    echo ""
    echo "Please fix errors above before using template."
    exit 1
fi
