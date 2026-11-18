# SENTINEL-X — Troubleshooting Guide

**Version:** Phase 4  
**Last Updated:** 2026-11-13

---

## 1. Quick Diagnostics

Run these first when something seems wrong:

```powershell
# Check all container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check resource usage
docker stats --no-stream

# Check ES cluster health
curl -s -u elastic:changeme_elastic_lab http://localhost:9200/_cluster/health | python -m json.tool
```

---

## 2. Common Issues

### 2.1 No Alerts in Kibana After an Attack

**Symptom:** You sent a SQL injection request, got a 403, but no alert appears in Kibana.

**Diagnosis flow:**

**Step 1 — Did Wazuh generate an alert?**
```powershell
docker exec sentinel_wazuh_manager tail -20 /var/ossec/logs/alerts/alerts.json
```
If no new lines: Wazuh didn't match a rule → go to Step 2.  
If new lines exist: Filebeat isn't shipping → go to Step 4.

**Step 2 — Did ModSecurity log the event?**
```powershell
docker exec sentinel_nginx_waf sh -c "tail -5 /var/log/modsecurity/audit/modsec_audit.log"
```
If no log: ModSecurity didn't fire → check SecRuleEngine is On.  
If log exists: Wazuh isn't reading it → check localfile config.

**Step 3 — Are the custom rules loaded?**
```powershell
docker exec sentinel_wazuh_manager grep "Total rules enabled" /var/ossec/logs/ossec.log | tail -1
# Should be 6690+ (baseline 6676 + custom rules)
```
If 6676: Rules not loaded → check `<rule_dir>etc/rules/sentinel-x</rule_dir>` in ossec.conf.

**Step 4 — Is Filebeat shipping?**
```powershell
docker logs sentinel_filebeat --tail 10 2>&1 | Select-String "output|error|event"
```
Look for `events published` and no connection errors.

**Step 5 — Check the right ES index**
```powershell
curl -s -u elastic:changeme_elastic_lab "http://localhost:9200/_cat/indices/wazuh*?v"
```
The index is `wazuh-alerts-YYYY.MM.DD` matching today's date.

---

### 2.2 Wazuh Manager Won't Start

**Symptom:** `docker logs sentinel_wazuh_manager` shows CRITICAL errors, analysisd not running.

**Known causes and fixes:**

| Error Message | Cause | Fix |
|--------------|-------|-----|
| `CRITICAL: (1202): Configuration error at 'etc/ossec.conf'` | Invalid ossec.conf | Use `ossec.conf.default` to restore, check syntax |
| `ERROR: (2107): Decoder configuration error: 'sentinel-modsecurity-srcip'` | Broken custom decoder | Remove `<decoder_dir>etc/decoders/sentinel-x</decoder_dir>` from ossec.conf |
| `wazuh-dbd: CRITICAL: (1202)` | `<rule_file>` directive used instead of `<rule_dir>` | Replace `<rule_file>` with `<rule_dir>etc/rules/sentinel-x</rule_dir>` |
| Startup hang, analysisd never starts | Duplicate `<if_matched_sid>` referencing same parent | Check rules — two rules cannot both use `<if_matched_sid>` referencing the same parent |

**To restart Wazuh after fixing config:**
```powershell
docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart
```

**To check analysisd specifically:**
```powershell
docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control status
# Should show: wazuh-analysisd is running
```

---

### 2.3 ModSecurity Passes Attacks Instead of Blocking

**Symptom:** SQL injection request returns 200, not 403.

**Check SecRuleEngine:**
```powershell
docker exec sentinel_nginx_waf sh -c "grep SecRuleEngine /etc/modsecurity.d/modsecurity.conf"
# Must be: SecRuleEngine On
# NOT: SecRuleEngine DetectionOnly
```

**Check CRS rules are loaded:**
```powershell
docker exec sentinel_nginx_waf sh -c "ls /etc/modsecurity.d/owasp-crs/rules/*.conf | wc -l"
# Should be 51
```

**Check anomaly threshold:**
```powershell
docker exec sentinel_nginx_waf sh -c "grep 'inbound_anomaly_score_threshold' /etc/modsecurity.d/owasp-crs/crs-setup.conf"
# Should be: setvar:tx.inbound_anomaly_score_threshold=5
```

---

### 2.4 Rule Fires But Shows Wrong Rule ID

**Symptom:** Rule 100040 appears instead of 100020/100021/100022.

**Cause:** Rule 100040 was a child rule of 100020/100021/100022 using `<if_sid>`. In Wazuh 4.9.2, the deepest child rule always wins regardless of level.

**Fix:** Rule 100040 has been removed in Phase 3. If it reappears, check:
```powershell
docker exec sentinel_wazuh_manager grep "100040" /var/ossec/etc/rules/sentinel-x/sentinel_x_rules.xml
# Should return nothing
```

---

### 2.5 Elasticsearch at 99%+ Memory

**Symptom:** `docker stats` shows ES at 99%+ memory. Kibana becomes slow. Filebeat can't publish.

**Immediate check:**
```powershell
curl -s -u elastic:changeme_elastic_lab "http://localhost:9200/_cluster/health?pretty"
# Check status field
```

**Fix (increase memory limit):**
1. Edit `docker-compose.yml`
2. Find `elasticsearch` service
3. Change `mem_limit: 2g` to `mem_limit: 4g`
4. Change `ES_JAVA_OPTS: "-Xms1g -Xmx1g"` to `"-Xms2g -Xmx2g"`
5. Restart: `docker restart sentinel_elasticsearch`

---

## 3. Log Locations

| Component | Log Location (in container) | Host Volume |
|-----------|---------------------------|-------------|
| Wazuh alerts (JSON) | `/var/ossec/logs/alerts/alerts.json` | `sentinel_wazuh_logs` |
| Wazuh manager log | `/var/ossec/logs/ossec.log` | `sentinel_wazuh_logs` |
| Wazuh archive (all events) | `/var/ossec/logs/archives/archives.json` | `sentinel_wazuh_logs` |
| ModSecurity audit log | `/var/log/modsecurity/audit/modsec_audit.log` | `sentinel_modsec_logs` |
| NGINX access log (JSON) | `/var/log/nginx/access_json.log` | `sentinel_nginx_logs` |
| NGINX error log | `/var/log/nginx/error.log` | `sentinel_nginx_logs` |
| Filebeat internal logs | stdout (use `docker logs sentinel_filebeat`) | — |
| Elasticsearch logs | stdout (use `docker logs sentinel_elasticsearch`) | — |

**Quick log tailing:**
```powershell
# Wazuh alert stream (live)
docker exec sentinel_wazuh_manager tail -f /var/ossec/logs/alerts/alerts.json

# ModSec audit log
docker exec sentinel_nginx_waf sh -c "tail -f /var/log/modsecurity/audit/modsec_audit.log"

# NGINX access log
docker exec sentinel_nginx_waf sh -c "tail -f /var/log/nginx/access_json.log"
```

---

## 4. Testing a Specific Rule with wazuh-logtest

Wazuh includes `wazuh-logtest` to test rules against sample log lines without sending real traffic.

```powershell
# Enter Wazuh manager container
docker exec -it sentinel_wazuh_manager bash

# Run logtest
/var/ossec/bin/wazuh-logtest
```

Then paste a sample ModSec log line (JSON) and press Enter twice. The tool shows which decoder and rule matched.

**Example — test SQLi rule 100020:**
Paste a ModSec JSON line containing `"ruleId":"942160"` and `"http_code":403`. Expected output: `Rule 100020 fired`.

---

## 5. Verifying Rule Loading

After every change to `ossec.conf` or `sentinel_x_rules.xml`:

```powershell
# 1. Restart Wazuh
docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart

# 2. Check rule count (should be 6690+)
docker exec sentinel_wazuh_manager grep "Total rules enabled" /var/ossec/logs/ossec.log | tail -1

# 3. Verify no config errors
docker exec sentinel_wazuh_manager grep "ERROR\|CRITICAL" /var/ossec/logs/ossec.log | tail -20

# 4. Verify analysisd is running
docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control status | grep analysisd
```

---

## 6. Container Restart Procedure

### Safe Restart (no data loss)

```powershell
# Restart a single container (preserves volumes)
docker restart sentinel_wazuh_manager

# Restart all containers
docker restart sentinel_nginx_waf sentinel_webapp sentinel_wazuh_manager sentinel_filebeat sentinel_elasticsearch sentinel_kibana
```

### Recovery After OOM Kill (Elasticsearch)

If Elasticsearch was OOM-killed:
1. Data stream and indices survive in `sentinel_elasticsearch_data` volume
2. Simply restart: `docker start sentinel_elasticsearch`
3. Filebeat re-reads from its registry — no data loss if registry volume survived
4. Wait ~60s for ES to become healthy before Kibana connects

### NEVER use these commands

```powershell
# NEVER - deletes all volumes and all alert data
docker compose down -v

# NEVER - removes named volumes
docker volume rm sentinel_elasticsearch_data
docker volume rm sentinel_wazuh_logs
```

---

## 7. Verifying the Kibana Dashboard

```powershell
# Check Kibana is healthy
curl -s http://localhost:5601/api/status | python -m json.tool | Select-String "level"

# List SENTINEL-X saved objects
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("elastic:changeme_elastic_lab"))
Invoke-RestMethod "http://localhost:5601/api/saved_objects/_find?type=dashboard&search=SENTINEL-X" `
  -Headers @{"Authorization"="Basic $b64"}
```

---

## 8. Known Non-Issues

| Observation | Explanation |
|-------------|-------------|
| ES `ERROR: resource limit for file descriptors` | Expected in Docker on Windows — not fatal |
| Filebeat `Non-zero metrics` messages | Normal health reporting every 30s |
| Wazuh SCA/rootcheck alerts in Kibana | Expected Wazuh internal monitoring — filter with `rule.groups: "sentinel-x"` |
| `srcip` empty in alert descriptions | Custom decoders not loaded (decoder dir removed to prevent crash) — raw IP is in `data.remote_addr` |
| Alert count delta between tests | Each test run adds 6-12 new SENTINEL-X alerts |

---

## 9. Phase 4 — Wazuh Official Dashboard Troubleshooting

### 9.1 "APPLICATION NOT FOUND" After Login at :5602

**Cause:** Wazuh Dashboard 4.9.2 registers its main app as `wz-home`, not `wazuh`. The old `/app/wazuh` path is deprecated.

**Fix:** Already applied — `opensearch_dashboards.yml` sets:
```yaml
uiSettings.overrides.defaultRoute: "/app/wz-home"
```
If you still see it, clear browser cache or navigate manually to `https://localhost:5602/app/wz-home`.

---

### 9.2 Wazuh Dashboard Not Connecting to Wazuh Manager API

**Symptom:** Dashboard shows "No agents connected" or Wazuh plugin shows API error.

**Check wazuh.yml inside the container:**
```powershell
docker exec sentinel_wazuh_dashboard cat /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
```
Must show:
```yaml
hosts:
  - 1513629884013:
      url: https://wazuh-manager
      port: 55000
      username: wazuh-wui
      password: SentinelX_Wazuh!2024
      run_as: false
```

**Test API directly from dashboard container:**
```powershell
docker exec sentinel_wazuh_dashboard curl -sk -u "wazuh-wui:SentinelX_Wazuh!2024" `
  -X POST "https://wazuh-manager:55000/security/user/authenticate?raw=true" -w " HTTP:%{http_code}"
```
Expected: a JWT token + `HTTP:200`.

---

### 9.3 No Alerts Visible in Wazuh Dashboard

**Symptom:** Wazuh Overview shows 0 events.

**Step 1 — Check indexer alert count:**
```powershell
docker exec sentinel_wazuh_indexer curl -sk -u admin:SecretPassword `
  "https://localhost:9200/wazuh-alerts-4.x-*/_count"
```
Expected: `{"count":500+}`.

**Step 2 — Check Filebeat inside manager:**
```powershell
docker exec sentinel_wazuh_manager pgrep -a filebeat
# Should return PID + path
```
If no output: Filebeat died. Restart: `docker restart sentinel_wazuh_manager`.

**Step 3 — Check OpenSearch Security is initialized:**
```powershell
docker exec sentinel_wazuh_indexer curl -sk -u admin:SecretPassword `
  "https://localhost:9200/_cat/indices?v" | Select-String "security"
```
If `401 Unauthorized` on all calls: re-run securityadmin.sh.

```powershell
docker exec sentinel_wazuh_indexer bash /usr/share/wazuh-indexer/run-securityadmin.sh
# Or use the script at: infrastructure/wazuh-stack/run-securityadmin.sh
```

---

### 9.4 Wazuh Indexer Certificate / securityadmin.sh Errors

**Symptom:** After indexer restart, all API calls return 401 or connection refused.

**Re-initialize OpenSearch Security:**
```powershell
$script = @'
export JAVA_HOME=/usr/share/wazuh-indexer/jdk
export PATH=$JAVA_HOME/bin:$PATH
TOOLS=/usr/share/wazuh-indexer/plugins/opensearch-security/tools
DEFAULTS=/usr/share/wazuh-indexer/opensearch-security
CERTS=/usr/share/wazuh-indexer/certs
${TOOLS}/securityadmin.sh -cd ${DEFAULTS}/ -icl -nhnv \
  -cacert ${CERTS}/root-ca.pem -cert ${CERTS}/admin.pem -key ${CERTS}/admin.key -h 127.0.0.1
'@
docker exec sentinel_wazuh_indexer bash -c $script
```
All 10 config types should report `SUCC`.

---

### 9.5 Private Key Permissions (Windows Docker Limitation)

**Observation:** `.key` files inside containers show permissions `644` (world-readable) instead of `640`.

**Root cause:** Windows NTFS bind mounts do not support Unix permission bits. Docker cannot set `640` on files from Windows host paths — the bits reset to `644` on every container start.

**Mitigation in place:**
- `wazuh_stack_net` has `internal: true` — indexer, manager, Filebeat, and dashboard (OpenSearch side) are not reachable from outside the Docker bridge
- Port 5602 (dashboard) is on `management_net` which is NOT `internal`, but only the dashboard (not the keys) is exposed there
- For a production deployment, use Docker secrets or a dedicated cert volume created inside a Linux Docker VM

**Verification — confirm isolation:**
```powershell
docker network inspect sentinel_wazuh_stack | Select-String '"Internal"'
# Expected: "Internal": true
```

---

### 9.6 ES Memory at 99%+ After Adding Wazuh Indexer

**Current state:** Elasticsearch is at 99.67% / 2GiB. The container pre-dates the `memory: 4G` setting in compose and was not recreated to pick it up.

**Fix (brief ES downtime — Kibana only, Wazuh pipeline unaffected):**
```powershell
# Recreate ES container with the 4G compose limit (data volume preserved)
docker compose -f "C:\Prime Kosova\WORK\SENTINEL-X\docker-compose.yml" `
  up -d --force-recreate elasticsearch
```
Or reduce Java heap to 1G (stays within 2G container limit):
```powershell
# Add to .env: ES_JAVA_OPTS=-Xms1g -Xmx1g
# Then: docker restart sentinel_elasticsearch
```
