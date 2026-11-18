<#
.SYNOPSIS
    SENTINEL-X – Start all services.
.DESCRIPTION
    Starts the full SENTINEL-X stack, waits for each service to become healthy,
    and displays access URLs and status.
#>
param(
    [switch]$Build  # Force rebuild of custom images
)
$ErrorActionPreference = "Stop"
$base = $PSScriptRoot | Split-Path
Set-Location $base

function Info  { param($m) Write-Host "  [INFO]  $m" -ForegroundColor Cyan }
function Ok    { param($m) Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Fail  { param($m) Write-Host "  [FAIL]  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  –  Starting Services                     " -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# ── Prerequisite check ───────────────────────────────────────────────────────
Info "Verifying Docker is running..."
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Docker is not running. Start Docker Desktop first." }
Ok "Docker running"

if (-not (Test-Path (Join-Path $base ".env"))) {
    Warn ".env not found — creating from .env.example (change passwords!)"
    Copy-Item (Join-Path $base ".env.example") (Join-Path $base ".env")
}

# ── Start services ───────────────────────────────────────────────────────────
Info "Pulling/building images and starting containers..."
if ($Build) {
    docker compose up -d --build 2>&1
} else {
    docker compose up -d 2>&1
}
if ($LASTEXITCODE -ne 0) { Fail "docker compose up failed. Check logs with: docker compose logs" }
Ok "Containers started"

# ── Wait for Elasticsearch ────────────────────────────────────────────────────
Info "Waiting for Elasticsearch (up to 3 minutes)..."
$esReady = $false
for ($i = 0; $i -lt 36; $i++) {
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:9200/_cluster/health" `
                               -Credential (New-Object PSCredential("elastic", (ConvertTo-SecureString "changeme_elastic_lab" -AsPlainText -Force))) `
                               -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200) { $esReady = $true; break }
    } catch {}
    Write-Host "    ... waiting ($([int](($i+1)*5))s)" -ForegroundColor DarkGray
}
if ($esReady) { Ok "Elasticsearch is healthy" }
else          { Warn "Elasticsearch did not respond in 3 minutes — check: docker logs sentinel_elasticsearch" }

# ── Wait for Kibana ───────────────────────────────────────────────────────────
Info "Waiting for Kibana (up to 3 minutes)..."
$kbReady = $false
for ($i = 0; $i -lt 36; $i++) {
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:5601/api/status" `
                               -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200) { $kbReady = $true; break }
    } catch {}
    Write-Host "    ... waiting ($([int](($i+1)*5))s)" -ForegroundColor DarkGray
}
if ($kbReady) { Ok "Kibana is healthy" }
else          { Warn "Kibana did not respond — check: docker logs sentinel_kibana" }

# ── Wait for Wazuh Manager ────────────────────────────────────────────────────
Info "Waiting for Wazuh Manager API (up to 3 minutes)..."
$wzReady = $false
for ($i = 0; $i -lt 36; $i++) {
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-WebRequest -Uri "https://localhost:55000/" `
                               -SkipCertificateCheck -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($r.StatusCode -in 200,401) { $wzReady = $true; break }
    } catch {}
    Write-Host "    ... waiting ($([int](($i+1)*5))s)" -ForegroundColor DarkGray
}
if ($wzReady) { Ok "Wazuh Manager API is responding" }
else          { Warn "Wazuh API did not respond — check: docker logs sentinel_wazuh_manager" }

# ── Status summary ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>&1
Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ACCESS POINTS:" -ForegroundColor Yellow
Write-Host "  Web App (via WAF)  : http://localhost/" -ForegroundColor White
Write-Host "  Kibana Dashboard   : http://localhost:5601  (elastic / <ELASTIC_PASSWORD>)" -ForegroundColor White
Write-Host "  Elasticsearch API  : http://localhost:9200  (elastic / <ELASTIC_PASSWORD>)" -ForegroundColor White
Write-Host "  Wazuh API          : https://localhost:55000" -ForegroundColor White
Write-Host ""
Write-Host "  Next: run .\scripts\validate.ps1 to execute the security test suite" -ForegroundColor Cyan
Write-Host ""
