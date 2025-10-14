#!/bin/bash
# Validate secrets configuration and connectivity
# Usage: ./scripts/validate-secrets.sh [namespace]

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE=${1:-""}
ERRORS=0
WARNINGS=0

echo "🔐 LFH Infrastructure - Secrets Validation"
echo "=========================================="
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "Checking prerequisites..."
if ! command_exists kubectl; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

if ! command_exists aws && ! command_exists az && ! command_exists gcloud; then
    echo -e "${YELLOW}Warning: No cloud CLI found (aws, az, or gcloud)${NC}"
    echo "  Cannot validate KMS connectivity"
    WARNINGS=$((WARNINGS + 1))
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Get namespaces to check
if [ -z "$NAMESPACE" ]; then
    NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E '(-prod|-staging)$' || true)
    if [ -z "$NAMESPACES" ]; then
        echo -e "${YELLOW}No application namespaces found (looking for *-prod or *-staging)${NC}"
        exit 0
    fi
else
    NAMESPACES=$NAMESPACE
fi

echo "Checking namespaces: $NAMESPACES"
echo ""

# Check External Secrets Operator
echo "Checking External Secrets Operator..."
if kubectl get deployment -n external-secrets-system external-secrets >/dev/null 2>&1; then
    if kubectl wait --for=condition=Available deployment/external-secrets \
        -n external-secrets-system --timeout=10s >/dev/null 2>&1; then
        echo -e "${GREEN}✓ External Secrets Operator is running${NC}"
    else
        echo -e "${RED}✗ External Secrets Operator not ready${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}✗ External Secrets Operator not deployed${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check each namespace
for NS in $NAMESPACES; do
    echo "Validating namespace: $NS"
    echo "-------------------"
    
    # Check if namespace exists
    if ! kubectl get namespace "$NS" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Namespace $NS does not exist${NC}"
        WARNINGS=$((WARNINGS + 1))
        continue
    fi
    
    # Check SecretStore
    echo "  Checking SecretStore..."
    SECRET_STORES=$(kubectl get secretstore -n "$NS" -o name 2>/dev/null || true)
    if [ -z "$SECRET_STORES" ]; then
        echo -e "${YELLOW}  ⚠ No SecretStore found in $NS${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        for STORE in $SECRET_STORES; then
            STORE_NAME=$(echo "$STORE" | cut -d'/' -f2)
            STATUS=$(kubectl get secretstore "$STORE_NAME" -n "$NS" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            
            if [ "$STATUS" == "True" ]; then
                echo -e "${GREEN}  ✓ SecretStore $STORE_NAME is ready${NC}"
            else
                echo -e "${RED}  ✗ SecretStore $STORE_NAME is not ready (status: $STATUS)${NC}"
                ERRORS=$((ERRORS + 1))
            fi
        done
    fi
    
    # Check ExternalSecrets
    echo "  Checking ExternalSecrets..."
    EXTERNAL_SECRETS=$(kubectl get externalsecret -n "$NS" -o name 2>/dev/null || true)
    if [ -z "$EXTERNAL_SECRETS" ]; then
        echo -e "${YELLOW}  ⚠ No ExternalSecrets found in $NS${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        for ES in $EXTERNAL_SECRETS; then
            ES_NAME=$(echo "$ES" | cut -d'/' -f2)
            STATUS=$(kubectl get externalsecret "$ES_NAME" -n "$NS" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            
            if [ "$STATUS" == "True" ]; then
                echo -e "${GREEN}  ✓ ExternalSecret $ES_NAME is synced${NC}"
                
                # Check if corresponding Kubernetes secret exists
                SECRET_NAME=$(kubectl get externalsecret "$ES_NAME" -n "$NS" \
                    -o jsonpath='{.spec.target.name}' 2>/dev/null || echo "")
                if [ -n "$SECRET_NAME" ]; then
                    if kubectl get secret "$SECRET_NAME" -n "$NS" >/dev/null 2>&1; then
                        echo -e "${GREEN}    ✓ Secret $SECRET_NAME exists${NC}"
                    else
                        echo -e "${RED}    ✗ Secret $SECRET_NAME not found${NC}"
                        ERRORS=$((ERRORS + 1))
                    fi
                fi
            else
                echo -e "${RED}  ✗ ExternalSecret $ES_NAME not synced (status: $STATUS)${NC}"
                
                # Show error message if available
                ERROR_MSG=$(kubectl get externalsecret "$ES_NAME" -n "$NS" \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || echo "")
                if [ -n "$ERROR_MSG" ]; then
                    echo -e "${RED}    Error: $ERROR_MSG${NC}"
                fi
                
                ERRORS=$((ERRORS + 1))
            fi
        done
    fi
    
    echo ""
done

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ No errors found${NC}"
else
    echo -e "${RED}✗ Found $ERRORS error(s)${NC}"
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found $WARNINGS warning(s)${NC}"
fi

echo ""
echo "Next steps:"
if [ $ERRORS -gt 0 ]; then
    echo "  1. Check cloud provider IAM/RBAC permissions (IRSA, Workload Identity)"
    echo "  2. Verify secret names in cloud KMS match ExternalSecret definitions"
    echo "  3. Check External Secrets Operator logs:"
    echo "     kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets"
fi

exit $ERRORS
