# SENTINEL-X — Custom Implementation Reference

Everything that was manually configured, written, or designed for this project.
Distinguishes custom work from defaults provided by Docker images.

---

## What Came from Docker Images (NOT Custom)

The following came pre-configured inside the official Docker images:

| Component | Provided by Image |
|---|---|
| NGINX reverse proxy binary | `owasp/modsecurity-crs:nginx-alpine` |
| ModSecurity v3.0.17 module | `owasp/modsecurity-crs:nginx-alpine` |
| OWASP CRS 4.30.0 rules (856 rules) | `owasp/modsecurity-crs:nginx-alpine` |
| Wazuh Manager daemon suite | `wazuh/wazuh-manager:4.9.2` |
| Wazuh default decoders | `wazuh/wazuh-manager:4.9.2` |
| Wazuh default rules | `wazuh/wazuh-manager:4.9.2` |
| Wazuh Filebeat module | `docker.elastic.co/beats/filebeat-oss:7.10.2` |
| Elasticsearch binaries | `elasticsearch:8.15.3` |
| Kibana binaries | `kibana:8.15.3` |
| Wazuh Indexer (OpenSearch) | `wazuh/wazuh-indexer:4.9.2` |
| Wazuh Dashboard | `wazuh/wazuh-dashboard:4.9.2` |

---

## Custom Work — What YOU Built

### 1. Docker Compose Architecture (`docker-compose.yml`)

**Fully custom.** You designed the entire 9-container topology.

**Custom decisions:**
- 6 Docker networks with correct isolation (4 internal, 2 external bridge)
- 16 named volumes with correct mount points for log sharing between containers
- `security_opt: no-new-privileges: true` on 4 containers
- `read_only: true` filesystem on the webapp container
- `tmpfs: /tmp` on the webapp container (writable temp without persistent storage)
- Resource limits and reservations on all 9 containers
- Healthchecks with appropriate intervals and start periods
- Service dependencies using `service_healthy` condition (waits for healthchecks, not just container start)
- Environment variable injection from `.env` file
- The `MODSEC_RULE_ENGINE`, `PARANOIA`, `ANOMALY_INBOUND`, `ANOMALY_OUTBOUND` env vars

**Key architecture decision:**  
The webapp container is on `application_net` (internal: true) with **no host port mapping**. This means it is completely unreachable from outside Docker. The only path in is through nginx-waf. This is not a default — you configured it this way deliberately.

---

### 2. NGINX Configuration (`sentinel.conf`)

**Fully custom.** The OWASP image ships with a default NGINX config. You replaced it.

**Custom additions:**
```nginx
# JSON access log format with 15 fields (all parseable by Wazuh decoder)
log_format json_access escape=json '{...}';

# 6 security headers
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; ..." always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# server_tokens off (hides NGINX version from Server header)

# Request limits (body 10MB, timeouts 30s)

# /health endpoint returning JSON directly from NGINX (no proxy hop)

# Scanner path blocking: .git, .env, .htaccess, .htpasswd, .DS_Store
location ~* \.(git|env|htaccess|htpasswd|DS_Store)$ { deny all; }
```

**Why the JSON log format matters:**  
The 15-field JSON format in NGINX access logs is specifically designed to be parseable by the Wazuh NGINX decoder. The fields map to exactly what the decoder extracts. Without this format, Wazuh cannot parse the access logs.

---

### 3. ModSecurity Configuration

**Custom overrides** applied on top of image defaults.

**`modsecurity-override.conf`:**
- Changed audit log format to JSON (image default is non-JSON)
- Set audit log path to `/var/log/modsecurity/audit.log`
- Set `SecAuditEngine RelevantOnly` (only blocked requests logged, not every request)
- Enabled both request and response body inspection
- Set debug log level to 0 (silent in production)

**`crs-setup-override.conf`:**
- Allowed HTTP methods: added PUT, DELETE, PATCH (image default is GET/HEAD/POST only)
- Allowed content types: added `application/json` (required for REST API testing)
- Restricted extensions: added sensitive file extensions (.key, .pem, .bak, .cfg, .cmd, .exe, .dll)

**False positive exclusion files** (`exclusions/`):
- `REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf` — currently minimal exclusions
- `RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf` — currently minimal exclusions

---

### 4. Custom Wazuh Detection Rules (sentinel_x_rules.xml)

**Fully custom.** This is the most technically important custom component.

**Why custom rules were necessary:**  
The default Wazuh rules do not understand our specific log format. They don't know what OWASP CRS rule IDs like `942xxx` mean. The default rules produce generic alerts. Custom rules produce classified, MITRE-mapped, severity-graded alerts.

**Rule development challenge solved:**  
In Wazuh 4.9.2, JSON log events passed to `analysisd` are stored in `data.*` fields in archive output, but the `<field name="data.X">` rule condition does NOT match these fields. This is because `analysisd` uses the raw log text string for rule matching, not parsed fields. The only working approach is `<match>` against the raw JSON text. All 15 rules use this approach.

**Complete rule inventory:**

| Rule ID | Level | Type | Trigger | MITRE |
|---|---|---|---|---|
| 100001 | 0 (silent) | Base | NGINX JSON: `@timestamp` in log | — |
| 100002 | 3 | Child | NGINX: `"status":4` (4xx errors) | — |
| 100003 | 6 | Child | NGINX: `"status":403` (WAF block) | T1190 |
| 100004 | 5 | Child | NGINX: `"status":5` (5xx errors) | — |
| 100006 | 10 | Frequency | 10× 4xx from same IP in 60s | T1595 |
| 100007 | 8 | Child | Scanner user agents (sqlmap, nikto, etc.) | T1595.001 |
| 100010 | 0 (silent) | Base | ModSec JSON: `"transaction":` in log | — |
| 100011 | 8 | Child | ModSec: `"http_code":403` | T1190 |
| 100012 | 10 | Child | ModSec: `"ruleId":"949110"` (anomaly gate) | T1190 |
| 100020 | 12 | Child | ModSec: `"ruleId":"942` (SQLi) | T1190, T1059.007 |
| 100021 | 11 | Child | ModSec: `"ruleId":"941` (XSS) | T1190 |
| 100022 | 11 | Child | ModSec: `"ruleId":"930` (LFI) | T1190, T1083 |
| 100023 | 14 | Child | ModSec: `"ruleId":"932` (RCE pattern) | T1190, T1059 |
| 100030 | 13 | Frequency | 5× WAF blocks from same IP in 2 min | T1190, T1595 |

**Severity scale:**
- 0–2: Debug/informational (not shown by default)
- 3–5: Low
- 6–8: Medium
- 9–11: High
- 12–14: Critical
- 15: Maximum

**Rule hierarchy:**
```
100001 (NGINX base, level 0)
├── 100002 (4xx error, level 3)
│   └── 100006 (10× 4xx in 60s, level 10)
├── 100003 (403 specifically, level 6)
└── 100004 (5xx error, level 5)

100010 (ModSec base, level 0)
├── 100011 (blocked, level 8)
│   ├── 100012 (anomaly threshold exceeded, level 10)
│   ├── 100020 (SQLi 942xxx, level 12)
│   ├── 100021 (XSS 941xxx, level 11)
│   ├── 100022 (LFI 930xxx, level 11)
│   └── 100023 (RCE 932xxx, level 14)
│       └── 100030 (5× blocks in 2 min, level 13)
```

---

### 5. Custom Wazuh Decoders

**`modsecurity_decoders.xml`:**  
Extracts from ModSecurity JSON:
- `srcip` ← `client_ip` field inside `transaction` object
- `url` ← `request.uri`
- `protocol` ← `request.http_version`
- `id` ← HTTP status code

**`nginx_decoders.xml`:**  
Extracts from NGINX JSON access log:
- `srcip` ← `remote_addr`
- `url` ← `uri`
- `method` ← `method`
- `id` ← HTTP status

**Key design:** Both logs are JSON and both use the JSON decoder as parent. The custom child decoders extract the specific fields needed for rule conditions.

---

### 6. Flask Web Application

**Fully custom.** You wrote `applications\vulnerable-lab\src\app.py`.

**7 custom endpoints designed for specific WAF detections:**
- `/search?q=` → SQLi and XSS parameter
- `/?file=` → LFI parameter
- `/?cmd=` → RCE parameter
- `/api/users?id=` → Numeric SQLi parameter
- `/contact` (POST) → Request body inspection
- `/files?name=` → Path traversal
- `/admin` → Returns 403 (scanner detection)

**Security in the app itself:**  
All inputs are `html.escape()`d before being reflected. The app does not access the filesystem or database. If a request somehow bypasses the WAF, the app itself would not be exploitable.

---

### 7. Filebeat Pipeline 1 Configuration

**Custom.** `infrastructure\ingestion\config\filebeat.yml`

Custom additions over defaults:
- Input type: `log` with `json.keys_under_root: true` (Wazuh alerts are JSON)
- `ignore_older: 24h` (prevents reprocessing old events on restart)
- `scan_frequency: 5s` (check for new events every 5 seconds)
- `close_inactive: 2h` (close file handle after 2 hours of no new events)
- Tags: `["wazuh-alert", "sentinel-x"]` added to every document
- ECS version set to 8.0.0

---

### 8. TLS Certificate Infrastructure

**Custom generated.** Using `infrastructure\wazuh-stack\gen-certs.sh`

Generated certificates:
- Root CA (self-signed)
- Wazuh Indexer server cert (signed by Root CA)
- Wazuh Manager cert
- Wazuh Dashboard cert
- Admin client cert (for `run-securityadmin.sh`)

These enable mutual TLS between:
- Filebeat-wazuh → Wazuh Indexer
- Wazuh Manager → Wazuh Indexer
- Wazuh Dashboard → Wazuh Indexer

---

### 9. Custom Dashboards (Wazuh Dashboard)

4 custom OpenSearch Dashboards saved in Wazuh Dashboard:

**Executive Overview:**  
KPI tiles for Critical/High/Medium/Low event counts. Timeline of alerts by level. Total event count.

**Threat Detection & WAF:**  
WAF-specific visualizations. Blocked attacks by type (SQLi/XSS/LFI/RCE). Source IP frequency table. Rule ID distribution pie chart.

**MITRE ATT&CK Coverage:**  
Tactic distribution bar chart. Technique frequency table. Maps all 15 rules to their ATT&CK IDs.

**Infrastructure & Incidents:**  
Agent inventory (shows wazuh-manager as the monitoring agent). Service status. Event volume over time.

**Backup file:** `infrastructure\wazuh-stack\dashboard\config\sentinel_x_saved_objects_backup_20261113.ndjson`

---

### 10. Kibana Data View

Pre-configured via API:
- Name: "SENTINEL-X Wazuh Alerts"
- Pattern: `wazuh-alerts-*`
- Time field: `@timestamp`
- ID: `1c0ea900-67d7-4919-b6a2-5972824a42a8`

---

### 11. Management Scripts

Custom PowerShell scripts in `scripts\`:
- `start.ps1` — Ordered startup with health checks
- `stop.ps1` — Graceful shutdown
- `validate.ps1` — Full system validation (10 checks)
- `health-check.ps1` — Quick health status
- `backup.ps1` — Configuration and dashboard backup
- `init-elasticsearch.ps1` — First-time ES setup

---

### 12. Elasticsearch Index Template

Custom template at `infrastructure\elasticsearch\templates\sentinel-x-template.json`:
- Applies to `wazuh-alerts-*` data streams
- Sets `number_of_replicas: 0` (single-node lab, no replicas needed)
- Sets `refresh_interval: 5s` (events appear in search within 5 seconds)
- Defines field mappings for Wazuh alert fields

---

## Summary: Custom vs. Default

| Component | Custom | Default from Image |
|---|---|---|
| docker-compose.yml | ✓ 100% | — |
| NGINX sentinel.conf | ✓ 100% | Replaced default |
| ModSecurity audit settings | ✓ override | Base from image |
| CRS paranoia/thresholds | ✓ via env vars | Base from image |
| CRS rules (856 rules) | — | 100% from image |
| Flask application | ✓ 100% | — |
| Wazuh rules (sentinel_x_rules.xml) | ✓ 100% | Added on top of default rules |
| Wazuh decoders | ✓ custom decoders | Plus default decoders |
| Wazuh ossec.conf | ✓ customized | Based on default |
| Filebeat pipeline 1 config | ✓ 100% | — |
| Filebeat pipeline 2 config | ✓ customized | Based on Wazuh module |
| TLS certificates | ✓ generated | — |
| Wazuh dashboards (4) | ✓ 100% | — |
| Kibana Data View | ✓ configured | — |
| ES index template | ✓ customized | — |
| PowerShell scripts | ✓ 100% | — |
