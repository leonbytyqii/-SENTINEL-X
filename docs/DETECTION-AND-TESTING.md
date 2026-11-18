# SENTINEL-X — Detection and Testing

Attack detection verification for all four detection categories.
All tests performed 2026-11-13 against the local lab at `http://localhost`.

---

## Test Environment

| Component | Value |
|---|---|
| WAF | NGINX + ModSecurity v3.0.17, OWASP CRS 4.30.0 |
| Rules engine | On (blocking mode — `MODSEC_RULE_ENGINE=On` in `.env`) |
| Paranoia level | 1 (lowest — fewest false positives) |
| Anomaly threshold | 5 (`ANOMALY_INBOUND=5`) |
| Test endpoint | `http://localhost` → proxied to `webapp:8080` |

---

## Test 1 — Normal Request (Baseline)

**Command:**
```bash
curl -v http://localhost/health
```

**Expected:** HTTP 200, no alert  
**Actual:** HTTP 200 — `{"status": "ok"}`  
**Wazuh alert:** None generated  
**What this proves:** Normal traffic passes through the WAF without interference.

---

## Test 2 — SQL Injection

**Command:**
```bash
curl -v "http://localhost/search?q=1+OR+1=1--"
```

**Expected:** HTTP 403, WAF blocks  
**Actual:** HTTP 403 Forbidden (nginx)  

**ModSecurity detection chain:**
| CRS Rule | File | Match |
|---|---|---|
| 942100 | `REQUEST-942-APPLICATION-ATTACK-SQLI.conf` | "SQL Injection Attack Detected via libinjection" — `Matched Data: 1&1c found within ARGS:q: 1 OR 1=1--` |
| 949110 | `REQUEST-949-BLOCKING-EVALUATION.conf` | "Inbound Anomaly Score Exceeded (Total Score: 8)" — threshold 5 exceeded |

**Wazuh rule triggered:** 100020 (level 12, groups: `sql_injection,blocked,waf`)  
**MITRE ATT&CK:** T1190 (Exploit Public-Facing Application), T1059.007 (JavaScript)  

**Evidence in Elasticsearch:**
```
rule.id:          100020
rule.level:       12
data.transaction.request.uri:        /search?q=1+OR+1=1--
data.transaction.response.http_code: 403
data.transaction.is_interrupted:     true
data.transaction.producer.components: ["OWASP_CRS/4.30.0"]
```

**What this proves:** The full pipeline works end-to-end. ModSecurity detects SQLi using libinjection, blocks the request, generates a ModSec audit log entry, Wazuh ingests and fires rule 100020, the alert is forwarded to both Wazuh Indexer and Elasticsearch.

---

## Test 3 — Cross-Site Scripting (XSS)

**Command:**
```bash
curl -v "http://localhost/search?q=<script>alert(1)</script>"
```

**Expected:** HTTP 403, WAF blocks  
**Actual:** HTTP 403 Forbidden (nginx)  

**CRS detection:** Rules 941xxx (XSS pattern matching), anomaly score exceeds threshold  
**Wazuh rule triggered:** 100021 (level 11, groups: `xss,blocked,waf`)  
**MITRE ATT&CK:** T1190  

**What this proves:** XSS payloads are detected and blocked before reaching the Flask application.

---

## Test 4 — Remote Command Execution Pattern

**Command:**
```bash
curl -v "http://localhost/?cmd=cat+/etc/passwd"
```

**Expected:** HTTP 403, WAF blocks  
**Actual:** HTTP 403 Forbidden (nginx)  

**CRS detection:** Rules 932xxx (OS command injection patterns)  
**Wazuh rule triggered:** 100023 (level 14, groups: `rce,blocked,waf,critical`)  
**MITRE ATT&CK:** T1190, T1059 (Command and Scripting Interpreter)  

**Important clarification:** Rule 100023 fires on CRS 932xxx *pattern* detection. This is WAF interception — no code execution occurred on the server. The word "attempt" in the rule description is intentional and accurate.

---

## Test 5 — Local File Inclusion / Path Traversal

**Command:**
```bash
curl -v "http://localhost/?file=../../../etc/passwd"
curl -v "http://localhost/files?path=..%2F..%2F..%2Fetc%2Fpasswd"
```

**Expected:** HTTP 403, WAF blocks  
**Actual:** Both returned HTTP 403 Forbidden (nginx)  

**CRS detection:** Rules 930xxx (LFI patterns — directory traversal, restricted file access)  
**Wazuh rule triggered:** 100022 (level 11, groups: `lfi,blocked,waf`)  
**MITRE ATT&CK:** T1190, T1083 (File and Directory Discovery)  

**What this proves:** Both plain-text and URL-encoded path traversal sequences are detected and blocked by the CRS.

---

## Summary Table

| Attack Type | HTTP Response | CRS Rules | Wazuh Rule | Level | In Wazuh Indexer | In Elasticsearch |
|---|---|---|---|---|---|---|
| Normal GET | 200 OK | None | None | — | No alert | No alert |
| SQL Injection | 403 Forbidden | 942100 + 949110 | 100020 | 12 (High) | ✓ Confirmed | ✓ Confirmed |
| XSS | 403 Forbidden | 941xxx + 949110 | 100021 | 11 (Medium) | ✓ Confirmed | ✓ Confirmed |
| RCE pattern | 403 Forbidden | 932xxx + 949110 | 100023 | 14 (High) | ✓ Confirmed | ✓ Confirmed |
| LFI / Path traversal | 403 Forbidden | 930xxx + 949110 | 100022 | 11 (Medium) | ✓ Triggered | Pending ingestion |

---

## Wazuh Custom Rules Reference

| Rule ID | Level | Trigger | Groups |
|---|---|---|---|
| 100003 | 6 | NGINX HTTP 403 (from access log) | `nginx,waf_block` |
| 100011 | 8 | ModSec blocked (http_code=403) | `modsecurity,waf,blocked` |
| 100020 | 12 | CRS 942xxx — SQL Injection | `sql_injection,blocked,waf` |
| 100021 | 11 | CRS 941xxx — XSS | `xss,blocked,waf` |
| 100022 | 11 | CRS 930xxx — LFI | `lfi,blocked,waf` |
| 100023 | 14 | CRS 932xxx — RCE pattern | `rce,blocked,waf,critical` |

Rules use `<match>` against raw log text (not `<field>`) — required because Wazuh 4.9 passes JSON events as decoded flat strings to analysisd, not as structured objects.

---

## Known Limitations

- **Rule 100023 (RCE):** Detects OS command injection *patterns* at the WAF layer. Does not confirm code execution occurred. Description correctly says "attempt detected and blocked."
- **Paranoia level 1:** Lowest CRS sensitivity. At PL 2–4, more patterns are detected but false positives increase.
- **Internal network only:** Tests only cover external→WAF→app path. Lateral movement within the Docker network is not covered.
- **No SSL on webapp traffic path (HTTP only):** The WAF and webapp communicate over HTTP internally, which is acceptable in this isolated lab network.
- **LFI test events:** May appear in Elasticsearch with up to 60s delay (Filebeat 5-second scan interval + pipeline latency).
