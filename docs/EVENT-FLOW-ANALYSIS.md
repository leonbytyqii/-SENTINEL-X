# SENTINEL-X — Event Flow Analysis

Tracing real attacks through every component in the stack.
All evidence is from the actual SENTINEL-X environment (verified 2026-11-13).

---

## Terminology

- **Detection:** The WAF or SIEM recognizes a malicious pattern
- **Prevention:** The WAF blocks the request — it never reaches the application
- **Alert generation:** Wazuh creates a structured alert document
- **Event forwarding:** Filebeat ships the alert to storage
- **Storage:** The alert is indexed in Elasticsearch or Wazuh Indexer
- **Visualization:** The alert is visible in Kibana or Wazuh Dashboard

---

## Attack 1: SQL Injection

### Step 1 — Client Sends Attack Request

```
Attacker/client sends:
  GET /search?q=1+OR+1=1-- HTTP/1.1
  Host: localhost
```

The URL-decoded query: `1 OR 1=1--`  
This is a classic SQL injection "always-true" condition. `OR 1=1` makes any WHERE clause return all rows. `--` comments out the rest of the SQL query.

---

### Step 2 — NGINX Receives the Request

NGINX listens on internal port 8080 (exposed as host port 80).

**Config file:** `infrastructure\nginx\conf.d\sentinel.conf`  
**Key setting:** `proxy_pass http://webapp:8080;`

NGINX receives the request and passes it to ModSecurity BEFORE forwarding.

**NGINX access log entry (written after response):**
```json
{
  "@timestamp": "2026-11-13T11:07:23+00:00",
  "remote_addr": "172.17.0.1",
  "method": "GET",
  "uri": "/search?q=1+OR+1=1--",
  "status": 403,
  "bytes_sent": 157,
  "user_agent": "curl/8.11.0"
}
```

---

### Step 3 — ModSecurity Inspects the Request

**Config files:**  
- `infrastructure\modsecurity\modsecurity-override.conf` (audit log settings)
- `infrastructure\modsecurity\crs-setup-override.conf` (paranoia level, thresholds)

ModSecurity runs the request through the OWASP CRS in phases:

**Phase 1 (headers):** No matches on URI path alone.

**Phase 2 (query parameters):**  
- CRS rule **942100** runs libinjection on `ARGS:q = "1 OR 1=1--"`
- libinjection fingerprints: SQL injection detected, fingerprint code `1&1c`
- Match: `Matched Data: 1&1c found within ARGS:q: 1 OR 1=1--`
- Anomaly score +5 (Critical)

**Phase 2 continued:**  
- CRS rule **920350** (IP address in Host header): +3
- Total inbound score: **8**

**Rule 949110 fires:**  
"Inbound Anomaly Score Exceeded (Total Score: 8)" — threshold is 5.  
Result: **REQUEST IS INTERRUPTED** — `is_interrupted: true`

**Client receives:**
```
HTTP/1.1 403 Forbidden
Server: nginx
<html><head><title>403 Forbidden</title></head></html>
```

The Flask application **never receives this request.**  
**This is Prevention, not just Detection.**

---

### Step 4 — ModSecurity Writes Audit Log

**Config:** `SecAuditLog /var/log/modsecurity/audit.log` + `SecAuditLogFormat JSON`

**Audit log entry (key fields):**
```json
{
  "transaction": {
    "time": "13/Nov/2026:11:07:23 +0000",
    "client_ip": "172.17.0.1",
    "request": {
      "method": "GET",
      "uri": "/search?q=1+OR+1=1--",
      "http_version": "1.1"
    },
    "response": {
      "http_code": 403
    },
    "is_interrupted": true,
    "producer": {
      "components": ["OWASP_CRS/4.30.0"]
    },
    "messages": [
      {
        "message": "SQL Injection Attack Detected via libinjection",
        "details": {
          "ruleId": "942100",
          "file": "REQUEST-942-APPLICATION-ATTACK-SQLI.conf",
          "data": "Matched Data: 1&1c found within ARGS:q: 1 OR 1=1--",
          "severity": "CRITICAL",
          "tags": ["application-multi","language-multi","platform-multi","attack-sqli","OWASP_CRS","capec/1000/152/248/66","PCI/6.5.2"]
        }
      },
      {
        "message": "Inbound Anomaly Score Exceeded (Total Score: 8)",
        "details": {
          "ruleId": "949110"
        }
      }
    ]
  }
}
```

This file is in the `modsec_logs` Docker volume: `/var/log/modsecurity/audit.log`

---

### Step 5 — Wazuh Processes the Event

**Config file:** `infrastructure\wazuh\manager\ossec.conf`  
Wazuh `logcollector` monitors the ModSecurity audit log via the `modsec_logs` volume.

**Decoder applies first:**  
`infrastructure\wazuh\decoders\modsecurity_decoders.xml`  
Extracts: `srcip = 172.17.0.1`, request URI, http_code = 403

**Rule evaluation (in order):**

1. Base rule **100010** matches: `<match>"transaction":</match>`  
   → Level 0, silent. Marks this as a ModSecurity event.

2. Child rule **100011** evaluates: `<match>"http_code":403</match>`  
   → Matches. Level 8. ModSecurity BLOCKED request.

3. Child of 100011 — rule **100020** evaluates: `<match>"ruleId":"942</match>`  
   → Matches. Level 12. SQL Injection detected.

Rule 100020 wins (last matching child rule). Alert generated.

---

### Step 6 — Wazuh Writes Alert to alerts.json

**Config file:** `infrastructure\wazuh\rules\sentinel_x_rules.xml` (rule 100020)

**Alert written to:** `/var/ossec/logs/alerts/alerts.json` → `wazuh_logs` volume

**Alert document (key fields):**
```json
{
  "@timestamp": "2026-11-13T11:07:23Z",
  "rule": {
    "id": "100020",
    "level": 12,
    "description": "SENTINEL-X: SQL Injection detected and blocked from 172.17.0.1",
    "groups": ["sentinel-x", "web", "modsecurity", "waf", "blocked", "sql_injection"],
    "mitre": {
      "id": ["T1190", "T1059.007"],
      "tactic": ["Initial Access", "Execution"]
    }
  },
  "data": {
    "transaction": {
      "client_ip": "172.17.0.1",
      "request": { "uri": "/search?q=1+OR+1=1--" },
      "response": { "http_code": 403 },
      "is_interrupted": true,
      "producer": { "components": ["OWASP_CRS/4.30.0"] }
    }
  },
  "agent": { "name": "wazuh-manager", "id": "000" },
  "location": "/var/log/modsecurity/audit.log"
}
```

---

### Step 7 — Filebeat Reads and Ships to Elasticsearch

**Config file:** `infrastructure\ingestion\config\filebeat.yml`

Filebeat (Pipeline 1, v8.15.3) reads the new line from `alerts.json` within ~5 seconds.

Adds ECS metadata:
```json
{
  "agent": { "type": "filebeat", "version": "8.15.3" },
  "ecs": { "version": "8.0.0" },
  "tags": ["wazuh-alert", "sentinel-x"]
}
```

Sends to `http://elasticsearch:9200` using the `elastic` user.

---

### Step 8 — Elasticsearch Indexes the Document

The document lands in the data stream: `.ds-wazuh-alerts-2026.11.13-000001`

**Verification:**
```powershell
curl -s -u elastic:changeme_elastic_lab -X POST "http://localhost:9200/.ds-wazuh-alerts-*/_search" -H "Content-Type: application/json" -d "{\"query\":{\"term\":{\"rule.id\":\"100020\"}},\"size\":1}"
```

Returns the full alert document. Count: 6+ events of this type.

---

### Step 9 — Kibana Displays the Event

**URL:** `http://localhost:5601` → Discover → "SENTINEL-X Wazuh Alerts"

Search: `rule.id: 100020`

Kibana queries Elasticsearch and renders the event in a table with:
- @timestamp
- rule.description
- data.transaction.request.uri
- data.transaction.client_ip
- rule.level
- rule.mitre.id

Expand the event to see all 50+ fields including the full CRS chain.

**Simultaneously:** Wazuh Indexer (via Filebeat Pipeline 2) has the same event visible in the Wazuh Dashboard at `https://localhost:5602`.

---

## Attack 2: Cross-Site Scripting (XSS)

### Request
```
GET /search?q=<script>alert(1)</script> HTTP/1.1
```

### WAF Processing

**CRS rule family:** 941xxx (XSS)

Specific rules that fire:
- **941100:** XSS Attack Detected via libinjection — libinjection's HTML tokenizer detects `<script>` tag
- **941110:** XSS Filter Evasion Attempt
- **941160:** NoScript XSS InjectionChecker: HTML Injection

Each adds anomaly points. Total exceeds 5. Rule **949110** blocks.

**Client receives:** HTTP 403  
**Flask app:** never receives the request

### Wazuh Alert

Rule **100021** fires (parent: 100011):
```xml
<rule id="100021" level="11">
  <if_sid>100011</if_sid>
  <match>"ruleId":"941</match>
  <description>SENTINEL-X: XSS attempt detected and blocked</description>
  <mitre><id>T1190</id></mitre>
</rule>
```

Level: 11 (Medium severity)  
Groups: `modsecurity, waf, blocked, xss`  
MITRE: T1190

### Key distinction from SQLi
XSS attacks are for the **browser** (they execute in victim's browser when reflected). The WAF blocks the payload at the HTTP level. If the app reflected the payload unsafely, a victim loading that URL would have JavaScript execute in their browser. The WAF prevents this.

---

## Attack 3: Path Traversal / LFI

### Request
```
GET /?file=../../../etc/passwd HTTP/1.1
```
Also tested:
```
GET /files?path=..%2F..%2F..%2Fetc%2Fpasswd HTTP/1.1
```
(URL-encoded version — both blocked)

### WAF Processing

**CRS rule family:** 930xxx (LFI)

Specific rules that fire:
- **930100:** Path Traversal Attack (/../)
- **930110:** Path Traversal Attack (/../) — multiple traversal sequences

CRS decodes `%2F` to `/` before matching, so URL-encoded traversal sequences are caught.

**Client receives:** HTTP 403 for BOTH requests  
**Verification:** Both `?file=../../../etc/passwd` AND `?path=..%2F..%2F..%2Fetc%2Fpasswd` return 403.

### What LFI actually is
**Local File Inclusion (LFI)** attacks exploit applications that read files based on user input. For example, if the app did: `open(request.args.get('file'))`, an attacker could request `../../../etc/passwd` to read the system password file. The SENTINEL-X Flask app does **not** actually read files — it's a detection target only. The WAF blocks the pattern regardless.

### Wazuh Alert

Rule **100022** fires:
```xml
<rule id="100022" level="11">
  <if_sid>100011</if_sid>
  <match>"ruleId":"930</match>
  <description>SENTINEL-X: LFI attempt detected and blocked</description>
  <mitre><id>T1190</id><id>T1083</id></mitre>
</rule>
```

Level: 11  
MITRE: T1190 (Exploit Public-Facing Application) + T1083 (File and Directory Discovery)

---

## RCE Pattern (Additional)

### Request
```
GET /?cmd=cat+/etc/passwd HTTP/1.1
```

### WAF Processing
**CRS rule family:** 932xxx (OS Command Injection)

Rules fire on: `cat`, OS command patterns in URL parameters.

### CRITICAL DISTINCTION
Rule **100023** fires at level **14** (highest of all custom rules). The description says "CRITICAL — RCE attempt detected and **blocked**."

**What this means:**  
The WAF detected a pattern that looks like a Remote Code Execution attempt. ModSecurity blocked the HTTP request. **No code executed on the server.** The Flask app never received `cmd=cat+/etc/passwd`. Whether the app would have been vulnerable is irrelevant — the request was stopped at the network layer.

**Always say:** "RCE attempt detected and blocked" — never "RCE successful."

---

## Summary Table

| Attack | CRS Family | Client Gets | Flask Sees | Wazuh Rule | Level |
|---|---|---|---|---|---|
| Normal GET /health | — | 200 OK | request arrives | — | — |
| SQLi `1 OR 1=1--` | 942xxx | 403 Forbidden | nothing | 100020 | 12 (High) |
| XSS `<script>` | 941xxx | 403 Forbidden | nothing | 100021 | 11 (Med) |
| LFI `../etc/passwd` | 930xxx | 403 Forbidden | nothing | 100022 | 11 (Med) |
| RCE `cmd=cat` | 932xxx | 403 Forbidden | nothing | 100023 | 14 (High) |
| Scanner UA (nikto) | (UA match) | 403 Forbidden | nothing | 100007 | 8 (Med) |

---

## End-to-End Timing

From attack to Kibana visibility:
1. HTTP request → WAF block: **< 10ms**
2. ModSec audit log write: **< 100ms**
3. Wazuh processes event: **1–5 seconds**
4. Wazuh writes alert to alerts.json: **< 1 second after rule fires**
5. Filebeat detects new content (scan interval 5s): **up to 5 seconds**
6. Filebeat ships to Elasticsearch: **1–2 seconds**
7. Elasticsearch indexes document: **< 1 second**
8. Total end-to-end: **approximately 10–60 seconds**
