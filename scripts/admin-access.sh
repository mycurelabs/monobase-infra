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

# Command-line arguments
OPT_KUBECONFIG=""

# Usage
usage() {
    echo "Usage: $0 [--kubeconfig <path>] <service> [namespace]"
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
    echo "  $0 --kubeconfig ~/.kube/mycure-doks-main argocd"
    echo "  $0 grafana"
    echo "  $0 --kubeconfig ~/.kube/mycure-doks-main minio myclient-prod"
    echo ""
    exit 1
}

# Select kubeconfig
select_kubeconfig() {
    # If kubeconfig provided via flag, use it directly
    if [ -n "$OPT_KUBECONFIG" ]; then
        if [ ! -f "$OPT_KUBECONFIG" ]; then
            echo -e "${RED}Error: Kubeconfig file not found: $OPT_KUBECONFIG${NC}"
            return 1
        fi
        export KUBECONFIG="$OPT_KUBECONFIG"
        echo -e "${BLUE}Using kubeconfig: $KUBECONFIG${NC}"
        return 0
    fi
    
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Select Kubernetes Cluster${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # Find all kubeconfig files
    local kubeconfigs=()
    local kubeconfig_paths=()

    # Check default location
    if [ -f "${HOME}/.kube/config" ]; then
        kubeconfigs+=("Default (~/.kube/config)")
        kubeconfig_paths+=("${HOME}/.kube/config")
    fi

    # Check ~/.kube/ directory for other configs
    if [ -d "${HOME}/.kube" ]; then
        while IFS= read -r file; do
            local basename=$(basename "$file")
            # Skip default config (already added), directories, and backup files
            if [ "$file" != "${HOME}/.kube/config" ] && [ -f "$file" ] && [[ ! "$basename" =~ \.backup\. ]]; then
                kubeconfigs+=("$basename")
                kubeconfig_paths+=("$file")
            fi
        done < <(find "${HOME}/.kube" -maxdepth 1 -type f 2>/dev/null | sort)
    fi

    if [ ${#kubeconfigs[@]} -eq 0 ]; then
        echo -e "${RED}Error: No kubeconfig files found${NC}"
        echo -e "${BLUE}Create a cluster first or set KUBECONFIG environment variable${NC}"
        return 1
    fi

    # Check if fzf is available
    if command -v fzf &>/dev/null; then
        # Build display list with current KUBECONFIG marker
        local display_list=()
        local current_kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}"
        
        for i in "${!kubeconfigs[@]}"; do
            local marker="  "
            if [ "${kubeconfig_paths[$i]}" = "$current_kubeconfig" ]; then
                marker="* "
            fi
            display_list+=("${marker}${kubeconfigs[$i]}")
        done
        
        # Add special options
        display_list+=("  Use current KUBECONFIG (${KUBECONFIG:-not set})")
        display_list+=("  Exit")
        
        # Use fzf for selection
        local selected
        selected=$(printf '%s\n' "${display_list[@]}" | fzf \
            --height=15 \
            --border \
            --prompt="Select Kubeconfig: " \
            --header="* = current | TAB to select | ESC to cancel" \
            --ansi)
        
        if [ -z "$selected" ]; then
            echo -e "${RED}No kubeconfig selected${NC}"
            return 1
        fi
        
        # Handle selection
        if [[ "$selected" == *"Exit"* ]]; then
            exit 0
        elif [[ "$selected" == *"Use current KUBECONFIG"* ]]; then
            if [ -z "${KUBECONFIG:-}" ]; then
                echo -e "${YELLOW}KUBECONFIG not set, using kubectl default${NC}"
            fi
        else
            # Extract kubeconfig name (remove marker)
            local selected_name="${selected:2}"
            
            # Find matching kubeconfig path
            for i in "${!kubeconfigs[@]}"; do
                if [ "${kubeconfigs[$i]}" = "$selected_name" ]; then
                    export KUBECONFIG="${kubeconfig_paths[$i]}"
                    echo -e "${GREEN}Using kubeconfig: ${KUBECONFIG}${NC}"
                    break
                fi
            done
        fi
        
    else
        # Fallback to numbered menu if fzf not available
        echo -e "${YELLOW}fzf not found. Using numbered menu.${NC}"
        echo
        
        # Display options
        echo "Available clusters:"
        for i in "${!kubeconfigs[@]}"; do
            local marker="  "
            if [ -n "${KUBECONFIG:-}" ] && [ "${kubeconfig_paths[$i]}" = "$KUBECONFIG" ]; then
                marker="* "
            fi
            echo "  ${marker}$((i + 1)). ${kubeconfigs[$i]}"
        done
        echo "  $((${#kubeconfigs[@]} + 1)). Use current KUBECONFIG (${KUBECONFIG:-not set})"
        echo "  $((${#kubeconfigs[@]} + 2)). Exit"
        echo
        
        # Prompt for selection
        read -rp "Select cluster (1-$((${#kubeconfigs[@]} + 2))): " choice
        
        if [ "$choice" -eq $((${#kubeconfigs[@]} + 2)) ]; then
            exit 0
        elif [ "$choice" -eq $((${#kubeconfigs[@]} + 1)) ]; then
            if [ -z "${KUBECONFIG:-}" ]; then
                echo -e "${YELLOW}KUBECONFIG not set, using kubectl default${NC}"
            fi
        elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#kubeconfigs[@]} ]; then
            export KUBECONFIG="${kubeconfig_paths[$((choice - 1))]}"
            echo -e "${GREEN}Using kubeconfig: ${KUBECONFIG}${NC}"
        else
            echo -e "${RED}Invalid selection${NC}"
            return 1
        fi
    fi
    
    # Verify cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to cluster${NC}"
        echo -e "${BLUE}Kubeconfig: ${KUBECONFIG:-not set}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Connected to cluster: $(kubectl config current-context)${NC}"
    echo
}

# Verify kubectl context
verify_context() {
    # Skip verification if namespace is explicitly provided or kubeconfig was specified
    if [ -n "$2" ] || [ -n "$OPT_KUBECONFIG" ]; then
        return 0
    fi
    
    # Get current context
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null)
    
    if [ -z "$CURRENT_CONTEXT" ]; then
        echo -e "${RED}Error: No kubectl context is set${NC}"
        echo "Please configure your kubectl context first."
        exit 1
    fi
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Context Verification${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Current context: ${GREEN}$CURRENT_CONTEXT${NC}"
    echo ""
    
    # Prompt for confirmation
    read -p "Continue with this context? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}Available contexts:${NC}"
        kubectl config get-contexts
        echo ""
        echo -e "${YELLOW}To switch context, use:${NC}"
        echo "  kubectl config use-context <context-name>"
        echo ""
        exit 0
    fi
    
    echo ""
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --kubeconfig)
            OPT_KUBECONFIG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [ $# -lt 1 ]; then
    usage
fi

SERVICE=$1
NAMESPACE=${2:-""}

# Select kubeconfig (interactive if not provided)
select_kubeconfig || exit 1

# Verify context before proceeding (skip if namespace is provided)
verify_context "$SERVICE" "$NAMESPACE"

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
        PASSWORD=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
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
        PASSWORD=$(kubectl -n "$NAMESPACE" get secret grafana-credentials \
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
        MINIO_USER=$(kubectl get secret minio-credentials -n "$NAMESPACE" \
            -o jsonpath='{.data.root-user}' 2>/dev/null | base64 -d || echo "admin")
        MINIO_PASS=$(kubectl get secret minio-credentials -n "$NAMESPACE" \
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
