# GeoServer Helm Chart Installation Script for PowerShell
# This script helps deploy GeoServer with different configurations

param(
    [Parameter(Position=0)]
    [ValidateSet("dev", "prod", "custom")]
    [string]$Environment,
    
    [string]$Namespace = "geoserver",
    [string]$ReleaseName = "geoserver",
    [string]$ValuesFile,
    [switch]$Help
)

$ChartDir = "./geoserver-chart"

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
Usage: .\deploy.ps1 [ENVIRONMENT] [OPTIONS]

ENVIRONMENT:
  dev         Deploy with development configuration
  prod        Deploy with production configuration
  custom      Deploy with custom values file

OPTIONS:
  -Namespace     Kubernetes namespace (default: geoserver)
  -ReleaseName   Helm release name (default: geoserver)
  -ValuesFile    Custom values file path
  -Help          Show this help message

Examples:
  .\deploy.ps1 dev
  .\deploy.ps1 prod -Namespace production
  .\deploy.ps1 custom -ValuesFile my-values.yaml
"@
}

function Test-Requirements {
    Write-Info "Checking requirements..."
    
    # Check if helm is installed
    if (!(Get-Command helm -ErrorAction SilentlyContinue)) {
        Write-Error "Helm is not installed. Please install Helm first."
        exit 1
    }
    
    # Check if kubectl is installed
    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl is not installed. Please install kubectl first."
        exit 1
    }
    
    # Check if chart directory exists
    if (!(Test-Path $ChartDir)) {
        Write-Error "Chart directory '$ChartDir' not found."
        exit 1
    }
    
    Write-Info "Requirements check passed."
}

function New-Namespace {
    Write-Info "Creating namespace '$Namespace' if it doesn't exist..."
    try {
        kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create namespace"
        }
    }
    catch {
        Write-Error "Failed to create namespace: $_"
        exit 1
    }
}

function Deploy-GeoServer {
    param(
        [string]$Env,
        [string]$CustomValuesFile
    )
    
    Write-Info "Deploying GeoServer with $Env configuration..."
    
    $valuesFilePath = ""
    
    switch ($Env) {
        "dev" {
            $valuesFilePath = "$ChartDir/values-development.yaml"
        }
        "prod" {
            $valuesFilePath = "$ChartDir/values-production.yaml"
            Write-Warn "Production deployment detected. Make sure to:"
            Write-Warn "1. Change default admin password"
            Write-Warn "2. Configure proper SSL certificates"
            Write-Warn "3. Set up database credentials"
        }
        "custom" {
            if ([string]::IsNullOrEmpty($CustomValuesFile)) {
                Write-Error "Custom values file not specified."
                exit 1
            }
            $valuesFilePath = $CustomValuesFile
        }
        default {
            Write-Error "Invalid environment: $Env"
            exit 1
        }
    }
    
    if (!(Test-Path $valuesFilePath)) {
        Write-Error "Values file '$valuesFilePath' not found."
        exit 1
    }
    
    # Deploy using Helm
    Write-Info "Running helm upgrade --install..."
    try {
        helm upgrade --install $ReleaseName $ChartDir `
            --namespace $Namespace `
            --values $valuesFilePath `
            --wait `
            --timeout 600s
        
        if ($LASTEXITCODE -ne 0) {
            throw "Helm deployment failed"
        }
        
        Write-Info "GeoServer deployed successfully!"
        Write-Info "Release: $ReleaseName"
        Write-Info "Namespace: $Namespace"
        Write-Host ""
        Write-Info "Getting deployment status..."
        helm status $ReleaseName -n $Namespace
    }
    catch {
        Write-Error "Deployment failed: $_"
        exit 1
    }
}

function Show-AccessInfo {
    Write-Info "Access Information:"
    Write-Host ""
    
    # Get ingress information
    try {
        $ingressHost = kubectl get ingress -n $Namespace -o jsonpath='{.items[0].spec.rules[0].host}' 2>$null
        
        if (![string]::IsNullOrEmpty($ingressHost)) {
            Write-Info "GeoServer URL: https://$ingressHost/geoserver"
            Write-Info "Web Interface: https://$ingressHost/geoserver/web"
            Write-Info "REST API: https://$ingressHost/geoserver/rest"
        }
        else {
            Write-Info "Use port-forward to access GeoServer:"
            Write-Host "  kubectl port-forward -n $Namespace service/$ReleaseName 8080:8080"
            Write-Host "  Then visit: http://localhost:8080/geoserver"
        }
    }
    catch {
        Write-Info "Use port-forward to access GeoServer:"
        Write-Host "  kubectl port-forward -n $Namespace service/$ReleaseName 8080:8080"
        Write-Host "  Then visit: http://localhost:8080/geoserver"
    }
    
    Write-Host ""
    Write-Warn "Default credentials: admin/geoserver"
    Write-Warn "Please change the default password immediately!"
}

# Main execution
if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrEmpty($Environment)) {
    Write-Error "Environment not specified."
    Show-Usage
    exit 1
}

Write-Info "Starting GeoServer deployment..."
Write-Info "Environment: $Environment"
Write-Info "Namespace: $Namespace"
Write-Info "Release: $ReleaseName"

Test-Requirements
New-Namespace
Deploy-GeoServer -Env $Environment -CustomValuesFile $ValuesFile
Show-AccessInfo

Write-Info "Deployment completed successfully!"
