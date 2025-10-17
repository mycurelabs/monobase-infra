#!/usr/bin/env bash
# SOPS + age Provider for Secrets Management
# Implements Git-encrypted secrets using SOPS and age

set -euo pipefail

# This script is sourced by secrets.sh, which provides:
# - SCRIPT_DIR, REPO_ROOT
# - log_* functions
# - check_command, select_kubeconfig, check_kubeconfig
# - collect_tls_config, template_clusterissuers, update_infrastructure_values

setup_sops() {
    log_info "Setting up SOPS + age encryption..."

    # Check required commands
    check_command sops || return 1
    check_command age || return 1

    # Select cluster
    select_kubeconfig || return 1
    check_kubeconfig || return 1

    # Check if age key exists
    AGE_KEY_FILE="${REPO_ROOT}/age.agekey"

    if [ -f "$AGE_KEY_FILE" ]; then
        log_warn "Age key already exists at: $AGE_KEY_FILE"
        read -rp "Use existing key? (y/n): " use_existing
        if [[ ! "$use_existing" =~ ^[Yy]$ ]]; then
            log_warn "Removing old age key..."
            rm -f "$AGE_KEY_FILE"
            log_info "Generating new age keypair..."
            age-keygen -o "$AGE_KEY_FILE"
            log_success "Generated new age keypair"
        fi
    else
        log_info "Generating age keypair..."
        age-keygen -o "$AGE_KEY_FILE"
        log_success "Generated age keypair at: $AGE_KEY_FILE"
    fi

    # Extract public key
    AGE_PUBLIC_KEY=$(grep "# public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
    log_info "Age public key: $AGE_PUBLIC_KEY"

    # Update .sops.yaml
    log_info "Updating .sops.yaml with age public key..."
    sed -i "s/AGE_PUBLIC_KEY_PLACEHOLDER/$AGE_PUBLIC_KEY/g" "${REPO_ROOT}/.sops.yaml"
    log_success "Updated .sops.yaml"

    # Collect TLS configuration
    collect_tls_config

    # Create bootstrap secret in cluster
    log_info "Creating sops-age-key secret in cert-manager namespace..."
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic sops-age-key \
        --from-file=age.agekey="$AGE_KEY_FILE" \
        --namespace=cert-manager \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "Created sops-age-key secret"

    # Encrypt Cloudflare token
    encrypt_cloudflare_token_sops

    # Update ExternalSecrets configuration
    log_info "Updating External Secrets configuration for SOPS..."
    update_infrastructure_values "sops"

    # Template ClusterIssuers
    template_clusterissuers

    log_success "SOPS setup complete!"
    show_next_steps_sops
}

encrypt_cloudflare_token_sops() {
    log_info "Encrypting Cloudflare API token..."

    # Use temp file with .enc.yaml extension so SOPS can match rules
    TEMP_FILE="${REPO_ROOT}/infrastructure/tls/.cloudflare-token-temp.enc.yaml"
    OUTPUT_FILE="${REPO_ROOT}/infrastructure/tls/cloudflare-token.enc.yaml"

    # Create plaintext secret in temp file
    cat > "$TEMP_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: "${CLOUDFLARE_API_TOKEN}"
EOF

    # Encrypt in-place (SOPS will match .enc.yaml pattern from filename)
    sops --encrypt --in-place "$TEMP_FILE"

    # Move to final location
    mv "$TEMP_FILE" "$OUTPUT_FILE"

    log_success "Encrypted Cloudflare API token to $OUTPUT_FILE"
}

show_next_steps_sops() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " Next Steps"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_success "SOPS setup complete!"
    echo
    echo "1. Backup your age private key securely:"
    echo "   ${REPO_ROOT}/age.agekey"
    echo
    echo "2. Commit the encrypted files to Git:"
    echo "   git add ."
    echo "   git commit -m \"feat: Add TLS certificate automation with SOPS\""
    echo "   git push"
    echo
    echo "3. Wait for ArgoCD to sync (or trigger manually)"
    echo
    echo "4. Verify ClusterIssuer is ready:"
    echo "   kubectl get clusterissuer"
    echo
    echo "5. Check certificate provisioning:"
    echo "   kubectl get certificate -n gateway-system"
    echo
}
