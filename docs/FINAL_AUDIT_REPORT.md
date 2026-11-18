# SENTINEL-X — Final Infrastructure Audit Report

**Date:** 2026-11-13 (Phase 4 update; original Phase 3: 2026-11-12)  
**Phase:** 4  
**Auditor:** SENTINEL-X Engineering Review  
**Status:** COMPLETED

---

## 1. Executive Summary

This report documents the complete infrastructure audit of the SENTINEL-X security monitoring stack. Phase 3 (2026-11-12) covered 6 containers. Phase 4 (2026-11-13) added 3 Wazuh-stack containers (indexer, manager upgrade, dashboard), bringing the total to 8 healthy containers with two parallel SIEM pipelines.

**Key findings:**
- 1 CRITICAL security issue (default credentials — both ES and OpenSearch stacks)
- 4 HIGH issues (ES RAM pressure 99.67%, exposed ports, no TLS, cert permissions 644)
- 3 MEDIUM issues
- 3 LOW/INFO findings
- Zero blocking operational defects

---

## 2. Container Inventory

### 2.1 Container Status Overview (Phase 4 — 8 containers)

| Container | Image | Version | Status | Health | Port |
|-----------|-------|---------|--------|--------|------|
| sentinel_nginx_waf | owasp/modsecurity-crs | nginx-alpine | Up | healthy | 80→8080 |
| sentinel_webapp | sentinel-x-webapp | latest | Up | healthy | internal |
| sentinel_wazuh_manager | wazuh/wazuh-manager | 4.9.2 | Up | healthy | internal |
| sentinel_filebeat | docker.elastic.co/beats/filebeat | 8.15.3 | Up | — | — |
| sentinel_elasticsearch | docker.elastic.co/elasticsearch/elasticsearch | 8.15.3 | Up | healthy | 9200→9200 |
| sentinel_kibana | docker.elastic.co/kibana/kibana | 8.15.3 | Up | healthy | 5601→5601 |
| sentinel_wazuh_indexer | wazuh/wazuh-indexer | 4.9.2 | Up | healthy | internal |
| sentinel_wazuh_dashboard | wazuh/wazuh-dashboard | 4.9.2 | Up | healthy | 5602→5601 |

### 2.2 Container Details

#### sentinel_nginx_waf
- **Role:** Reverse proxy + ModSecurity WAF (OWASP CRS 4.x, 51 rule files)
- **Port:** `0.0.0.0:80→8080/tcp` (host port 80 to container 8080)
- **Networks:** sentinel_frontend (172.20.0.0/16), sentinel_application (172.20.1.0/24)
- **Image size:** 152 MB
- **Health check:** `curl -f http://localhost:8080/health`

#### sentinel_webapp
- **Role:** Python Flask vulnerable-lab test application
- **Port:** 8080/tcp (internal only, no host binding)
- **Networks:** sentinel_application
- **Image size:** 94.5 MB

#### sentinel_wazuh_manager
- **Role:** SIEM engine — log collection, decoding, rule matching, alert generation
- **Port:** 55000/tcp (Wazuh API, internal only)
- **Networks:** sentinel_analytics, sentinel_monitoring
- **Image size:** 2 GB
- **Health check:** Wazuh manager process check

#### sentinel_filebeat
- **Role:** Log shipper — reads Wazuh alerts.json, forwards to Elasticsearch
- **Port:** None (outbound only)
- **Networks:** sentinel_analytics
- **Image size:** 499 MB
- **Health check:** None configured (gap identified)

#### sentinel_elasticsearch
- **Role:** Centralized alert storage and search engine
- **Port:** `0.0.0.0:9200→9200/tcp` (host-accessible)
- **Networks:** sentinel_analytics, sentinel_management
- **Image size:** 1.96 GB
- **Health check:** `curl -sf -u elastic:... http://localhost:9200/_cluster/health`

#### sentinel_kibana
- **Role:** SOC dashboard and alert investigation UI
- **Port:** `0.0.0.0:5601→5601/tcp` (host-accessible)
- **Networks:** sentinel_analytics, sentinel_management
- **Image size:** 1.85 GB
- **Health check:** Kibana status API

---

## 3. Resource Utilization

| Container | CPU % | Memory Used | Memory Limit | Memory % |
|-----------|-------|-------------|--------------|----------|
| sentinel_nginx_waf | 0.00% | 118.6 MiB | 256 MiB | 46.32% |
| sentinel_kibana | 4.74% | 479.9 MiB | 1 GiB | 46.86% |
| sentinel_elasticsearch | 2.27% | **1.993 GiB** | 2 GiB | **99.67%** ⚠️ |
| sentinel_wazuh_manager | 0.65% | 371.2 MiB | 1 GiB | 36.25% |
| sentinel_webapp | 0.03% | 25.83 MiB | 128 MiB | 20.18% |
| sentinel_filebeat | 0.02% | 44.27 MiB | 256 MiB | 17.29% |
| sentinel_wazuh_indexer | 1.15% | 2.686 GiB | 4 GiB | 67.15% |
| sentinel_wazuh_dashboard | 0.26% | 183.5 MiB | 2 GiB | 8.96% |

> **⚠️ CRITICAL RESOURCE ALERT:** Elasticsearch is using 99.67% of its 2 GiB memory limit. Root cause: container was created before the `memory: 4G` compose limit was set and has not been recreated to pick up the new limit. The Java heap is `-Xms2g -Xmx2g` leaving no room for OS/off-heap overhead. Fix: `docker compose up -d --force-recreate elasticsearch` (data volume preserved). Alternatively reduce heap to `-Xms1g -Xmx1g` via `.env`.

**Note (2026-11-13):** Stats captured with Wazuh Indexer running (2.686 GiB). Both SIEM backends operational simultaneously.

---

## 4. Network Topology

```
HOST MACHINE (Windows 11)
│
├─ port 80  ──────────────── sentinel_frontend ──── sentinel_nginx_waf
│                                                         │
├─ port 5601 ─── sentinel_management ─────────── sentinel_kibana
│                      │                               │
├─ port 9200 ───────────┘                       sentinel_analytics
│                                                │       │      │
│                              sentinel_elasticsearch sentinel_wazuh_manager
│                                       │               │
│                              sentinel_filebeat ────────┘
│                                                │
│                             sentinel_monitoring ── sentinel_wazuh_manager
│
└─ sentinel_application: sentinel_nginx_waf ──── sentinel_webapp
```

### Network Membership

| Network | Members | Purpose |
|---------|---------|---------|
| sentinel_frontend | nginx_waf | External traffic ingress |
| sentinel_application | nginx_waf, webapp | WAF-to-app proxy |
| sentinel_analytics | elasticsearch, filebeat, kibana, wazuh_manager | Log/alert pipeline |
| sentinel_management | elasticsearch, kibana | Admin access |
| sentinel_monitoring | wazuh_manager | Wazuh internal |

---

## 5. Volume Inventory

| Volume Name | Purpose | Risk if Lost |
|-------------|---------|--------------|
| sentinel_elasticsearch_data | All Elasticsearch indices and alert data | HIGH — all alerts lost |
| sentinel_kibana_data | Kibana saved dashboards and configurations | MEDIUM — dashboards lost |
| sentinel_wazuh_data | Wazuh internal database | MEDIUM — history lost |
| sentinel_wazuh_logs | Wazuh alerts.json and other logs | HIGH — alert history lost |
| sentinel_wazuh_queue | Wazuh event queue | LOW — in-flight events only |
| sentinel_modsec_logs | ModSecurity JSON audit logs | MEDIUM — raw WAF evidence lost |
| sentinel_nginx_logs | NGINX access and error logs | LOW — NGINX internal |
| sentinel_filebeat_data | Filebeat registry (read position tracking) | MEDIUM — could cause duplicate delivery |
| sentinel_wazuh_active_response | Active response scripts | LOW |
| sentinel_wazuh_agentless | Agentless monitoring config | LOW |
| sentinel_wazuh_integrations | Wazuh integrations | LOW |
| sentinel_wazuh_multigroups | Agent group configs | LOW |
| sentinel_wazuh_wodles | Wazuh module data | LOW |

**13 volumes total. None deleted during this engagement.**

---

## 6. Elasticsearch Data Summary

| Metric | Value |
|--------|-------|
| Cluster name | sentinel-x-cluster |
| Cluster status | GREEN |
| Nodes | 1 (single-node) |
| Active shards | 31 |
| Data stream | wazuh-alerts-2026.11.12 |
| Backing index | .ds-wazuh-alerts-2026.11.12-2026.11.12-000001 |
| Total documents | 246+ |
| SENTINEL-X alerts | 18+ |
| Index status | GREEN |

---

## 7. Security Hardening Findings

### CRITICAL

#### C-01: Default Credentials in Use

| Field | Value |
|-------|-------|
| **Severity** | CRITICAL |
| **Component** | Elasticsearch, Kibana |
| **Evidence** | `.env` contains `ELASTIC_PASSWORD=changeme_elastic_lab`, `KIBANA_PASSWORD=changeme_kibana_lab` |
| **Impact** | Any attacker with network access to ports 9200/5601 can authenticate and access all security alerts, modify configurations, or delete indices |
| **Recommendation** | Change all credentials before any network exposure. Use `docker compose exec elasticsearch elasticsearch-reset-password -u elastic` |
| **Status** | ⚠️ OPEN — acceptable for isolated lab; must be resolved before any production or shared-network deployment |

---

### HIGH

#### H-01: Elasticsearch Memory Pressure (99.66%)

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Component** | sentinel_elasticsearch |
| **Evidence** | `docker stats`: 1.993 GiB / 2 GiB = 99.66% |
| **Impact** | JVM OOM kill risk. ES may refuse writes, causing alert data loss. Under increased load (more attacks, more rules) the container will be OOM-killed by Docker. |
| **Recommendation** | Increase `mem_limit` to 4g in docker-compose.yml: `mem_limit: 4g`. Also set JVM heap: `ES_JAVA_OPTS: "-Xms2g -Xmx2g"` |
| **Status** | ⚠️ OPEN |

#### H-02: Elasticsearch Port 9200 Exposed Without TLS

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Component** | sentinel_elasticsearch |
| **Evidence** | `0.0.0.0:9200->9200/tcp` — accessible from any interface on the host |
| **Impact** | Credentials sent in plaintext. Any process on the host (or on the same LAN if host firewall is open) can query or modify all alert data. |
| **Recommendation** | Restrict to `127.0.0.1:9200:9200` for lab use. For production, enable TLS in elasticsearch.yml and use HTTPS. |
| **Status** | ⚠️ OPEN — acceptable for isolated local lab |

#### H-03: Kibana Port 5601 Exposed Without TLS

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Component** | sentinel_kibana |
| **Evidence** | `0.0.0.0:5601->5601/tcp` — accessible from any interface |
| **Impact** | Session cookies transmitted in plaintext. Credentials sent over HTTP. Susceptible to MITM on shared networks. |
| **Recommendation** | For production: add TLS termination (nginx reverse proxy with cert, or Kibana native TLS). For lab: restrict to `127.0.0.1:5601:5601`. |
| **Status** | ⚠️ OPEN — acceptable for isolated local lab |

#### H-04: No TLS Between Services

| Field | Value |
|-------|-------|
| **Severity** | HIGH |
| **Component** | Filebeat → Elasticsearch, Kibana → Elasticsearch |
| **Evidence** | `filebeat.yml`: `hosts: ["http://elasticsearch:9200"]` (HTTP not HTTPS) |
| **Impact** | Internal alert data transmitted unencrypted between containers. Mitigated partially by Docker network isolation, but not compliant with security best practices. |
| **Recommendation** | Enable Elasticsearch security features (`xpack.security.enabled: true`, `xpack.security.http.ssl.enabled: true`) and configure Filebeat/Kibana with certificates. |
| **Status** | ⚠️ OPEN — Docker network provides partial isolation |

---

### MEDIUM

#### M-01: Filebeat Has No Health Check

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Component** | sentinel_filebeat |
| **Evidence** | `docker inspect sentinel_filebeat`: no Health configuration |
| **Impact** | Docker Compose cannot detect if Filebeat stops shipping logs. Alerts would stop appearing in Kibana with no visible indication. |
| **Recommendation** | Add health check: `test: ["CMD-SHELL", "filebeat test output 2>&1 | grep -q 'talk to server... OK'"]` |
| **Status** | ⚠️ OPEN |

#### M-02: Wazuh Manager Image Size (2 GB)

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Component** | sentinel_wazuh_manager |
| **Evidence** | Image size: 2 GB — includes many unused Wazuh components |
| **Impact** | Larger attack surface. Slower startup and pull times. |
| **Recommendation** | Accept for lab use. For production, consider Wazuh single-node deployment or trim unused wodles. |
| **Status** | ACCEPTED for lab |

#### M-03: No CPU Limits on Containers

| Field | Value |
|-------|-------|
| **Severity** | MEDIUM |
| **Component** | All containers |
| **Evidence** | docker-compose.yml does not set `cpus` limits |
| **Impact** | A runaway container (e.g., Kibana during heavy query) can consume all host CPU, starving other containers. |
| **Recommendation** | Add `cpus: "1.0"` limits to Kibana and Elasticsearch in docker-compose.yml |
| **Status** | ⚠️ OPEN |

---

### LOW / INFORMATIONAL

#### L-01: Wazuh API Credentials in .env

| Field | Value |
|-------|-------|
| **Severity** | LOW |
| **Evidence** | `.env`: `WAZUH_API_PASSWORD=SentinelX_Wazuh!2024` |
| **Impact** | .env is excluded from git (.gitignore) but stored in plaintext on disk |
| **Recommendation** | Use Docker secrets or a secrets manager for production |
| **Status** | ACCEPTED for lab |

#### I-01: No Read-Only Filesystems

Containers do not use `read_only: true`. Acceptable for lab. For production, consider read-only root filesystems with explicit tmpfs mounts.

#### I-02: No Log Rotation for Wazuh/ModSecurity

Log files in `sentinel_wazuh_logs` and `sentinel_modsec_logs` volumes grow indefinitely. Implement `logrotate` or Wazuh's built-in log rotation for long-running deployments.

#### I-03: NGINX server_tokens Disabled ✅

NGINX is correctly configured with `server_tokens off` and `more_set_headers 'Server: nginx'` to suppress version disclosure.

---

## 8. Conclusions

The SENTINEL-X stack is operationally sound for an isolated local security lab. All six containers are healthy, the detection pipeline is functional, and security alerts are correctly generated and stored.

**Before any non-isolated deployment:**
1. Change all default credentials (C-01)
2. Increase Elasticsearch memory to 4 GB (H-01)
3. Restrict or TLS-protect ports 9200 and 5601 (H-02, H-03, H-04)
4. Add Filebeat health check (M-01)

The core value of this platform — WAF → Wazuh → Elasticsearch → Kibana detection pipeline — is fully verified and working.
