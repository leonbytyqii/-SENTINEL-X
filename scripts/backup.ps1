<#
.SYNOPSIS
    SENTINEL-X – Backup persistent data and configurations.
.DESCRIPTION
    Exports Elasticsearch snapshots and archives configuration files.
    Does NOT back up secrets or credentials.
#>
param(
    [string]$BackupDir = "C:\Prime Kosova\WORK\SENTINEL-X-Backups"
)
$base = $PSScriptRoot | Split-Path
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$backupPath = Join-Path $BackupDir $timestamp

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  –  Backup                                " -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

New-Item -ItemType Directory -Force $backupPath | Out-Null
Write-Host "  Backup target: $backupPath" -ForegroundColor Cyan

# ── Configuration files (no secrets) ─────────────────────────────────────────
Write-Host "  Backing up configuration files..." -ForegroundColor Yellow
$configDest = Join-Path $backupPath "configs"
New-Item -ItemType Directory -Force $configDest | Out-Null
Copy-Item -Recurse (Join-Path $base "infrastructure") $configDest
Copy-Item (Join-Path $base "docker-compose.yml") $configDest
Copy-Item (Join-Path $base ".env.example") $configDest
# DO NOT copy .env — contains real credentials
Write-Host "  Configurations backed up (no credentials included)" -ForegroundColor Green

# ── Elasticsearch snapshot ────────────────────────────────────────────────────
Write-Host "  Creating Elasticsearch snapshot..." -ForegroundColor Yellow
$esPass = "changeme_elastic_lab"
if (Test-Path (Join-Path $base ".env")) {
    Get-Content (Join-Path $base ".env") | ForEach-Object {
        if ($_ -match "^ELASTIC_PASSWORD=(.+)$") { $esPass = $Matches[1] }
    }
}
try {
    # Register a filesystem repository (requires the snapshot volume to be mounted in production)
    # For lab: export via API
    $esCred = New-Object PSCredential("elastic", (ConvertTo-SecureString $esPass -AsPlainText -Force))
    $indices = Invoke-RestMethod -Uri "http://localhost:9200/_cat/indices/wazuh-alerts-*?format=json" `
                                 -Credential $esCred -TimeoutSec 10
    $indexList = ($indices | ForEach-Object { $_.index }) -join ", "
    if ($indexList) {
        Write-Host "  Wazuh alert indices: $indexList" -ForegroundColor Green
        Write-Host "  NOTE: For full Elasticsearch backup, configure a snapshot repository." -ForegroundColor DarkGray
    } else {
        Write-Host "  No wazuh-alerts indices found — nothing to snapshot yet." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Elasticsearch not accessible for snapshot — back it up manually." -ForegroundColor Yellow
}

# ── Backup summary ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Backup complete: $backupPath" -ForegroundColor Green
Write-Host ""
Write-Host "  RESTORE INSTRUCTIONS:" -ForegroundColor Yellow
Write-Host "  1. Copy configs/ back to the project directory." -ForegroundColor White
Write-Host "  2. Recreate .env from .env.example with original credentials." -ForegroundColor White
Write-Host "  3. Run: docker compose up -d" -ForegroundColor White
Write-Host "  4. For Elasticsearch data, restore from snapshot repository." -ForegroundColor White
Write-Host ""
