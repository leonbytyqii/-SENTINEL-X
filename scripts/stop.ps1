<#
.SYNOPSIS
    SENTINEL-X – Stop all services (preserves persistent data).
.DESCRIPTION
    Stops containers without removing named volumes.
    Use -Destroy to also remove all persistent data (irreversible).
#>
param(
    [switch]$Destroy    # WARNING: removes all persistent data volumes
)
$base = $PSScriptRoot | Split-Path
Set-Location $base

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  –  Stopping Services                     " -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

if ($Destroy) {
    Write-Host "  WARNING: -Destroy flag will DELETE all persistent data." -ForegroundColor Red
    Write-Host "  Elasticsearch indices, Wazuh alerts, and Kibana dashboards will be LOST." -ForegroundColor Red
    $confirm = Read-Host "  Type 'DELETE' to confirm"
    if ($confirm -ne "DELETE") {
        Write-Host "  Aborted." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "  Stopping and removing all data..." -ForegroundColor Red
    docker compose down -v 2>&1
} else {
    Write-Host "  Stopping containers (data preserved)..." -ForegroundColor Cyan
    docker compose down 2>&1
    Write-Host "  Services stopped. Data preserved in named volumes." -ForegroundColor Green
    Write-Host "  Restart with: .\scripts\start.ps1" -ForegroundColor Cyan
}
Write-Host ""
