#!/bin/bash
# admin-access.sh
# Convenient port-forwarding for admin UIs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage
usage() {
    echo "Usage: $0 <service> [namespace]"
    echo ""
    echo "Quick access to admin UIs via port-forward."
    echo ""
    echo "Available services:"
    echo "  argocd      - ArgoCD UI (port 8080)"
    echo "  grafana     - Grafana UI (port 8080)"
    echo "  prometheus  - Prometheus UI (port 9090)"
    echo "  longhorn    - Longhorn UI (port 8080)"
    echo "  minio       - MinIO Console (port 9001)"
    echo "  mailpit     - Mailpit UI (port 8025)"
    echo ""
    echo "Examples:"
    echo "  $0 argocd"
    echo "  $0 grafana"
    echo "  $0 minio myclient-prod"
    echo ""
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    usage
fi

SERVICE=$1
NAMESPACE=${2:-""}

# Service configurations
case $SERVICE in
    argocd)
        NAMESPACE=${NAMESPACE:-"argocd"}
        SVC_NAME="argocd-server"
        LOCAL_PORT=8080
        REMOTE_PORT=443
        URL="https://localhost:${LOCAL_PORT}"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  ArgoCD Admin Access${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}Getting admin password...${NC}"
        PASSWORD=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \\
            -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Secret not found")
        
        echo -e "Username: ${GREEN}admin${NC}"
        echo -e "Password: ${GREEN}$PASSWORD${NC}"
        echo ""
        ;;
    
    grafana)
        NAMESPACE=${NAMESPACE:-"monitoring"}
        SVC_NAME="monitoring-grafana"
        LOCAL_PORT=8080
        REMOTE_PORT=80
        URL="http://localhost:${LOCAL_PORT}"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  Grafana Admin Access${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}Getting admin password...${NC}"
        PASSWORD=$(kubectl -n "$NAMESPACE" get secret grafana-credentials \\
            -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d || echo "admin")
        
        echo -e "Username: ${GREEN}admin${NC}"
        echo -e "Password: ${GREEN}$PASSWORD${NC}"
        echo ""
        ;;
    
    prometheus)
        NAMESPACE=${NAMESPACE:-"monitoring"}
        SVC_NAME="monitoring-prometheus"
        LOCAL_PORT=9090
        REMOTE_PORT=9090
        URL="http://localhost:${LOCAL_PORT}"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  Prometheus Access${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        ;;
    
    longhorn)
        NAMESPACE=${NAMESPACE:-"longhorn-system"}
        SVC_NAME="longhorn-frontend"
        LOCAL_PORT=8080
        REMOTE_PORT=80
        URL="http://localhost:${LOCAL_PORT}"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  Longhorn UI Access${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        ;;
    
    minio)
        if [ -z "$NAMESPACE" ]; then
            echo -e "${RED}Error: Namespace required for MinIO${NC}"
            echo "Usage: $0 minio <namespace>"
            exit 1
        fi
        
        SVC_NAME="minio"
        LOCAL_PORT=9001
        REMOTE_PORT=9001
        URL="http://localhost:${LOCAL_PORT}"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  MinIO Console Access${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}Getting credentials...${NC}"
        MINIO_USER=$(kubectl get secret minio-credentials -n "$NAMESPACE" \\
            -o jsonpath='{.data.root-user}' 2>/dev/null | base64 -d || echo "admin")
        MINIO_PASS=$(kubectl get secret minio-credentials -n "$NAMESPACE" \\
            -o jsonpath='{.data.root-password}' 2>/dev/null | base64 -d || echo "Not found")
        
        echo -e "Username: ${GREEN}$MINIO_USER${NC}"
        echo -e "Password: ${GREEN}$MINIO_PASS${NC}"
        echo ""
        ;;
    
    mailpit)
        if [ -z "$NAMESPACE" ]; then
            echo -e "${RED}Error: Namespace required for Mailpit${NC}"
            echo "Usage: $0 mailpit <namespace>"
            exit 1
        fi
        
        SVC_NAME="mailpit"
        LOCAL_PORT=8025
        REMOTE_PORT=8025
        URL="http://localhost:${LOCAL_PORT}"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  Mailpit UI Access${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}No authentication required (dev/staging only)${NC}"
        echo ""
        ;;
    
    *)
        echo -e "${RED}Error: Unknown service '$SERVICE'${NC}"
        usage
        ;;
esac

# Check service exists
if ! kubectl get svc "$SVC_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: Service '$SVC_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo ""
    echo "Check if service is deployed:"
    echo "  kubectl get svc -n $NAMESPACE"
    exit 1
fi

echo -e "${YELLOW}Starting port-forward...${NC}"
echo -e "URL: ${GREEN}$URL${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Start port-forward
kubectl port-forward -n "$NAMESPACE" "svc/$SVC_NAME" "${LOCAL_PORT}:${REMOTE_PORT}"
