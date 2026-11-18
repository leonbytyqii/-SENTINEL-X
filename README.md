# SENTINEL-X
## Enterprise Web Security Monitoring & Threat Detection Platform

> Local Docker Compose stack demonstrating a complete web security monitoring lifecycle:
> **Request → NGINX → ModSecurity WAF → Application → Wazuh SIEM → Elasticsearch → Kibana**
>
> **Current build (2026-11-18):** Dual-pipeline SIEM with official Wazuh Dashboard 4.9.2. 9 containers, 1,820+ Wazuh alerts + 1,000+ Wazuh Indexer alerts — all produced by real attack traffic. Security test suite: **10/10 PASS**.

---

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │          SENTINEL-X Architecture            │
                    └─────────────────────────────────────────────┘

  Browser / Test Client
          │
          │ :80 (only exposed port)
          ▼
  ┌───────────────────────┐
  │   NGINX + ModSecurity  │  ← Reverse proxy + WAF (owasp/modsecurity-crs)
  │   OWASP CRS v4         │  ← Attack detection (SQLi, XSS, LFI, RCE, traversal)
  └────────────┬──────────┘
               │  (application_net – internal)
               ▼
  ┌───────────────────────┐
  │   Test Web Application │  ← Flask app with WAF-trigger endpoints
  └───────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │                       Monitoring Pipeline                        │
  │                                                                  │
  │  nginx_logs + modsec_logs volumes (read-only)                   │
  │          │                                                       │
  │          ▼                                                       │
  │  ┌──────────────────┐                                           │
  │  │  Wazuh Manager   │  ← Decoders + Custom rules (SIEM engine) │
  │  └────────┬─────────┘                                           │
  │           │  alerts.json                                         │
  │           ▼                                                       │
  │  ┌──────────────────┐                                           │
  │  │    Filebeat       │  ← Reads Wazuh alerts → Elasticsearch   │
  │  └────────┬─────────┘                                           │
  │           │                                                       │
  │           ▼                                                       │
  │  ┌──────────────────┐    ┌──────────────────────────┐          │
  │  │  Elasticsearch   │───▶│        Kibana             │  :5601  │
  │  │  wazuh-alerts-*  │    │  Security Dashboards      │          │
  │  └──────────────────┘    └──────────────────────────┘          │
  └─────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Component      | Image / Version                                 | Role |
|----------------|------------------------------------------------|------|
| nginx-waf         | `owasp/modsecurity-crs:nginx-alpine`               | Reverse proxy + WAF |
| webapp            | `python:3.12-alpine` (custom)                      | Test application |
| wazuh-manager     | `wazuh/wazuh-manager:4.9.2`                        | SIEM engine + internal Filebeat |
| filebeat          | `docker.elastic.co/beats/filebeat:8.15.3`          | Alert forwarder → Elasticsearch |
| filebeat-wazuh    | `docker.elastic.co/beats/filebeat-oss:7.10.2`      | Alert forwarder → Wazuh Indexer |
| elasticsearch     | `docker.elastic.co/elasticsearch/elasticsearch:8.15.3` | Storage & analytics |
| kibana            | `docker.elastic.co/kibana/kibana:8.15.3`           | Kibana dashboards (:5601) |
| wazuh-indexer     | `wazuh/wazuh-indexer:4.9.2`                        | OpenSearch alert store |
| wazuh-dashboard   | `wazuh/wazuh-dashboard:4.9.2`                      | Official Wazuh UI (:5602) |

---

## Requirements

- Windows 11 with Docker Desktop (WSL2 backend)
- 8+ GB RAM available to Docker (16+ GB recommended)
- 15 GB free disk space
- Ports 80, 5601, 9200, 55000 available

---

## Quick Start

```powershell
cd SENTINEL-X

# 1. Prerequisites check and .env setup
.\scripts\setup.ps1

# 2. Edit .env — change all passwords from defaults
notepad .env

# 3. Start the stack
.\scripts\start.ps1

# 4. First-run Elasticsearch initialisation (run once)
.\scripts\init-elasticsearch.ps1

# 5. Run security test suite
.\scripts\validate.ps1
```

---

## Access Points

| Service              | URL                            | Credentials |
|----------------------|--------------------------------|-------------|
| Web App              | http://localhost/              | — |
| Kibana               | http://localhost:5601          | elastic / `ELASTIC_PASSWORD` from .env |
| Elasticsearch        | http://localhost:9200          | elastic / `ELASTIC_PASSWORD` from .env |
| Wazuh Dashboard      | https://localhost:5602         | admin / SecretPassword (rotate before sharing) |
| Wazuh Indexer        | https://localhost:9201         | admin / SecretPassword (internal; for diagnostics) |
| Wazuh Manager API    | https://localhost:55000        | wazuh-wui / `WAZUH_API_PASSWORD` from .env |

---

## Security Test Suite (10/10 PASS)

The `validate.ps1` script runs 10 automated tests. **Current mode: `MODSEC_RULE_ENGINE=On` (active blocking).**

| Test | Scenario | Expected | Result | Wazuh Rule |
|------|----------|----------|--------|------------|
| T01  | GET /health (legitimate) | 200 | ✅ PASS | None |
| T02  | GET /api/users (legitimate) | 200 | ✅ PASS | None |
| T03  | SQL injection OR clause | 403 | ✅ PASS | 100020 lvl12 |
| T04  | SQL injection UNION SELECT | 403 | ✅ PASS | 100020 lvl12 |
| T05  | XSS script tag | 403 | ✅ PASS | 100021 lvl11 |
| T06  | LFI path traversal | 403 | ✅ PASS | 100023 lvl14 |
| T07  | RCE shell injection | 403 | ✅ PASS | 100023 lvl14 |
| T08  | sqlmap User-Agent | 403 | ✅ PASS | 100007 lvl8 |
| T09  | Elasticsearch has 50+ wazuh-alerts | pass | ✅ PASS | None |
| T10  | Kibana SOC dashboards present (≥3) | pass | ✅ PASS | None |

Full evidence: `docs/SECURITY_TEST_REPORT.md`

---

## WAF → SIEM → Kibana Pipeline (Verified Phase 3)

```
1. HTTP request → NGINX (port 80)
2. ModSecurity + OWASP CRS v4 inspects → anomaly score computed
3. If score ≥ 5 → HTTP 403 returned, JSON entry written to modsec_audit.log
4. Wazuh logcollector reads modsec_audit.log (log_format:json)
5. JSON plugin decoder processes the event
6. Custom rules 100001-100030 match attack patterns → alert generated
7. Alert written to /var/ossec/logs/alerts/alerts.json (level ≥ 7)
8. Filebeat reads alerts.json every 5s → ships to Elasticsearch
9. Elasticsearch stores in wazuh-alerts-YYYY.MM.DD data stream
10. Kibana SOC dashboards visualize alerts in real time
```

End-to-end latency: HTTP request → Kibana visible: **under 15 seconds**

---

## Troubleshooting

See `docs/TROUBLESHOOTING_GUIDE.md` for the full 8-section guide.

| Problem | Quick Check |
|---------|-------------|
| Elasticsearch fails to start | `wsl -e sudo sysctl -w vm.max_map_count=262144` |
| Kibana shows "not ready" | Wait 2–3 minutes; check `docker logs sentinel_kibana` |
| No events in Kibana | Verify rule count: `docker exec sentinel_wazuh_manager grep "Total rules" /var/ossec/logs/ossec.log \| tail -1` — must be 6690+ |
| WAF not blocking attacks | Confirm `MODSEC_RULE_ENGINE=On` in `.env`; check `docker exec sentinel_nginx_waf sh -c "grep SecRuleEngine /etc/modsecurity.d/modsecurity.conf"` |
| Wrong rule ID in alerts | Check `docs/DETECTION_ENGINEERING.md` section 3 (deepest child wins) |
| ES at 99%+ memory | Increase `mem_limit: 4g` and `ES_JAVA_OPTS: "-Xms2g -Xmx2g"` in docker-compose.yml |

---

## Directory Structure

```
SENTINEL-X/
├── docker-compose.yml          Main stack definition
├── .env.example                Credential template (copy to .env)
├── docs/
│   ├── FINAL_AUDIT_REPORT.md       Infrastructure audit, 12 security findings
│   ├── SECURITY_TEST_REPORT.md     Phase 2 + Phase 3 test evidence (9/10 PASS)
│   ├── DETECTION_ENGINEERING.md    Rule design, decoder notes, pipeline docs
│   ├── DASHBOARD_GUIDE.md          Kibana SOC dashboard guide
│   ├── CONFIGURATION_INVENTORY.md  All config file paths and key settings
│   ├── TROUBLESHOOTING_GUIDE.md    8-section debug guide
│   ├── EVIDENCE_REGISTER.md        Timestamped test evidence register
│   ├── PHASE_3_COMPLETION_REPORT.md 16-item acceptance checklist + presentation
│   ├── INTERVIEW_PREPARATION.md    10-lesson curriculum (Albanian) + interview simulation
│   ├── TECHNICAL_REPORT.md         Technical implementation report
│   └── ARCHITECTURE.md             System architecture
├── infrastructure/
│   ├── nginx/                  Reverse proxy configuration
│   ├── modsecurity/            WAF + CRS rules and exclusions
│   ├── wazuh/                  SIEM decoders and detection rules
│   ├── elasticsearch/          Storage configuration and templates
│   ├── ingestion/              Filebeat (Wazuh → Elasticsearch pipeline)
│   └── dashboards/             Kibana configuration
├── applications/
│   └── vulnerable-lab/         Flask test application
├── scripts/                    PowerShell operational scripts
├── tests/                      Automated test suite
└── evidence/                   Test results, screenshots, logs
```

---

## Current Status (2026-11-18)

9 containers deployed. Dual ingestion pipeline fully operational and verified end-to-end.

| Component | Status |
|-----------|--------|
| WAF blocking (SecRuleEngine On) | ✅ Active |
| Wazuh custom rules (100001-100030) | ✅ 14 rules loaded |
| SQLi → Rule 100020 (lvl12) | ✅ Verified — HTTP 403 returned |
| XSS → Rule 100021 (lvl11) | ✅ Verified — HTTP 403 returned |
| LFI → Rule 100022 (lvl11) | ✅ Verified — HTTP 403 returned |
| RCE → Rule 100023 (lvl14) | ✅ Verified — HTTP 403 returned |
| Scanner UA → Rule 100007 (lvl8) | ✅ Verified — HTTP 403 returned |
| Pipeline 1: Filebeat → Elasticsearch | ✅ 1,820+ documents |
| Pipeline 2: Filebeat OSS → Wazuh Indexer | ✅ 1,000+ documents |
| Kibana SOC dashboards | ✅ 4 dashboards |
| Wazuh Dashboard | ✅ 4 SOC dashboards |
| Wazuh Manager | ✅ Stable — 0 restarts, API Online v4.9.2, all daemons running |

## Known Limitations

1. **No TLS** between internal services — acceptable for a local lab; production requires full TLS mesh.
2. **Single-node** Elasticsearch — no replication or HA; increase `mem_limit: 4g` and `ES_JAVA_OPTS: "-Xms2g -Xmx2g"` for sustained use.
3. **Default credentials** — `changeme_elastic_lab` must be changed before any shared deployment.
4. **No HTTPS** on the web application — add a self-signed cert for HSTS testing.
5. **Wazuh Agent** not deployed as a separate container — manager reads logs from shared Docker volumes.
6. **srcip field empty** in some alert descriptions — custom decoder error 2107; raw IP is in `data.remote_addr`.
7. **Hardcoded credentials in Wazuh Indexer healthcheck** — `admin:SecretPassword` appears in docker-compose.yml healthcheck command; acceptable for local lab, must be rotated for any shared environment.

---

## Operational Scripts

| Script | Purpose |
|--------|---------|
| `setup.ps1` | Prerequisite check, .env creation, WSL2 configuration |
| `start.ps1` | Start services, wait for health, display URLs |
| `stop.ps1` | Stop services (data preserved) |
| `health-check.ps1` | Full stack health check |
| `validate.ps1` | 10-test security validation suite |
| `init-elasticsearch.ps1` | First-run Elasticsearch setup |
| `backup.ps1` | Backup configs and Elasticsearch data |
| `cleanup.ps1` | Remove temporary resources (safe) |
