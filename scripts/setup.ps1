<#
.SYNOPSIS
    SENTINEL-X – Environment setup and prerequisite validation.
.DESCRIPTION
    Validates Docker, creates .env from .env.example if missing,
    and prepares the deployment environment.
#>
param()
$ErrorActionPreference = "Stop"
$base = $PSScriptRoot | Split-Path

function Info  { param($m) Write-Host "  [INFO]  $m" -ForegroundColor Cyan }
function Ok    { param($m) Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Warn  { param($m) Write-Host "  [WARN]  $m" -ForegroundColor Yellow }
function Fail  { param($m) Write-Host "  [FAIL]  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  –  Environment Setup                     " -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# ── 1. Docker ────────────────────────────────────────────────────────────────
Info "Checking Docker..."
try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "Docker daemon is not running. Start Docker Desktop and retry." }
    Ok "Docker Engine $dockerVersion"
} catch {
    Fail "docker not found in PATH. Install Docker Desktop: https://docs.docker.com/desktop/windows/"
}

# ── 2. Docker Compose ────────────────────────────────────────────────────────
Info "Checking Docker Compose..."
try {
    $composeVersion = docker compose version --short 2>&1
    Ok "Docker Compose $composeVersion"
} catch {
    Fail "docker compose not available."
}

# ── 3. .env file ─────────────────────────────────────────────────────────────
Info "Checking .env file..."
$envFile = Join-Path $base ".env"
$envExample = Join-Path $base ".env.example"
if (-not (Test-Path $envFile)) {
    Copy-Item $envExample $envFile
    Warn ".env created from .env.example — REVIEW AND CHANGE ALL PASSWORDS before deploying."
} else {
    Ok ".env exists"
    # Check for default passwords
    $envContent = Get-Content $envFile -Raw
    if ($envContent -match "changeme") {
        Warn "Default passwords detected in .env — change them before exposing any port."
    }
}

# ── 4. WSL2 virtual memory (required for Elasticsearch) ─────────────────────
Info "Checking vm.max_map_count (Elasticsearch requirement)..."
try {
    $mapCount = wsl -e sysctl vm.max_map_count 2>&1
    if ($mapCount -match "(\d+)") {
        $val = [int]$Matches[1]
        if ($val -lt 262144) {
            Warn "vm.max_map_count=$val is below 262144. Setting it now..."
            wsl -e sudo sysctl -w vm.max_map_count=262144 2>&1 | Out-Null
            # Persist in WSL
            wsl -e bash -c "echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf" 2>&1 | Out-Null
            Ok "vm.max_map_count set to 262144"
        } else {
            Ok "vm.max_map_count=$val (OK)"
        }
    }
} catch {
    Warn "Could not check vm.max_map_count via WSL. If Elasticsearch fails to start, run: wsl -e sudo sysctl -w vm.max_map_count=262144"
}

# ── 5. Required directories ───────────────────────────────────────────────────
Info "Verifying project directories..."
$requiredDirs = @(
    "infrastructure\nginx\conf.d",
    "infrastructure\modsecurity\exclusions",
    "infrastructure\wazuh\manager",
    "infrastructure\wazuh\decoders",
    "infrastructure\wazuh\rules",
    "infrastructure\elasticsearch\config",
    "infrastructure\ingestion\config",
    "infrastructure\dashboards\kibana",
    "applications\vulnerable-lab\src",
    "tests\scripts",
    "scripts",
    "evidence"
)
foreach ($dir in $requiredDirs) {
    $path = Join-Path $base $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        Warn "Created missing directory: $dir"
    }
}
Ok "All required directories present"

# ── 6. Port availability ──────────────────────────────────────────────────────
Info "Checking port availability..."
$ports = @(80, 9200, 5601, 55000)
$blocked = @()
foreach ($port in $ports) {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($conn) { $blocked += $port }
}
if ($blocked.Count -gt 0) {
    Warn "Ports already in use: $($blocked -join ', ') — check for conflicts before starting."
} else {
    Ok "Required ports 80, 9200, 5601, 55000 are available"
}

# ── 7. Disk space ─────────────────────────────────────────────────────────────
Info "Checking disk space..."
$free = (Get-PSDrive C).Free / 1GB
if ($free -lt 10) {
    Warn "Less than 10 GB free on C: ($([math]::Round($free,1)) GB). Elasticsearch requires at least 5 GB."
} else {
    Ok "$([math]::Round($free,1)) GB free on C: (sufficient)"
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Setup complete. Next step: .\scripts\start.ps1        " -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
