#!/bin/bash

# Script to add keystore to GeoServer HTTPS secret
# This script helps add a JKS keystore file to the auto-generated HTTPS secret

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -k, --keystore      Path to keystore.jks file (required)"
    echo "  -n, --namespace     Kubernetes namespace (default: geoserver)"
    echo "  -r, --release       Helm release name (default: geoserver)"
    echo "  -s, --secret        Secret name (auto-detected if not provided)"
    echo "  --dry-run           Show what would be done without executing"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -k keystore.jks"
    echo "  $0 -k /path/to/keystore.jks -n production -r my-geoserver"
    echo "  $0 -k keystore.jks --dry-run"
    echo ""
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    log_info "Requirements check passed."
}

detect_secret_name() {
    local namespace=$1
    local release=$2
    
    # Try to find the HTTPS secret
    local secret_name="${release}-https"
    
    if kubectl get secret "$secret_name" -n "$namespace" &> /dev/null; then
        echo "$secret_name"
    else
        # Try alternative naming patterns
        local alt_names=(
            "${release}-geoserver-https"
            "geoserver-https"
            "${release}-https-keystore"
        )
        
        for name in "${alt_names[@]}"; do
            if kubectl get secret "$name" -n "$namespace" &> /dev/null; then
                echo "$name"
                return
            fi
        done
        
        log_error "Could not find HTTPS secret in namespace '$namespace'"
        log_info "Available secrets:"
        kubectl get secrets -n "$namespace" | grep -E "(https|keystore|tls)" || echo "  No HTTPS-related secrets found"
        exit 1
    fi
}

add_keystore_to_secret() {
    local keystore_file=$1
    local namespace=$2
    local secret_name=$3
    local dry_run=$4
    
    log_info "Adding keystore to secret..."
    log_info "Keystore file: $keystore_file"
    log_info "Namespace: $namespace"
    log_info "Secret: $secret_name"
    
    # Verify keystore file exists
    if [ ! -f "$keystore_file" ]; then
        log_error "Keystore file '$keystore_file' not found."
        exit 1
    fi
    
    # Verify secret exists
    if ! kubectl get secret "$secret_name" -n "$namespace" &> /dev/null; then
        log_error "Secret '$secret_name' not found in namespace '$namespace'."
        exit 1
    fi
    
    # Base64 encode the keystore file
    log_info "Encoding keystore file..."
    local keystore_b64=$(base64 -w 0 "$keystore_file")
    
    if [ "$dry_run" = "true" ]; then
        log_warn "DRY RUN: Would patch secret '$secret_name' with keystore data"
        echo "Command that would be executed:"
        echo "kubectl patch secret $secret_name -n $namespace --patch='{\"data\":{\"keystore.jks\":\"<base64-encoded-data>\"}}'"
        return
    fi
    
    # Patch the secret with the keystore
    log_info "Patching secret with keystore..."
    if kubectl patch secret "$secret_name" -n "$namespace" \
        --patch="{\"data\":{\"keystore.jks\":\"$keystore_b64\"}}" \
        --type=merge; then
        log_info "Keystore successfully added to secret!"
    else
        log_error "Failed to patch secret."
        exit 1
    fi
    
    # Verify the keystore was added
    log_info "Verifying keystore was added..."
    if kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.keystore\.jks}' &> /dev/null; then
        log_info "✓ Keystore verified in secret"
    else
        log_error "✗ Keystore not found in secret after patching"
        exit 1
    fi
    
    # Show secret status
    log_info "Secret contents:"
    kubectl get secret "$secret_name" -n "$namespace" -o custom-columns="NAME:.metadata.name,DATA KEYS:.data" --no-headers
}

restart_geoserver() {
    local namespace=$1
    local release=$2
    local dry_run=$3
    
    log_info "Restarting GeoServer deployment to pick up new keystore..."
    
    local deployment_name="${release}"
    
    if [ "$dry_run" = "true" ]; then
        log_warn "DRY RUN: Would restart deployment '$deployment_name'"
        return
    fi
    
    if kubectl get deployment "$deployment_name" -n "$namespace" &> /dev/null; then
        kubectl rollout restart deployment "$deployment_name" -n "$namespace"
        log_info "Waiting for deployment to be ready..."
        kubectl rollout status deployment "$deployment_name" -n "$namespace" --timeout=300s
        log_info "✓ GeoServer deployment restarted successfully"
    else
        log_warn "Deployment '$deployment_name' not found. You may need to restart manually."
    fi
}

# Parse command line arguments
KEYSTORE_FILE=""
NAMESPACE="geoserver"
RELEASE_NAME="geoserver"
SECRET_NAME=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--keystore)
            KEYSTORE_FILE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -s|--secret)
            SECRET_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check required parameters
if [ -z "$KEYSTORE_FILE" ]; then
    log_error "Keystore file not specified."
    print_usage
    exit 1
fi

# Main execution
log_info "Starting keystore addition process..."

check_requirements

# Auto-detect secret name if not provided
if [ -z "$SECRET_NAME" ]; then
    log_info "Auto-detecting secret name..."
    SECRET_NAME=$(detect_secret_name "$NAMESPACE" "$RELEASE_NAME")
    log_info "Detected secret: $SECRET_NAME"
fi

add_keystore_to_secret "$KEYSTORE_FILE" "$NAMESPACE" "$SECRET_NAME" "$DRY_RUN"

if [ "$DRY_RUN" != "true" ]; then
    restart_geoserver "$NAMESPACE" "$RELEASE_NAME" "$DRY_RUN"
    
    log_info "Process completed successfully!"
    log_info ""
    log_info "Next steps:"
    echo "1. Wait for GeoServer to start up completely"
    echo "2. Check the logs: kubectl logs -f deployment/$RELEASE_NAME -n $NAMESPACE"
    echo "3. Test HTTPS access to your GeoServer instance"
    echo "4. Update your ingress configuration if needed"
fi
