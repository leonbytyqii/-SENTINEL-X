# SENTINEL-X — Master Project Handbook

**Version:** 1.0.0  
**Date:** 2026-11-14  
**Status:** Complete — All components verified  
**Location:** `C:\Prime Kosova\WORK\SENTINEL-X`

---

## What Is SENTINEL-X?

SENTINEL-X is a local security monitoring architecture you built using Docker Compose. It demonstrates how a real Security Operations Center (SOC) monitors web traffic, detects attacks, and stores evidence for investigation.

**In plain language:**
- You have a web application (Flask) protected by a firewall (WAF)
- The firewall blocks attacks and writes evidence to log files
- A detection engine (Wazuh SIEM) reads those logs and fires alerts
- Two pipelines forward alerts to two separate databases (Elasticsearch and Wazuh Indexer)
- Two dashboards let you investigate attacks visually (Kibana and Wazuh Dashboard)

---

## Project Goals

| Goal | Status |
|---|---|
| Docker Compose multi-container deployment | ✓ Complete |
| NGINX reverse proxy | ✓ Complete |
| OWASP ModSecurity WAF (blocking mode) | ✓ Complete |
| Wazuh SIEM with custom detection rules | ✓ Complete |
| Elasticsearch for storage and analytics | ✓ Complete |
| Kibana for visualization | ✓ Complete |
| Verified attack detection (SQLi, XSS, LFI, RCE) | ✓ Complete |

---

## Project Stack (9 Containers)

```
sentinel_nginx_waf        NGINX + ModSecurity v3.0.17 + OWASP CRS 4.30.0
sentinel_webapp           Flask test web application (Python)
sentinel_wazuh_manager    Wazuh Manager 4.9.2 (SIEM engine)
sentinel_filebeat         Filebeat 8.15.3 → Elasticsearch
sentinel_elasticsearch    Elasticsearch 8.15.3 (primary analytics store)
sentinel_kibana           Kibana 8.15.3 at port 5601
sentinel_wazuh_indexer    Wazuh Indexer 4.9.2 / OpenSearch (Wazuh-native store)
sentinel_wazuh_dashboard  Wazuh Dashboard 4.9.2 at port 5602
sentinel_filebeat_wazuh   Filebeat-OSS 7.10.2 → Wazuh Indexer
```

---

## Directory Structure

```
C:\Prime Kosova\WORK\SENTINEL-X\
├── .env                              Credentials and environment variables (DO NOT COMMIT)
├── .env.example                      Credential template (safe to commit)
├── .gitignore                        Git exclusion rules
├── docker-compose.yml                Main orchestration file — defines all 9 containers
├── CHANGELOG.md                      Project history
├── README.md                         Project overview
│
├── applications\
│   └── vulnerable-lab\
│       ├── Dockerfile                Builds the Flask web application container
│       ├── requirements.txt          Python dependencies (flask only)
│       └── src\app.py                Flask application code with 7 test endpoints
│
├── infrastructure\
│   ├── nginx\
│   │   ├── conf.d\sentinel.conf      NGINX server block: proxy_pass, logging, security headers
│   │   ├── conf.d\sentinel_json_log.conf  JSON log format definition
│   │   └── modsecurity-override.conf Local override for ModSecurity settings
│   │
│   ├── modsecurity\
│   │   ├── modsecurity-override.conf Main ModSec config: audit log format, body inspection
│   │   ├── crs-setup-override.conf   CRS config: paranoia level, anomaly thresholds
│   │   └── exclusions\               False-positive exclusion rules (before and after CRS)
│   │
│   ├── wazuh\
│   │   ├── manager\ossec.conf        Main Wazuh configuration: log sources, decoders, rules
│   │   ├── rules\sentinel_x_rules.xml  Your 15 custom detection rules (DO NOT OVERWRITE)
│   │   └── decoders\                 Custom JSON decoders for NGINX and ModSecurity logs
│   │
│   ├── ingestion\
│   │   └── config\filebeat.yml       Filebeat pipeline 1 config (ES output)
│   │
│   ├── elasticsearch\
│   │   ├── config\elasticsearch.yml  ES cluster config
│   │   ├── lifecycle\                ILM retention policy
│   │   └── templates\                Index template for wazuh-alerts data stream
│   │
│   ├── dashboards\kibana\
│   │   └── kibana.yml                Kibana config: ES connection, server settings
│   │
│   └── wazuh-stack\
│       ├── certs\                    TLS certificates for Wazuh components (NEVER DELETE)
│       ├── filebeat\                 Filebeat pipeline 2 config (Wazuh Indexer output)
│       ├── indexer\                  Wazuh Indexer (OpenSearch) config
│       └── dashboard\
│           ├── config\opensearch_dashboards.yml   Wazuh Dashboard config
│           └── config\sentinel_x_saved_objects_backup_20261113.ndjson  Dashboard backup
│
├── docs\                             All project documentation (21 files)
├── scripts\                          PowerShell management scripts
├── backups\                          Configuration snapshots
├── evidence\                         Test results and screenshots
└── secrets\                          Reserved for future secret files (currently empty)
```

---

## Quick Start and Health Verification

```powershell
# Start the stack
cd "C:\Prime Kosova\WORK\SENTINEL-X"
docker compose up -d

# Check all containers
docker ps --format "table {{.Names}}\t{{.Status}}"

# Verify WAF is responding
curl http://localhost/health

# Verify Elasticsearch is healthy
curl -s -u elastic:changeme_elastic_lab http://localhost:9200/_cluster/health | python -c "import sys,json; d=json.load(sys.stdin); print('ES status:', d['status'])"
```

---

## Access Credentials Summary

Credentials are stored in `.env` at the project root.  
They are also in `docs/ACCESS-AND-RESOURCES.md`.  
**Never commit `.env` to Git — it is in `.gitignore`.**

| Service | URL | Username |
|---|---|---|
| Web App (WAF) | http://localhost | None |
| Kibana | http://localhost:5601 | elastic |
| Elasticsearch API | http://localhost:9200 | elastic |
| Wazuh Dashboard | https://localhost:5602 | admin |
| Wazuh Indexer API | https://localhost:9201 | admin |
| Wazuh Manager API | http://localhost:55000 | wazuh-wui |

Passwords: see `.env` or `docs/ACCESS-AND-RESOURCES.md` (never expose in Git commits).

---

## Critical Rules — What NEVER To Do

1. **Never run `docker compose down -v`** — this destroys all alert data in Docker volumes
2. **Never delete the `certs/` directory** — Wazuh TLS will break
3. **Never overwrite `sentinel_x_rules.xml` from an external source** — these are your custom rules
4. **Never commit `.env`** — it contains credentials
5. **Never delete the `.kibana_1` index** — it stores Wazuh Dashboard saved objects
6. **Never delete the saved objects backup file** — it is your recovery point for dashboards

---

## Maintenance Commands

```powershell
# Stop stack (preserves all data)
docker compose down

# Restart a single container
docker restart sentinel_filebeat_wazuh

# View container logs
docker logs sentinel_wazuh_manager --tail 50
docker logs sentinel_filebeat --tail 30

# Check event counts
# Elasticsearch
curl -s -u elastic:changeme_elastic_lab "http://localhost:9200/.ds-wazuh-alerts-*/_count"
# Wazuh Indexer
curl -sk -u admin:SecretPassword "https://localhost:9201/wazuh-alerts-4.x-*/_count"

# Backup dashboards
# See scripts\backup.ps1
```

---

## Published Artifacts

| Artifact | URL | Purpose |
|---|---|---|
| Interview Prep | https://claude.ai/artifact/6EUuwRCtX6EAJdDeejLzcR | Demo guide, Q&A, credentials |
| Final Audit Report | https://claude.ai/artifact/5nkBeVRQFPrqydEB2d2SDG | 12-phase acceptance scorecard |
| Release Report | https://claude.ai/artifact/3oHeuFdpNamfVGLBmcBafq | Pre-release verification |
| Compliance Audit | https://claude.ai/artifact/9TQ2WVMmQY3FMv36H8rcvX | ES integration evidence |

---

## Documentation Index

| File | Lines | Purpose |
|---|---|---|
| MASTER-PROJECT-HANDBOOK.md | this file | Complete project overview |
| COMPLETE-FILE-INVENTORY.md | — | Every file explained |
| ACCESS-AND-RESOURCES.md | — | All URLs, logins, artifacts |
| ARCHITECTURE-DEEP-DIVE.md | — | Component-by-component explanation |
| EVENT-FLOW-ANALYSIS.md | — | SQLi/XSS/LFI traced through every component |
| CUSTOM-IMPLEMENTATION-REFERENCE.md | — | Your custom rules, configs, decisions |
| COMPLETE-LEARNING-ROADMAP.md | — | 7-level curriculum with resources |
| PRACTICAL-LAB-WORKBOOK.md | — | Hands-on exercises using this lab |
| OFFICIAL-LEARNING-RESOURCES.md | — | Curated links with descriptions |
| ARCHITECTURE.md | 143L | System overview |
| DATA-FLOW.md | 111L | Pipeline flow |
| DETECTION-AND-TESTING.md | ~130L | Attack test results |
| DOCKER-INFRASTRUCTURE.md | ~130L | Service/network/volume inventory |
| DEMO-RUNBOOK.md | ~200L | Live demo script |
| INTERVIEW-GUIDE.md | ~500L | 20 Q&A, design decisions |
| DEPLOYMENT-GUIDE.md | 126L | Startup/shutdown guide |
| TROUBLESHOOTING_GUIDE.md | 297L | Common issues and fixes |
| DETECTION_ENGINEERING.md | 188L | Rule design reference |
| FINAL-ACCEPTANCE-REPORT.md | 225L | Phase acceptance report |
| SECURITY_TEST_REPORT.md | 186L | Security test evidence |
| TECHNICAL_REPORT.md | 199L | Technical decisions |
