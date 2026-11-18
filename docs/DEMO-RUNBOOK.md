# SENTINEL-X — Demo Runbook

Step-by-step live demonstration script for interview or presentation.
All commands tested on 2026-11-13. Expected to run from Windows PowerShell or any terminal with Docker access.

---

## Pre-Demo Checklist

Run these before starting the demo:

```powershell
# 1. Verify all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}" | findstr sentinel

# Expected: 9 containers, all "Up X hours"
# If sentinel_filebeat_wazuh shows "Exited": docker start sentinel_filebeat_wazuh

# 2. Quick stack health check
curl -s -u elastic:changeme_elastic_lab http://localhost:9200/_cluster/health | python -c "import sys,json; d=json.load(sys.stdin); print('ES:', d['status'])"

# Expected: ES: green
```

---

## Step 1 — Normal Request (baseline)

**What to show:** Traffic passes through the WAF normally.

```bash
curl -v http://localhost/health
```

**Expected:** `HTTP/1.1 200 OK` with body `{"status": "ok"}`

**What to say:** "Here the request goes to port 80 on the host, is received by NGINX, forwarded through ModSecurity, and proxied to the Flask application on the internal Docker network. The app returns 200."

---

## Step 2 — SQL Injection Attack

**What to show:** WAF detects and blocks SQLi.

```bash
curl -v "http://localhost/search?q=1+OR+1=1--"
```

**Expected:** `HTTP/1.1 403 Forbidden` — nginx

**What to say:** "This is a classic SQL injection attempt — `1 OR 1=1--`. OWASP CRS rule 942100 uses libinjection to detect the SQLi pattern. ModSecurity scores it 8 points. The threshold is 5. The request is blocked before it reaches the application."

---

## Step 3 — NGINX + ModSecurity Response Evidence

**What to show:** The raw ModSec audit log entry.

```bash
# From inside the container:
docker exec sentinel_nginx_waf tail -5 /var/log/modsecurity/audit/modsec_audit.log | python3 -c "import sys,json; d=json.load(sys.stdin); print('Blocked:', d['transaction']['response']['http_code']); print('URI:', d['transaction']['request']['uri']); [print('Rule:', m['details']['ruleId'], '-', m['message']) for m in d['transaction']['messages'] if 'details' in m]"
```

**What to say:** "ModSecurity writes a full JSON audit record for every blocked request. It includes the client IP, the full request, every CRS rule that matched, the anomaly score calculation, and the HTTP 403 response that was sent."

---

## Step 4 — OWASP CRS Detection Evidence

**Key rule IDs to quote:**
- **942100**: SQL Injection Attack via libinjection (`REQUEST-942-APPLICATION-ATTACK-SQLI.conf`)
- **949110**: Inbound Anomaly Score Exceeded (threshold 5, actual score 8)
- **OWASP_CRS/4.30.0**: Component version loaded

**What to say:** "The OWASP Core Rule Set is a community-maintained set of ModSecurity rules. We're running CRS v4.30.0 at Paranoia Level 1. Rule 942100 is a SQLi signature using libinjection — a purpose-built injection detection library. Rule 949110 is the anomaly scoring gate: each matching rule adds to the score, and when the total exceeds the threshold, the request is blocked."

---

## Step 5 — Wazuh Alert Evidence

**What to show:** The same event as a Wazuh alert.

```powershell
# Query Wazuh Indexer directly
$body = '{"size":1,"query":{"term":{"rule.id":"100020"}},"sort":[{"@timestamp":{"order":"desc"}}],"_source":["@timestamp","rule.id","rule.level","rule.description","data.transaction.request.uri","data.transaction.client_ip","data.transaction.response.http_code"]}'
Invoke-RestMethod -Uri "https://localhost:9201/wazuh-alerts-4.x-*/_search" -Method POST -Headers @{Authorization="Basic "+[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:SecretPassword"));"Content-Type"="application/json"} -Body $body -SkipCertificateCheck | ConvertTo-Json -Depth 5
```

**What to say:** "Wazuh Manager read the ModSecurity audit log from the shared Docker volume, decoded the JSON, and applied custom rule 100020. This rule fires when it sees a ModSec event with CRS ID 932xxx... actually 942xxx. It assigns MITRE ATT&CK technique T1190 and T1059.007. The alert is at level 12 — that's our High severity band."

---

## Step 6 — The Same Alert in Elasticsearch

**What to show:** The event exists in Elasticsearch, with the same content.

```powershell
$auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("elastic:changeme_elastic_lab"))
$body = '{"size":1,"query":{"term":{"rule.id":"100020"}},"sort":[{"@timestamp":{"order":"desc"}}]}'
Invoke-RestMethod -Uri "http://localhost:9200/.ds-wazuh-alerts-*/_search" -Method POST -Headers @{Authorization=$auth;"Content-Type"="application/json"} -Body $body | Select-Object -ExpandProperty hits | Select-Object -ExpandProperty hits | ForEach-Object { $._source | ConvertTo-Json -Depth 3 }
```

**What to say:** "The same alert is in Elasticsearch via the separate Filebeat pipeline. Both Wazuh Indexer and Elasticsearch receive every Wazuh alert. The Wazuh Dashboard reads from the Wazuh Indexer; Kibana reads from Elasticsearch. This satisfies both the Wazuh native workflow and the assignment's Elasticsearch requirement."

---

## Step 7 — Kibana Discover

**Browser URL:** `http://localhost:5601`  
**Credentials:** elastic / changeme_elastic_lab

**Steps in browser:**
1. Navigate to **Discover** (left sidebar)
2. Select Data View: **SENTINEL-X Wazuh Alerts** (`wazuh-alerts-*`)
3. Set time range: **Last 24 hours**
4. Search: `rule.id: 100020`
5. Click on the event — expand the document
6. Point out fields: `rule.description`, `data.transaction.request.uri`, `data.transaction.response.http_code`, `rule.mitre.tactic`

**What to say:** "Here in Kibana Discover I can search the same events that are in Elasticsearch. I can filter by rule ID, by attack type, by time range. A SOC analyst would use this to investigate an alert, see the full HTTP request that was blocked, and pivot to other events from the same source IP."

---

## XSS Demonstration (supplementary)

```bash
curl -v "http://localhost/search?q=<script>alert(1)</script>"
# Expected: HTTP 403, rule 100021, CRS 941xxx
```

---

## LFI / Path Traversal Demonstration (supplementary)

```bash
curl -v "http://localhost/?file=../../../etc/passwd"
# Expected: HTTP 403, rule 100022, CRS 930xxx
```

---

## Wazuh Dashboard Demonstration

**Browser URL:** `https://localhost:5602`  
**Accept self-signed certificate warning**  
**Credentials:** admin / SecretPassword

**Key screens to show:**
1. **Executive Overview** dashboard — KPI tiles (Critical/High/Medium/Low counts), timeline
2. **Threat Detection & WAF** dashboard — WAF block events, attack type breakdown
3. **MITRE ATT&CK Coverage** dashboard — tactic distribution
4. **Infrastructure & Incidents** — agent inventory

---

## Troubleshooting

**Container not running:**
```powershell
docker ps -a | findstr sentinel  # find which container is down
docker start sentinel_<name>     # restart it
```

**filebeat_wazuh exited:**
```powershell
docker start sentinel_filebeat_wazuh  # always safe to restart
```

**Kibana not loading:**
```powershell
docker logs sentinel_kibana --tail 20  # check startup
# Wait up to 2 minutes for Kibana to fully initialize
```

**No events in Discover:**
1. Check time range — set to "Last 7 days" first
2. Verify Data View is set to `wazuh-alerts-*`
3. Check ES health: `curl -u elastic:changeme_elastic_lab http://localhost:9200/_cluster/health`

**ModSecurity not blocking:**
```powershell
# Check MODSEC_RULE_ENGINE in .env
Get-Content "C:\Prime Kosova\WORK\SENTINEL-X\.env" | Select-String MODSEC
# Should show: MODSEC_RULE_ENGINE=On
```

---

## Safe Cleanup

```powershell
# Stop stack but KEEP all data
docker compose down

# Start stack again (data preserved)
docker compose up -d

# NEVER run this — destroys all alert data:
# docker compose down -v
```
