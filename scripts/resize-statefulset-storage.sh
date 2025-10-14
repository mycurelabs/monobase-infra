#!/bin/bash
# resize-statefulset-storage.sh
# Generic script to resize StatefulSet PVCs (MongoDB, MinIO, Typesense)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage
usage() {
    echo "Usage: $0 <statefulset-name> <namespace> <new-size>"
    echo ""
    echo "Resizes all PVCs for a StatefulSet without downtime."
    echo ""
    echo "Arguments:"
    echo "  statefulset-name  Name of the StatefulSet (e.g., mongodb)"
    echo "  namespace         Kubernetes namespace"
    echo "  new-size          New storage size (e.g., 200Gi)"
    echo ""
    echo "Examples:"
    echo "  $0 mongodb myclient-prod 200Gi"
    echo "  $0 minio myclient-prod 500Gi"
    echo ""
    echo "⚠️  WARNING: This script:"
    echo "  - Temporarily deletes the StatefulSet (pods keep running)"
    echo "  - Expands all PVCs"
    echo "  - Recreates the StatefulSet"
    echo "  - Performs rolling restart"
    echo ""
    exit 1
}

# Check arguments
if [ $# -ne 3 ]; then
    echo -e "${RED}Error: Invalid number of arguments${NC}"
    usage
fi

STATEFULSET_NAME=$1
NAMESPACE=$2
NEW_SIZE=$3

# Validate new size format
if ! [[ "$NEW_SIZE" =~ ^[0-9]+[GT]i$ ]]; then
    echo -e "${RED}Error: Invalid size format. Use format like: 100Gi, 1Ti${NC}"
    exit 1
fi

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Check StatefulSet exists
if ! kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: StatefulSet '$STATEFULSET_NAME' not found in namespace '$NAMESPACE'${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  StatefulSet Storage Resize${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "StatefulSet:  ${GREEN}$STATEFULSET_NAME${NC}"
echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "New Size:     ${GREEN}$NEW_SIZE${NC}"
echo ""

# Get current replica count
REPLICAS=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
echo -e "Current replicas: ${GREEN}$REPLICAS${NC}"

# Get PVC template name
PVC_TEMPLATE=$(kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}')
echo -e "PVC template: ${GREEN}$PVC_TEMPLATE${NC}"

# List current PVCs
echo ""
echo -e "${YELLOW}Current PVCs:${NC}"
kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/name="$STATEFULSET_NAME" \
    -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase

# Get current sizes
CURRENT_SIZE=$(kubectl get pvc "${PVC_TEMPLATE}-${STATEFULSET_NAME}-0" -n "$NAMESPACE" \
    -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null || echo "unknown")
echo ""
echo -e "Current size: ${YELLOW}$CURRENT_SIZE${NC} → New size: ${GREEN}$NEW_SIZE${NC}"

# Confirm
echo ""
echo -e "${YELLOW}⚠️  This will:${NC}"
echo "  1. Temporarily delete the StatefulSet (pods keep running)"
echo "  2. Expand all $REPLICAS PVCs to $NEW_SIZE"
echo "  3. Recreate the StatefulSet with new size"
echo "  4. Perform rolling restart of pods"
echo ""
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo -e "${YELLOW}Aborted${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}[1/5] Backing up StatefulSet definition...${NC}"

# Backup StatefulSet YAML
kubectl get statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" -o yaml > \\
    "/tmp/${STATEFULSET_NAME}-backup-$(date +%Y%m%d-%H%M%S).yaml"
echo -e "${GREEN}✓ Backup saved to /tmp/${STATEFULSET_NAME}-backup-$(date +%Y%m%d-%H%M%S).yaml${NC}"

echo ""
echo -e "${BLUE}[2/5] Deleting StatefulSet (--cascade=orphan)...${NC}"
echo -e "${YELLOW}  (Pods will keep running)${NC}"

# Delete StatefulSet but keep pods
kubectl delete statefulset "$STATEFULSET_NAME" -n "$NAMESPACE" --cascade=orphan
echo -e "${GREEN}✓ StatefulSet deleted (pods still running)${NC}"

# Verify pods still running
sleep 2
RUNNING_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name="$STATEFULSET_NAME" \
    --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
echo -e "  Running pods: ${GREEN}$RUNNING_PODS${NC}/$REPLICAS"

echo ""
echo -e "${BLUE}[3/5] Expanding PVCs...${NC}"

# Expand each PVC
for i in $(seq 0 $((REPLICAS - 1))); do
    PVC_NAME="${PVC_TEMPLATE}-${STATEFULSET_NAME}-${i}"
    
    echo -n "  - Expanding $PVC_NAME... "
    
    kubectl patch pvc "$PVC_NAME" -n "$NAMESPACE" \
        --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/resources/requests/storage\", \"value\": \"$NEW_SIZE\"}]" \
        > /dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
done

echo -e "${GREEN}✓ All PVCs patched${NC}"

# Wait for expansion
echo ""
echo -e "${YELLOW}Waiting for Longhorn to expand volumes (this may take a minute)...${NC}"
sleep 10

echo ""
echo -e "${BLUE}[4/5] Recreating StatefulSet with new size...${NC}"

# Update volumeClaimTemplate size in backup file
sed -i.bak "s/storage: $CURRENT_SIZE/storage: $NEW_SIZE/g" \\
    "/tmp/${STATEFULSET_NAME}-backup-$(date +%Y%m%d-%H%M%S).yaml"

# Recreate StatefulSet
kubectl apply -f "/tmp/${STATEFULSET_NAME}-backup-$(date +%Y%m%d-%H%M%S).yaml"
echo -e "${GREEN}✓ StatefulSet recreated${NC}"

echo ""
echo -e "${BLUE}[5/5] Performing rolling restart...${NC}"

# Rolling restart (one pod at a time)
for i in $(seq $((REPLICAS - 1)) -1 0); do
    POD_NAME="${STATEFULSET_NAME}-${i}"
    
    echo -n "  - Restarting $POD_NAME... "
    
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE"
    
    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod "$POD_NAME" -n "$NAMESPACE" --timeout=600s \
        > /dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗ (check manually)${NC}"
    
    sleep 5
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Storage resize complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Verification:${NC}"
echo ""
echo -e "1. Check PVC sizes:"
echo -e "   ${BLUE}kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=$STATEFULSET_NAME${NC}"
echo ""
echo -e "2. Verify in pods:"
echo -e "   ${BLUE}kubectl exec -it ${STATEFULSET_NAME}-0 -n $NAMESPACE -- df -h${NC}"
echo ""
echo -e "3. Check StatefulSet:"
echo -e "   ${BLUE}kubectl get statefulset $STATEFULSET_NAME -n $NAMESPACE${NC}"
echo ""
echo -e "${GREEN}All PVCs should now show: $NEW_SIZE${NC}"
echo ""
