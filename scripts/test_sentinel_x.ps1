# SENTINEL-X Security Test Suite
# Runs 10 WAF + pipeline checks and prints a PASS/FAIL summary.
# Usage: .\scripts\test_sentinel_x.ps1

param(
    [string]$BaseUrl  = "http://localhost",
    [string]$ESUrl    = "http://localhost:9200",
    [string]$ESUser   = "elastic",
    [string]$ESPass   = "changeme_elastic_lab",
    [int]   $MinAlerts = 50
)

$docker = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
$pass   = 0
$fail   = 0
$results = @()

function Test-Case {
    param($Id, $Name, $Expr)
    try {
        $ok = & $Expr
        if ($ok) {
            $script:pass++
            $script:results += [pscustomobject]@{ ID=$Id; Name=$Name; Result="PASS" }
        } else {
            $script:fail++
            $script:results += [pscustomobject]@{ ID=$Id; Name=$Name; Result="FAIL" }
        }
    } catch {
        $script:fail++
        $script:results += [pscustomobject]@{ ID=$Id; Name=$Name; Result="ERROR: $_" }
    }
}

Write-Host ""
Write-Host "====================================================="
Write-Host "   SENTINEL-X Security Test Suite"
Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "====================================================="
Write-Host ""

# ── T01: Health endpoint returns 200 ─────────────────────────────────────────
Test-Case "T01" "Health endpoint returns 200" {
    $r = Invoke-WebRequest "$BaseUrl/health" -UseBasicParsing -EA Stop
    $r.StatusCode -eq 200
}

# ── T02: Normal API request returns 200 ──────────────────────────────────────
Test-Case "T02" "Normal API request returns 200" {
    $r = Invoke-WebRequest "$BaseUrl/api/users?id=1" -UseBasicParsing -EA Stop
    $r.StatusCode -eq 200
}

# ── T03: SQL injection (OR clause) blocked 403 ───────────────────────────────
Test-Case "T03" "SQL injection OR clause blocked (403)" {
    try { $null = Invoke-WebRequest "$BaseUrl/search?q=1'+OR+1=1--" -UseBasicParsing -EA Stop; $false }
    catch { $_.Exception.Response.StatusCode.value__ -eq 403 }
}

# ── T04: SQL injection UNION SELECT blocked 403 ──────────────────────────────
Test-Case "T04" "SQL injection UNION SELECT blocked (403)" {
    try { $null = Invoke-WebRequest "$BaseUrl/api/users?id=1+UNION+SELECT+1,2,3--" -UseBasicParsing -EA Stop; $false }
    catch { $_.Exception.Response.StatusCode.value__ -eq 403 }
}

# ── T05: XSS script tag blocked 403 ──────────────────────────────────────────
Test-Case "T05" "XSS <script> tag blocked (403)" {
    try { $null = Invoke-WebRequest "$BaseUrl/search?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E" -UseBasicParsing -EA Stop; $false }
    catch { $_.Exception.Response.StatusCode.value__ -eq 403 }
}

# ── T06: LFI path traversal blocked 403 ──────────────────────────────────────
Test-Case "T06" "LFI path traversal blocked (403)" {
    try { $null = Invoke-WebRequest "$BaseUrl/files?name=../../etc/passwd" -UseBasicParsing -EA Stop; $false }
    catch { $_.Exception.Response.StatusCode.value__ -eq 403 }
}

# ── T07: RCE shell command blocked 403 ───────────────────────────────────────
Test-Case "T07" "RCE shell injection blocked (403)" {
    try { $null = Invoke-WebRequest "$BaseUrl/search?q=;cat+/etc/passwd" -UseBasicParsing -EA Stop; $false }
    catch { $_.Exception.Response.StatusCode.value__ -eq 403 }
}

# ── T08: Scanner User-Agent blocked 403 ──────────────────────────────────────
Test-Case "T08" "sqlmap User-Agent blocked (403)" {
    try {
        $h = @{"User-Agent"="sqlmap/1.7.8#stable"}
        $null = Invoke-WebRequest "$BaseUrl/" -Headers $h -UseBasicParsing -EA Stop; $false
    }
    catch { $_.Exception.Response.StatusCode.value__ -eq 403 }
}

# ── T09: Elasticsearch alerts ingested ────────────────────────────────────────
Test-Case "T09" "Elasticsearch has $MinAlerts+ wazuh-alerts" {
    $authHdr = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ESUser}:${ESPass}"))
    $r = Invoke-RestMethod "$ESUrl/wazuh-alerts-*/_count" -Headers @{"Authorization"="Basic $authHdr"} -EA Stop
    $r.count -ge $MinAlerts
}

# ── T10: Kibana dashboards present ───────────────────────────────────────────
Test-Case "T10" "Kibana SOC dashboards present (>=3)" {
    $authHdr = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ESUser}:${ESPass}"))
    $r = Invoke-RestMethod "http://localhost:5601/api/saved_objects/_find?type=dashboard&per_page=20" `
        -Headers @{"Authorization"="Basic $authHdr";"kbn-xsrf"="true"} -EA Stop
    $r.total -ge 3
}

# ── Results ────────────────────────────────────────────────────────────────────
Write-Host ""
$results | Format-Table -AutoSize

$total = $pass + $fail
Write-Host ""
Write-Host "====================================================="
if ($fail -eq 0) {
    Write-Host "   RESULT: $pass/$total PASS -- ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "   RESULT: $pass/$total PASS / $fail FAIL" -ForegroundColor Yellow
}
Write-Host "====================================================="
Write-Host ""
