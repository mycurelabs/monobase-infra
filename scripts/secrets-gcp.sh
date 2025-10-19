#!/usr/bin/env bash
# GCP Secret Manager Provider for Secrets Management
# Integrates with Google Cloud Secret Manager for secret storage

set -euo pipefail

# This script is sourced by secrets.sh, which provides:
# - SCRIPT_DIR, REPO_ROOT
# - log_* functions
# - check_command, select_kubeconfig, check_kubeconfig
# - collect_tls_config, template_clusterissuers, update_infrastructure_values

setup_gcp() {
    log_info "Setting up GCP Secret Manager..."

    # Check required commands
    check_command gcloud || {
        log_error "gcloud CLI not found"
        log_info "Install with: mise install gcloud"
        return 1
    }
    check_command kubectl || return 1

    # Select cluster
    select_kubeconfig || return 1
    check_kubeconfig || return 1

    # ===========================================================================
    # Step 1: Select GCP Project
    # ===========================================================================
    echo
    log_info "Selecting GCP project..."
    
    # Try to auto-detect project ID from existing ClusterSecretStore (idempotent)
    local SECRETSTORE_FILE="${REPO_ROOT}/infrastructure/external-secrets/gcp-secretstore.yaml"
    local DETECTED_PROJECT=""
    
    if [ -f "$SECRETSTORE_FILE" ]; then
        DETECTED_PROJECT=$(grep "projectID:" "$SECRETSTORE_FILE" | head -1 | sed 's/.*projectID: *"\?\([^"]*\)"\?.*/\1/' | tr -d ' ')
        
        # Check if value is real (not template like {{ PROJECT_ID }})
        if [[ ! "$DETECTED_PROJECT" =~ "{{" ]] && [ -n "$DETECTED_PROJECT" ]; then
            # If --project flag was provided, it takes precedence
            if [ -n "$OPT_GCP_PROJECT" ]; then
                if [ "$OPT_GCP_PROJECT" != "$DETECTED_PROJECT" ]; then
                    log_warning "Flag --project='$OPT_GCP_PROJECT' overrides detected project '$DETECTED_PROJECT'"
                fi
                PROJECT_ID="$OPT_GCP_PROJECT"
            else
                PROJECT_ID="$DETECTED_PROJECT"
                log_success "Using existing GCP project from ClusterSecretStore: $PROJECT_ID"
            fi
        fi
    fi
    
    # If not auto-detected and project provided via flag, use it directly
    if [ -z "${PROJECT_ID:-}" ] && [ -n "$OPT_GCP_PROJECT" ]; then
        # Verify project exists and user has access
        if ! gcloud projects describe "$OPT_GCP_PROJECT" &>/dev/null; then
            log_error "GCP project not found or no access: $OPT_GCP_PROJECT"
            log_info "Check project ID and your gcloud authentication"
            return 1
        fi
        PROJECT_ID="$OPT_GCP_PROJECT"
        log_info "Using GCP project: $PROJECT_ID"
    fi
    
    # If still not set, do interactive selection
    if [ -z "${PROJECT_ID:-}" ]; then
        # Interactive project selection
        # Get current default project
        CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
        
        # Check if fzf is available
        if command -v fzf &>/dev/null; then
        # Fetch all GCP projects
        log_info "Fetching available GCP projects..."
        
        # Build project list with formatting: "PROJECT_ID (NAME) [NUMBER]"
        PROJECTS_RAW=$(gcloud projects list --format="value(projectId,name,projectNumber)" 2>/dev/null)
        
        if [ -z "$PROJECTS_RAW" ]; then
            log_error "No GCP projects found. Check your gcloud authentication."
            return 1
        fi
        
        # Format projects for fzf display
        PROJECTS_FORMATTED=$(echo "$PROJECTS_RAW" | awk -v current="$CURRENT_PROJECT" '{
            project_id = $1
            project_name = $2
            project_number = $3
            # Reconstruct name if it has spaces (everything between project_id and project_number)
            for(i=2; i<NF; i++) {
                if(i==2) project_name = $i
                else project_name = project_name " " $i
            }
            project_number = $NF
            
            marker = (project_id == current) ? "* " : "  "
            printf "%s%-25s  %-30s  [%s]\n", marker, project_id, project_name, project_number
        }')
        
        # Use fzf for selection
        SELECTED=$(echo "$PROJECTS_FORMATTED" | fzf \
            --height=20 \
            --border \
            --prompt="Select GCP Project: " \
            --header="* = current default | TAB to select | ESC to cancel" \
            --preview='echo "Project Details:" && echo "" && echo "ID: {2}" && echo "Name: {3}" && echo "Number: {NF}" | sed "s/\[//g" | sed "s/\]//g"' \
            --preview-window=right:40% \
            --ansi)
        
        if [ -z "$SELECTED" ]; then
            log_error "No project selected"
            return 1
        fi
        
        # Extract project ID (second field, after the marker)
        PROJECT_ID=$(echo "$SELECTED" | awk '{print $2}')
        
    else
        # Fallback to numbered menu if fzf not available
        log_warn "fzf not found. Using numbered menu. Install with: mise install fzf"
        echo
        
        # Fetch all projects
        mapfile -t PROJECT_IDS < <(gcloud projects list --format="value(projectId)" 2>/dev/null)
        mapfile -t PROJECT_NAMES < <(gcloud projects list --format="value(name)" 2>/dev/null)
        
        if [ ${#PROJECT_IDS[@]} -eq 0 ]; then
            log_error "No GCP projects found. Check your gcloud authentication."
            return 1
        fi
        
        # Display numbered list
        echo "Available GCP Projects:"
        echo
        for i in "${!PROJECT_IDS[@]}"; do
            marker=""
            if [ "${PROJECT_IDS[$i]}" = "$CURRENT_PROJECT" ]; then
                marker=" (current)"
            fi
            echo "  $((i+1))) ${PROJECT_IDS[$i]} - ${PROJECT_NAMES[$i]}${marker}"
        done
        echo
        
        read -rp "Enter choice [1-${#PROJECT_IDS[@]}]: " choice
        
        if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#PROJECT_IDS[@]}" ]; then
            PROJECT_ID="${PROJECT_IDS[$((choice-1))]}"
        else
            log_error "Invalid choice"
            return 1
        fi
        fi
    fi  # End of interactive project selection

    # Set project
    gcloud config set project "$PROJECT_ID" &>/dev/null
    log_success "Project set to: $PROJECT_ID"

    # ===========================================================================
    # Step 2: Enable Secret Manager API
    # ===========================================================================
    echo
    log_info "Enabling Secret Manager API..."
    
    if gcloud services list --enabled --filter="name:secretmanager.googleapis.com" --format="value(name)" 2>/dev/null | grep -q secretmanager; then
        log_success "Secret Manager API already enabled"
    else
        gcloud services enable secretmanager.googleapis.com
        log_success "Enabled Secret Manager API"
    fi

    # ===========================================================================
    # Step 3: Collect TLS Configuration
    # ===========================================================================
    echo
    collect_tls_config

    # ===========================================================================
    # Step 4: Collect Cloudflare API Token
    # ===========================================================================
    echo
    log_info "Cloudflare API Token Configuration"
    echo
    
    # Check if secret already exists in GCP (idempotent)
    if gcloud secrets describe "infrastructure-cloudflare-api-token" --project="$PROJECT_ID" &>/dev/null; then
        log_success "Cloudflare API token already exists in GCP Secret Manager"
        log_info "Skipping token collection"
    else
        # Secret doesn't exist - need to collect it
        if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
            log_info "Using CLOUDFLARE_API_TOKEN from environment: ***masked***"
        elif [ ! -t 0 ]; then
            # Non-interactive mode without env var
            log_error "Cloudflare API token not found in GCP Secret Manager"
            log_error "CLOUDFLARE_API_TOKEN environment variable not set"
            log_error ""
            log_error "Please either:"
            log_error "  1. Set environment variable: export CLOUDFLARE_API_TOKEN='your-token'"
            log_error "  2. Run in interactive mode: bash scripts/secrets-gcp.sh"
            return 1
        else
            # Interactive mode - prompt for token
            read -rp "Enter your Cloudflare API token: " CLOUDFLARE_API_TOKEN
            export CLOUDFLARE_API_TOKEN
        fi
    fi

    # ===========================================================================
    # Step 5: Create Secrets in GCP
    # ===========================================================================
    echo
    log_info "Creating secrets in GCP Secret Manager..."

    # Create Cloudflare API token secret
    SECRET_NAME="infrastructure-cloudflare-api-token"
    
    # Check if secret exists in GCP Secret Manager (idempotent)
    if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_success "Secret '$SECRET_NAME' already exists in GCP Secret Manager, skipping"
    else
        # Secret doesn't exist - create it
        if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
            # Use environment variable or value from collect_tls_config
            echo -n "$CLOUDFLARE_API_TOKEN" | gcloud secrets create "$SECRET_NAME" \
                --data-file=- \
                --replication-policy="automatic" \
                --project="$PROJECT_ID"
            log_success "Created secret: $SECRET_NAME"
        elif [ ! -t 0 ]; then
            # Non-interactive mode without CLOUDFLARE_API_TOKEN set
            log_error "Secret not found in GCP and CLOUDFLARE_API_TOKEN environment variable not set"
            log_error "Please set CLOUDFLARE_API_TOKEN or run in interactive mode"
            return 1
        else
            # Interactive mode - CLOUDFLARE_API_TOKEN should be set from collect_tls_config
            echo -n "$CLOUDFLARE_API_TOKEN" | gcloud secrets create "$SECRET_NAME" \
                --data-file=- \
                --replication-policy="automatic" \
                --project="$PROJECT_ID"
            log_success "Created secret: $SECRET_NAME"
        fi
    fi

    # ===========================================================================
    # Step 6: Collect Google OAuth Credentials (Optional)
    # ===========================================================================
    echo
    log_info "Google OAuth Configuration (Optional)"
    echo "Google OAuth credentials enable SSO authentication in HapiHub."
    echo
    
    # Determine if user wants to setup Google OAuth
    SETUP_GOOGLE_OAUTH="${SETUP_GOOGLE_OAUTH:-}"
    
    if [ -z "$SETUP_GOOGLE_OAUTH" ]; then
        if [ ! -t 0 ]; then
            # Non-interactive mode - skip by default unless explicitly set
            log_info "Non-interactive mode: Skipping Google OAuth (set SETUP_GOOGLE_OAUTH=true to enable)"
            SETUP_GOOGLE_OAUTH="false"
        else
            # Interactive mode - ask user
            read -rp "Do you want to configure Google OAuth credentials? (y/N): " SETUP_GOOGLE_OAUTH
        fi
    fi
    
    if [[ "$SETUP_GOOGLE_OAUTH" =~ ^[Yy] ]] || [[ "$SETUP_GOOGLE_OAUTH" == "true" ]]; then
        # ===========================================================================
        # Select Deployments for Google OAuth
        # ===========================================================================
        
        # Get list of deployment directories (exclude examples and hidden)
        DEPLOYMENTS_LIST=$(find "${REPO_ROOT}/deployments" -mindepth 1 -maxdepth 1 -type d \
            -not -name 'example*' -not -name '_*' \
            -exec basename {} \; | sort)
        
        SELECTED_DEPLOYMENTS=()
        
        if [ -n "${GOOGLE_OAUTH_DEPLOYMENTS:-}" ]; then
            # Use deployments from environment variable
            IFS=',' read -ra SELECTED_DEPLOYMENTS <<< "$GOOGLE_OAUTH_DEPLOYMENTS"
            log_info "Using deployments from GOOGLE_OAUTH_DEPLOYMENTS: ${SELECTED_DEPLOYMENTS[*]}"
        elif [ ! -t 0 ]; then
            # Non-interactive mode without GOOGLE_OAUTH_DEPLOYMENTS
            log_error "GOOGLE_OAUTH_DEPLOYMENTS environment variable not set"
            log_error "Example: export GOOGLE_OAUTH_DEPLOYMENTS='mycure-staging,mycure-production'"
            return 1
        elif command -v fzf &>/dev/null; then
            # Interactive mode with fzf - multi-select
            local selected
            selected=$(echo "$DEPLOYMENTS_LIST" | fzf \
                --multi \
                --height=15 \
                --border \
                --prompt="Select deployments for Google OAuth: " \
                --header="TAB/Space to select | Enter to confirm | Esc to cancel")
            
            if [ -z "$selected" ]; then
                log_info "No deployments selected, skipping Google OAuth setup"
                SETUP_GOOGLE_OAUTH="false"
            else
                mapfile -t SELECTED_DEPLOYMENTS <<< "$selected"
            fi
        else
            # Fallback: numbered menu
            log_warn "fzf not found. Using numbered menu."
            echo
            echo "Available deployments:"
            echo "$DEPLOYMENTS_LIST" | nl
            echo
            read -rp "Enter deployment numbers (comma-separated, e.g., '1,3' or 'all'): " SELECTION
            
            if [ "$SELECTION" = "all" ]; then
                mapfile -t SELECTED_DEPLOYMENTS <<< "$DEPLOYMENTS_LIST"
            else
                IFS=',' read -ra INDICES <<< "$SELECTION"
                for idx in "${INDICES[@]}"; do
                    deployment=$(echo "$DEPLOYMENTS_LIST" | sed -n "${idx}p")
                    if [ -n "$deployment" ]; then
                        SELECTED_DEPLOYMENTS+=("$deployment")
                    fi
                done
            fi
        fi
        
        # ===========================================================================
        # Collect Google OAuth Credentials
        # ===========================================================================
        
        if [[ "$SETUP_GOOGLE_OAUTH" =~ ^[Yy] ]] || [[ "$SETUP_GOOGLE_OAUTH" == "true" ]]; then
            if [ "${#SELECTED_DEPLOYMENTS[@]}" -eq 0 ]; then
                log_warning "No deployments selected, skipping Google OAuth setup"
            else
                # Collect credentials (once for all deployments)
                if [ -n "${GOOGLE_CLIENT_ID:-}" ] && [ -n "${GOOGLE_CLIENT_SECRET:-}" ]; then
                    log_info "Using Google OAuth credentials from environment variables"
                elif [ ! -t 0 ]; then
                    log_error "GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables not set"
                    return 1
                else
                    echo
                    read -rp "Google Client ID: " GOOGLE_CLIENT_ID
                    read -rp "Google Client Secret: " GOOGLE_CLIENT_SECRET
                    export GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET
                fi
                
                # Create secrets for each selected deployment
                echo
                log_info "Creating Google OAuth secrets for selected deployments..."
                
                for deployment in "${SELECTED_DEPLOYMENTS[@]}"; do
                    GOOGLE_CLIENT_ID_SECRET="${deployment}-google-oauth-client-id"
                    GOOGLE_CLIENT_SECRET_SECRET="${deployment}-google-oauth-client-secret"
                    
                    # Create Client ID secret
                    if gcloud secrets describe "$GOOGLE_CLIENT_ID_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $GOOGLE_CLIENT_ID_SECRET"
                    else
                        echo -n "$GOOGLE_CLIENT_ID" | gcloud secrets create "$GOOGLE_CLIENT_ID_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $GOOGLE_CLIENT_ID_SECRET"
                    fi
                    
                    # Create Client Secret secret
                    if gcloud secrets describe "$GOOGLE_CLIENT_SECRET_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $GOOGLE_CLIENT_SECRET_SECRET"
                    else
                        echo -n "$GOOGLE_CLIENT_SECRET" | gcloud secrets create "$GOOGLE_CLIENT_SECRET_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $GOOGLE_CLIENT_SECRET_SECRET"
                    fi
                done
            fi
        fi
    else
        log_info "Skipping Google OAuth setup"
    fi

    # ===========================================================================
    # Step 6.5: Database Credentials (MongoDB, PostgreSQL, MinIO)
    # ===========================================================================
    echo
    log_info "Database Credentials Configuration"
    echo "Configure database credentials for deployments (MongoDB, PostgreSQL, MinIO)."
    echo
    
    # Determine if user wants to setup database credentials
    SETUP_DATABASE_CREDENTIALS="${SETUP_DATABASE_CREDENTIALS:-}"
    
    if [ -z "$SETUP_DATABASE_CREDENTIALS" ]; then
        if [ ! -t 0 ]; then
            # Non-interactive mode - skip by default unless explicitly set
            log_info "Non-interactive mode: Skipping database credentials (set SETUP_DATABASE_CREDENTIALS=true to enable)"
            SETUP_DATABASE_CREDENTIALS="false"
        else
            # Interactive mode - ask user
            read -rp "Do you want to configure database credentials? (y/N): " SETUP_DATABASE_CREDENTIALS
        fi
    fi
    
    if [[ "$SETUP_DATABASE_CREDENTIALS" =~ ^[Yy] ]] || [[ "$SETUP_DATABASE_CREDENTIALS" == "true" ]]; then
        # ===========================================================================
        # Select Deployments for Database Credentials
        # ===========================================================================
        
        # Get list of deployment directories (exclude examples and hidden)
        DEPLOYMENTS_LIST=$(find "${REPO_ROOT}/deployments" -mindepth 1 -maxdepth 1 -type d \
            -not -name 'example*' -not -name '_*' \
            -exec basename {} \; | sort)
        
        SELECTED_DB_DEPLOYMENTS=()
        
        if [ -n "${DATABASE_DEPLOYMENTS:-}" ]; then
            # Use deployments from environment variable
            IFS=',' read -ra SELECTED_DB_DEPLOYMENTS <<< "$DATABASE_DEPLOYMENTS"
            log_info "Using deployments from DATABASE_DEPLOYMENTS: ${SELECTED_DB_DEPLOYMENTS[*]}"
        elif [ ! -t 0 ]; then
            # Non-interactive mode without DATABASE_DEPLOYMENTS
            log_error "DATABASE_DEPLOYMENTS environment variable not set"
            log_error "Example: export DATABASE_DEPLOYMENTS='mycure-staging,mycure-production'"
            return 1
        elif command -v fzf &>/dev/null; then
            # Interactive mode with fzf - multi-select
            local selected
            selected=$(echo "$DEPLOYMENTS_LIST" | fzf \
                --multi \
                --height=15 \
                --border \
                --prompt="Select deployments for database credentials: " \
                --header="TAB/Space to select | Enter to confirm | Esc to cancel")
            
            if [ -z "$selected" ]; then
                log_info "No deployments selected, skipping database credentials setup"
                SETUP_DATABASE_CREDENTIALS="false"
            else
                mapfile -t SELECTED_DB_DEPLOYMENTS <<< "$selected"
            fi
        else
            # Fallback: numbered menu
            log_warn "fzf not found. Using numbered menu."
            echo
            echo "Available deployments:"
            echo "$DEPLOYMENTS_LIST" | nl
            echo
            read -rp "Enter deployment numbers (comma-separated, e.g., '1,3' or 'all'): " SELECTION
            
            if [ "$SELECTION" = "all" ]; then
                mapfile -t SELECTED_DB_DEPLOYMENTS <<< "$DEPLOYMENTS_LIST"
            else
                IFS=',' read -ra INDICES <<< "$SELECTION"
                for idx in "${INDICES[@]}"; do
                    deployment=$(echo "$DEPLOYMENTS_LIST" | sed -n "${idx}p")
                    if [ -n "$deployment" ]; then
                        SELECTED_DB_DEPLOYMENTS+=("$deployment")
                    fi
                done
            fi
        fi
        
        # ===========================================================================
        # Create Database Secrets
        # ===========================================================================
        
        if [[ "$SETUP_DATABASE_CREDENTIALS" =~ ^[Yy] ]] || [[ "$SETUP_DATABASE_CREDENTIALS" == "true" ]]; then
            if [ "${#SELECTED_DB_DEPLOYMENTS[@]}" -eq 0 ]; then
                log_warning "No deployments selected, skipping database credentials setup"
            else
                echo
                log_info "Creating database credential secrets for selected deployments..."
                
                for deployment in "${SELECTED_DB_DEPLOYMENTS[@]}"; do
                    echo
                    log_info "Configuring database credentials for: $deployment"
                    
                    # ===========================================================================
                    # MongoDB Credentials
                    # ===========================================================================
                    
                    # Collect MongoDB credentials
                    MONGODB_ROOT_PASSWORD="${MONGODB_ROOT_PASSWORD:-}"
                    MONGODB_REPLICA_SET_KEY="${MONGODB_REPLICA_SET_KEY:-}"
                    
                    if [ -z "$MONGODB_ROOT_PASSWORD" ] || [ -z "$MONGODB_REPLICA_SET_KEY" ]; then
                        if [ ! -t 0 ]; then
                            log_error "MONGODB_ROOT_PASSWORD and MONGODB_REPLICA_SET_KEY environment variables not set"
                            return 1
                        else
                            echo
                            log_info "MongoDB credentials:"
                            read -rp "  MongoDB root password: " MONGODB_ROOT_PASSWORD
                            read -rp "  MongoDB replica set key: " MONGODB_REPLICA_SET_KEY
                        fi
                    fi
                    
                    # Create MongoDB secrets
                    MONGODB_ROOT_PASSWORD_SECRET="${deployment}-mongodb-root-password"
                    MONGODB_REPLICA_SET_KEY_SECRET="${deployment}-mongodb-replica-set-key"
                    
                    if gcloud secrets describe "$MONGODB_ROOT_PASSWORD_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $MONGODB_ROOT_PASSWORD_SECRET"
                    else
                        echo -n "$MONGODB_ROOT_PASSWORD" | gcloud secrets create "$MONGODB_ROOT_PASSWORD_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $MONGODB_ROOT_PASSWORD_SECRET"
                    fi
                    
                    if gcloud secrets describe "$MONGODB_REPLICA_SET_KEY_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $MONGODB_REPLICA_SET_KEY_SECRET"
                    else
                        echo -n "$MONGODB_REPLICA_SET_KEY" | gcloud secrets create "$MONGODB_REPLICA_SET_KEY_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $MONGODB_REPLICA_SET_KEY_SECRET"
                    fi
                    
                    # ===========================================================================
                    # PostgreSQL Credentials
                    # ===========================================================================
                    
                    # Collect PostgreSQL credentials
                    POSTGRESQL_PASSWORD="${POSTGRESQL_PASSWORD:-}"
                    
                    if [ -z "$POSTGRESQL_PASSWORD" ]; then
                        if [ ! -t 0 ]; then
                            log_error "POSTGRESQL_PASSWORD environment variable not set"
                            return 1
                        else
                            echo
                            log_info "PostgreSQL credentials:"
                            read -rp "  PostgreSQL postgres password: " POSTGRESQL_PASSWORD
                        fi
                    fi
                    
                    # Create PostgreSQL secret
                    POSTGRESQL_PASSWORD_SECRET="${deployment}-postgresql-postgres-password"
                    
                    if gcloud secrets describe "$POSTGRESQL_PASSWORD_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $POSTGRESQL_PASSWORD_SECRET"
                    else
                        echo -n "$POSTGRESQL_PASSWORD" | gcloud secrets create "$POSTGRESQL_PASSWORD_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $POSTGRESQL_PASSWORD_SECRET"
                    fi
                    
                    # ===========================================================================
                    # MinIO Credentials
                    # ===========================================================================
                    
                    # Collect MinIO credentials
                    MINIO_ROOT_USER="${MINIO_ROOT_USER:-}"
                    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-}"
                    
                    if [ -z "$MINIO_ROOT_USER" ] || [ -z "$MINIO_ROOT_PASSWORD" ]; then
                        if [ ! -t 0 ]; then
                            log_error "MINIO_ROOT_USER and MINIO_ROOT_PASSWORD environment variables not set"
                            return 1
                        else
                            echo
                            log_info "MinIO credentials:"
                            read -rp "  MinIO root user: " MINIO_ROOT_USER
                            read -rp "  MinIO root password: " MINIO_ROOT_PASSWORD
                        fi
                    fi
                    
                    # Create MinIO secrets
                    MINIO_ROOT_USER_SECRET="${deployment}-minio-root-user"
                    MINIO_ROOT_PASSWORD_SECRET="${deployment}-minio-root-password"
                    
                    if gcloud secrets describe "$MINIO_ROOT_USER_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $MINIO_ROOT_USER_SECRET"
                    else
                        echo -n "$MINIO_ROOT_USER" | gcloud secrets create "$MINIO_ROOT_USER_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $MINIO_ROOT_USER_SECRET"
                    fi
                    
                    if gcloud secrets describe "$MINIO_ROOT_PASSWORD_SECRET" --project="$PROJECT_ID" &>/dev/null; then
                        log_success "Secret already exists: $MINIO_ROOT_PASSWORD_SECRET"
                    else
                        echo -n "$MINIO_ROOT_PASSWORD" | gcloud secrets create "$MINIO_ROOT_PASSWORD_SECRET" \
                            --data-file=- \
                            --replication-policy="automatic" \
                            --project="$PROJECT_ID"
                        log_success "Created secret: $MINIO_ROOT_PASSWORD_SECRET"
                    fi
                done
            fi
        fi
    else
        log_info "Skipping database credentials setup"
    fi

    # ===========================================================================
    # Step 7: Create GCP Service Account for External Secrets
    # ===========================================================================
    echo
    log_info "Setting up GCP Service Account..."

    GSA_NAME="external-secrets"
    GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$GSA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
        log_success "Service account $GSA_NAME already exists"
    else
        gcloud iam service-accounts create "$GSA_NAME" \
            --display-name="External Secrets Operator" \
            --project="$PROJECT_ID"
        log_success "Created service account: $GSA_NAME"
        
        # Wait for service account to propagate (GCP eventual consistency)
        log_info "Waiting for service account to propagate..."
        sleep 5
    fi

    # ===========================================================================
    # Step 8: Grant Secret Manager Access
    # ===========================================================================
    echo
    log_info "Granting Secret Manager access to service account..."

    # Retry logic for GCP propagation delays
    MAX_RETRIES=5
    RETRY_COUNT=0
    RETRY_DELAY=2
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${GSA_EMAIL}" \
            --role="roles/secretmanager.secretAccessor" \
            --condition=None \
            >/dev/null 2>&1; then
            log_success "Granted secretAccessor role to $GSA_NAME"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                log_info "Service account not yet propagated, retrying in ${RETRY_DELAY}s (attempt $RETRY_COUNT/$MAX_RETRIES)..."
                sleep $RETRY_DELAY
                RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
            else
                log_error "Failed to grant IAM role after $MAX_RETRIES attempts"
                log_error "Service account may still be propagating. Please run the script again in a few moments."
                return 1
            fi
        fi
    done

    # ===========================================================================
    # Step 9: Create Service Account Key (Idempotent)
    # ===========================================================================
    echo
    log_info "Creating service account key for authentication..."

    # Create directory for GCP keys
    KEY_DIR="$HOME/.gcp"
    KEY_FILE="${KEY_DIR}/external-secrets-${PROJECT_ID}.json"
    
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    
    # Check if key already exists
    if [ -f "$KEY_FILE" ]; then
        log_success "Service account key already exists at: $KEY_FILE"
    else
        log_info "Creating new service account key..."
        gcloud iam service-accounts keys create "$KEY_FILE" \
            --iam-account="${GSA_EMAIL}" \
            --project="$PROJECT_ID"
        
        chmod 600 "$KEY_FILE"
        log_success "Service account key created at: $KEY_FILE"
    fi

    # ===========================================================================
    # Step 10: Create Kubernetes Secret (Idempotent)
    # ===========================================================================
    echo
    log_info "Creating Kubernetes secret for External Secrets Operator..."

    # Namespace and secret for External Secrets Operator
    K8S_NAMESPACE="external-secrets-system"
    K8S_SECRET="gcpsm-secret"
    
    # Ensure namespace exists
    log_info "Ensuring namespace exists: $K8S_NAMESPACE"
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    # Check if secret already exists
    if kubectl get secret "$K8S_SECRET" -n "$K8S_NAMESPACE" &>/dev/null; then
        log_success "Kubernetes secret '$K8S_SECRET' already exists in namespace '$K8S_NAMESPACE'"
        log_info "To update the secret, delete it first:"
        log_info "  kubectl delete secret $K8S_SECRET -n $K8S_NAMESPACE"
    else
        log_info "Creating Kubernetes secret from service account key..."
        kubectl create secret generic "$K8S_SECRET" \
            --from-file=secret-access-credentials="$KEY_FILE" \
            -n "$K8S_NAMESPACE"
        
        log_success "Kubernetes secret '$K8S_SECRET' created in namespace '$K8S_NAMESPACE'"
    fi

    # ===========================================================================
    # Step 11: Generate ClusterSecretStore YAML
    # ===========================================================================
    echo
    log_info "Generating ClusterSecretStore manifest..."

    SECRETSTORE_FILE="${REPO_ROOT}/infrastructure/external-secrets/gcp-secretstore.yaml"

    cat > "$SECRETSTORE_FILE" <<EOF
# GCP Secret Manager ClusterSecretStore
# Provides access to secrets stored in Google Cloud Secret Manager
# Authentication: Service Account Key (works with any Kubernetes cluster)

apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: gcp-secretstore
  labels:
    app.kubernetes.io/name: gcp-secretstore
    app.kubernetes.io/component: external-secrets
spec:
  provider:
    gcpsm:
      projectID: "${PROJECT_ID}"
      
      # Authentication using Service Account Key
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: ${K8S_SECRET}
            key: secret-access-credentials
            namespace: ${K8S_NAMESPACE}
EOF

    log_success "Created ClusterSecretStore at: $SECRETSTORE_FILE"

    # ===========================================================================
    # Step 12: Create Cloudflare ExternalSecret
    # ===========================================================================
    echo
    log_info "Creating Cloudflare ExternalSecret manifest..."

    EXTERNALSECRET_FILE="${REPO_ROOT}/infrastructure/tls/cloudflare-token-externalsecret.yaml"

    cat > "$EXTERNALSECRET_FILE" <<EOF
# External Secret for Cloudflare API Token
# Syncs from GCP Secret Manager to Kubernetes Secret

apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
  labels:
    app.kubernetes.io/name: cloudflare-token
    app.kubernetes.io/component: tls
spec:
  # Refresh interval
  refreshInterval: 1h
  
  # Reference to ClusterSecretStore
  secretStoreRef:
    name: gcp-secretstore
    kind: ClusterSecretStore
  
  # Target Kubernetes secret
  target:
    name: cloudflare-api-token
    creationPolicy: Owner
  
  # Data mapping
  data:
    - secretKey: api-token
      remoteRef:
        key: infrastructure-cloudflare-api-token
EOF

    log_success "Created ExternalSecret at: $EXTERNALSECRET_FILE"

    # ===========================================================================
    # Step 13: Update Infrastructure Configuration
    # ===========================================================================
    echo
    update_infrastructure_values "gcp"

    # Template ClusterIssuers
    template_clusterissuers

    # ===========================================================================
    # Step 14: Show Next Steps
    # ===========================================================================
    show_next_steps_gcp
}

show_next_steps_gcp() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Next Steps"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_success "GCP Secret Manager setup complete!"
    echo
    echo "1. Review generated files:"
    echo "   - infrastructure/external-secrets/gcp-secretstore.yaml"
    echo "   - infrastructure/tls/cloudflare-token-externalsecret.yaml"
    echo
    echo "2. Commit the configuration to Git:"
    echo "   git add infrastructure/"
    echo "   git commit -m \"feat: Add GCP Secret Manager integration\""
    echo "   git push"
    echo
    echo "3. ArgoCD will automatically deploy External Secrets Operator"
    echo
    echo "4. Verify ClusterSecretStore is ready:"
    echo "   kubectl get clustersecretstore gcp-secretstore"
    echo
    echo "5. Check ExternalSecret sync status:"
    echo "   kubectl get externalsecret -n cert-manager"
    echo
    echo "6. Verify Kubernetes secret was created:"
    echo "   kubectl get secret cloudflare-api-token -n cert-manager"
    echo
    echo "7. Check certificate provisioning:"
    echo "   kubectl get certificate -n gateway-system"
    echo
    echo "Note: All secrets are now managed via GCP Secret Manager + GitOps!"
    echo
}
