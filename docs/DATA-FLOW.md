# SENTINEL-X – Security Event Data Flow

## End-to-End Event Lifecycle

This document traces a single malicious HTTP request from browser to Kibana dashboard.

---

## Step 1 – HTTP Request arrives at NGINX

**Component:** `sentinel_nginx_waf` (owasp/modsecurity-crs:nginx-alpine)
**Network:** `frontend_net` (port 80)

The browser or test client sends an HTTP request to `http://localhost/`.
NGINX receives the connection and passes it to the ModSecurity input filter before proxying.

---

## Step 2 – ModSecurity inspects the request

**Location:** ModSecurity v3 (libmodsecurity), embedded in NGINX via the NGINX connector.

ModSecurity evaluates the request against:
1. Base ModSecurity rules (body/header limits, protocol checks)
2. OWASP CRS rules (loaded from `/etc/modsecurity.d/owasp-crs/rules/`)

Each matching CRS rule adds to the **anomaly score**.
When the inbound anomaly score reaches the configured threshold:
- **DetectionOnly mode:** request passes through, event is logged.
- **Blocking mode (On):** NGINX returns HTTP 403.

**Audit log entry** written to `/var/log/modsecurity/audit.log` (JSON format):
```json
{
  "transaction": {
    "client_ip": "172.20.0.1",
    "request": {
      "method": "GET",
      "uri": "/api/users?id=1' OR '1'='1",
      "headers": { ... }
    },
    "messages": [
      { "message": "SQL Injection Attack Detected", "details": { "id": "942100" } }
    ]
  }
}
```

---

## Step 3 – NGINX writes access log

Regardless of WAF disposition, NGINX writes to `/var/log/nginx/access.log` (JSON format):
```json
{
  "@timestamp": "2024-11-12T14:00:00+00:00",
  "remote_addr": "172.20.0.1",
  "method": "GET",
  "uri": "/api/users?id=1%27+OR+%271%27%3D%271",
  "status": 403,
  "bytes_sent": 157
}
```

Both `/var/log/nginx/` and `/var/log/modsecurity/` are **named Docker volumes** shared with the Wazuh Manager container.

---

## Step 4 – Wazuh Manager detects the event

**Component:** `sentinel_wazuh_manager` (wazuh/wazuh-manager:4.9.2)
**Volume mount:** `nginx_logs:/var/log/nginx:ro` and `modsec_logs:/var/log/modsecurity:ro`

Wazuh's `logcollector` daemon monitors the log files via `<localfile>` configuration (`ossec.conf`).

**Processing pipeline:**
1. New line detected in `audit.log`
2. `logcollector` reads the line and routes it to the analysis engine
3. **Decoder** `sentinel-modsecurity` matches the JSON structure and extracts:
   - `srcip` (transaction.client_ip)
   - `url` (transaction.request.uri)
   - CRS rule IDs from messages array
4. **Rules engine** evaluates extracted fields against `sentinel_x_rules.xml`
5. Rule `100020` (SQL injection, level 12) matches → **alert generated**

Alert appended to `/var/ossec/logs/alerts/alerts.json`:
```json
{
  "timestamp": "2024-11-12T14:00:01.123+0000",
  "rule": { "id": "100020", "level": 12, "description": "SENTINEL-X: SQL Injection attempt detected" },
  "agent": { "id": "000", "name": "sentinel-manager" },
  "data": { "srcip": "172.20.0.1", "url": "/api/users?id=..." },
  "full_log": "..."
}
```

---

## Step 5 – Filebeat ships alerts to Elasticsearch

**Component:** `sentinel_filebeat` (filebeat:8.15.3)
**Input:** `/var/ossec/logs/alerts/alerts.json` (read-only via `wazuh_logs` volume)
**Output:** Elasticsearch `http://elasticsearch:9200`

Filebeat reads new lines (JSON), enriches with metadata fields (`sentinel-x`, `wazuh-alert` tags), and indexes into `wazuh-alerts-YYYY.MM.DD`.

---

## Step 6 – Elasticsearch indexes the event

**Component:** `sentinel_elasticsearch`
**Index:** `wazuh-alerts-2024.11.12`
**Template:** `sentinel-x` (custom field mappings for `rule.*`, `data.srcip`, `data.url`)
**ILM policy:** 7-day hot, 7-day warm (readonly), 30-day delete

The event is now searchable via Elasticsearch Query DSL or Kibana.

---

## Step 7 – Kibana surfaces the alert

**Component:** `sentinel_kibana`
**Index pattern:** `wazuh-alerts-*`

Analysts can query:
```
rule.level: >9 AND data.srcip: "172.20.0.1"
```
Or use the pre-built SENTINEL-X dashboards:
- **Security Operations Overview** – traffic volume, top attackers, severity distribution
- **WAF Attack Monitoring** – CRS rule triggers, blocked URIs, attack categories
- **SIEM Detection** – Wazuh rule alerts, MITRE ATT&CK mapping

---

## Data Flow Summary Diagram

```
Browser           NGINX+ModSecurity     Wazuh Manager      Filebeat        Elasticsearch    Kibana
   │                     │                    │                │                 │               │
   │── GET /api/users?id=1'OR─▶               │                │                 │               │
   │                     │── CRS match ──▶    │                │                 │               │
   │                     │── audit.log ──────▶│                │                 │               │
   │                     │── access.log ─────▶│                │                 │               │
   │◀──── HTTP 403 ───────│                    │── alert.json──▶│                 │               │
   │                     │                    │                │── wazuh-alerts──▶               │
   │                     │                    │                │                 │── dashboard──▶│
```
