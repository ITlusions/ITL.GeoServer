#!/bin/bash

# GeoServer Helm Chart Installation Script
# This script helps deploy GeoServer with different configurations

set -e

CHART_DIR="./geoserver-chart"
NAMESPACE="geoserver"
RELEASE_NAME="geoserver"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [ENVIRONMENT] [OPTIONS]"
    echo ""
    echo "ENVIRONMENT:"
    echo "  dev         Deploy with development configuration"
    echo "  prod        Deploy with production configuration"
    echo "  custom      Deploy with custom values file"
    echo ""
    echo "OPTIONS:"
    echo "  -n, --namespace     Kubernetes namespace (default: geoserver)"
    echo "  -r, --release       Helm release name (default: geoserver)"
    echo "  -f, --values-file   Custom values file path"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 prod -n production"
    echo "  $0 custom -f my-values.yaml"
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
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check if chart directory exists
    if [ ! -d "$CHART_DIR" ]; then
        log_error "Chart directory '$CHART_DIR' not found."
        exit 1
    fi
    
    log_info "Requirements check passed."
}

create_namespace() {
    log_info "Creating namespace '$NAMESPACE' if it doesn't exist..."
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

deploy_geoserver() {
    local environment=$1
    local values_file=$2
    
    log_info "Deploying GeoServer with $environment configuration..."
    
    case $environment in
        "dev")
            values_file="$CHART_DIR/values-development.yaml"
            ;;
        "prod")
            values_file="$CHART_DIR/values-production.yaml"
            log_warn "Production deployment detected. Make sure to:"
            log_warn "1. Change default admin password"
            log_warn "2. Configure proper SSL certificates"
            log_warn "3. Set up database credentials"
            ;;
        "custom")
            if [ -z "$values_file" ]; then
                log_error "Custom values file not specified."
                exit 1
            fi
            ;;
        *)
            log_error "Invalid environment: $environment"
            exit 1
            ;;
    esac
    
    if [ ! -f "$values_file" ]; then
        log_error "Values file '$values_file' not found."
        exit 1
    fi
    
    # Deploy using Helm
    helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
        --namespace "$NAMESPACE" \
        --values "$values_file" \
        --wait \
        --timeout 600s
    
    if [ $? -eq 0 ]; then
        log_info "GeoServer deployed successfully!"
        log_info "Release: $RELEASE_NAME"
        log_info "Namespace: $NAMESPACE"
        echo ""
        log_info "Getting deployment status..."
        helm status "$RELEASE_NAME" -n "$NAMESPACE"
    else
        log_error "Deployment failed!"
        exit 1
    fi
}

show_access_info() {
    log_info "Access Information:"
    echo ""
    
    # Get ingress information
    INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    
    if [ -n "$INGRESS_HOST" ]; then
        log_info "GeoServer URL: https://$INGRESS_HOST/geoserver"
        log_info "Web Interface: https://$INGRESS_HOST/geoserver/web"
        log_info "REST API: https://$INGRESS_HOST/geoserver/rest"
    else
        log_info "Use port-forward to access GeoServer:"
        echo "  kubectl port-forward -n $NAMESPACE service/$RELEASE_NAME 8080:8080"
        echo "  Then visit: http://localhost:8080/geoserver"
    fi
    
    echo ""
    log_warn "Default credentials: admin/geoserver"
    log_warn "Please change the default password immediately!"
}

# Parse command line arguments
ENVIRONMENT=""
CUSTOM_VALUES_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|prod|custom)
            ENVIRONMENT="$1"
            shift
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values-file)
            CUSTOM_VALUES_FILE="$2"
            shift 2
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

# Check if environment is specified
if [ -z "$ENVIRONMENT" ]; then
    log_error "Environment not specified."
    print_usage
    exit 1
fi

# Main execution
log_info "Starting GeoServer deployment..."
log_info "Environment: $ENVIRONMENT"
log_info "Namespace: $NAMESPACE"
log_info "Release: $RELEASE_NAME"

check_requirements
create_namespace
deploy_geoserver "$ENVIRONMENT" "$CUSTOM_VALUES_FILE"
show_access_info

log_info "Deployment completed successfully!"
