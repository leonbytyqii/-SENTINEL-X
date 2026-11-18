# SENTINEL-X — Configuration Inventory

**Date:** 2026-11-12  
**Phase:** 3

This document lists every configuration file in SENTINEL-X, its location (host and container paths), and its purpose.

---

## 1. Project Root

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Defines all 6 services, networks, volumes, and environment variables |
| `.env` | Runtime secrets — ELASTIC_PASSWORD, KIBANA_PASSWORD, WAZUH_API_PASSWORD |
| `.env.example` | Template for .env — safe to commit |
| `.gitignore` | Excludes .env, secrets/, evidence/screenshots/ from git |
| `README.md` | Project overview |
| `CHANGELOG.md` | Version history |

---

## 2. NGINX + ModSecurity (sentinel_nginx_waf)

### Host Paths → Container Paths

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| (built-in) | `/etc/nginx/nginx.conf` | Main NGINX config — worker processes, HTTP block, includes |
| (built-in) | `/etc/nginx/conf.d/default.conf` | Server block — listen 8080, proxy_pass to webapp |
| (built-in) | `/etc/nginx/conf.d/logging.conf` | Log format definitions |
| `infrastructure/nginx/conf.d/sentinel_json_log.conf` | `/etc/nginx/conf.d/sentinel_json_log.conf` | JSON access log format for Wazuh ingestion |
| `infrastructure/nginx/modsecurity-override.conf` | `/etc/nginx/modsecurity-override.conf` | NGINX-level ModSec config overrides |
| `infrastructure/modsecurity/modsecurity-override.conf` | `/etc/modsecurity.d/modsecurity-override.conf` | ModSecurity engine settings override |
| `infrastructure/modsecurity/crs-setup-override.conf` | `/etc/modsecurity.d/owasp-crs/crs-setup.conf` | CRS anomaly thresholds and paranoia level |

### Key NGINX Settings

```nginx
# nginx.conf
worker_processes auto;
client_body_timeout 10s;
keepalive_timeout 60s;
server_tokens off;        # Version disclosure disabled ✓

# default.conf
listen 8080 default_server;
proxy_pass http://webapp:8080;    # Reverse proxy to Flask app
client_max_body_size 0;           # No body size limit (ModSec handles this)
```

### Key ModSecurity Settings

```
SecRuleEngine On                  # Active blocking mode
SecAuditLogFormat JSON            # JSON audit logs for Wazuh ingestion
SecAuditLog /var/log/modsecurity/audit/modsec_audit.log
SecAuditLogParts ABIJDEFHZ        # Full request/response logging
```

### Key CRS Settings

```
tx.inbound_anomaly_score_threshold=5    # Block when score ≥ 5
tx.outbound_anomaly_score_threshold=4   # Block responses when score ≥ 4
# Paranoia level: 1 (default, low false positives)
# CRS rule files: 51 total
```

---

## 3. Wazuh Manager (sentinel_wazuh_manager)

### Host Paths → Container Paths

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `infrastructure/wazuh/manager/ossec.conf` | `/var/ossec/etc/ossec.conf` | Main Wazuh config — log sources, ruleset, global settings |
| `infrastructure/wazuh/rules/sentinel_x_rules.xml` | `/var/ossec/etc/rules/sentinel-x/sentinel_x_rules.xml` | Custom SENTINEL-X detection rules |
| `infrastructure/wazuh/decoders/nginx_decoders.xml` | `/var/ossec/etc/decoders/sentinel-x/nginx_decoders.xml` | Custom NGINX decoder (not currently loaded) |
| `infrastructure/wazuh/decoders/modsecurity_decoders.xml` | `/var/ossec/etc/decoders/sentinel-x/modsecurity_decoders.xml` | Custom ModSec decoder (not loaded — error 2107) |
| `infrastructure/wazuh/manager/init-shared.sh` | Container init | Shared volume initialization script |

### ossec.conf Key Sections

```xml
<global>
  <jsonout_output>yes</jsonout_output>    <!-- Alert output as JSON -->
  <logall_json>no</logall_json>           <!-- Archive all events: OFF (debugging only) -->
  <log_alert_level>3</log_alert_level>   <!-- Only alert at level ≥ 3 -->
</global>

<!-- Log sources: NGINX JSON access log -->
<localfile>
  <log_format>json</log_format>
  <location>/var/log/nginx/access_json.log</location>
</localfile>

<!-- Log sources: ModSecurity JSON audit log -->
<localfile>
  <log_format>json</log_format>
  <location>/var/log/modsecurity/audit/modsec_audit.log</location>
</localfile>

<!-- Ruleset: standard + SENTINEL-X custom rules -->
<ruleset>
  <rule_dir>ruleset/rules</rule_dir>
  <rule_dir>etc/rules</rule_dir>
  <rule_dir>etc/rules/sentinel-x</rule_dir>  <!-- CRITICAL: not recursive, explicit needed -->
</ruleset>
```

### sentinel_x_rules.xml Summary

| Rule ID | Level | Trigger | Description |
|---------|-------|---------|-------------|
| 100001 | 0 | `@timestamp` in log | NGINX access log base event (silent) |
| 100002 | 3 | `"status":4` | HTTP 4xx client error |
| 100003 | 6 | `"status":403` | HTTP 403 WAF block confirmed |
| 100004 | 5 | `"status":5` | HTTP 5xx server error |
| 100006 | 10 | 10x 4xx in 60s | Repeated errors — possible scanner |
| 100007 | 8 | sqlmap/nikto/etc UA | Security scanner detected |
| 100010 | 0 | `"transaction":` in log | ModSecurity audit log base event (silent) |
| 100011 | 8 | `"http_code":403` | ModSec BLOCKED request |
| 100012 | 10 | `"ruleId":"949110"` | CRS anomaly threshold exceeded |
| 100020 | 12 | `"ruleId":"942` | **SQL Injection detected and blocked** |
| 100021 | 11 | `"ruleId":"941` | **XSS attempt detected and blocked** |
| 100022 | 11 | `"ruleId":"930` | **LFI attempt detected and blocked** |
| 100023 | 14 | `"ruleId":"932` | **CRITICAL RCE attempt detected and blocked** |
| 100030 | 13 | 5x blocks in 120s | Persistent attack from same IP |

> **Note:** Rule 100040 (generic correlation) was removed in Phase 2/3 because Wazuh always reports the deepest child rule, which caused the generic rule to mask the specific attack-type rules (SQLi/XSS/LFI).

---

## 4. Filebeat (sentinel_filebeat)

### Host Paths → Container Paths

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| (built into compose) | `/usr/share/filebeat/filebeat.yml` | Filebeat configuration |

### filebeat.yml Summary

```yaml
filebeat.inputs:
  - type: log
    id: wazuh-alerts
    enabled: true
    paths:
      - /var/ossec/logs/alerts/alerts.json
    json.keys_under_root: true
    scan_frequency: 5s
    tags: ["wazuh-alert", "sentinel-x"]

output.elasticsearch:
  hosts: ["http://elasticsearch:9200"]
  username: "elastic"
  password: "${ELASTICSEARCH_PASSWORD}"
  index: "wazuh-alerts-%{+yyyy.MM.dd}"

setup.template.name: "wazuh-alerts"
setup.template.pattern: "wazuh-alerts-*"
```

---

## 5. Elasticsearch (sentinel_elasticsearch)

### Configuration Source

Configured entirely via environment variables in docker-compose.yml:

```yaml
environment:
  - cluster.name=sentinel-x-cluster
  - node.name=sentinel-elasticsearch
  - discovery.type=single-node
  - bootstrap.memory_lock=true
  - ES_JAVA_OPTS=-Xms1g -Xmx1g
  - ELASTIC_PASSWORD=${ELASTIC_PASSWORD:-changeme_elastic_lab}
  - xpack.security.enabled=true
  - xpack.security.http.ssl.enabled=false   # TLS disabled in lab
```

**Data stream:** `wazuh-alerts-2026.11.12`  
**Template:** `wazuh-alerts` (created by Filebeat on first start)  
**ILM:** Disabled (`setup.ilm.enabled: false`)

---

## 6. Kibana (sentinel_kibana)

### Configuration Source

Environment variables in docker-compose.yml:

```yaml
environment:
  - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
  - ELASTICSEARCH_USERNAME=elastic
  - ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD:-changeme_elastic_lab}
  - SERVER_NAME=sentinel-kibana
```

### Saved Objects (Phase 3)

| Object ID | Type | Title |
|-----------|------|-------|
| `1c0ea900-67d7-4919-b6a2-5972824a42a8` | index-pattern | wazuh-alerts-* |
| `sx-lens-total-alerts` | lens | [SX] Total Wazuh Alerts |
| `sx-lens-sentinel-alerts` | lens | [SX] SENTINEL-X Alerts |
| `sx-lens-critical-alerts` | lens | [SX] Critical Alerts (lvl 12+) |
| `sx-lens-waf-blocked` | lens | [SX] WAF Blocked Requests |
| `sx-lens-timeline` | lens | [SX] Alert Activity Timeline |
| `sx-lens-sentinel-timeline` | lens | [SX] SENTINEL-X Threat Timeline |
| `sx-lens-top-rules` | lens | [SX] Top SENTINEL-X Rules |
| `sx-lens-attack-dist` | lens | [SX] Attack Rule Distribution |
| `sx-lens-events-table` | lens | [SX] Recent SENTINEL-X Events |
| `sx-lens-sqli-count` | lens | [SX] SQLi Detections |
| `sx-lens-xss-count` | lens | [SX] XSS Detections |
| `sx-dashboard-overview` | dashboard | SENTINEL-X \| SOC Overview |
| `sx-dashboard-threats` | dashboard | SENTINEL-X \| Threat Detection |
| `sx-dashboard-investigation` | dashboard | SENTINEL-X \| Alert Investigation |

---

## 7. Environment Variables (.env)

| Variable | Default Value | Used By |
|----------|--------------|---------|
| `ELASTIC_VERSION` | 8.15.3 | docker-compose image tags |
| `ELASTIC_PASSWORD` | changeme_elastic_lab | Elasticsearch, Filebeat, Kibana |
| `KIBANA_PASSWORD` | changeme_kibana_lab | Kibana system user |
| `WAZUH_VERSION` | 4.9.2 | Wazuh Manager image |
| `WAZUH_API_USER` | wazuh-wui | Wazuh REST API |
| `WAZUH_API_PASSWORD` | SentinelX_Wazuh!2024 | Wazuh REST API |
| `WAZUH_REGISTRATION_PASSWORD` | SentinelX_Reg!2024 | Agent registration |
| `MODSEC_RULE_ENGINE` | On | ModSecurity blocking mode |
