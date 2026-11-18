# SENTINEL-X — Complete File Inventory

Every file in the project explained.

---

## Root Directory Files

### `.env`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\.env`  
**Purpose:** Contains all credentials and environment variables used by docker-compose.yml.  
**Used by:** Docker Compose at startup — values are injected into container environments.  
**Important:** This is the most sensitive file in the project. It contains Elasticsearch, Kibana, Wazuh, and admin passwords.  
**Edit?** Yes, to change credentials — but always restart containers after editing.  
**Git:** NEVER COMMIT — it is in `.gitignore`. Use `.env.example` as a template instead.  
**Contains:** ELASTIC_PASSWORD, KIBANA_PASSWORD, WAZUH_API_PASSWORD, MODSEC_RULE_ENGINE, PARANOIA level, ANOMALY thresholds.

### `.env.example`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\.env.example`  
**Purpose:** Shows the structure of `.env` with placeholder values — safe reference.  
**Edit?** Yes, to document new variables. Safe to commit.

### `.gitignore`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\.gitignore`  
**Purpose:** Tells Git which files to never track. Includes `.env`, TLS keys, and backup files.  
**Edit?** Only to add new files that should never be committed.

### `docker-compose.yml`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\docker-compose.yml`  
**Purpose:** The master orchestration file. Defines all 9 containers, their images, volumes, networks, environment variables, healthchecks, and dependencies.  
**Used by:** Docker Compose — this is the entire system definition.  
**Edit?** Be very careful. Any change here affects the whole stack. Always back up first.  
**Key sections:** services (9 containers), networks (6 networks), volumes (16 named volumes).

### `docker-compose.yml.bak-20261112-2007` and `docker-compose.yml.bak-20261113-0047`
**Purpose:** Automatic backups made during development sessions.  
**Status:** Obsolete — the current `docker-compose.yml` is correct and complete.  
**Can delete?** Yes, after confirming the current stack works. Keep for reference if needed.

### `README.md`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\README.md`  
**Purpose:** Project overview, architecture summary, startup instructions.  
**Edit?** Safe to update with new information.

### `CHANGELOG.md`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\CHANGELOG.md`  
**Purpose:** Records changes made during each development phase.  
**Edit?** Add entries when you make changes in the future.

---

## Application Files

### `applications\vulnerable-lab\src\app.py`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\applications\vulnerable-lab\src\app.py`  
**Purpose:** The Flask web application. Provides 7 HTTP endpoints as targets for WAF testing.  
**Used by:** `sentinel_webapp` container.  
**Endpoints:** `/health`, `/`, `/search`, `/api/users`, `/api/items`, `/contact`, `/files`, `/admin`  
**Important:** The app does NOT access any real database or filesystem. Inputs are HTML-escaped before returning. The WAF catches attacks at the HTTP layer before the app sees them.  
**Edit?** Yes — you can safely add new test endpoints here.

### `applications\vulnerable-lab\Dockerfile`
**Path:** `C:\Prime Kosova\WORK\SENTINEL-X\applications\vulnerable-lab\Dockerfile`  
**Purpose:** Builds the Docker image for the Flask app. Uses Python 3.11-slim, installs flask.  
**Edit?** Only if you need to add Python packages.

### `applications\vulnerable-lab\requirements.txt`
**Purpose:** Python package list. Currently just `flask`.  
**Edit?** Add packages here and rebuild the image with `docker compose build webapp`.

---

## NGINX Configuration Files

### `infrastructure\nginx\conf.d\sentinel.conf`
**Path:** Full path as above.  
**Purpose:** The main NGINX server configuration. Defines:
- JSON access log format (all 15 fields that Wazuh parses)
- Security headers (X-Content-Type-Options, X-Frame-Options, CSP, etc.)
- Request limits (body size 10MB, timeouts)
- `/health` endpoint (bypasses proxy, returns JSON directly from NGINX)
- `proxy_pass http://webapp:8080` — forwards all other traffic to Flask
- Blocking of `.git`, `.env`, `.htaccess` file access  
**Edit?** Be careful — breaking this file stops all HTTP traffic. Test changes in a staging environment.

### `infrastructure\nginx\conf.d\sentinel_json_log.conf`
**Purpose:** Defines the JSON log format used by NGINX access logs. Each field maps to a JSON key that Wazuh's decoder reads.  
**Edit?** Only if you need to add new log fields.

### `infrastructure\nginx\modsecurity-override.conf`
**Purpose:** A short local override applied inside the container. References the main ModSecurity config from the OWASP base image.  
**Edit?** Only if you need to reference additional config files.

---

## ModSecurity Configuration Files

### `infrastructure\modsecurity\modsecurity-override.conf`
**Purpose:** Main ModSecurity settings that override the base image defaults:
- Audit log format: JSON (required for Wazuh parsing)
- Audit log path: `/var/log/modsecurity/audit.log`
- Audit parts: ABCEFHIJKZ (which sections to include)
- Request body inspection: On (inspects POST bodies)
- Response body inspection: On
- SecAuditEngine: RelevantOnly (only logs blocked/interesting events, not every request)  
**Edit?** Only if you need to change audit log behavior. Changing the format breaks Wazuh parsing.

### `infrastructure\modsecurity\crs-setup-override.conf`
**Purpose:** Configures the OWASP Core Rule Set:
- Paranoia Level: Controlled by PARANOIA env var (currently 1)
- Anomaly thresholds: Controlled by ANOMALY_INBOUND (currently 5) and ANOMALY_OUTBOUND env vars
- Allowed HTTP methods: GET, HEAD, POST, OPTIONS, PUT, DELETE, PATCH
- Allowed content types: JSON, form-urlencoded, multipart
- Restricted file extensions: .bak, .bat, .cfg, .dll, .exe, .key, .pem, etc.  
**Edit?** Safe to add new allowed methods or content types. Changing thresholds changes WAF sensitivity.

### `infrastructure\modsecurity\exclusions\REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf`
**Purpose:** False-positive suppression rules applied BEFORE the CRS runs. If a legitimate request triggers a false alert, you add exclusion rules here.  
**Edit?** When adding false-positive exclusions.

### `infrastructure\modsecurity\exclusions\RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf`
**Purpose:** False-positive suppression rules applied AFTER the CRS runs.  
**Edit?** Same as above but for response-side false positives.

---

## Wazuh Configuration Files

### `infrastructure\wazuh\manager\ossec.conf`
**Path:** This is the main Wazuh Manager configuration file.  
**Purpose:** Tells Wazuh:
- Which log files to monitor (NGINX access log, ModSecurity audit log)
- Which decoder files to use
- Which rule files to load
- Global settings: alert level, remote log forwarding  
**CRITICAL:** Do not replace this with the default. It has been customized to monitor our specific log paths.  
**Edit?** Only if you need to add new log sources or change alert settings.

### `infrastructure\wazuh\manager\ossec.conf.default`
**Purpose:** Backup of the original Wazuh default configuration.  
**Status:** Reference only — not actively used.  
**Edit?** No.

### `infrastructure\wazuh\rules\sentinel_x_rules.xml`
**Path:** This is the most important custom file you created.  
**Purpose:** Contains your 15 custom detection rules (IDs 100001–100030). These rules:
- Match on raw log text from NGINX and ModSecurity JSON logs
- Assign severity levels (3–14)
- Map to MITRE ATT&CK techniques
- Classify attacks as SQLi, XSS, LFI, RCE, brute force, scanner  
**CRITICAL:** Never overwrite this with an external file. These rules are the core of your detection capability.  
**Edit?** Yes — to add new rules. Use rule IDs 100031–100099 for new additions.

### `infrastructure\wazuh\rules\sentinel_x_rules.xml.bak3`
**Purpose:** Backup of an earlier version of the rules file.  
**Status:** Obsolete — the current rules file is correct and complete.  
**Can delete?** Not recommended — keep as recovery point.

### `infrastructure\wazuh\decoders\modsecurity_decoders.xml`
**Purpose:** Tells Wazuh how to parse ModSecurity JSON audit log events. Extracts:
- `srcip` from `client_ip` field
- Request URI, method, protocol
- Response HTTP code
- CRS rule IDs from messages array  
**Edit?** Only if the ModSecurity log format changes.

### `infrastructure\wazuh\decoders\nginx_decoders.xml`
**Purpose:** Tells Wazuh how to parse NGINX JSON access log events. Extracts:
- `srcip` from `remote_addr`
- Request URI, method
- HTTP status code
- Response size, timing  
**Edit?** Only if the NGINX log format changes.

### `infrastructure\wazuh\manager\init-shared.sh`
**Purpose:** Initialization script run when the Wazuh Manager container first starts. Copies custom rules and decoders into place inside the container.  
**Edit?** If you add new rules or decoder files.

---

## Filebeat Configuration Files

### `infrastructure\ingestion\config\filebeat.yml`
**Purpose:** Filebeat Pipeline 1 configuration. Reads Wazuh `alerts.json` and sends to Elasticsearch.  
**Key settings:**
- Input: `/var/ossec/logs/alerts/alerts.json` (JSON format)
- Output: `http://elasticsearch:9200`
- Tags: `["wazuh-alert","sentinel-x"]`
- `ignore_older: 24h` (skips events older than 24 hours on startup)
- ECS v8.0.0 field mapping  
**Edit?** If you need to change the ES destination or add index lifecycle rules.

### `infrastructure\wazuh-stack\filebeat\filebeat-wazuh.yml`
**Purpose:** Filebeat Pipeline 2 configuration. Reads same `alerts.json` and sends to Wazuh Indexer.  
**Key settings:**
- Input: same source file (independent registry)
- Output: `https://wazuh-indexer:9200` (TLS with client cert)
- Uses Wazuh Filebeat module (custom index template)  
**Edit?** Only if Wazuh Indexer address changes.

### `infrastructure\wazuh-stack\filebeat\module-wazuh\`
**Purpose:** The official Wazuh Filebeat module. Provides the index template and ingest pipeline that correctly formats Wazuh alerts for the Wazuh Indexer.  
**Edit?** Never — this is an official Wazuh-provided module.

### `infrastructure\wazuh-stack\filebeat\wazuh-template.json`
**Purpose:** The Elasticsearch/OpenSearch index template for Wazuh alert indices. 63KB — defines all field mappings for the `wazuh-alerts-4.x-*` indices.  
**Edit?** Never — official Wazuh template.

---

## Elasticsearch and Kibana Files

### `infrastructure\elasticsearch\config\elasticsearch.yml`
**Purpose:** Elasticsearch cluster configuration:
- Cluster name: `sentinel-x-cluster`
- Node name: `sentinel-node-1`
- Security: `xpack.security.enabled: true`
- HTTP SSL disabled (lab only)
- Network host: `0.0.0.0`  
**Edit?** To change cluster name or enable TLS before production.

### `infrastructure\elasticsearch\lifecycle\sentinel-x-policy.json`
**Purpose:** Index Lifecycle Management policy. Defines when alert indices roll over (size/age thresholds).  
**Edit?** To change retention periods before production.

### `infrastructure\elasticsearch\templates\sentinel-x-template.json`
**Purpose:** Index template for `wazuh-alerts-*` data streams. Defines field mappings, replica count, refresh interval.  
**Edit?** Only if you need to add custom field mappings.

### `infrastructure\dashboards\kibana\kibana.yml`
**Purpose:** Kibana configuration:
- Elasticsearch connection: `http://elasticsearch:9200`
- Server name, host, port
- Security cookie encryption key
- Logging settings  
**Edit?** To change Kibana server settings or connection.

---

## Wazuh Stack Files

### `infrastructure\wazuh-stack\certs\`
**Purpose:** TLS certificates for Wazuh components. Contains:
- `root-ca.pem` / `root-ca.key` — Certificate Authority
- `wazuh-indexer.pem` / `wazuh-indexer.key` — Wazuh Indexer server cert
- `wazuh-manager.pem` / `wazuh-manager.key` — Wazuh Manager cert
- `wazuh-dashboard.pem` / `wazuh-dashboard.key` — Dashboard cert
- `admin.pem` / `admin.key` — Admin client cert for security operations  
**CRITICAL:** Never delete this directory. Wazuh TLS communication breaks without it.  
**Edit?** Never directly — use `gen-certs.sh` to regenerate if needed.

### `infrastructure\wazuh-stack\indexer\opensearch-security\internal_users.yml`
**Purpose:** Defines users and hashed passwords for Wazuh Indexer (OpenSearch Security plugin).  
**Contains:** admin, wazuh-admin, and wazuh-ingest user entries with bcrypt-hashed passwords.  
**Edit?** When rotating passwords — requires running `run-securityadmin.sh` after changes.

### `infrastructure\wazuh-stack\dashboard\config\sentinel_x_saved_objects_backup_20261113.ndjson`
**Purpose:** Complete backup of all Wazuh Dashboard saved objects: dashboards, visualizations, index patterns.  
**Size:** 153KB — contains all 4 custom dashboards.  
**Edit?** Never directly. This is a recovery file.  
**Use:** If dashboards disappear, import via Wazuh Dashboard → Stack Management → Saved Objects → Import.

---

## Scripts

### `scripts\start.ps1`
**Purpose:** Automated startup script. Starts the stack in correct order with health checks.

### `scripts\stop.ps1`
**Purpose:** Graceful shutdown. Runs `docker compose down` (preserves volumes).

### `scripts\health-check.ps1`
**Purpose:** Checks all services are responding correctly. Tests all 6 endpoints.

### `scripts\validate.ps1`
**Purpose:** Full validation suite. Tests WAF blocking, event ingestion, and dashboard availability.

### `scripts\backup.ps1`
**Purpose:** Creates timestamped backups of configurations and dashboard exports.

### `scripts\init-elasticsearch.ps1`
**Purpose:** Initializes Elasticsearch index template and ILM policy on first run.

### `scripts\setup.ps1`
**Purpose:** First-time setup script.

### `scripts\cleanup.ps1`
**Purpose:** Removes old backups and temporary files. SAFE to run — does not touch Docker volumes.

---

## Sensitive Files — Never Commit to Git

| File | Contains | Risk |
|---|---|---|
| `.env` | All passwords | Full system compromise |
| `infrastructure\wazuh-stack\certs\*.key` | Private TLS keys | TLS impersonation |
| `infrastructure\wazuh-stack\indexer\opensearch-security\internal_users.yml` | Password hashes | Brute-forceable |
| `backups\*` | May contain config with credentials | Variable |

---

## Obsolete / Duplicate Files

| File | Status | Action |
|---|---|---|
| `docker-compose.yml.bak-20261112-2007` | Outdated backup | Can delete after verification |
| `docker-compose.yml.bak-20261113-0047` | Outdated backup | Can delete after verification |
| `infrastructure\wazuh\rules\sentinel_x_rules.xml.bak3` | Old rules backup | Keep as recovery point |
| `infrastructure\wazuh\manager\ossec.conf.default` | Reference copy | Keep for comparison |

---

## Evidence Files

### `evidence\test-results\validation-*.txt`
**Purpose:** Automated test results from the validation script. Record of which tests passed.  
**Status:** Verified — 9/10 checks PASS. The 1 failure is Wazuh Dashboard visual rendering (browser check needed).

### `backups\phase2-20261112-170543\`
**Purpose:** Configuration snapshot taken during phase 2 development. Contains working configs from that point.  
**Edit?** No — read-only reference.
