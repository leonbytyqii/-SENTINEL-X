<#
.SYNOPSIS
    SENTINEL-X - One-time Elasticsearch initialisation.
.DESCRIPTION
    Sets the kibana_system password, creates the ILM policy,
    and registers the index template.
    Run this ONCE after first docker compose up -d.
#>
$base = Split-Path $PSScriptRoot
$ErrorActionPreference = "Stop"

function Info { param($m) Write-Host "  [INIT]  $m" -ForegroundColor Cyan }
function Ok   { param($m) Write-Host "  [ OK ]  $m" -ForegroundColor Green }
function Fail { param($m) Write-Host "  [FAIL]  $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "====================================================" -ForegroundColor Magenta
Write-Host "  SENTINEL-X  -  Elasticsearch Initialisation      " -ForegroundColor Magenta
Write-Host "====================================================" -ForegroundColor Magenta
Write-Host ""

# Load passwords from .env
$esPass = "changeme_elastic_lab"; $kbPass = "changeme_kibana_lab"
if (Test-Path (Join-Path $base ".env")) {
    Get-Content (Join-Path $base ".env") | ForEach-Object {
        if ($_ -match "^ELASTIC_PASSWORD=(.+)$")  { $esPass = $Matches[1] }
        if ($_ -match "^KIBANA_PASSWORD=(.+)$")   { $kbPass = $Matches[1] }
    }
}
$esCred = New-Object PSCredential("elastic", (ConvertTo-SecureString $esPass -AsPlainText -Force))
$esBase = "http://localhost:9200"
$headers = @{ "Content-Type" = "application/json" }

# Wait for Elasticsearch
Info "Waiting for Elasticsearch..."
for ($i = 0; $i -lt 30; $i++) {
    try {
        $r = Invoke-RestMethod -Uri "$esBase/_cluster/health" -Credential $esCred -TimeoutSec 5
        if ($r.status -in "green","yellow") { Ok "Elasticsearch ready"; break }
    } catch {}
    $sec = $i * 5
    Write-Host "    ... waiting (${sec}s)" -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
    if ($i -eq 29) { Fail "Elasticsearch not ready after 150s" }
}

# Set kibana_system password
Info "Setting kibana_system password..."
$body = ConvertTo-Json @{ password = $kbPass }
try {
    Invoke-RestMethod -Uri "$esBase/_security/user/kibana_system/_password" `
                      -Method POST -Credential $esCred -Body $body -Headers $headers | Out-Null
    Ok "kibana_system password set"
} catch {
    Write-Host "  [WARN] Could not set kibana_system password: $_" -ForegroundColor Yellow
}

# Create ILM policy
Info "Creating ILM policy sentinel-x-policy..."
$policyJson = Get-Content (Join-Path $base "infrastructure\elasticsearch\lifecycle\sentinel-x-policy.json") -Raw
try {
    Invoke-RestMethod -Uri "$esBase/_ilm/policy/sentinel-x-policy" `
                      -Method PUT -Credential $esCred -Body $policyJson -Headers $headers | Out-Null
    Ok "ILM policy created"
} catch {
    Write-Host "  [WARN] ILM policy: $_" -ForegroundColor Yellow
}

# Create index template
Info "Creating index template sentinel-x..."
$templateJson = Get-Content (Join-Path $base "infrastructure\elasticsearch\templates\sentinel-x-template.json") -Raw
try {
    Invoke-RestMethod -Uri "$esBase/_index_template/sentinel-x" `
                      -Method PUT -Credential $esCred -Body $templateJson -Headers $headers | Out-Null
    Ok "Index template created"
} catch {
    Write-Host "  [WARN] Index template: $_" -ForegroundColor Yellow
}

Write-Host ""
Ok "Elasticsearch initialisation complete."
Write-Host "  Open Kibana at: http://localhost:5601 (login: elastic / $esPass)" -ForegroundColor Cyan
Write-Host ""
