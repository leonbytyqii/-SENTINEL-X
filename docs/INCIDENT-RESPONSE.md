# SENTINEL-X – Incident Response Procedures

## IR-01: Investigating a Suspicious Source IP

**Trigger:** Analyst notices repeated WAF blocks or multiple Wazuh alerts from a single IP.

**Step 1 – Kibana query**
```
data.srcip: "1.2.3.4" AND rule.level: >6
```
Sort by `@timestamp` descending. Review:
- First and last seen timestamps
- Rule IDs fired (SQL injection, XSS, scanner, etc.)
- URIs targeted

**Step 2 – Check NGINX access log**
```powershell
docker exec sentinel_nginx_waf grep "1.2.3.4" /var/log/nginx/access.log | tail -50
```

**Step 3 – Check ModSecurity audit log**
```powershell
docker exec sentinel_nginx_waf grep "1.2.3.4" /var/log/modsecurity/audit.log | head -20
```

**Step 4 – Decision**
- Isolated probe → note, monitor
- Sustained attack → enable blocking mode (`MODSEC_RULE_ENGINE=On`), consider IP-level block at network
- Automated scanner → review CRS scanner detection rules (913xxx), verify they fired

---

## IR-02: Investigating a WAF Block

**Trigger:** `rule.id: 100011` alert in Kibana (WAF blocked request).

**Step 1 – Identify the blocked request**
```
rule.id: "100011"
```
Note `data.url`, `data.srcip`, `@timestamp`.

**Step 2 – Find the full audit log entry**
```powershell
# Get recent audit entries
docker exec sentinel_nginx_waf tail -100 /var/log/modsecurity/audit.log | python -m json.tool 2>/dev/null
```
Look for `transaction.messages` to identify which CRS rule(s) matched.

**Step 3 – Assess**
- Is this a true positive? → document, escalate if severity > 10
- False positive? → document the specific rule ID, add a targeted exclusion in `exclusions/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf`, restart nginx-waf

**Step 4 – Exclusion documentation template**
```
# Rule ID: <XXXXX>
# Reason: <why this rule fires on legitimate traffic>
# Scope: <which endpoint or parameter>
# Risk: <what attack surface this exclusion opens>
# Date: <YYYY-MM-DD>
# Analyst: <name>
# SecRuleRemoveById XXXXX
```

---

## IR-03: Reviewing Correlated Alerts

**Trigger:** Rule `100030` fires (5+ blocks from same IP in 2 minutes = active attacker).

**Step 1 – Get the full alert timeline**
```
rule.id: "100030" OR rule.id: "100040"
```

**Step 2 – Group by source IP**
Use Kibana Lens: Metric `count`, split by `data.srcip`.

**Step 3 – Review attack categories**
```
data.srcip: "<attacker_ip>" AND tags: "wazuh-alert"
```
Check which rule groups match: `sql_injection`, `xss`, `lfi`, `scanning`, `brute_force`.

**Step 4 – Timeline reconstruction**
Add `@timestamp`, `data.url`, `rule.id` columns. Export to CSV for the incident report.

---

## IR-04: Identifying Targeted Endpoints

**Trigger:** Analyst wants to know which application paths are being attacked.

**Kibana aggregation:**
1. Open **Discover** → index `wazuh-alerts-*`
2. Add filter: `rule.groups: "web_attack"`
3. Add column: `data.url`
4. Click **Visualize** → Top 10 values of `data.url`

**PowerShell alternative:**
```powershell
$cred = Get-Credential
Invoke-RestMethod -Uri "http://localhost:9200/wazuh-alerts-*/_search" -Credential $cred `
    -Method POST -ContentType "application/json" -Body '{
      "size": 0,
      "aggs": {
        "top_urls": { "terms": { "field": "data.url.keyword", "size": 10 } }
      }
    }' | ConvertTo-Json -Depth 5
```

---

## IR-05: Preserving Evidence

**Step 1 – Export relevant Kibana events**
In Discover, apply filters, then: Share → CSV → Generate CSV.
Save to `evidence/reports/incident-<date>.csv`.

**Step 2 – Capture log snapshots**
```powershell
$ts = Get-Date -Format "yyyy-MM-dd_HHmmss"
docker exec sentinel_nginx_waf cat /var/log/nginx/access.log > "evidence\logs\nginx-access-$ts.log"
docker exec sentinel_nginx_waf cat /var/log/modsecurity/audit.log > "evidence\logs\modsec-audit-$ts.log"
docker exec sentinel_wazuh_manager cat /var/ossec/logs/alerts/alerts.json > "evidence\logs\wazuh-alerts-$ts.json"
```

**Step 3 – Document**
Create `evidence/reports/incident-<date>.md` with:
- Timeline
- Source IPs
- Attack types observed (CRS rule IDs)
- Actions taken
- False positive assessment

---

## IR-06: Escalation Criteria

| Condition | Action |
|-----------|--------|
| `rule.level` ≥ 14 (RCE signature) | Immediate escalation — treat as active intrusion attempt |
| `rule.id: 100030` from new IP | Block IP, increase monitoring for 24h |
| WAF bypass suspected (HTTP 200 on attack payload) | Review ModSecurity debug log, check CRS version/paranoia level |
| Elasticsearch ingestion lag > 5 min | Check Filebeat logs, Elasticsearch health |
