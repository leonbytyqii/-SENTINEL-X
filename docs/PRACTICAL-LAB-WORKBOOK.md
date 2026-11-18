# SENTINEL-X — Practical Lab Workbook

Hands-on exercises using your existing SENTINEL-X environment.
All exercises are safe — no data destruction, no configuration changes.

---

## Prerequisites

All exercises assume SENTINEL-X is running. Verify before starting:
```powershell
docker ps --format "table {{.Names}}\t{{.Status}}" | Select-String sentinel
# All 9 containers should show "Up X hours"
```

If a container is not running:
```powershell
cd "C:\Prime Kosova\WORK\SENTINEL-X"
docker compose start <container_name>
```

---

## Exercise 1 — Start and Stop Individual Containers

**Objective:** Learn how to control individual services without affecting others.  
**Time:** 10 minutes  
**Risk:** None — no data loss.

```powershell
# Stop Kibana only
docker stop sentinel_kibana
# Verify it stopped
docker ps | Select-String kibana
# Notice: Kibana is now "Exited" but Elasticsearch still runs

# Restart Kibana
docker start sentinel_kibana
# Wait for Kibana to become healthy (up to 2 minutes)
docker exec sentinel_kibana curl -s http://localhost:5601/api/status | python -c "import sys,json; d=json.load(sys.stdin); print(d['status']['overall']['level'])"
# Should print: available

# Stop the entire stack (safely)
docker compose stop
# Restart it
docker compose start
```

**What you learned:**  
- Individual containers can be stopped without destroying data
- Kibana takes 1–2 minutes to fully start (Elasticsearch must be healthy first)
- `docker stop` gracefully shuts down; `docker kill` forces immediate termination

---

## Exercise 2 — Inspect Docker Networks

**Objective:** Understand why the webapp is isolated.  
**Time:** 15 minutes

```powershell
# List all SENTINEL-X networks
docker network ls | Select-String sentinel

# Inspect the application network (nginx-waf <-> webapp)
docker network inspect sentinel_application_net
# Look for: "Internal": true  <-- this is what blocks external access
# Look for: containers listed (nginx_waf and webapp)

# Inspect the frontend network
docker network inspect sentinel_frontend_net
# Look for: "Internal": false  <-- external bridge
# Only nginx_waf is here

# Try to ping webapp directly from your host (should FAIL)
# This confirms isolation
docker run --rm alpine ping -c 2 webapp
# Error: "bad address 'webapp'" -- host has no route to internal network
```

**Now try reaching webapp through NGINX (should work):**
```powershell
curl http://localhost/health
# 200 OK -- NGINX proxied to webapp
```

**What you learned:**  
- `internal: true` networks have no default gateway
- Containers on internal networks are only reachable by other containers on the same network
- NGINX is the only container on BOTH frontend_net and application_net — it's the bridge

---

## Exercise 3 — Read NGINX Logs

**Objective:** Understand the JSON log format and what fields Wazuh reads.  
**Time:** 15 minutes

```powershell
# Generate a request first
curl http://localhost/health
curl http://localhost/search?q=test

# Read the NGINX access log from inside the container
docker exec sentinel_nginx_waf tail -5 /var/log/nginx/access.log
```

**You should see output like:**
```json
{"@timestamp":"2026-11-14T10:00:00+00:00","remote_addr":"172.17.0.1","method":"GET","uri":"/health","protocol":"HTTP/1.1","status":200,...}
```

**Parse a specific field:**
```powershell
docker exec sentinel_nginx_waf cat /var/log/nginx/access.log | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        print(d.get('@timestamp'), d.get('status'), d.get('uri'))
    except: pass
" 2>/dev/null
```

**What you learned:**  
- NGINX writes JSON (not plain text) so Wazuh can parse it without complex regex
- The `status` field is an integer (403, 200) — Wazuh's rule matches `"status":403` as text
- Every field in the log format definition in `sentinel.conf` appears here

---

## Exercise 4 — Trigger SQL Injection Detection

**Objective:** Produce a real WAF block event and trace it.  
**Time:** 20 minutes

```powershell
# Classic SQLi — always-true condition
curl -v "http://localhost/search?q=1 OR 1=1--"
# Expected: HTTP/1.1 403 Forbidden

# Union-based SQLi
curl -v "http://localhost/api/users?id=1 UNION SELECT 1,2,3--"
# Expected: HTTP/1.1 403 Forbidden

# Stacked queries
curl -v "http://localhost/search?q=test; DROP TABLE users--"
# Expected: HTTP/1.1 403 Forbidden

# Wait 10-15 seconds, then check Wazuh Indexer for the alerts
curl -sk -u admin:SecretPassword "https://localhost:9201/wazuh-alerts-4.x-*/_search?size=3&sort=@timestamp:desc" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for h in d['hits']['hits']:
    s = h['_source']
    print(s.get('@timestamp'), 'rule:', s.get('rule',{}).get('id'), s.get('rule',{}).get('description','')[:60])
"
```

**What you learned:**  
- Multiple SQLi patterns are blocked by different CRS rules (942100, 942160, 942260...)
- All map to Wazuh rule 100020 because they all contain `"ruleId":"942`
- The alert appears in Wazuh Indexer within ~10 seconds

---

## Exercise 5 — Find the ModSecurity Audit Event

**Objective:** Read raw WAF evidence from the audit log.  
**Time:** 20 minutes

```powershell
# Generate a fresh attack
curl "http://localhost/search?q=1 OR 1=1--" 2>$null

# Read the audit log inside the container
# Note: audit.log has one JSON object per blocked request
docker exec sentinel_nginx_waf python3 -c "
import json, sys
with open('/var/log/modsecurity/audit.log') as f:
    content = f.read().strip()
    # Find last complete JSON object
    # Each entry ends with }}
    entries = []
    depth = 0
    start = 0
    for i, c in enumerate(content):
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                try:
                    obj = json.loads(content[start:i+1])
                    entries.append(obj)
                except: pass
                start = i+1
    if entries:
        last = entries[-1]
        t = last.get('transaction', {})
        print('Client IP:', t.get('client_ip'))
        print('URI:', t.get('request', {}).get('uri'))
        print('HTTP code:', t.get('response', {}).get('http_code'))
        print('Interrupted:', t.get('is_interrupted'))
        for m in t.get('messages', []):
            d = m.get('details', {})
            print('Rule:', d.get('ruleId'), '-', m.get('message','')[:60])
"
```

**Expected output:**
```
Client IP: 172.17.0.1
URI: /search?q=1 OR 1=1--
HTTP code: 403
Interrupted: True
Rule: 942100 - SQL Injection Attack Detected via libinjection
Rule: 949110 - Inbound Anomaly Score Exceeded (Total Score: ...)
```

**What you learned:**  
- The audit log contains the FULL evidence chain: every rule that matched, the matched data, the score
- This is exactly what Wazuh reads and what appears in `data.transaction.messages` in Kibana
- `is_interrupted: true` confirms the request was blocked (not just logged)

---

## Exercise 6 — Identify the Wazuh Rule That Triggered

**Objective:** Understand how Wazuh processes the audit log event.  
**Time:** 15 minutes

```powershell
# Query Wazuh Indexer for the most recent SQLi alert
$body = '{"query":{"term":{"rule.id":"100020"}},"sort":[{"@timestamp":{"order":"desc"}}],"size":1}'
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:SecretPassword"))
    "Content-Type" = "application/json"
}
$result = Invoke-RestMethod -Uri "https://localhost:9201/wazuh-alerts-4.x-*/_search" -Method POST -Headers $headers -Body $body -SkipCertificateCheck

$hit = $result.hits.hits[0]._source
Write-Host "Time:        " $hit.'@timestamp'
Write-Host "Rule ID:     " $hit.rule.id
Write-Host "Level:       " $hit.rule.level
Write-Host "Description: " $hit.rule.description
Write-Host "MITRE:       " ($hit.rule.mitre.id -join ", ")
Write-Host "Groups:      " ($hit.rule.groups -join ", ")
Write-Host "URI:         " $hit.data.transaction.request.uri
```

**Now read the actual rule:**
```powershell
Get-Content "C:\Prime Kosova\WORK\SENTINEL-X\infrastructure\wazuh\rules\sentinel_x_rules.xml" | Select-String -Context 2,8 "100020"
```

**What you learned:**  
- The rule ID in the Wazuh alert matches exactly the rule in `sentinel_x_rules.xml`
- The `if_sid: 100011` in the rule means it only fires AFTER rule 100011 (blocked request) fires
- `<match>"ruleId":"942</match>` is the trigger — it matches the string in the ModSec audit JSON

---

## Exercise 7 — Query Events from Elasticsearch

**Objective:** Use the Elasticsearch API to investigate alerts.  
**Time:** 20 minutes

```powershell
$auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("elastic:changeme_elastic_lab"))

# Get total alert count
Invoke-RestMethod -Uri "http://localhost:9200/.ds-wazuh-alerts-*/_count" -Headers @{Authorization=$auth}

# Count by rule level (aggregation)
$body = '{"aggs":{"by_level":{"terms":{"field":"rule.level","size":10}}},"size":0}'
$r = Invoke-RestMethod -Uri "http://localhost:9200/.ds-wazuh-alerts-*/_search" -Method POST -Headers @{Authorization=$auth;"Content-Type"="application/json"} -Body $body
$r.aggregations.by_level.buckets | ForEach-Object { Write-Host "Level $($_.key): $($_.doc_count) events" }

# Get all SQLi events
$body = '{"query":{"term":{"rule.id":"100020"}},"_source":["@timestamp","rule.level","data.transaction.client_ip"],"size":10}'
$r = Invoke-RestMethod -Uri "http://localhost:9200/.ds-wazuh-alerts-*/_search" -Method POST -Headers @{Authorization=$auth;"Content-Type"="application/json"} -Body $body
$r.hits.hits._source | ForEach-Object { Write-Host $_.'@timestamp', "from", $_.data.transaction.client_ip }
```

**What you learned:**  
- Elasticsearch REST API uses POST with a JSON body for complex queries
- Aggregations let you group and count events (like SQL GROUP BY)
- The same alert exists in BOTH Elasticsearch AND Wazuh Indexer (independent pipelines)

---

## Exercise 8 — Find the Event in Kibana

**Objective:** Use Kibana Discover to investigate the same alert in a browser.  
**Time:** 15 minutes

**Steps:**
1. Open `http://localhost:5601` → login with `elastic` / `changeme_elastic_lab`
2. Click **Discover** in the left sidebar
3. Select Data View: **SENTINEL-X Wazuh Alerts** (from dropdown at top left)
4. Set time range: **Last 24 hours** (top right)
5. In the search box type: `rule.id: 100020`
6. Press Enter — you should see SQLi events
7. Click on the **>** to expand one event
8. Find these fields and understand what they mean:
   - `rule.description`
   - `data.transaction.request.uri`
   - `data.transaction.client_ip`
   - `rule.mitre.id`
   - `data.transaction.producer.components`

**Advanced:** Add columns to the table:
- Click the + next to `rule.description`
- Click the + next to `rule.level`
- Now the table shows those fields inline

**What you learned:**  
- Kibana Discover is the analyst's primary investigation tool
- KQL (Kibana Query Language) is similar to Elasticsearch query DSL but human-readable
- You can filter, group, and pivot on any indexed field

---

## Exercise 9 — Add a Custom Wazuh Detection Rule

**Objective:** Write a new rule that detects HTTP 404 errors from scanning tools.  
**Time:** 25 minutes  
**Risk:** Low — adding rules does not affect existing detection.

**Step 1 — Add the rule:**

Open `C:\Prime Kosova\WORK\SENTINEL-X\infrastructure\wazuh\rules\sentinel_x_rules.xml`

After the `100007` rule block, add:
```xml
  <!-- HTTP 404 Not Found — potential scanner/recon -->
  <rule id="100008" level="4">
    <if_sid>100001</if_sid>
    <match>"status":404</match>
    <description>SENTINEL-X: HTTP 404 from $(srcip) - possible recon</description>
    <group>nginx,http_error,recon,</group>
    <mitre>
      <id>T1595</id>
    </mitre>
  </rule>
```

**Step 2 — Reload Wazuh rules (without restarting):**
```powershell
$env:PATH += ";C:\Program Files\Docker\Docker\resources\bin"
docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart
# Wait 10 seconds
```

**Step 3 — Trigger the new rule:**
```powershell
curl http://localhost/nonexistent-page-12345
# Should return 403 from NGINX (scanner path block) or 404 from app
# Try:
curl "http://localhost/api/doesnotexist"
```

**Step 4 — Verify:**
```powershell
# Check Wazuh Indexer for rule 100008
Start-Sleep -Seconds 15
$body = '{"query":{"term":{"rule.id":"100008"}},"sort":[{"@timestamp":{"order":"desc"}}],"size":3}'
$headers = @{Authorization="Basic "+[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:SecretPassword"));"Content-Type"="application/json"}
Invoke-RestMethod -Uri "https://localhost:9201/wazuh-alerts-4.x-*/_search" -Method POST -Headers $headers -Body $body -SkipCertificateCheck | ConvertTo-Json -Depth 3
```

**What you learned:**  
- Rules are hot-reloadable without restarting the full stack
- `if_sid: 100001` means the rule only evaluates NGINX access log events
- Level 4 = low severity (informational)
- T1595 (Active Scanning) is the appropriate MITRE tactic for recon

---

## Exercise 10 — Build a Kibana Visualization

**Objective:** Create a simple bar chart showing alert counts by rule level.  
**Time:** 20 minutes

**Steps:**
1. Open `http://localhost:5601`
2. Click **Visualize Library** in the left sidebar
3. Click **Create visualization**
4. Select **Lens**
5. Set Data View: **SENTINEL-X Wazuh Alerts**
6. Time range: **Last 7 days**
7. In the chart builder:
   - Set X-axis: `rule.level` (keyword field)
   - Set Y-axis: Count of events
   - Chart type: **Bar vertical**
8. Click **Save**
9. Name it: "Alert Levels Distribution"

**What you learned:**  
- Kibana Lens is a drag-and-drop chart builder
- You can visualize any field in Elasticsearch without writing queries
- This same technique builds the dashboards in the professional SOC tools

---

## Exercise 11 — Troubleshoot a Stopped Filebeat

**Objective:** Reproduce and recover from the Filebeat silent-exit issue.  
**Time:** 20 minutes  
**Safe to do:** Yes — Filebeat state is preserved in Docker volumes.

**Simulate the issue:**
```powershell
$env:PATH += ";C:\Program Files\Docker\Docker\resources\bin"
# Stop Filebeat cleanly (simulates the close_inactive exit)
docker stop sentinel_filebeat_wazuh
docker ps | Select-String filebeat
# sentinel_filebeat_wazuh is now Exited
```

**Check how long Wazuh Indexer event count stays the same:**
```powershell
$headers = @{Authorization="Basic "+[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:SecretPassword"))}
$before = (Invoke-RestMethod -Uri "https://localhost:9201/wazuh-alerts-4.x-*/_count" -Headers $headers -SkipCertificateCheck).count
Write-Host "Count before restart: $before"

# Generate some attacks
curl "http://localhost/search?q=1 OR 1=1--" 2>$null
Start-Sleep -Seconds 15

$after_stopped = (Invoke-RestMethod -Uri "https://localhost:9201/wazuh-alerts-4.x-*/_count" -Headers $headers -SkipCertificateCheck).count
Write-Host "Count while stopped: $after_stopped"
# Should be same as before — Filebeat not running = events not forwarded
```

**Recover:**
```powershell
docker start sentinel_filebeat_wazuh
Start-Sleep -Seconds 20

$after_restart = (Invoke-RestMethod -Uri "https://localhost:9201/wazuh-alerts-4.x-*/_count" -Headers $headers -SkipCertificateCheck).count
Write-Host "Count after restart: $after_restart"
# Should be higher — Filebeat caught up on missed events
```

**What you learned:**  
- Filebeat does NOT lose events when stopped — it resumes from the registry position
- The registry is in the `filebeat_wazuh_data` Docker volume
- `restart: unless-stopped` does NOT auto-restart clean exits — the gap in coverage is real
- Fix: change to `restart: always` in docker-compose.yml

---

## Exercise 12 — Investigate a Suspicious Event Like a SOC Analyst

**Objective:** Practice the full analyst workflow from alert to context.  
**Time:** 30 minutes

**Scenario:** You receive an alert. Rule 100030 fired — "Persistent attack: 5+ WAF blocks from same IP in 2 minutes."

**Step 1 — Trigger the scenario:**
```powershell
# Generate 6 attacks rapidly from the same source (your machine)
1..6 | ForEach-Object {
    curl "http://localhost/search?q=1 OR 1=1--" 2>$null
    curl "http://localhost/search?q=<script>alert(1)</script>" 2>$null
    Start-Sleep -Milliseconds 500
}
```

**Step 2 — Triage the alert in Wazuh Dashboard:**
1. Open `https://localhost:5602`
2. Navigate to Threat Detection & WAF dashboard
3. Look for high-level events in the last 15 minutes

**Step 3 — Investigate in Kibana:**
1. Open `http://localhost:5601` → Discover
2. Time range: Last 15 minutes
3. Search: `rule.level >= 10`
4. Find the events from your IP (172.17.0.1 or 127.0.0.1)
5. Answer:
   - What attack types were used? (rule.groups)
   - How many requests were made? (count the events)
   - What URIs were targeted? (data.transaction.request.uri)

**Step 4 — Pivot to find all events from that IP:**
1. In Kibana, right-click on the `data.transaction.client_ip` value
2. Select "Filter for value"
3. Now see ALL events from that IP — both attack attempts

**Step 5 — Write a summary (practice for real SOC work):**
```
INCIDENT SUMMARY
Date: [today]
Source IP: 172.17.0.1
Attack types: SQL injection, XSS
Request count: ~12 blocked requests
Timeframe: 2 minutes
Disposition: All requests blocked by WAF
Recommended action: Monitor. If attacks continue from same IP, consider IP block.
```

**What you learned:**  
- SOC analysis is about context, not just individual alerts
- Kibana filtering lets you pivot from one field to find related events
- The difference between detection (Wazuh rule fired), prevention (WAF blocked), and response (what the analyst decides)

---

## Checkpoint — Can You Answer These?

After completing all exercises:

1. What is the difference between `docker stop` and `docker compose down -v`?
2. Why can't you reach the Flask app directly from your browser?
3. What two log files does Wazuh read in SENTINEL-X?
4. What field in the ModSec audit log does Wazuh rule 100020 match on?
5. What is the difference between Elasticsearch `.ds-wazuh-alerts-*` and `wazuh-alerts-4.x-*`?
6. If Filebeat stops, do you lose the events that occurred while it was stopped?
7. How do you reload Wazuh rules without restarting the entire container?
8. What does `rule.level: 14` mean in a Wazuh alert?
9. What MITRE technique does rule 100023 (RCE) map to?
10. What is the KQL query in Kibana to find all blocking events?

**Answers:**  
1. `docker stop` = graceful stop, volumes preserved. `docker compose down -v` = destroys all volumes and data.
2. `sentinel_webapp` has no host port mapping and is on `internal: true` network.
3. `/var/log/nginx/access.log` and `/var/log/modsecurity/audit.log`
4. `"ruleId":"942` — the string must appear in the raw log text.
5. ES uses data streams (`ds-wazuh-alerts-*`); Wazuh Indexer uses regular indices (`wazuh-alerts-4.x-*`).
6. No — Filebeat resumes from the registry position when restarted.
7. `docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart`
8. Critical severity (scale 0–15; 12–14 = critical).
9. T1190 (Exploit Public-Facing Application) + T1059 (Command and Scripting Interpreter).
10. `rule.groups: blocked` or `rule.level >= 11`
