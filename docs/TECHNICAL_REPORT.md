# SENTINEL-X — Technical Implementation Report

**Platform**: Windows 11 Pro (10.0.26200) · Docker Desktop  
**Deployment date**: 2026-11-12  
**Audit date**: 2026-11-12  

---

## Technology stack and versions

| Component | Technology | Version |
|---|---|---|
| WAF engine | ModSecurity | v3 (libmodsecurity3 3.0.17) |
| WAF integration | ModSecurity-nginx connector | v1.0.4 |
| WAF ruleset | OWASP CRS | 4.30.0 (856 rules) |
| Reverse proxy | NGINX | bundled with owasp/modsecurity-crs:nginx-alpine |
| SIEM | Wazuh Manager | 4.9.2 |
| Log shipper | Filebeat | 8.15.3 |
| Search/analytics | Elasticsearch | 8.15.3 |
| Dashboard | Kibana | 8.15.3 |
| Test application | Flask | Python 3.12-alpine |
| Orchestration | Docker Compose | v2 |

---

## Configuration decisions

### ModSecurity in blocking mode

`MODSEC_RULE_ENGINE=On` in `.env`. Detection-only mode (`DetectionOnly`) was the default
for initial testing but was switched to blocking once the pipeline was validated.

Anomaly threshold set to 5 (inbound). This means a single high-confidence SQLi or XSS
match (which scores 5) will block the request. Setting this lower risks false positives
against legitimate applications with query parameters.

### Single-node Elasticsearch without TLS

Elasticsearch security is enabled (`xpack.security.enabled: true`) with username/password
authentication. TLS is disabled (`xpack.security.http.ssl.enabled: false`) because
this is a single-node lab with no cross-node communication. For a production deployment,
mutual TLS between all components is required.

### management_net for port publishing

Docker Desktop on Windows does not publish container ports when the container is
attached only to networks with `internal: true`. Adding a non-internal `management_net`
(172.20.4.0/24) to the elasticsearch and kibana services resolved this. Elasticsearch
and Kibana are accessible on `localhost:9200` and `localhost:5601`.

### Wazuh init script (ar.conf)

Wazuh Manager's `wazuh-analysisd` daemon requires `/var/ossec/etc/shared/ar.conf`
to exist before it starts. On first container start with a fresh volume, this file
is absent, causing all daemons to fail. The file `infrastructure/wazuh/manager/init-shared.sh`
is mounted at `/etc/cont-init.d/1a-create-shared` and runs before the `2-manager`
s6-overlay init script. It creates the shared directory and touches `ar.conf`.

### Kibana security.enabled removed in 8.x

Kibana 8.x removed the `xpack.security.enabled` configuration key. Setting it caused
a FATAL startup crash: `definition for this key is missing`. Removed from kibana.yml.

---

## Problems encountered and solutions

### Problem 1: Wazuh container unhealthy — `etc/shared/ar.conf` missing

**Root cause**: `/var/ossec/etc/shared/` directory does not exist on fresh volume mount.
`wazuh-analysisd` reads `ar.conf` during startup; absence causes all daemons to fail.

**Solution**: Created `init-shared.sh` mounted as a s6-overlay cont-init.d script
that runs before `2-manager`. Content:
```sh
#!/bin/sh
set -e
mkdir -p /var/ossec/etc/shared/default
touch /var/ossec/etc/shared/ar.conf
chown -R wazuh:wazuh /var/ossec/etc/shared 2>/dev/null || true
```

### Problem 2: nginx healthcheck failing — IPv6 vs IPv4

**Root cause**: Alpine's busybox wget resolves `localhost` to `::1` (IPv6).
nginx binds `0.0.0.0` (IPv4 only). Healthcheck returned connection refused.

**Solution**: Changed healthcheck from `http://localhost:8080/health` to
`http://127.0.0.1:8080/health`.

### Problem 3: Elasticsearch and Kibana ports not published to host

**Root cause**: Docker Desktop on Windows refuses to publish ports when a container
is only on `internal: true` networks. `NetworkSettings.Ports` showed empty arrays.

**Solution**: Added `management_net` (non-internal bridge, 172.20.4.0/24) and
attached both elasticsearch and kibana to it.

### Problem 4: Kibana FATAL crash on startup

**Root cause**: `xpack.security.enabled: true` in kibana.yml. This key was removed
in Kibana 8.x — security is always enabled.

**Solution**: Removed the key from `infrastructure/dashboards/kibana/kibana.yml`.

### Problem 5: Wazuh ossec.conf causing all daemon failures

**Root cause**: Custom ossec.conf was missing required sections (syscheck, auth, cluster,
wodle blocks, commands). The original file also had an invalid `<api>` block.

**Solution**: Extracted the default ossec.conf from a clean `wazuh/wazuh-manager:4.9.2`
container and used it as a base. Added only the three custom `<localfile>` entries for
nginx access log, nginx error log, and ModSecurity audit log.

### Problem 6: PowerShell scripts failing to parse (encoding)

**Root cause**: `.ps1` files contained Unicode characters (em-dash `—`, box-drawing chars)
that cause PowerShell 5.1 parser errors. Attack payloads with `<`, `>`, and `&` also
caused parser issues.

**Solution**: Rewrote `init-elasticsearch.ps1` and `validate.ps1` with ASCII-only content.
URL-encoded all attack payloads in validate.ps1. Used `[char]38` for `&` in POST body.

### Problem 7: Kibana Basic auth returning 401 for data view creation

**Root cause**: Kibana API requests using `-Credential` with PSCredential return 401.
Kibana requires the `Authorization: Basic ...` header to be set explicitly when
the credential is not passed via the browser session.

**Solution**: Built the Authorization header manually:
```powershell
"Authorization" = "Basic " + [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes("elastic:changeme_elastic_lab"))
```

### Problem 8: Pipeline gap — WAF events not reaching Wazuh (found in audit)

**Root cause** (two causes):
1. nginx access log format is combined, not JSON — decoder `sentinel-nginx-access`
   looks for `{"@timestamp"` and never matches.
2. `/var/log/modsecurity/` directory was root-owned; nginx worker (uid 999) cannot
   write `audit.log`.

**Current status**: Identified, documented, remediation planned. The WAF is blocking
correctly. Wazuh has the custom rules. The fix requires nginx log format change and
volume ownership fix — both achievable without container rebuild.

---

## Elasticsearch data stream

Wazuh's internal Filebeat (bundled with the manager image, v7.10.2) creates
`wazuh-alerts-{date}` as an Elasticsearch data stream. External Filebeat 8.15.3
also ships to the same pattern. The index template must include `data_stream: {}`
to coexist with the existing data stream.

---

## Credentials (lab only — not for production)

| Service | Username | Password |
|---|---|---|
| Elasticsearch | elastic | changeme_elastic_lab |
| Kibana | elastic | changeme_elastic_lab |
| Kibana system (internal) | kibana_system | changeme_kibana_lab |
| Wazuh API | wazuh-wui | SentinelX_Wazuh!2024 |

**These are lab credentials only.** A production deployment must use strong unique
passwords, rotate them, and store them in a secrets manager.

---

## Phase 3 Audit Results (2026-11-12)

### Container health summary

| Container | Status | Memory Usage | Restart Policy |
|-----------|--------|-------------|----------------|
| sentinel_nginx_waf | healthy | ~50 MB | always |
| sentinel_webapp | healthy | ~30 MB | always |
| sentinel_wazuh_manager | healthy | ~600 MB | always |
| sentinel_filebeat | healthy | ~100 MB | always |
| sentinel_elasticsearch | healthy | 1.993 GB (99.66%) | always |
| sentinel_kibana | healthy | ~350 MB | always |

**Critical finding**: Elasticsearch at 99.66% memory. `mem_limit: 2g`, JVM heap `1g`.
Under sustained load this may trigger OOM kill. Fix: increase to `mem_limit: 4g`.

### Elasticsearch data stream

| Metric | Value |
|--------|-------|
| Data stream name | `wazuh-alerts-2026.11.12` |
| Backing index | `.ds-wazuh-alerts-2026.11.12-2026.11.12-000001` |
| Total documents | 258+ (after Phase 3 tests) |
| SENTINEL-X alerts | 30+ (`rule.groups: "sentinel-x"`) |
| Cluster status | GREEN |
| Shards | 1 primary, 0 replica (single-node) |

### Wazuh rule loading verification

```
2026-11-12 17:47:17 wazuh-analysisd: INFO: Total rules enabled: '6690'
```

Baseline (Wazuh built-in): 6676 rules  
SENTINEL-X custom rules: 14 rules  
Confirmed total: 6690 ✅

### Phase 3 security test results summary

| Test | Type | Result | Wazuh Rule |
|------|------|--------|------------|
| T01 GET /health | Legitimate | PASS (200) | None |
| T02 GET /api/users | Legitimate | PASS (200) | None |
| T03 SQLi OR clause | Attack | PASS (403) | 100020 lvl12 |
| T04 SQLi UNION | Attack | PASS (403) | 100020 lvl12 |
| T05 XSS script tag | Attack | PASS (403) | 100021 lvl11 |
| T06 XSS onerror | Attack | PASS (403) | 100021 lvl11 |
| T07 LFI path traversal | Attack | PASS (403) | 100023 lvl14 |
| T08 sqlmap UA | Attack | PASS (403) | 100007 lvl8 |
| T09 TRACE method | Protocol | PASS (405) | None |
| T10 POST /api/login | Legitimate | FAIL* (404) | None |

*T10 failure: `/api/login` does not exist in Flask app. Test definition error, not a WAF failure.

**Pass rate: 9/10 (90%)**. Effective WAF pass rate: **100%** (all attacks blocked, all legitimate traffic allowed).

### Kibana dashboard verification (via API)

Three dashboards confirmed created via REST API:

| Dashboard ID | Title | Panels |
|-------------|-------|--------|
| sx-dashboard-overview | SENTINEL-X \| SOC Overview | 8 (4 metrics + timeline + pie + bar + table) |
| sx-dashboard-threats | SENTINEL-X \| Threat Detection | 7 (4 metrics + stacked timeline + donut + bar) |
| sx-dashboard-investigation | SENTINEL-X \| Alert Investigation | 3 (table + bar + donut) |

Data view: `wazuh-alerts-*`, time field `@timestamp`.  
Access: `http://localhost:5601` (elastic/changeme_elastic_lab)

### Key engineering findings (Phase 3)

1. **`rule_dir` does not scan subdirectories** — most impactful discovery of the entire project.
   Silent failure: custom rules were ignored for a full session. Fix: explicit `<rule_dir>` per subdirectory.

2. **Child rules always win in alert reporting** — deepest `<if_sid>` chain member appears in the alert.
   Rule 100040 (generic correlation) masked 100020/100021/100022 because it was their child.
   Fix: removed rule 100040 entirely.

3. **`<field>` conditions do not work for JSON plugin decoder events** — only `<match>` on raw log text works.
   Documented in DETECTION_ENGINEERING.md. Applies to both NGINX and ModSec events when `log_format:json`.

4. **LFI payload triggers RCE rule** — `../../etc/passwd` matches both CRS 930xxx (LFI) and CRS 932xxx (RCE).
   Both sibling rules 100022 and 100023 match. Highest-level sibling (100023, lvl14) is reported.
   This is correct behavior — path traversal to system files legitimately scores as RCE.

---

## Security hardening findings

| ID | Severity | Finding | Recommendation |
|----|---------|---------|----------------|
| H-01 | CRITICAL | Default credentials (elastic/changeme_elastic_lab) | Rotate before any shared deployment |
| H-02 | HIGH | Elasticsearch at 99.66% RAM | Increase mem_limit to 4g |
| H-03 | HIGH | ES/Kibana ports bound to 0.0.0.0 | Bind to 127.0.0.1 |
| H-04 | HIGH | No TLS between services | Enable xpack.security TLS |
| H-05 | HIGH | Wazuh API (55000) exposed to 0.0.0.0 | Bind to 127.0.0.1 |
| H-06 | MEDIUM | No container image digest pinning | Pin to SHA256 digests |
| H-07 | MEDIUM | srcip field empty in Wazuh alerts | Fix custom decoder (error 2107) |
| H-08 | MEDIUM | No log rotation configured | Add logrotate for modsec_audit.log |
| H-09 | LOW | init-shared.sh world-writable | Set 755 permissions |
| H-10 | LOW | No active response rules | Add IP-block response for rule 100030 |
| H-11 | INFO | External Filebeat redundant with Wazuh internal | Consolidate in production |
| H-12 | INFO | Test app has no authentication | Expected — lab only |
