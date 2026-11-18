# SENTINEL-X — Security Test Report

**Last Updated:** 2026-11-13 (Phase 4 added)  
**Mode:** `MODSEC_RULE_ENGINE=On` (active blocking)  
**Target:** `http://localhost` (nginx-waf → webapp)

---

## Summary

| Phase | Tests | PASS | FAIL | Pass Rate |
|-------|-------|------|------|-----------|
| Phase 2 (validation) | 4 | 4 | 0 | 100% |
| Phase 3 (full suite) | 10 | 9 | 1* | 90% |
| Phase 4 (Wazuh pipeline) | 5 | 5 | 0 | 100% |

*T10 failure is a test definition error — the endpoint `/api/login` does not exist in the Flask app. HTTP 404 is application behavior, not a WAF block. The WAF correctly passed the POST request.

---

## Phase 4 Pipeline Verification (2026-11-13)

**Purpose:** Verify the full chain — WAF block → Wazuh Indexer alert — with the new Wazuh Official Dashboard stack.

### Pre-test alert count: 564

| Test | Payload | WAF Response | Chain Verified |
|------|---------|--------------|----------------|
| SQLi | `username=admin'--&password=x` POST /login | **403** | ✅ |
| XSS | GET /search?q=`<script>alert(1)</script>` | **403** | ✅ |
| LFI | GET /file?path=`../../etc/passwd` | **403** | ✅ |
| RCE | GET /?cmd=`id;whoami` | **403** | ✅ |
| Legitimate | GET / | **200** JSON response | ✅ (no false block) |

### Post-test alert count: 572 (+8 new alerts)

**Full pipeline confirmed:** Attack → NGINX/ModSecurity 403 → Wazuh Manager analysisd → `alerts.json` → Filebeat (PID 1349 inside manager) → Wazuh Indexer → stored and searchable.

**Wazuh Indexer document sample (most recent attack alert):**
```json
{
  "agent": {"name": "fa8783d606c8", "id": "000"},
  "data": {
    "source": "modsecurity-audit",
    "transaction": {
      "request": {"uri": "/login", "method": "POST"},
      "response": {"http_code": "403"},
      "producer": {"modsecurity": "ModSecurity v3.0.17"},
      "is_interrupted": "true"
    }
  },
  "rule": {
    "id": "100020",
    "level": 12,
    "description": "SENTINEL-X: SQL Injection detected and blocked"
  }
}
```

---

## Phase 3 Full Test Suite (2026-11-12 18:28:22 UTC)

### T01 — Legitimate GET /health

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/health` |
| Expected status | 200 |
| Actual status | **200** |
| WAF action | Pass (no rules matched) |
| Wazuh alert generated | No (expected — legitimate traffic) |
| **Result** | ✅ **PASS** |

### T02 — Legitimate GET /api/users

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/api/users` |
| Expected status | 200 |
| Actual status | **200** |
| WAF action | Pass |
| Wazuh alert generated | No |
| **Result** | ✅ **PASS** |

### T03 — SQL Injection (GET parameter, OR clause)

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/search?q=1'+OR+'1'='1--` |
| Expected status | 403 |
| Actual status | **403** |
| CRS rules matched | 942xxx (SQLi family) |
| Wazuh rule | **100020** (SQL Injection detected and blocked, level 12) |
| ES document | Confirmed in wazuh-alerts-2026.11.12 |
| **Result** | ✅ **PASS** |

### T04 — SQL Injection (UNION SELECT)

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/search?id=1+UNION+SELECT+1,2,3--` |
| Expected status | 403 |
| Actual status | **403** |
| CRS rules matched | 942xxx (SQLi — UNION SELECT pattern) |
| Wazuh rule | **100020** (level 12) |
| ES document | Confirmed |
| **Result** | ✅ **PASS** |

### T05 — XSS (Script Tag)

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/page?name=<script>alert(1)</script>` |
| Expected status | 403 |
| Actual status | **403** |
| CRS rules matched | 941xxx (XSS family) |
| Wazuh rule | **100021** (XSS attempt detected and blocked, level 11) |
| ES document | Confirmed |
| **Result** | ✅ **PASS** |

### T06 — XSS (Event Handler / onerror)

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/page?x=<img src=x onerror=alert(1)>` |
| Expected status | 403 |
| Actual status | **403** |
| CRS rules matched | 941xxx (XSS — attribute injection) |
| Wazuh rule | **100021** (level 11) |
| ES document | Confirmed |
| **Result** | ✅ **PASS** |

### T07 — LFI / Path Traversal

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/file?path=../../etc/passwd` |
| Expected status | 403 |
| Actual status | **403** |
| CRS rules matched | 930xxx (LFI) AND 932xxx (RCE) |
| Wazuh rule | **100023** (CRITICAL RCE, level 14) — highest severity sibling wins |
| Note | Both rule 100022 (LFI, lvl11) and 100023 (RCE, lvl14) matched; 100023 reported per Wazuh sibling rule semantics. Classification correct: /etc/passwd path traversal legitimately scores both LFI and RCE. |
| ES document | Confirmed |
| **Result** | ✅ **PASS** |

### T08 — Suspicious User-Agent (sqlmap)

| Field | Value |
|-------|-------|
| Request | `GET http://localhost:80/` with `User-Agent: sqlmap/1.7` |
| Expected status | 403 |
| Actual status | **403** |
| Detection | CRS 913xxx (scanner detection) |
| Wazuh rule | **100007** (Security scanner detected, level 8) — NGINX 403 from CRS |
| ES document | Confirmed |
| **Result** | ✅ **PASS** |

### T09 — Unsupported HTTP Method (TRACE)

| Field | Value |
|-------|-------|
| Request | `TRACE http://localhost:80/` |
| Expected status | 405 |
| Actual status | **405** |
| Handling | NGINX-level method restriction (returns 405 Method Not Allowed) |
| Wazuh alert | None generated (NGINX 405 not in WAF audit log) |
| **Result** | ✅ **PASS** |

### T10 — Legitimate POST to /api/login

| Field | Value |
|-------|-------|
| Request | `POST http://localhost:80/api/login` with JSON body |
| Expected status | 200 |
| Actual status | **404** |
| Cause | Flask app does not have a `/api/login` endpoint |
| WAF action | Pass (POST body inspection active, no WAF block issued) |
| **Result** | ❌ **FAIL** — test expectation wrong, not a WAF failure |
| Fix | Update test to target an existing endpoint (e.g., `/health` or `/api/users`) |

---

## Phase 2 Validation Run (2026-11-12 17:47:51 UTC)

| Test | Request | Status | Wazuh Rule | Level |
|------|---------|--------|------------|-------|
| SQLi | `/?id=1'+OR+'1'='1` | 403 | 100020 | 12 |
| XSS | `/?q=<script>alert(1)</script>` | 403 | 100021 | 11 |
| LFI | `/?file=../../etc/passwd` | 403 | 100023 | 14 |
| Legitimate | `/health` | 200 | None | — |

**4/4 PASS**

---

## End-to-End Pipeline Verification

The following checks confirm the full pipeline works for a SQL injection event:

| Stage | Verified | Method |
|-------|---------|--------|
| 1. HTTP 403 returned | ✅ | Invoke-WebRequest shows StatusCode 403 |
| 2. ModSec writes audit log | ✅ | JSON entry visible in modsec_audit.log |
| 3. Wazuh reads log (logcollector) | ✅ | logcollector running, monitoring the file |
| 4. Correct decoder processes event | ✅ | JSON plugin decoder (decoder.name: "json" in alert) |
| 5. Rule 100020 matches | ✅ | Rule ID 100020 in alerts.json |
| 6. Alert written to alerts.json | ✅ | Visible via tail -f /var/ossec/logs/alerts/alerts.json |
| 7. Filebeat reads alert | ✅ | Filebeat registry tracks alerts.json |
| 8. Alert shipped to Elasticsearch | ✅ | Document count increments in ES |
| 9. Alert searchable in Kibana | ✅ | Query returns document via REST API and dashboard |

**All 9 pipeline stages verified.**

---

## Wazuh Rule Count Evidence

```
2026-11-12 17:47:17 wazuh-analysisd: INFO: Total rules enabled: '6690'
```

Baseline (no custom rules): 6676  
Custom SENTINEL-X rules added: 14  
Expected total: 6690 ✅

---

## Container Restart Recovery Test

Wazuh manager was restarted 3+ times during Phase 2 and Phase 3 testing:

- Configuration changes applied each time
- All alerts in alerts.json survived (volume-mounted)
- Elasticsearch data survived all restarts
- Kibana dashboards survived all restarts
- Filebeat registry preserved — no duplicate documents detected

**Recovery: ✅ PASS**
