# GeoServer HTTPS Secret Management

This document explains the secure HTTPS keystore password management implemented in the GeoServer Helm chart.

## Overview

The chart now includes intelligent secret management that:
- ✅ **Generates secure random passwords** on initial deployment
- ✅ **Preserves passwords** across Helm upgrades
- ✅ **Never overwrites existing secrets**
- ✅ **Provides easy keystore addition** with helper scripts

## How It Works

### 1. Automatic Secret Generation

When you enable HTTPS with `https.enabled=true`, the chart automatically:

```yaml
# templates/https-secret-generator.yaml
apiVersion: v1
kind: Secret
metadata:
  name: geoserver-https
  annotations:
    "helm.sh/hook": pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
type: Opaque
data:
  keystorePassword: <random-32-char-base64-encoded>
```

### 2. Secret Preservation Logic

The template uses Helm's `lookup` function to check for existing secrets:

```yaml
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace (printf "%s-https" (include "geoserver.fullname" .)) }}
{{- if $existingSecret }}
# Preserve existing keystore password
keystorePassword: {{ index $existingSecret.data "keystorePassword" }}
{{- else }}
# Generate new keystore password
keystorePassword: {{ randAlphaNum 32 | b64enc }}
{{- end }}
```

### 3. Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| `https.enabled` | Enable HTTPS functionality | `false` |
| `https.manualSecretCreation` | Use static password from values | `false` |
| `https.keystoreSecret` | Use existing secret name | `""` |
| `https.keystorePassword` | Static password (when manual=true) | `"changeit"` |

## Usage Scenarios

### Scenario 1: New Deployment (Recommended)

```yaml
# values.yaml
https:
  enabled: true
  manualSecretCreation: false  # Use auto-generation
```

**What happens:**
1. Helm generates a random 32-character password
2. Creates secret with password but empty keystore
3. You add keystore using helper script

```bash
# Deploy
helm install geoserver ./geoserver-chart -f values.yaml

# Add keystore
./add-keystore.sh -k your-keystore.jks
```

### Scenario 2: Upgrade Existing Deployment

```bash
# Upgrade - password is preserved
helm upgrade geoserver ./geoserver-chart -f values.yaml

# Keystore remains intact, no action needed
```

### Scenario 3: Manual Secret Management

```yaml
# values.yaml
https:
  enabled: true
  manualSecretCreation: true
  keystorePassword: "my-static-password"
```

**What happens:**
1. Chart creates secret with your static password
2. You must manually add keystore data

### Scenario 4: External Secret

```yaml
# values.yaml
https:
  enabled: true
  keystoreSecret: "my-existing-secret"
```

**What happens:**
1. Chart uses your existing secret
2. No secret generation occurs

## Security Benefits

### 🔐 **Strong Random Passwords**
- 32-character alphanumeric passwords
- Generated using Helm's cryptographically secure `randAlphaNum`
- Unique per deployment

### 🛡️ **No Hardcoded Secrets**
- No passwords in values files (default mode)
- No secrets in version control
- Passwords generated at deploy time

### 🔄 **Upgrade Safety**
- Existing passwords never overwritten
- Keystore data preserved across upgrades
- Rollback safe

### 📝 **Audit Trail**
- Secret creation tracked in Helm history
- Clear annotations on secret objects
- Hook-based generation for proper ordering

## Helper Scripts

### Linux/Mac: `add-keystore.sh`

```bash
# Basic usage
./add-keystore.sh -k keystore.jks

# With options
./add-keystore.sh -k keystore.jks -n production -r my-geoserver

# Dry run
./add-keystore.sh -k keystore.jks --dry-run
```

### Windows: `add-keystore.ps1`

```powershell
# Basic usage
.\add-keystore.ps1 -KeystoreFile keystore.jks

# With options
.\add-keystore.ps1 -KeystoreFile keystore.jks -Namespace production -ReleaseName my-geoserver

# Dry run
.\add-keystore.ps1 -KeystoreFile keystore.jks -DryRun
```

## Troubleshooting

### Check Secret Status

```bash
# List secrets
kubectl get secrets -n geoserver

# Check secret contents
kubectl get secret geoserver-https -n geoserver -o yaml

# Verify keystore presence
kubectl get secret geoserver-https -n geoserver -o jsonpath='{.data}' | jq
```

### View Generated Password

```bash
# Decode the password (for debugging)
kubectl get secret geoserver-https -n geoserver -o jsonpath='{.data.keystorePassword}' | base64 -d
```

### Manual Secret Creation

If you need to create the secret manually:

```bash
# Create with random password
PASSWORD=$(openssl rand -base64 32)
kubectl create secret generic geoserver-https \
  --from-file=keystore.jks=your-keystore.jks \
  --from-literal=keystorePassword="$PASSWORD" \
  --namespace geoserver
```

### Regenerate Secret

To regenerate the password (will break existing keystores):

```bash
# Delete existing secret
kubectl delete secret geoserver-https -n geoserver

# Redeploy to regenerate
helm upgrade geoserver ./geoserver-chart -f values.yaml
```

## Migration Guide

### From Manual to Auto-Generated

If you have existing manual secrets and want to use auto-generation:

1. **Backup existing secret:**
   ```bash
   kubectl get secret geoserver-https -n geoserver -o yaml > backup-secret.yaml
   ```

2. **Note your keystore file:**
   ```bash
   kubectl get secret geoserver-https -n geoserver -o jsonpath='{.data.keystore\.jks}' | base64 -d > keystore.jks
   ```

3. **Update values.yaml:**
   ```yaml
   https:
     enabled: true
     manualSecretCreation: false  # Switch to auto-generation
   ```

4. **Delete old secret and redeploy:**
   ```bash
   kubectl delete secret geoserver-https -n geoserver
   helm upgrade geoserver ./geoserver-chart -f values.yaml
   ```

5. **Re-add keystore:**
   ```bash
   ./add-keystore.sh -k keystore.jks
   ```

## Best Practices

1. **Use auto-generation for new deployments**
2. **Keep backup of keystore files separately**
3. **Test deployments in staging first**
4. **Monitor secret expiration if using cert-manager**
5. **Use strong keystores with proper certificates**
6. **Regularly rotate certificates (not passwords)**

## Integration with Monitoring

The secret management integrates with the chart's monitoring features:

```yaml
# Monitor secret health
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    # Will monitor HTTPS endpoints when configured
```

## Conclusion

This secret management system provides:
- **Security**: Strong random passwords, no hardcoded secrets
- **Reliability**: Preserved across upgrades, never overwrites
- **Usability**: Simple scripts for keystore management
- **Flexibility**: Multiple configuration options
- **Safety**: Dry-run capabilities, backup friendly

The implementation follows Kubernetes and Helm best practices while providing a secure, user-friendly experience for HTTPS configuration.
