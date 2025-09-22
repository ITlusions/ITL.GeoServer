# PowerShell script to add keystore to GeoServer HTTPS secret
# This script helps add a JKS keystore file to the auto-generated HTTPS secret

param(
    [Parameter(Mandatory=$true)]
    [string]$KeystoreFile,
    
    [string]$Namespace = "geoserver",
    [string]$ReleaseName = "geoserver", 
    [string]$SecretName,
    [switch]$DryRun,
    [switch]$Help
)

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "[INFO] $Message" -Color Green
}

function Write-Warn {
    param([string]$Message)
    Write-ColorOutput "[WARN] $Message" -Color Yellow
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "[ERROR] $Message" -Color Red
}

function Show-Usage {
    Write-Host @"
Usage: .\add-keystore.ps1 -KeystoreFile <path> [OPTIONS]

PARAMETERS:
  -KeystoreFile    Path to keystore.jks file (required)
  -Namespace       Kubernetes namespace (default: geoserver)
  -ReleaseName     Helm release name (default: geoserver)
  -SecretName      Secret name (auto-detected if not provided)
  -DryRun          Show what would be done without executing
  -Help            Show this help message

Examples:
  .\add-keystore.ps1 -KeystoreFile keystore.jks
  .\add-keystore.ps1 -KeystoreFile C:\path\to\keystore.jks -Namespace production -ReleaseName my-geoserver
  .\add-keystore.ps1 -KeystoreFile keystore.jks -DryRun
"@
}

function Test-Requirements {
    Write-Info "Checking requirements..."
    
    # Check if kubectl is installed
    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl is not installed. Please install kubectl first."
        exit 1
    }
    
    # Check kubectl connectivity
    try {
        kubectl cluster-info | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl cluster-info failed"
        }
    }
    catch {
        Write-Error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    }
    
    Write-Info "Requirements check passed."
}

function Find-SecretName {
    param(
        [string]$Namespace,
        [string]$Release
    )
    
    # Try to find the HTTPS secret
    $secretName = "$Release-https"
    
    try {
        kubectl get secret $secretName -n $Namespace | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return $secretName
        }
    }
    catch {}
    
    # Try alternative naming patterns
    $altNames = @(
        "$Release-geoserver-https",
        "geoserver-https",
        "$Release-https-keystore"
    )
    
    foreach ($name in $altNames) {
        try {
            kubectl get secret $name -n $Namespace | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return $name
            }
        }
        catch {}
    }
    
    Write-Error "Could not find HTTPS secret in namespace '$Namespace'"
    Write-Info "Available secrets:"
    try {
        kubectl get secrets -n $Namespace | Select-String -Pattern "(https|keystore|tls)"
    }
    catch {
        Write-Host "  No HTTPS-related secrets found"
    }
    exit 1
}

function Add-KeystoreToSecret {
    param(
        [string]$KeystoreFile,
        [string]$Namespace,
        [string]$SecretName,
        [bool]$DryRun
    )
    
    Write-Info "Adding keystore to secret..."
    Write-Info "Keystore file: $KeystoreFile"
    Write-Info "Namespace: $Namespace"
    Write-Info "Secret: $SecretName"
    
    # Verify keystore file exists
    if (!(Test-Path $KeystoreFile)) {
        Write-Error "Keystore file '$KeystoreFile' not found."
        exit 1
    }
    
    # Verify secret exists
    try {
        kubectl get secret $SecretName -n $Namespace | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Secret not found"
        }
    }
    catch {
        Write-Error "Secret '$SecretName' not found in namespace '$Namespace'."
        exit 1
    }
    
    # Base64 encode the keystore file
    Write-Info "Encoding keystore file..."
    try {
        $keystoreBytes = [System.IO.File]::ReadAllBytes($KeystoreFile)
        $keystoreB64 = [System.Convert]::ToBase64String($keystoreBytes)
    }
    catch {
        Write-Error "Failed to read and encode keystore file: $_"
        exit 1
    }
    
    if ($DryRun) {
        Write-Warn "DRY RUN: Would patch secret '$SecretName' with keystore data"
        Write-Host "Command that would be executed:"
        Write-Host "kubectl patch secret $SecretName -n $Namespace --patch='{`"data`":{`"keystore.jks`":`"<base64-encoded-data>`"}}'"
        return
    }
    
    # Patch the secret with the keystore
    Write-Info "Patching secret with keystore..."
    try {
        $patchData = @{
            data = @{
                "keystore.jks" = $keystoreB64
            }
        } | ConvertTo-Json -Compress
        
        kubectl patch secret $SecretName -n $Namespace --patch=$patchData --type=merge
        
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl patch failed"
        }
        
        Write-Info "Keystore successfully added to secret!"
    }
    catch {
        Write-Error "Failed to patch secret: $_"
        exit 1
    }
    
    # Verify the keystore was added
    Write-Info "Verifying keystore was added..."
    try {
        $keystoreData = kubectl get secret $SecretName -n $Namespace -o jsonpath='{.data.keystore\.jks}' 2>$null
        if (![string]::IsNullOrEmpty($keystoreData)) {
            Write-Info "✓ Keystore verified in secret"
        }
        else {
            throw "Keystore not found in secret"
        }
    }
    catch {
        Write-Error "✗ Keystore not found in secret after patching"
        exit 1
    }
    
    # Show secret status
    Write-Info "Secret contents:"
    kubectl get secret $SecretName -n $Namespace -o custom-columns="NAME:.metadata.name,DATA KEYS:.data" --no-headers
}

function Restart-GeoServer {
    param(
        [string]$Namespace,
        [string]$Release,
        [bool]$DryRun
    )
    
    Write-Info "Restarting GeoServer deployment to pick up new keystore..."
    
    $deploymentName = $Release
    
    if ($DryRun) {
        Write-Warn "DRY RUN: Would restart deployment '$deploymentName'"
        return
    }
    
    try {
        kubectl get deployment $deploymentName -n $Namespace | Out-Null
        if ($LASTEXITCODE -eq 0) {
            kubectl rollout restart deployment $deploymentName -n $Namespace
            Write-Info "Waiting for deployment to be ready..."
            kubectl rollout status deployment $deploymentName -n $Namespace --timeout=300s
            Write-Info "✓ GeoServer deployment restarted successfully"
        }
        else {
            Write-Warn "Deployment '$deploymentName' not found. You may need to restart manually."
        }
    }
    catch {
        Write-Warn "Could not restart deployment: $_"
    }
}

# Main execution
if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrEmpty($KeystoreFile)) {
    Write-Error "Keystore file not specified."
    Show-Usage
    exit 1
}

Write-Info "Starting keystore addition process..."

Test-Requirements

# Auto-detect secret name if not provided
if ([string]::IsNullOrEmpty($SecretName)) {
    Write-Info "Auto-detecting secret name..."
    $SecretName = Find-SecretName -Namespace $Namespace -Release $ReleaseName
    Write-Info "Detected secret: $SecretName"
}

Add-KeystoreToSecret -KeystoreFile $KeystoreFile -Namespace $Namespace -SecretName $SecretName -DryRun $DryRun

if (!$DryRun) {
    Restart-GeoServer -Namespace $Namespace -Release $ReleaseName -DryRun $DryRun
    
    Write-Info "Process completed successfully!"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "1. Wait for GeoServer to start up completely"
    Write-Host "2. Check the logs: kubectl logs -f deployment/$ReleaseName -n $Namespace"
    Write-Host "3. Test HTTPS access to your GeoServer instance"
    Write-Host "4. Update your ingress configuration if needed"
}
