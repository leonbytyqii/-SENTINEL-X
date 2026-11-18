# SENTINEL-X — Detection Rules Reference

Custom Wazuh rules: `infrastructure/wazuh/rules/sentinel_x_rules.xml`  
Custom decoders: `infrastructure/wazuh/decoders/`  
Rule ID range: 100001–100099

---

## Decoders

### sentinel-modsecurity
Prematch: `transaction`  
Extracts: `srcip` from `client_ip` field in ModSecurity JSON.  
Source log: `/var/log/modsecurity/audit/modsec_audit.log`

### sentinel-nginx (via JSON plugin)
NGINX access log in JSON format processed by Wazuh's built-in JSON decoder.  
Fields stored in `data.*`: `remote_addr`, `method`, `uri`, `status`, `user_agent`, `bytes_sent`.  
Source log: `/var/log/nginx/access_json.log`

---

## Rules

### NGINX Access Log Group

| Rule ID | Level | Description | Groups |
|---|---|---|---|
| 100001 | 0 | Base: any NGINX JSON access log event (silent) | nginx |
| 100002 | 3 | HTTP 4xx client error from `$(srcip)` | nginx, http_error |
| 100003 | 6 | HTTP 403 Forbidden — WAF block | nginx, waf_block |
| 100004 | 5 | HTTP 5xx server error | nginx, http_error, server_error |
| 100006 | 10 | Repeated HTTP errors (10× in 60s) — scanner | nginx, web_attack, brute_force |
| 100007 | 8 | Security scanner User-Agent detected | nginx, web_attack, scanner |

**Rule 100003 HTTP 403 evidence field:** `data.status` (integer 403, from NGINX JSON `"status":403`).  
IP is in `data.remote_addr`. URI in `data.uri`.

**MITRE:** 100003 → T1190, 100006 → T1595, 100007 → T1595.001

---

### ModSecurity WAF Group

| Rule ID | Level | Description | Groups |
|---|---|---|---|
| 100010 | 0 | Base: any ModSecurity audit event (silent) | modsecurity, waf |
| 100011 | 8 | ModSecurity BLOCKED request (`http_code:403`) | modsecurity, waf, blocked |
| 100012 | 10 | Anomaly threshold exceeded (CRS 949110) | modsecurity, waf, blocked, anomaly_score |
| 100020 | 12 | SQL Injection detected and blocked (CRS 942xxx) | modsecurity, waf, blocked, sql_injection |
| 100021 | 11 | XSS attempt detected and blocked (CRS 941xxx) | modsecurity, waf, blocked, xss |
| 100022 | 11 | LFI attempt detected and blocked (CRS 930xxx) | modsecurity, waf, blocked, lfi |
| 100023 | 14 | RCE attempt detected and blocked (CRS 932xxx) | modsecurity, waf, blocked, rce, critical |
| 100030 | 13 | Persistent attack: 5+ blocks in 2 min (frequency rule) | modsecurity, waf, blocked, persistent_attack |

**Rule 100023 important note:** This rule fires when OWASP CRS rule family 932xxx (Remote Command Execution patterns) triggers. The description says "RCE *attempt* detected and blocked." This is WAF pattern-matching, not evidence of successful code execution. The WAF blocked the request before it reached the application.

**ModSec HTTP 403 evidence field:** `data.transaction.response.http_code` (string "403").  
IP: `data.transaction.client_ip`. URI: `data.transaction.request.uri`.

**MITRE:** All → T1190; 100020 adds T1059.007; 100023 adds T1059; 100022 adds T1083.

---

## Rule Hierarchy

```
NGINX JSON log
  └─ 100001 (base, level 0)
       ├─ 100002 (4xx)
       │    └─ 100006 (frequency: 10x in 60s → brute_force)
       ├─ 100003 (403)
       └─ 100004 (5xx)
  100007 (independent: scanner UA, pcre2)

ModSec JSON log
  └─ 100010 (base, level 0)
       └─ 100011 (blocked: http_code:403)
            ├─ 100012 (949110: anomaly threshold)
            ├─ 100020 (942xxx: SQLi)
            ├─ 100021 (941xxx: XSS)
            ├─ 100022 (930xxx: LFI)
            └─ 100023 (932xxx: RCE pattern)
  100030 (frequency: 5x 100011 in 120s)
```

---

## Live Event Counts (2026-11-13)

| Rule | Description | Count |
|---|---|---|
| 100003 | NGINX 403 / WAF block | 46 |
| 100020 | SQL Injection | 11 |
| 100021 | XSS | 10 |
| 100023 | RCE pattern | 10 |
| 100012 | Anomaly threshold | 6 |
| 100011 | ModSec blocked (all subtypes) | ~32 |

Counts increase with each test run. The dashboard KPI shows live counts; values in this table are snapshots.

---

## Detection Rule Tests

Safe test payloads (confirmed 2026-11-13):

```bash
# Normal — expect 200
curl http://localhost/health

# SQLi — expect 403, triggers rule 100020 (via 100011 → 100010)
curl 'http://localhost/search?q=1+OR+1=1--'

# XSS — expect 403, triggers rule 100021
curl 'http://localhost/search?q=<script>alert(1)</script>'

# RCE pattern — expect 403, triggers rule 100023
curl 'http://localhost/?cmd=cat+/etc/passwd'
```

All four tests confirmed functional. New events appear in Wazuh Indexer within ~60 seconds (filebeat harvest interval).

---

## False Positive Considerations

| Rule | FP risk | Notes |
|---|---|---|
| 100003 | Low | Only fires on NGINX-logged HTTP 403 — requires WAF to have already blocked |
| 100007 | Low-Medium | Scanner UA pattern is broad; custom tools with unusual UAs might match |
| 100012 | Low | CRS 949110 is the final anomaly scoring rule — fires only when score exceeds threshold |
| 100020 | Low | CRS 942xxx family has very low FP rate at Paranoia Level 1 |
| 100021 | Low | CRS 941xxx family; may flag legitimate HTML in POST bodies |
| 100023 | Low | CRS 932xxx fires on shell metacharacters — legitimate admin tools may trigger |
| 100030 | Medium | Frequency rule; could fire on heavily crawled sites |

---

## Configuration Notes

- `MODSEC_RULE_ENGINE=On` in `.env` — blocking mode active
- `ANOMALY_INBOUND=5` — anomaly score threshold before blocking
- `CRS_PARANOIA_LEVEL=1` — lowest paranoia (fewest FPs)
- Rules stored in Wazuh data volume; survive container restart
- To reload rules after edit: `docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart`
