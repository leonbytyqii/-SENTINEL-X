<#
.SYNOPSIS
    SENTINEL-X – Full health check for all components.
#>
$base = $PSScriptRoot | Split-Path

function Pass  { param($svc,$msg) Write-Host "  [PASS] $svc : $msg" -ForegroundColor Green }
function Fail  { param($svc,$msg) Write-Host "  [FAIL] $svc : $msg" -ForegroundColor Red }
function Warn  { param($svc,$msg) Write-Host "  [WARN] $svc : $msg" -ForegroundColor Yellow }
function Check { param($svc,$uri,$pattern,$credential=$null) {
    try {
        $params = @{ Uri=$uri; UseBasicParsing=$true; TimeoutSec=5; ErrorAction="Stop" }
        if ($credential) { $params.Credential = $credential }
        $r = Invoke-WebRequest @params
        if ($pattern -and $r.Content -notmatch $pattern) {
            Fail $svc "Unexpected response (pattern '$pattern' not found)"
        } else {
            Pass $svc "HTTP $($r.StatusCode)"
        }
    } catch {
        Fail $svc "$_"
    }
}}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  –  Health Check                          " -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# ── Load credentials from .env ────────────────────────────────────────────────
$envPath = Join-Path $base ".env"
$esPass = "changeme_elastic_lab"
if (Test-Path $envPath) {
    $envLines = Get-Content $envPath
    foreach ($line in $envLines) {
        if ($line -match "^ELASTIC_PASSWORD=(.+)$") { $esPass = $Matches[1] }
    }
}
$esCred = New-Object PSCredential("elastic", (ConvertTo-SecureString $esPass -AsPlainText -Force))

# ── Container status ──────────────────────────────────────────────────────────
Write-Host "  [CONTAINERS]" -ForegroundColor Yellow
docker compose -f (Join-Path $base "docker-compose.yml") ps --format "table {{.Name}}\t{{.State}}\t{{.Health}}" 2>&1
Write-Host ""

# ── HTTP endpoint checks ──────────────────────────────────────────────────────
Write-Host "  [ENDPOINTS]" -ForegroundColor Yellow

Check "nginx-waf (health)"    "http://localhost/health"               '"status":"ok"'
Check "webapp (via WAF)"      "http://localhost/"                      "SENTINEL-X"
Check "elasticsearch"         "http://localhost:9200/_cluster/health"  '"status"'  $esCred
Check "kibana"                "http://localhost:5601/api/status"       '"level"'

# ── Log file check ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [LOG VOLUMES]" -ForegroundColor Yellow
$logCheck = docker exec sentinel_nginx_waf ls /var/log/nginx/ 2>&1
if ($LASTEXITCODE -eq 0) {
    Pass "nginx-logs volume" "accessible ($logCheck)"
} else {
    Fail "nginx-logs volume" "cannot list /var/log/nginx"
}

# ── Wazuh alert file ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [WAZUH ALERTS]" -ForegroundColor Yellow
$alertCheck = docker exec sentinel_wazuh_manager ls -la /var/ossec/logs/alerts/ 2>&1
if ($LASTEXITCODE -eq 0) {
    Pass "wazuh-alerts path" "$alertCheck"
} else {
    Fail "wazuh-alerts path" "cannot access /var/ossec/logs/alerts"
}

# ── Elasticsearch index check ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  [ELASTICSEARCH INDICES]" -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest -Uri "http://localhost:9200/_cat/indices?v" `
                           -Credential $esCred -UseBasicParsing -TimeoutSec 5
    if ($r.Content -match "wazuh-alerts") {
        Pass "wazuh-alerts index" "index exists and has data"
    } else {
        Warn "wazuh-alerts index" "no wazuh-alerts-* index yet (normal before first event)"
    }
    Write-Host $r.Content -ForegroundColor DarkGray
} catch {
    Fail "elasticsearch indices" "$_"
}

Write-Host ""
Write-Host "  Health check complete." -ForegroundColor Cyan
Write-Host ""
