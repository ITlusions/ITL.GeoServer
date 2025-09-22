# GeoServer HTTPS Configuration Guide

This guide provides detailed instructions for configuring HTTPS in your GeoServer Helm deployment.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Method 1: Using Ingress with cert-manager (Recommended)](#method-1-using-ingress-with-cert-manager-recommended)
4. [Method 2: Using Application-Level HTTPS](#method-2-using-application-level-https)
5. [Method 3: Self-Signed Certificates](#method-3-self-signed-certificates)
6. [Testing HTTPS Configuration](#testing-https-configuration)
7. [Troubleshooting](#troubleshooting)

## Overview

There are several ways to enable HTTPS for GeoServer in Kubernetes:

1. **Ingress-level HTTPS** (Recommended): TLS termination at the ingress controller
2. **Application-level HTTPS**: TLS termination at the GeoServer container
3. **Self-signed certificates**: For development and testing

## Prerequisites

- Kubernetes cluster with ingress controller (nginx recommended)
- Helm 3.x installed
- kubectl configured to access your cluster
- cert-manager installed (for automatic certificate management)

### Installing cert-manager

```bash
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
helm repo update

# Install cert-manager
kubectl create namespace cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.0 \
  --set installCRDs=true
```

## Method 1: Using Ingress with cert-manager (Recommended)

This method uses cert-manager to automatically obtain and renew SSL certificates from Let's Encrypt.

### Step 1: Create ClusterIssuer

```bash
# Use the provided script
./create-ssl.sh cert-manager

# Or create manually
cat > letsencrypt-clusterissuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: your-email@example.com  # Change this
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

kubectl apply -f letsencrypt-clusterissuer.yaml
```

### Step 2: Configure values.yaml

```yaml
# values-production.yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: geoserver.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: geoserver-letsencrypt-tls
      hosts:
        - geoserver.yourdomain.com

# Keep application-level HTTPS disabled
https:
  enabled: false
```

### Step 3: Deploy GeoServer

```bash
./deploy.sh prod
# or
helm install geoserver ./geoserver-chart -f values-production.yaml
```

### Step 4: Verify Certificate

```bash
# Check certificate status
kubectl get certificate -n geoserver
kubectl describe certificate geoserver-letsencrypt-tls -n geoserver

# Check ingress
kubectl get ingress -n geoserver
```

## Method 2: Using Application-Level HTTPS

This method configures HTTPS directly in the GeoServer application using a Java keystore.

### Step 1: Create SSL Certificate and Keystore

#### Option A: From existing PEM files
```bash
./create-ssl.sh from-pem -c your-cert.pem -k your-key.pem -p your-password
```

#### Option B: Create self-signed certificate
```bash
./create-ssl.sh self-signed -d geoserver.yourdomain.com -p your-password
```

### Step 2: Create Kubernetes Secret

```bash
kubectl create secret generic geoserver-https \
  --from-file=keystore.jks=keystore.jks \
  --from-literal=keystorePassword=your-password \
  --namespace geoserver
```

### Step 3: Configure values.yaml

```yaml
# Enable application-level HTTPS
https:
  enabled: true
  keystoreSecret: "geoserver-https"
  keystorePassword: "your-password"
  keyAlias: "server"

# Configure service to expose HTTPS port
service:
  type: ClusterIP
  port: 8080
  httpsPort: 8443

# Configure ingress for HTTPS backend
ingress:
  enabled: true
  className: "nginx"
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  hosts:
    - host: geoserver.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: geoserver-tls
      hosts:
        - geoserver.yourdomain.com
```

### Step 4: Deploy GeoServer

```bash
helm install geoserver ./geoserver-chart -f your-values.yaml
```

## Method 3: Self-Signed Certificates

For development and testing environments.

### Step 1: Create Self-Signed Certificate

```bash
./create-ssl.sh self-signed -d geoserver.local
```

### Step 2: Create Kubernetes Secret

```bash
kubectl apply -f geoserver-https-secret.yaml
```

### Step 3: Deploy with Development Values

```yaml
# values-development-https.yaml
https:
  enabled: true
  keystoreSecret: "geoserver-https"

ingress:
  enabled: true
  hosts:
    - host: geoserver.local
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: geoserver-https-tls
      hosts:
        - geoserver.local
```

### Step 4: Update /etc/hosts (for local testing)

```bash
echo "127.0.0.1 geoserver.local" | sudo tee -a /etc/hosts
```

## Testing HTTPS Configuration

### 1. Check Pod Status

```bash
kubectl get pods -n geoserver
kubectl logs -f deployment/geoserver -n geoserver
```

### 2. Test Internal Connectivity

```bash
kubectl port-forward service/geoserver 8080:8080 -n geoserver
curl -k https://localhost:8080/geoserver/web
```

### 3. Test External Access

```bash
curl -I https://geoserver.yourdomain.com/geoserver/web
```

### 4. Browser Testing

Open https://geoserver.yourdomain.com/geoserver/web in your browser.

### 5. SSL Certificate Verification

```bash
# Check certificate details
openssl s_client -connect geoserver.yourdomain.com:443 -servername geoserver.yourdomain.com

# Check certificate expiration
echo | openssl s_client -connect geoserver.yourdomain.com:443 -servername geoserver.yourdomain.com 2>/dev/null | openssl x509 -noout -dates
```

## Troubleshooting

### Common Issues

#### 1. Certificate Not Ready

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate events
kubectl describe certificate geoserver-letsencrypt-tls -n geoserver

# Check challenge status
kubectl get challenges -n geoserver
```

#### 2. Ingress SSL Issues

```bash
# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verify ingress configuration
kubectl describe ingress geoserver -n geoserver
```

#### 3. Application-Level HTTPS Issues

```bash
# Check GeoServer logs for SSL errors
kubectl logs deployment/geoserver -n geoserver | grep -i ssl

# Verify keystore mounting
kubectl exec deployment/geoserver -n geoserver -- ls -la /opt/
```

#### 4. DNS Resolution Issues

```bash
# Test DNS resolution
nslookup geoserver.yourdomain.com

# Check ingress external IP
kubectl get ingress geoserver -n geoserver
```

### Debug Commands

```bash
# Get all resources in geoserver namespace
kubectl get all -n geoserver

# Check secret contents (base64 encoded)
kubectl get secret geoserver-https -n geoserver -o yaml

# Test connectivity from within cluster
kubectl run test-pod --image=curlimages/curl -it --rm -- /bin/sh
# Then inside the pod:
curl -k https://geoserver.geoserver.svc.cluster.local:8080/geoserver/web
```

### Performance Considerations

1. **TLS Version**: Ensure TLS 1.2+ is used
2. **Cipher Suites**: Use strong cipher suites
3. **Certificate Chain**: Include intermediate certificates
4. **HSTS**: Enable HTTP Strict Transport Security

### Security Best Practices

1. **Regular Certificate Renewal**: Use cert-manager for automatic renewal
2. **Strong Passwords**: Use complex keystore passwords
3. **Secret Management**: Store sensitive data in Kubernetes secrets
4. **Network Policies**: Restrict network access to necessary ports
5. **Regular Updates**: Keep GeoServer and dependencies updated

### Monitoring HTTPS

```yaml
# Add to values.yaml for monitoring
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
```

## Additional Resources

- [GeoServer HTTPS Documentation](https://docs.geoserver.org/latest/en/user/installation/docker.html#https)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Kubernetes Ingress TLS](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
