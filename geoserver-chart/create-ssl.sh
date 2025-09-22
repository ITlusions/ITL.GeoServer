#!/bin/bash

# SSL Certificate Helper Script for GeoServer
# This script helps create SSL certificates for GeoServer HTTPS deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "COMMANDS:"
    echo "  self-signed     Create a self-signed certificate"
    echo "  from-pem        Create keystore from existing PEM files"
    echo "  cert-manager    Create cert-manager ClusterIssuer"
    echo ""
    echo "OPTIONS for self-signed:"
    echo "  -d, --domain        Domain name (default: geoserver.local)"
    echo "  -p, --password      Keystore password (default: changeit)"
    echo "  -a, --alias         Key alias (default: server)"
    echo ""
    echo "OPTIONS for from-pem:"
    echo "  -c, --cert          Certificate PEM file path"
    echo "  -k, --key           Private key PEM file path"
    echo "  -p, --password      Keystore password (default: changeit)"
    echo "  -a, --alias         Key alias (default: server)"
    echo ""
    echo "Examples:"
    echo "  $0 self-signed -d geoserver.example.com"
    echo "  $0 from-pem -c cert.pem -k key.pem"
    echo "  $0 cert-manager"
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

check_openssl() {
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install OpenSSL first."
        exit 1
    fi
}

check_keytool() {
    if ! command -v keytool &> /dev/null; then
        log_error "keytool is not installed. Please install Java first."
        exit 1
    fi
}

create_self_signed() {
    local domain=$1
    local password=$2
    local alias=$3
    
    log_info "Creating self-signed certificate for domain: $domain"
    
    check_openssl
    check_keytool
    
    # Create private key
    log_info "Creating private key..."
    openssl genrsa -out server.key 2048
    
    # Create certificate signing request
    log_info "Creating certificate signing request..."
    openssl req -new -key server.key -out server.csr -subj "/CN=$domain/O=GeoServer/C=US"
    
    # Create certificate extensions
    cat > server.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF
    
    # Create self-signed certificate
    log_info "Creating self-signed certificate..."
    openssl x509 -req -in server.csr -signkey server.key -out server.crt -days 365 -extensions v3_req -extfile server.ext
    
    # Create PKCS12 keystore
    log_info "Creating PKCS12 keystore..."
    openssl pkcs12 -export -in server.crt -inkey server.key -out keystore.p12 -name "$alias" -password pass:"$password"
    
    # Convert to JKS keystore
    log_info "Converting to JKS keystore..."
    keytool -importkeystore -srckeystore keystore.p12 -srcstoretype PKCS12 -destkeystore keystore.jks -deststoretype JKS -srcstorepass "$password" -deststorepass "$password" -noprompt
    
    # Clean up temporary files
    rm -f server.csr server.ext keystore.p12
    
    log_info "Certificate created successfully!"
    log_info "Files created:"
    echo "  - keystore.jks (Java KeyStore)"
    echo "  - server.crt (Certificate)"
    echo "  - server.key (Private Key)"
    
    create_k8s_secret "$password"
}

create_from_pem() {
    local cert_file=$1
    local key_file=$2
    local password=$3
    local alias=$4
    
    log_info "Creating keystore from PEM files..."
    log_info "Certificate: $cert_file"
    log_info "Private Key: $key_file"
    
    check_openssl
    check_keytool
    
    # Verify files exist
    if [ ! -f "$cert_file" ]; then
        log_error "Certificate file '$cert_file' not found."
        exit 1
    fi
    
    if [ ! -f "$key_file" ]; then
        log_error "Private key file '$key_file' not found."
        exit 1
    fi
    
    # Create PKCS12 keystore
    log_info "Creating PKCS12 keystore..."
    openssl pkcs12 -export -in "$cert_file" -inkey "$key_file" -out keystore.p12 -name "$alias" -password pass:"$password"
    
    # Convert to JKS keystore
    log_info "Converting to JKS keystore..."
    keytool -importkeystore -srckeystore keystore.p12 -srcstoretype PKCS12 -destkeystore keystore.jks -deststoretype JKS -srcstorepass "$password" -deststorepass "$password" -noprompt
    
    # Clean up
    rm -f keystore.p12
    
    log_info "Keystore created successfully!"
    log_info "File created: keystore.jks"
    
    create_k8s_secret "$password"
}

create_k8s_secret() {
    local password=$1
    
    if [ -f "keystore.jks" ]; then
        log_info "Creating Kubernetes secret..."
        
        # Base64 encode the keystore
        local keystore_b64=$(base64 -w 0 keystore.jks)
        local password_b64=$(echo -n "$password" | base64 -w 0)
        
        cat > geoserver-https-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: geoserver-https
  namespace: geoserver
type: Opaque
data:
  keystore.jks: $keystore_b64
  keystorePassword: $password_b64
EOF
        
        log_info "Kubernetes secret template created: geoserver-https-secret.yaml"
        log_info "Apply it with: kubectl apply -f geoserver-https-secret.yaml"
    fi
}

create_cert_manager_issuer() {
    log_info "Creating cert-manager ClusterIssuer for Let's Encrypt..."
    
    cat > letsencrypt-clusterissuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Change this to your email address
    email: admin@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    # Change this to your email address
    email: admin@example.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
    
    log_info "ClusterIssuer template created: letsencrypt-clusterissuer.yaml"
    log_info "Update the email address and apply with: kubectl apply -f letsencrypt-clusterissuer.yaml"
    
    cat > cert-manager-certificate.yaml << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: geoserver-tls
  namespace: geoserver
spec:
  secretName: geoserver-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - geoserver.example.com  # Change this to your domain
EOF
    
    log_info "Certificate template created: cert-manager-certificate.yaml"
    log_info "Update the domain name and apply with: kubectl apply -f cert-manager-certificate.yaml"
}

# Parse command line arguments
COMMAND=""
DOMAIN="geoserver.local"
PASSWORD="changeit"
ALIAS="server"
CERT_FILE=""
KEY_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        self-signed|from-pem|cert-manager)
            COMMAND="$1"
            shift
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -a|--alias)
            ALIAS="$2"
            shift 2
            ;;
        -c|--cert)
            CERT_FILE="$2"
            shift 2
            ;;
        -k|--key)
            KEY_FILE="$2"
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

# Check if command is specified
if [ -z "$COMMAND" ]; then
    log_error "Command not specified."
    print_usage
    exit 1
fi

# Execute command
case $COMMAND in
    "self-signed")
        create_self_signed "$DOMAIN" "$PASSWORD" "$ALIAS"
        ;;
    "from-pem")
        if [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
            log_error "Certificate and key files must be specified for from-pem command."
            exit 1
        fi
        create_from_pem "$CERT_FILE" "$KEY_FILE" "$PASSWORD" "$ALIAS"
        ;;
    "cert-manager")
        create_cert_manager_issuer
        ;;
    *)
        log_error "Invalid command: $COMMAND"
        exit 1
        ;;
esac
