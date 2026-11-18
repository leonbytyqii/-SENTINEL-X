# SENTINEL-X — Docker Infrastructure

Complete service and infrastructure inventory.

---

## Service Inventory

| # | Container | Image | Version | Purpose |
|---|---|---|---|---|
| 1 | `sentinel_nginx_waf` | `owasp/modsecurity-crs:nginx-alpine` | CRS 4.30.0 / ModSec v3.0.17 | WAF entry point — all HTTP traffic enters here |
| 2 | `sentinel_webapp` | `sentinel-x-webapp` (local build) | Flask (Python) | Test web application — not directly reachable from host |
| 3 | `sentinel_wazuh_manager` | `wazuh/wazuh-manager` | 4.9.2 | SIEM engine — parses logs, fires detection rules, generates alerts |
| 4 | `sentinel_filebeat` | `docker.elastic.co/beats/filebeat` | 8.15.3 | Reads Wazuh alerts, forwards to Elasticsearch |
| 5 | `sentinel_elasticsearch` | `docker.elastic.co/elasticsearch/elasticsearch` | 8.15.3 | Primary analytics store — required by assignment |
| 6 | `sentinel_kibana` | `docker.elastic.co/kibana/kibana` | 8.15.3 | Elasticsearch analytics UI at :5601 |
| 7 | `sentinel_wazuh_indexer` | `wazuh/wazuh-indexer` | 4.9.2 (OpenSearch-based) | Wazuh-native alert store — required by Wazuh Dashboard |
| 8 | `sentinel_wazuh_dashboard` | `wazuh/wazuh-dashboard` | 4.9.2 (OpenSearch Dashboards-based) | Wazuh SOC UI at :5602 |
| 9 | `sentinel_filebeat_wazuh` | `docker.elastic.co/beats/filebeat-oss` | 7.10.2 | Reads Wazuh alerts, forwards to Wazuh Indexer (separate pipeline) |

---

## Exposed Ports

| Port (host) | Container | Purpose | Access restriction |
|---|---|---|---|
| 80 | nginx-waf (8080) | WAF entry point — HTTP traffic | Public (lab) |
| 5601 | kibana (5601) | Kibana analytics UI | Lab only |
| 5602 | wazuh-dashboard (5601) | Wazuh Dashboard | Lab only |
| 9200 | elasticsearch (9200) | ES REST API | Lab only — bind to 127.0.0.1 in production |
| 9201 | wazuh-indexer (9200) | Wazuh Indexer REST API | Lab only — bind to 127.0.0.1 in production |
| 55000 | wazuh-manager (55000) | Wazuh Manager API | Lab only |

---

## Internal Docker Networks

| Network | Subnet | Type | Connected services |
|---|---|---|---|
| `sentinel_frontend` | 172.20.0.0/24 | External (bridge) | nginx-waf |
| `sentinel_application` | 172.20.1.0/24 | **Internal** | nginx-waf ↔ webapp |
| `sentinel_monitoring` | 172.20.2.0/24 | **Internal** | wazuh-manager (reads log volumes) |
| `sentinel_analytics` | 172.20.3.0/24 | **Internal** | wazuh-manager ↔ filebeat ↔ elasticsearch ↔ kibana |
| `sentinel_management` | 172.20.4.0/24 | External (bridge) | elasticsearch, kibana, wazuh-dashboard |
| `sentinel_wazuh_stack` | 172.20.5.0/24 | **Internal** | wazuh-manager ↔ wazuh-indexer ↔ wazuh-dashboard ↔ filebeat-wazuh |

`internal: true` networks have no default gateway — containers cannot reach the internet or the host network.

---

## Volumes (16 named volumes)

| Volume | Mounted in | Purpose |
|---|---|---|
| `sentinel_nginx_logs` | nginx-waf, wazuh-manager | NGINX access + error logs (shared read path) |
| `sentinel_modsec_logs` | nginx-waf, wazuh-manager | ModSecurity audit logs (shared read path) |
| `sentinel_wazuh_data` | wazuh-manager | Wazuh data directory |
| `sentinel_wazuh_logs` | wazuh-manager, filebeat, filebeat-wazuh | Wazuh logs including `alerts.json` |
| `sentinel_wazuh_queue` | wazuh-manager | Wazuh event queue |
| `sentinel_wazuh_multigroups` | wazuh-manager | Agent group config |
| `sentinel_wazuh_integrations` | wazuh-manager | Integration scripts |
| `sentinel_wazuh_active_response` | wazuh-manager | Active response scripts |
| `sentinel_wazuh_agentless` | wazuh-manager | Agentless config |
| `sentinel_wazuh_wodles` | wazuh-manager | Wazuh module data |
| `sentinel_filebeat_data` | filebeat | Filebeat registry (ES pipeline state) |
| `sentinel_elasticsearch_data` | elasticsearch | Elasticsearch persistent data |
| `sentinel_kibana_data` | kibana | Kibana state/settings |
| `sentinel_wazuh_indexer_data` | wazuh-indexer | Wazuh Indexer (OpenSearch) persistent data |
| `sentinel_wazuh_dashboard_data` | wazuh-dashboard | Dashboard persistent state |
| `sentinel_filebeat_wazuh_data` | filebeat-wazuh | Filebeat registry (Wazuh Indexer pipeline state) |

---

## Service Dependencies

```
webapp
  └─ nginx-waf (depends on: webapp healthy)

wazuh-manager (no startup dependency — reads volumes)
  ├─ filebeat (depends on: elasticsearch healthy + wazuh-manager healthy)
  └─ filebeat-wazuh (depends on: wazuh-indexer healthy)

elasticsearch (no startup dependency)
  └─ kibana (depends on: elasticsearch healthy)

wazuh-indexer (no startup dependency)
  └─ wazuh-dashboard (depends on: wazuh-indexer healthy)
```

All `depends_on` conditions use `service_healthy` — Docker waits for the healthcheck to pass before starting the dependent service.

---

## Healthchecks

| Container | Test | Interval | Retries | Start period |
|---|---|---|---|---|
| nginx-waf | `wget -qO- http://127.0.0.1:8080/health` | 15s | 5 | 20s |
| webapp | Python urllib to localhost:8080/health | 10s | 10 | 15s |
| wazuh-manager | `wazuh-control status \| grep -q 'is running'` | 30s | 10 | 90s |
| elasticsearch | `curl health \| grep green\|yellow` | 20s | 15 | 90s |
| kibana | `curl /api/status \| grep available` | 20s | 15 | 120s |
| wazuh-indexer | `curl health \| grep green\|yellow` (TLS) | 30s | 15 | 120s |
| wazuh-dashboard | `curl wz-home \| grep -qi wazuh` (TLS) | 30s | 20 | 180s |
| filebeat | **None** | — | — | — |
| filebeat-wazuh | **None** | — | — | — |

Both Filebeat containers lack healthchecks. Combined with `restart: unless-stopped`, they will not auto-restart on clean exit (code 0). This caused `filebeat-wazuh` to exit silently for 15 hours during development.

**Recommendation:** Change both to `restart: always` or add a healthcheck.

---

## Restart Policies

All services use `restart: unless-stopped`. This means:
- Restarts on crash (non-zero exit code) ✓
- Does NOT restart on clean stop (exit code 0) ✗
- Does NOT restart when Docker daemon restarts if the container was stopped manually ✗

---

## Filebeat Pipelines

### Pipeline 1: Wazuh Alerts → Elasticsearch (`sentinel_filebeat`)

```
Input:  /var/ossec/logs/alerts/alerts.json  (wazuh_logs volume, read-only)
Config: infrastructure/ingestion/config/filebeat.yml
Output: http://elasticsearch:9200
Index:  wazuh-alerts-{date} (data stream)
Auth:   username=elastic password=${ELASTIC_PASSWORD}
Tags:   ["wazuh-alert","sentinel-x"]
ECS:    v8.0.0
```

### Pipeline 2: Wazuh Alerts → Wazuh Indexer (`sentinel_filebeat_wazuh`)

```
Input:  /var/ossec/logs/alerts/alerts.json  (wazuh_logs volume, read-only)
Config: infrastructure/wazuh-stack/filebeat/filebeat-wazuh.yml
Output: https://wazuh-indexer:9200  (TLS, with client cert)
Index:  wazuh-alerts-4.x-{date}
Auth:   TLS mutual auth with wazuh-manager cert
```

Both pipelines read the **same source file** and maintain **independent registry files** in separate Docker volumes (`filebeat_data` vs `filebeat_wazuh_data`). They do not interfere with each other.

---

## Resource Limits

| Container | Memory limit | Memory reserved |
|---|---|---|
| nginx-waf | 256M | 64M |
| webapp | 128M | 32M |
| wazuh-manager | 1G | 256M |
| filebeat | 256M | 64M |
| elasticsearch | 4G | 2G |
| kibana | 1G | 256M |
| wazuh-indexer | 4G | 2G |
| wazuh-dashboard | 2G | 512M |
| filebeat-wazuh | 256M | 64M |

Total reserved: ~5.4G. Total on 32GB host: comfortable headroom.

---

## Security Hardening in Compose

| Feature | Service | Setting |
|---|---|---|
| No new privileges | nginx-waf, webapp, filebeat, filebeat-wazuh | `security_opt: no-new-privileges:true` |
| Read-only filesystem | webapp | `read_only: true` |
| Writable temp | webapp | `tmpfs: /tmp` |
| Internal networks | webapp, wazuh pipeline | `internal: true` on 4 networks |
| No host port exposure | webapp | No `ports:` mapping |
| Env var secrets | All | Passwords sourced from `.env` file |

---

## Container Restart Recovery Test

**Scenario tested (2026-11-13):** `sentinel_filebeat_wazuh` found Exited (0) after 15 hours.

**Recovery:**
1. `docker start sentinel_filebeat_wazuh`
2. Container restarted within 5 seconds
3. Reconnected to Wazuh Indexer over TLS
4. Resumed reading `alerts.json` from last registry position
5. 20 new events appeared in `wazuh-alerts-4.x-2026.11.13` within 60 seconds
6. No data loss — Filebeat registry preserved in `sentinel_filebeat_wazuh_data` volume

**Root cause:** Filebeat's `close_inactive` timeout caused the process to close the alert file and exit cleanly (exit code 0). Docker's `unless-stopped` policy does not restart on clean exit.
