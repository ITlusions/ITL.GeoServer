# GeoServer Helm Chart

This Helm chart deploys GeoServer, an open-source geospatial server, on a Kubernetes cluster using the official Docker image from the GeoServer project.

## Features

- ✅ Official GeoServer Docker image (docker.osgeo.org/geoserver)
- ✅ HTTPS/TLS support with custom certificates
- ✅ Ingress configuration with cert-manager integration
- ✅ Persistent data storage
- ✅ PostgreSQL JNDI configuration
- ✅ Extension management (stable and community)
- ✅ Security hardening (non-root user, security contexts)
- ✅ Health checks and monitoring
- ✅ Horizontal Pod Autoscaling
- ✅ Network policies
- ✅ Prometheus ServiceMonitor support

## Quick Start

### 1. Basic Installation

```bash
helm install my-geoserver ./geoserver-chart
```

### 2. Installation with Custom Values

```bash
helm install my-geoserver ./geoserver-chart -f my-values.yaml
```

### 3. Installation with HTTPS

#### Option A: Auto-generated Secret (Recommended)
```bash
# Deploy with HTTPS enabled - secret will be auto-generated
helm install my-geoserver ./geoserver-chart \
  --set https.enabled=true

# Add your keystore to the auto-generated secret
./add-keystore.sh -k path/to/your/keystore.jks
```

#### Option B: Manual Secret Creation
```bash
# Create a secret with your SSL certificate
kubectl create secret generic geoserver-https \
  --from-file=keystore.jks=path/to/your/keystore.jks \
  --from-literal=keystorePassword=your-keystore-password

# Install with HTTPS enabled
helm install my-geoserver ./geoserver-chart \
  --set https.enabled=true \
  --set https.keystoreSecret=geoserver-https
```

## Configuration

### Basic Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of GeoServer replicas | `1` |
| `image.repository` | GeoServer image repository | `docker.osgeo.org/geoserver` |
| `image.tag` | GeoServer image tag | `2.27.2` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### GeoServer Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `geoserver.admin.username` | Admin username | `admin` |
| `geoserver.admin.autoGeneratePassword` | Auto-generate secure admin password | `true` |
| `geoserver.admin.password` | Admin password (when autoGenerate=false) | `""` |
| `geoserver.env.SKIP_DEMO_DATA` | Skip demo data installation | `false` |
| `geoserver.env.CORS_ENABLED` | Enable CORS | `true` |
| `geoserver.env.WEBAPP_CONTEXT` | Application context path | `geoserver` |

### HTTPS Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `https.enabled` | Enable HTTPS | `false` |
| `https.keystoreFile` | Path to keystore file | `/opt/keystore.jks` |
| `https.keystorePassword` | Keystore password | `changeit` |
| `https.keyAlias` | Key alias in keystore | `server` |
| `https.keystoreSecret` | Secret containing keystore | `""` |
| `https.manualSecretCreation` | Use manual secret creation | `false` |

#### Automatic Keystore Generation

| Parameter | Description | Default |
|-----------|-------------|---------|
| `https.autoGenerateKeystore` | Enable automatic keystore generation | `true` |
| `https.keystoreGenerator.secretName` | Override generated secret name | `""` |
| `https.keystoreGenerator.useInitContainer` | Use init container instead of job | `false` |
| `https.keystoreGenerator.domain` | Certificate domain name | `geoserver.local` |
| `https.keystoreGenerator.organization` | Certificate organization | `GeoServer` |
| `https.keystoreGenerator.country` | Certificate country code | `US` |
| `https.keystoreGenerator.validityDays` | Certificate validity in days | `365` |
| `https.keystoreGenerator.image` | Container image for generation | `docker.io/alpine/openssl:latest` |

#### HTTPS Setup Options

**Option 1: Automatic Keystore Generation (Default)**
```yaml
https:
  enabled: true
  # Uses job-based generation with persistent secret
  autoGenerateKeystore: true
  keystoreGenerator:
    domain: "geoserver.yourdomain.com"
    organization: "Your Organization"
    validityDays: 365
```

**Option 2: Bring Your Own Keystore**
```yaml
https:
  enabled: true
  autoGenerateKeystore: false
  keystoreSecret: "your-keystore-secret"
  keystorePassword: "your-keystore-password"
```

**Option 3: Init Container Generation**
```yaml
https:
  enabled: true
  autoGenerateKeystore: true
  keystoreGenerator:
    useInitContainer: true
    domain: "geoserver.yourdomain.com"
```

**Option 4: HTTPS Port Without Keystore (Ingress TLS Only)**
```yaml
https:
  enabled: true           # Exposes HTTPS port 8443
  autoGenerateKeystore: false  # No keystore creation
  keystoreSecret: ""      # No keystore secret

ingress:
  enabled: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # Backend uses HTTP
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: geoserver-tls
      hosts:
        - geoserver.yourdomain.com
```

**Creating Your Own Keystore Secret:**
```bash
# Generate keystore
keytool -genkeypair -alias server -keyalg RSA -keysize 2048 -validity 365 \
  -keystore keystore.jks -storepass changeit \
  -dname "CN=geoserver.yourdomain.com,O=Your Org,C=US"

# Create Kubernetes secret
kubectl create secret generic geoserver-keystore \
  --from-file=keystore.jks=keystore.jks \
  --from-literal=keystorePassword=changeit
```

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `nginx` |
| `ingress.hosts[0].host` | Hostname | `geoserver.example.com` |
| `ingress.tls[0].secretName` | TLS secret name | `geoserver-tls` |

### Persistence Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `geoserver.persistence.enabled` | Enable persistence | `true` |
| `geoserver.persistence.size` | PVC size | `10Gi` |
| `geoserver.persistence.storageClass` | Storage class | `""` |
| `geoserver.persistence.accessMode` | Access mode | `ReadWriteOnce` |

### Extension Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `geoserver.extensions.enabled` | Enable extension installation | `false` |
| `geoserver.extensions.stable` | List of stable extensions | `[]` |
| `geoserver.extensions.community` | List of community extensions | `[]` |

### PostgreSQL JNDI Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.jndi.enabled` | Enable PostgreSQL JNDI | `false` |
| `postgresql.jndi.host` | PostgreSQL host | `postgresql` |
| `postgresql.jndi.port` | PostgreSQL port | `5432` |
| `postgresql.jndi.database` | Database name | `geoserver` |
| `postgresql.jndi.username` | Database username | `geoserver` |
| `postgresql.jndi.password` | Database password | `geoserver` |

## Security Best Practices

### 1. Change Default Credentials

```yaml
geoserver:
  admin:
    username: "your-admin-user"
    password: "your-secure-password"
```

### 2. Enable HTTPS

```yaml
https:
  enabled: true
  keystoreSecret: "your-keystore-secret"
  keystorePassword: "your-keystore-password"

ingress:
  enabled: true
  tls:
    - secretName: "your-tls-secret"
      hosts:
        - "your-domain.com"
```

### 3. Configure Resource Limits

```yaml
resources:
  limits:
    cpu: "2000m"
    memory: "2Gi"
  requests:
    cpu: "500m"
    memory: "1Gi"
```

### 4. Enable Network Policies

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: allowed-namespace
      ports:
      - protocol: TCP
        port: 8080
```

## Example Configurations

### Production Configuration

```yaml
# production-values.yaml
replicaCount: 3

geoserver:
  admin:
    username: "admin"
    password: "super-secure-password"
  env:
    SKIP_DEMO_DATA: "true"
    EXTRA_JAVA_OPTS: "-Xms1g -Xmx2g"
  extensions:
    enabled: true
    stable:
      - "wps"
      - "css"
      - "importer"
      - "vectortiles"
  persistence:
    enabled: true
    size: "50Gi"
    storageClass: "fast-ssd"

https:
  enabled: true
  keystoreSecret: "geoserver-ssl-cert"

ingress:
  enabled: true
  hosts:
    - host: "geoserver.yourdomain.com"
      paths:
        - path: "/"
          pathType: "Prefix"
  tls:
    - secretName: "geoserver-tls"
      hosts:
        - "geoserver.yourdomain.com"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

resources:
  limits:
    cpu: "4000m"
    memory: "4Gi"
  requests:
    cpu: "1000m"
    memory: "2Gi"

postgresql:
  jndi:
    enabled: true
    host: "postgresql.database.svc.cluster.local"
    database: "geoserver"
    existingSecret: "postgresql-credentials"
```

### Development Configuration

```yaml
# dev-values.yaml
replicaCount: 1

geoserver:
  admin:
    username: "admin"
    password: "geoserver"
  env:
    SKIP_DEMO_DATA: "false"
  persistence:
    enabled: false

ingress:
  enabled: true
  hosts:
    - host: "geoserver.local"
      paths:
        - path: "/"
          pathType: "Prefix"

resources:
  limits:
    cpu: "1000m"
    memory: "1Gi"
  requests:
    cpu: "250m"
    memory: "512Mi"
```

## Secret Management

### HTTPS Keystore Secret

The chart supports two methods for managing HTTPS keystore secrets:

#### 1. Auto-generated Secret (Default)

When `https.enabled=true` and `https.manualSecretCreation=false` (default), the chart automatically:

- Generates a random keystore password on first install
- Preserves the password across upgrades
- Creates a secret with the password but requires manual keystore addition

```yaml
https:
  enabled: true
  manualSecretCreation: false  # Default
```

Add your keystore after deployment:
```bash
# Linux/Mac
./add-keystore.sh -k keystore.jks

# Windows
.\add-keystore.ps1 -KeystoreFile keystore.jks
```

#### 2. Manual Secret Creation

Set `https.manualSecretCreation=true` to use a static password from values:

```yaml
https:
  enabled: true
  manualSecretCreation: true
  keystorePassword: "your-static-password"
```

### Admin Password Secret

The chart supports two methods for managing admin password secrets:

#### 1. Auto-generated Password (Default)

When `geoserver.admin.autoGeneratePassword=true` (default), the chart automatically:

- Generates a secure 32-character random password on first install
- Preserves the password across upgrades
- Creates a secret with both username and password

```yaml
geoserver:
  admin:
    username: "admin"
    autoGeneratePassword: true  # Default
```

Retrieve the generated password:
```bash
# Linux/Mac
./scripts/get-admin-password.sh [release-name] [namespace]

# Windows
.\scripts\get-admin-password.ps1 -ReleaseName "geoserver" -Namespace "default"
```

#### 2. Manual Password

Set `geoserver.admin.autoGeneratePassword=false` to use a static password from values:

```yaml
geoserver:
  admin:
    username: "admin"
    autoGeneratePassword: false
    password: "your-static-password"
```

### Secret Preservation

- Auto-generated passwords are preserved across Helm upgrades
- Existing secrets are never overwritten
- Admin credentials are stored securely in Kubernetes secrets

## SSL Certificate Setup

### Using cert-manager with Let's Encrypt

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
  tls:
    - secretName: "geoserver-letsencrypt-tls"
      hosts:
        - "geoserver.yourdomain.com"
```

### Using custom certificates

```bash
# Create keystore from PEM files
openssl pkcs12 -export -in cert.pem -inkey key.pem -out keystore.p12 -name server
keytool -importkeystore -srckeystore keystore.p12 -srcstoretype PKCS12 -destkeystore keystore.jks

# Create secret
kubectl create secret generic geoserver-https \
  --from-file=keystore.jks=keystore.jks \
  --from-literal=keystorePassword=your-password
```

## Monitoring

### Prometheus Integration

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: "30s"
    path: "/geoserver/rest/about/version"
```

## Troubleshooting

### View logs

```bash
kubectl logs -f deployment/my-geoserver
```

### Access pod shell

```bash
kubectl exec -it deployment/my-geoserver -- /bin/bash
```

### Check persistent volume

```bash
kubectl get pvc
kubectl describe pvc my-geoserver-data
```

### Test connectivity

```bash
kubectl port-forward service/my-geoserver 8080:8080
# Visit http://localhost:8080/geoserver
```

## Upgrade

```bash
helm upgrade my-geoserver ./geoserver-chart -f my-values.yaml
```

## Uninstall

```bash
helm uninstall my-geoserver
# Note: PVCs are not automatically deleted
kubectl delete pvc my-geoserver-data
```

## License

This chart is licensed under the Apache License 2.0. GeoServer is licensed under the GPL 2.0.
