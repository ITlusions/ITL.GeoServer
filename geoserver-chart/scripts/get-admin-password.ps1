# PowerShell script to retrieve the auto-generated GeoServer admin password
# Usage: .\get-admin-password.ps1 [-ReleaseName "geoserver"] [-Namespace "default"]

param(
    [string]$ReleaseName = "geoserver",
    [string]$Namespace = "default"
)

Write-Host "Retrieving GeoServer admin password for release: $ReleaseName in namespace: $Namespace" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

# Check if kubectl is available
try {
    kubectl version --client --output=json | Out-Null
} catch {
    Write-Host "ERROR: kubectl is not available or not in PATH" -ForegroundColor Red
    exit 1
}

# Check if the secret exists
try {
    kubectl get secret "$ReleaseName-admin" -n $Namespace 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Admin Username:" -ForegroundColor Yellow
        $username = kubectl get secret "$ReleaseName-admin" -n $Namespace -o jsonpath='{.data.username}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
        Write-Host $username -ForegroundColor White
        Write-Host
        
        Write-Host "Admin Password:" -ForegroundColor Yellow
        $password = kubectl get secret "$ReleaseName-admin" -n $Namespace -o jsonpath='{.data.password}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
        Write-Host $password -ForegroundColor White
        Write-Host
        
        Write-Host "You can also export these credentials as environment variables:" -ForegroundColor Cyan
        Write-Host "`$env:GEOSERVER_ADMIN_USER = '$username'" -ForegroundColor Gray
        Write-Host "`$env:GEOSERVER_ADMIN_PASSWORD = '$password'" -ForegroundColor Gray
        
        # Optionally set the environment variables
        Write-Host
        $setEnv = Read-Host "Set environment variables now? (y/N)"
        if ($setEnv -eq 'y' -or $setEnv -eq 'Y') {
            $env:GEOSERVER_ADMIN_USER = $username
            $env:GEOSERVER_ADMIN_PASSWORD = $password
            Write-Host "Environment variables set for this session." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "ERROR: Admin secret '$ReleaseName-admin' not found in namespace '$Namespace'" -ForegroundColor Red
    Write-Host
    Write-Host "Available secrets in namespace '$Namespace':" -ForegroundColor Yellow
    kubectl get secrets -n $Namespace | Select-String $ReleaseName
    
    Write-Host
    Write-Host "If you're using manual admin credentials, check your values.yaml configuration." -ForegroundColor Cyan
    Write-Host "If you're using auto-generated passwords, ensure the admin-secret-generator job has completed successfully." -ForegroundColor Cyan
    exit 1
}
