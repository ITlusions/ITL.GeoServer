# GeoServer HTTPS Deployment Guide

This guide covers the different ways to deploy GeoServer with HTTPS support using the Helm chart.

## Quick Start - Automatic HTTPS

The easiest way to get HTTPS working is with automatic keystore generation:

```bash
# Deploy with automatic HTTPS
helm install geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.keystoreGenerator.domain=geoserver.yourdomain.com \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=geoserver.yourdomain.com
```

## HTTPS Configuration Methods

### Method 1: Job-Based Keystore Generation (Recommended)

This method generates the keystore once using a Kubernetes Job and stores it in a secret. The secret persists across pod restarts and upgrades.

**Advantages:**
- Keystore generated once and reused
- Password preserved across upgrades
- No delay on pod startup
- Certificate persists until secret is deleted

**Configuration:**
```yaml
https:
  enabled: true
  autoGenerateKeystore: true
  keystoreGenerator:
    useInitContainer: false  # Use job (default)
    domain: "geoserver.yourdomain.com"
    organization: "Your Organization"
    country: "US"
    validityDays: 365
```

**Deployment:**
```bash
helm install geoserver ./geoserver-chart -f your-values.yaml
```

### Method 2: Init Container Generation

This method generates a new keystore every time the pod starts. Useful for testing or when you want fresh certificates on each deployment.

**Advantages:**
- Always fresh certificates
- No external dependencies
- Simple setup

**Disadvantages:**
- Delay on every pod startup
- Certificate changes on pod restart
- Not suitable for production

**Configuration:**
```yaml
https:
  enabled: true
  autoGenerateKeystore: true
  keystoreGenerator:
    useInitContainer: true
    domain: "geoserver.yourdomain.com"
    organization: "Your Organization"
    validityDays: 365
```

### Method 3: Bring Your Own Keystore

Use your own JKS keystore file. This is recommended for production with proper CA-signed certificates.

**Steps:**

1. **Create or obtain your keystore:**
```bash
# Generate self-signed keystore
keytool -genkeypair -alias server -keyalg RSA -keysize 2048 \
  -validity 365 -keystore keystore.jks -storepass changeit \
  -dname "CN=geoserver.yourdomain.com,O=Your Org,C=US"

# Or import existing certificate
keytool -importkeystore -srckeystore your-cert.p12 -srcstoretype PKCS12 \
  -destkeystore keystore.jks -deststoretype JKS
```

2. **Create Kubernetes secret:**
```bash
kubectl create secret generic geoserver-keystore \
  --from-file=keystore.jks=keystore.jks \
  --from-literal=keystorePassword=changeit
```

3. **Configure chart:**
```yaml
https:
  enabled: true
  autoGenerateKeystore: false
  keystoreSecret: "geoserver-keystore"
  keystorePassword: "changeit"
```

### Method 4: HTTPS Port with Ingress-Only TLS

This method enables the HTTPS port in GeoServer but doesn't create any keystore. TLS termination happens entirely at the ingress level, and the ingress communicates with GeoServer over HTTP internally.

**Advantages:**
- Simplest configuration for ingress-based TLS
- No certificate management within GeoServer
- Automatic certificate renewal via cert-manager
- Better performance (TLS termination at edge)

**Use Cases:**
- Production deployments with ingress controllers
- Cloud environments with managed load balancers
- When using cert-manager for automatic certificates
- Microservices architectures with service mesh

**Configuration:**
```yaml
https:
  enabled: true              # Exposes HTTPS port 8443
  autoGenerateKeystore: false # No keystore creation
  keystoreSecret: ""         # No keystore needed

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # Backend uses HTTP
  hosts:
    - host: geoserver.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: geoserver-ingress-tls
      hosts:
        - geoserver.yourdomain.com
```

**Deployment:**
```bash
helm install geoserver ./geoserver-chart -f values-https-ingress-only.yaml
```

## Production Deployment Examples

### Example 1: Production with Let's Encrypt

```yaml
# values-production.yaml
https:
  enabled: true
  autoGenerateKeystore: true
  keystoreGenerator:
    domain: "geoserver.yourdomain.com"
    organization: "Your Company"
    country: "US"
    validityDays: 90  # Short validity, cert-manager will renew

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
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

resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 500m
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
```

**Deploy:**
```bash
helm install geoserver ./geoserver-chart -f values-production.yaml
```

### Example 2: Development with Self-Signed Certificate

```yaml
# values-development.yaml
https:
  enabled: true
  autoGenerateKeystore: true
  keystoreGenerator:
    domain: "geoserver.local"
    organization: "Development"
    validityDays: 30

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: geoserver.local
      paths:
        - path: /
          pathType: Prefix

# Add to /etc/hosts: 127.0.0.1 geoserver.local
```

**Deploy:**
```bash
helm install geoserver ./geoserver-chart -f values-development.yaml
```

### Example 3: Production with Ingress-Only TLS

This example shows a production setup where TLS termination happens only at the ingress level.

```yaml
# values-production-ingress-tls.yaml
https:
  enabled: true              # Enable HTTPS port
  autoGenerateKeystore: false # No internal keystore
  keystoreSecret: ""         # No keystore secret

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
  hosts:
    - host: geoserver.company.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: geoserver-production-tls
      hosts:
        - geoserver.company.com

resources:
  limits:
    cpu: 4000m
    memory: 8Gi
  requests:
    cpu: 1000m
    memory: 2Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 60

geoserver:
  persistence:
    enabled: true
    size: "100Gi"
    storageClass: "fast-ssd"
```

**Deploy:**
```bash
helm install geoserver ./geoserver-chart -f values-production-ingress-tls.yaml
```

## Certificate Management

### Viewing Certificate Information

```bash
# Get the keystore from the secret
kubectl get secret geoserver-https -o jsonpath='{.data.keystore\.jks}' | base64 -d > /tmp/keystore.jks

# View certificate details
keytool -list -v -keystore /tmp/keystore.jks -storepass $(kubectl get secret geoserver-https -o jsonpath='{.data.keystorePassword}' | base64 -d)
```

### Regenerating Certificates

**For Job-based generation:**
```bash
# Delete the secret to trigger regeneration
kubectl delete secret geoserver-https

# Upgrade the release to trigger the job
helm upgrade geoserver ./geoserver-chart -f your-values.yaml
```

**For Init container generation:**
```bash
# Simply restart the deployment
kubectl rollout restart deployment geoserver
```

### Certificate Renewal

For automatic renewal with cert-manager, configure your ingress with appropriate annotations:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    cert-manager.io/duration: "2160h"  # 90 days
    cert-manager.io/renew-before: "720h"  # 30 days before expiry
```

## Troubleshooting

### Common Issues

1. **Keystore Generation Job Fails**
```bash
# Check job logs
kubectl logs job/geoserver-keystore-generator

# Check RBAC permissions
kubectl auth can-i create secrets --as=system:serviceaccount:default:geoserver-keystore-generator
```

2. **HTTPS Port Not Accessible**
```bash
# Verify service has HTTPS port
kubectl get svc geoserver -o yaml

# Check if container is listening on HTTPS port
kubectl exec deployment/geoserver -- netstat -tulpn | grep 8443
```

3. **Certificate Errors in Browser**
   - For self-signed certificates, you'll need to accept the certificate warning
   - For production, use proper CA-signed certificates
   - Ensure the certificate domain matches your ingress hostname

4. **Init Container Timeout**
```bash
# Increase init container timeout in values.yaml
https:
  keystoreGenerator:
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
```

### Debug Commands

```bash
# Check if HTTPS is enabled in GeoServer
kubectl exec deployment/geoserver -- curl -k https://localhost:8443/geoserver/web/

# View GeoServer logs
kubectl logs deployment/geoserver

# Check ingress configuration
kubectl describe ingress geoserver

# Test HTTPS connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -k https://geoserver-service:8443/geoserver/web/
```

## Security Considerations

1. **Change Default Passwords**: Always change the default admin password
2. **Use Strong Certificates**: In production, use CA-signed certificates
3. **Network Policies**: Consider enabling network policies to restrict traffic
4. **Regular Updates**: Keep certificates updated before expiry
5. **Secret Management**: Protect keystore secrets with proper RBAC

## Performance Impact

- **Job-based generation**: Minimal performance impact after initial setup
- **Init container generation**: Adds 10-30 seconds to pod startup time
- **HTTPS overhead**: Typically 1-5% CPU overhead for SSL/TLS processing

## Migration Guide

### From HTTP to HTTPS

1. **Enable HTTPS in existing deployment:**
```bash
helm upgrade geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.autoGenerateKeystore=true \
  --set https.keystoreGenerator.domain=your-domain.com
```

2. **Update ingress to use HTTPS:**
```bash
helm upgrade geoserver ./geoserver-chart \
  --set ingress.tls[0].secretName=geoserver-tls \
  --set ingress.tls[0].hosts[0]=your-domain.com
```

3. **Test both HTTP and HTTPS work**
4. **Disable HTTP if needed:**
```bash
helm upgrade geoserver ./geoserver-chart \
  --set service.port=8443 \
  --set service.targetPort=https
```
