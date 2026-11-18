<#
.SYNOPSIS
    SENTINEL-X – Safe cleanup of temporary resources.
.DESCRIPTION
    Removes only temporary/generated files. Never silently deletes persistent data.
    Requires explicit confirmation for destructive operations.
#>
param(
    [switch]$PruneImages,     # Remove unused Docker images
    [switch]$ClearLogs,       # Clear evidence/logs directory
    [switch]$All              # All of the above (still confirms)
)
$base = $PSScriptRoot | Split-Path

function Confirm-Action {
    param($action)
    $r = Read-Host "  Confirm: $action? [y/N]"
    return $r -eq "y"
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  –  Cleanup                               " -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# ── Stop services first ───────────────────────────────────────────────────────
Write-Host "  Stopping services..." -ForegroundColor Cyan
Set-Location $base
docker compose down 2>&1
Write-Host "  Services stopped. Persistent volumes PRESERVED." -ForegroundColor Green

# ── Prune unused Docker images ────────────────────────────────────────────────
if ($PruneImages -or $All) {
    if (Confirm-Action "Remove unused Docker images (docker image prune)") {
        docker image prune -f 2>&1
        Write-Host "  Unused images removed." -ForegroundColor Green
    }
}

# ── Clear evidence logs ───────────────────────────────────────────────────────
if ($ClearLogs -or $All) {
    $logDir = Join-Path $base "evidence\logs"
    if (Confirm-Action "Clear evidence/logs directory ($logDir)") {
        Get-ChildItem $logDir -Recurse -File | Remove-Item -Force
        Write-Host "  Evidence logs cleared." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "  Cleanup complete. Named volumes and configurations are preserved." -ForegroundColor Green
Write-Host "  To completely remove all data: docker compose down -v" -ForegroundColor DarkGray
Write-Host ""
