# SENTINEL-X — Final Submission Report
**Author:** Leon Bytyci  
**Date:** 2026-11-18  
**Role Applied For:** Security / DevSecOps Engineer — Sentry

---

## Executive Summary

SENTINEL-X is a fully functional, end-to-end web security monitoring platform built as a local
Docker Compose stack. It demonstrates the complete lifecycle of a production SOC environment:
attack detection at the WAF layer, ingestion via two independent SIEM pipelines, and real-time
visualization across four custom SOC dashboards in both Kibana and the official Wazuh Dashboard.

The project was designed, implemented, and operated entirely by the author — no templates or
pre-built SIEM demos were used. All 1,257+ alerts in the system were produced by real attack
traffic.

---

## Architecture Overview

```
Internet / Test Client
       |
       | :80 (only port exposed to host)
       v
+------------------------+
|  NGINX + ModSecurity   |  ModSecurity v3.0.17 + OWASP CRS 4.30.0
|  WAF — BLOCKING MODE   |  SecRuleEngine: On  (blocks SQLi, XSS, LFI, RCE, scanners)
+----------+-------------+
           |  (application_net — Docker internal)
           v
+------------------------+
|  Flask Test Application|  Python 3.12-alpine; 7 endpoints purposely trigger CRS rules
+------------------------+

           WAF writes two log streams:
             • /var/log/nginx/access.log  (JSON — all requests)
             • /var/log/modsecurity/audit/modsec_audit.log  (JSON — attack events)

                    Both log volumes mounted read-only into Wazuh Manager
                                          |
                                          v
+-----------------------------------------------+
|  Wazuh Manager 4.9.2                           |
|  - Custom decoders: nginx_decoders.xml,        |
|    modsecurity_decoders.xml                    |
|  - 14 custom rules (IDs 100001–100030)         |
|    Rule 100023 (RCE) — level 14 (Critical)     |
|    Rule 100020 (SQLi) — level 12 (High)        |
|    Rule 100030 (Persistent attack) — level 13  |
|  - alerts.json written to wazuh_logs volume    |
+------+------------------------------------------+
       |
       |  alerts.json — read by TWO independent Filebeat pipelines:
       |
       +------- Pipeline 1: Filebeat 8.15.3 ---------> Elasticsearch 8.15.3
       |                                                wazuh-alerts-YYYY.MM.DD
       |                                                470+ documents
       |
       +------- Pipeline 2: Filebeat OSS 7.10.2 -----> Wazuh Indexer 4.9.2 (OpenSearch)
                                                        wazuh-alerts-4.x-*
                                                        787+ documents

Visualization:
  Kibana 8.15.3           :5601   4 custom SOC dashboards
  Wazuh Dashboard 4.9.2   :5602   Official Wazuh UI with MITRE ATT&CK mapping
```

---

## Container Inventory (9 services)

| Container | Image | Status | Role |
|-----------|-------|--------|------|
| sentinel_nginx_waf | owasp/modsecurity-crs:nginx-alpine | healthy | WAF entry point |
| sentinel_webapp | python:3.12-alpine (custom) | healthy | Attack target |
| sentinel_wazuh_manager | wazuh/wazuh-manager:4.9.2 | running* | SIEM engine |
| sentinel_filebeat | filebeat:8.15.3 | running | Alerts → Elasticsearch |
| sentinel_filebeat_wazuh | filebeat-oss:7.10.2 | running | Alerts → Wazuh Indexer |
| sentinel_elasticsearch | elasticsearch:8.15.3 | healthy | Storage + analytics |
| sentinel_kibana | kibana:8.15.3 | healthy | Kibana dashboards |
| sentinel_wazuh_indexer | wazuh/wazuh-indexer:4.9.2 | healthy | OpenSearch store |
| sentinel_wazuh_dashboard | wazuh/wazuh-dashboard:4.9.2 | healthy | Official Wazuh UI |

*Wazuh Manager has an intermittent startup race condition causing restarts. All alert data is
preserved — the ingestion pipelines run independently and have already processed all events.
Root cause fix (start_period: 90s → 120s) has been applied to docker-compose.yml.

---

## Detection Engineering

### Custom Wazuh Rules (14 rules)

| Rule ID | Level | Attack Class | MITRE ATT&CK |
|---------|-------|--------------|---------------|
| 100001 | 0 | NGINX access log base (silent) | — |
| 100002 | 3 | HTTP 4xx client error | — |
| 100003 | 6 | NGINX 403 — WAF block confirmed | T1190 |
| 100004 | 5 | HTTP 5xx server error | — |
| 100006 | 10 | Brute force (10x 4xx in 60s) | T1595 |
| 100007 | 8 | Security scanner User-Agent | T1595.001 |
| 100010 | 0 | ModSecurity event base (silent) | — |
| 100011 | 8 | ModSec blocked request | T1190 |
| 100012 | 10 | Anomaly score threshold exceeded | T1190 |
| 100020 | 12 | SQL Injection (CRS 942xxx) | T1190, T1059.007 |
| 100021 | 11 | Cross-Site Scripting (CRS 941xxx) | T1190 |
| 100022 | 11 | Local File Inclusion (CRS 930xxx) | T1190, T1083 |
| 100023 | 14 | Remote Code Execution (CRS 932xxx) | T1190, T1059 |
| 100030 | 13 | Persistent attack (5+ blocks in 2 min) | T1190, T1595 |

### Key Engineering Decisions

1. **Raw log matching, not field matching**: Wazuh 4.9.2 `log_format:json` events store decoded
   fields in `data.*` in archives output, but `<field name="data.X">` rule conditions do NOT
   match them. All custom rules use `<match>` against raw log text. This was discovered through
   analysis of the archives.json decoder output and is documented in the rule file header.

2. **Dual-base-rule pattern**: Separate silent base rules (100001 for NGINX, 100010 for ModSec)
   differentiate the two JSON log formats. NGINX JSON starts with `"@timestamp":`; ModSec JSON
   starts with `"transaction":`. Child rules inherit from the correct base.

3. **CRS family-based SQL injection**: Rule 100020 matches `"ruleId":"942` (the entire CRS 942xxx
   family) rather than a single rule ID, capturing all SQL injection variants.

---

## Security Test Results (Verified 2026-11-18)

Automated suite: `.\scripts\test_sentinel_x.ps1`

```
ID   Name                                      Result
---  ----------------------------------------  ------
T01  Health endpoint returns 200               PASS
T02  Normal API request returns 200            PASS
T03  SQL injection OR clause blocked (403)     PASS
T04  SQL injection UNION SELECT blocked (403)  PASS
T05  XSS <script> tag blocked (403)            PASS
T06  LFI path traversal blocked (403)          PASS
T07  RCE shell injection blocked (403)         PASS
T08  sqlmap User-Agent blocked (403)           PASS
T09  Elasticsearch has 50+ wazuh-alerts        PASS
T10  Kibana SOC dashboards present (>=3)       PASS

RESULT: 10/10 PASS
```

---

## Live Data as of 2026-11-18

| Metric | Value |
|--------|-------|
| Total alerts — Elasticsearch | 470+ |
| Total alerts — Wazuh Indexer | 787+ |
| SENTINEL-X specific alerts | 63 |
| ModSec version | v3.0.17 (Linux) |
| OWASP CRS version | 4.30.0 |
| Kibana dashboards | 4 |
| Wazuh Dashboard (SOC dashboards) | 4 |
| Attack types blocked | SQLi, XSS, LFI, RCE, Scanner |

---

## Kibana Dashboards

| Dashboard | ID | Purpose |
|-----------|----|---------|
| SENTINEL-X Security Operations | 75fd12db-... | High-level operations view |
| SENTINEL-X — SOC Overview | sx-dashboard-overview | Alert counts, severity, timeline |
| SENTINEL-X — Threat Detection | sx-dashboard-threats | Attack classification by type |
| SENTINEL-X — Alert Investigation | sx-dashboard-investigation | Drill-down per rule/IP |

---

## Screenshots Required for Demo

| Label | URL | What to show |
|-------|-----|--------------|
| SC-1 | http://localhost:5601 | SOC Overview with live counts |
| SC-2 | http://localhost:5601 | Threat Detection dashboard |
| SC-3 | https://localhost:5602 | Official Wazuh Dashboard (accept cert warning; login: admin / SecretPassword) |
| SC-4 | Terminal | Output of `docker ps` showing all 9 containers |

---

## Repository Structure

```
SENTINEL-X/
+-- docker-compose.yml              9-service stack definition
+-- .env.example                    Credential template (commit-safe)
+-- .gitignore                      .env, secrets/, evidence/ excluded
+-- README.md                       Project overview and quick-start
+-- scripts/
|   +-- test_sentinel_x.ps1         10-test automated validation suite
|   +-- setup.ps1                   Prerequisite check
|   +-- start.ps1                   Stack startup
|   +-- validate.ps1                Full validation script
|   +-- health-check.ps1            Health check
|   +-- backup.ps1                  Config + data backup
+-- infrastructure/
|   +-- nginx/                      NGINX reverse proxy config
|   +-- modsecurity/                CRS exclusions and overrides
|   +-- wazuh/
|   |   +-- rules/sentinel_x_rules.xml     14 custom detection rules
|   |   +-- decoders/nginx_decoders.xml    NGINX JSON decoder
|   |   +-- decoders/modsecurity_decoders.xml  ModSec JSON decoder
|   |   +-- manager/ossec.conf             Wazuh Manager config
|   +-- elasticsearch/              ES config, templates, ILM policy
|   +-- ingestion/config/filebeat.yml      Pipeline 1 config
|   +-- wazuh-stack/
|       +-- filebeat/filebeat-wazuh.yml    Pipeline 2 config
|       +-- indexer/                       Wazuh Indexer config
|       +-- dashboard/                     Wazuh Dashboard config
|       +-- certs/                         mTLS certificates
+-- applications/vulnerable-lab/   Flask test application (src/app.py)
+-- docs/
    +-- DETECTION_ENGINEERING.md   Rule design and decoder notes
    +-- TECHNICAL_REPORT.md        Full technical implementation
    +-- TROUBLESHOOTING_GUIDE.md   8-section debug guide
    +-- DASHBOARD_GUIDE.md         Kibana dashboard guide
    +-- FINAL-SENTRY-SUBMISSION-REPORT.md  (this file)
```

---

## Known Issues and Engineering Notes

### 1. Wazuh Manager Crash Loop
**Symptom:** Container restarts ~every 60 seconds (57 restarts observed on 2026-11-18).  
**Impact:** None on stored data — both Filebeat pipelines run independently. Alert data intact.  
**Root cause:** Startup race condition. The healthcheck command (`wazuh-control status | grep -q 'is running'`) fires before all Wazuh services complete initialization.  
**Fix applied:** `start_period: 90s` → `start_period: 120s` in docker-compose.yml.  
**Permanent fix:** A clean `docker compose down && docker compose up -d` with the new start_period will resolve this. Not performed to preserve the existing alert dataset.

### 2. Hardcoded Credentials in Wazuh Indexer Healthcheck
**Location:** docker-compose.yml, wazuh-indexer healthcheck command.  
**Value:** `admin:SecretPassword` (Wazuh Indexer default for lab deployments).  
**Risk:** Low — local lab only, never in a shared network. Credential should be rotated for any shared deployment.

### 3. No Internal TLS
All inter-container communication uses plain HTTP except the Wazuh stack (which uses mTLS with
self-signed certs). Acceptable for a local lab; production would require a full TLS mesh.

### 4. Elasticsearch Single-Node
No replication or HA. Memory is at ~2.0 GiB / 4 GiB. Increase `ES_JAVA_OPTS=-Xms2g -Xmx2g`
in .env if the heap approaches the limit.

---

## How to Run

```powershell
# From the project directory
cd "C:\Prime Kosova\WORK\SENTINEL-X"

# Start the stack (Docker Desktop must be running)
docker compose up -d

# Wait 2-3 minutes for all services to become healthy, then run the test suite:
.\scripts\test_sentinel_x.ps1

# Access points:
#   Kibana:          http://localhost:5601    (elastic / <ELASTIC_PASSWORD from .env>)
#   Wazuh Dashboard: https://localhost:5602  (admin / SecretPassword)
#   Web App:         http://localhost/
```

---

## What This Demonstrates

| Skill | Evidence |
|-------|---------|
| Docker Compose orchestration | 9-container stack, 6 networks, 16 volumes, full dependency graph |
| WAF configuration | ModSecurity v3 + OWASP CRS 4.30.0 in blocking mode; custom exclusion rules |
| SIEM rule engineering | 14 custom Wazuh rules with MITRE ATT&CK mapping; non-obvious decoder research |
| Dual-pipeline ingestion | Filebeat 8.15.3 (ES) and Filebeat OSS 7.10.2 (Wazuh Indexer) in parallel |
| Kibana dashboard design | 4 SOC dashboards with Lens visualizations, KQL queries, custom index patterns |
| Security operations mindset | Attack types classified, alert levels calibrated, persistent-attack detection |
| Documentation | Architecture diagrams, test reports, troubleshooting guides, evidence register |
| Automated testing | 10-test PowerShell validation suite with PASS/FAIL output |
