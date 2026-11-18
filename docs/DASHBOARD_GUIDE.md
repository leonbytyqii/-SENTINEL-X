# SENTINEL-X — Dashboard Guide (Kibana + Wazuh Official)

**Version:** Phase 4  
**Last Updated:** 2026-11-13  
**Kibana Version:** 8.15.3 | Wazuh Dashboard Version:** 4.9.2

---

## 1. Accessing Kibana

Open your browser and navigate to:

```
http://localhost:5601
```

**Credentials:**
- Username: `elastic`
- Password: `changeme_elastic_lab`

> ⚠️ These are lab credentials. Never use these in a production or shared environment.

---

## 2. Dashboard Overview

Three custom SENTINEL-X dashboards are available. Access them via:

**Menu:** Kibana → Analytics → Dashboards

Or navigate directly:

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| SOC Overview | `http://localhost:5601/app/dashboards#/view/sx-dashboard-overview` | Executive summary of all alerts |
| Threat Detection | `http://localhost:5601/app/dashboards#/view/sx-dashboard-threats` | WAF attack details |
| Alert Investigation | `http://localhost:5601/app/dashboards#/view/sx-dashboard-investigation` | Drill-down into specific incidents |

---

## 3. Dashboard A — SENTINEL-X SOC Overview

**Purpose:** High-level executive view of all security activity.

### Panels

| Panel | Description |
|-------|-------------|
| Total Wazuh Alerts | Count of all alerts in the selected time range |
| SENTINEL-X Alerts | Count of alerts from custom SENTINEL-X rules only (rule.groups:sentinel-x) |
| Critical Alerts (lvl 12+) | Count of alerts with rule.level ≥ 12 |
| WAF Blocked Requests | Count of alerts in waf_block or waf groups |
| Alert Activity Timeline | Bar chart: all Wazuh alerts over time |
| Attack Rule Distribution | Donut chart: distribution by rule ID for SENTINEL-X alerts |
| Top SENTINEL-X Rules | Bar chart: most triggered rule descriptions |
| Recent SENTINEL-X Events | Data table: rule ID, level, description, count per hour |

### Default Time Range
Last 7 days. The dashboard includes all Phase 2 and Phase 3 test data from 2026-11-12.

---

## 4. Dashboard B — SENTINEL-X Threat Detection

**Purpose:** Attack-specific analysis filtered to SENTINEL-X WAF events.

### Panels

| Panel | Description |
|-------|-------------|
| SQLi Detections | Count of rule 100020 (SQL Injection) alerts |
| XSS Detections | Count of rule 100021 (XSS) alerts |
| WAF Blocked Requests | Total WAF blocks |
| Critical Alerts | Alerts at severity 12+ |
| SENTINEL-X Threat Timeline | Stacked bar chart: blocked attacks over time, split by rule description |
| Attack Rule Distribution | Donut: rule ID distribution for SENTINEL-X alerts |
| Top SENTINEL-X Rules | Bar chart: rule hit frequency |

### Pre-Applied Filter
This dashboard applies `rule.groups: "sentinel-x"` as a base filter, so all panels show only SENTINEL-X WAF events (not Wazuh internal/SCA/rootcheck events).

---

## 5. Dashboard C — SENTINEL-X Alert Investigation

**Purpose:** Analyst workspace for investigating specific incidents.

### Panels

| Panel | Description |
|-------|-------------|
| Recent SENTINEL-X Events (table) | Tabular view: timestamp buckets, rule ID, severity level, description, count |
| Top SENTINEL-X Rules (bar) | Frequency chart for context |
| Attack Rule Distribution (donut) | Attack type breakdown |

### Time Range for November 12 Incidents
This dashboard is pre-configured with an absolute time range:
- From: `2026-11-12T00:00:00`
- To: `2026-11-13T00:00:00`

This shows all Phase 2 and Phase 3 test events from the validation day.

---

## 6. Setting Time Ranges

### Using the Time Picker
1. Click the calendar/clock icon in the top-right corner
2. Select a preset (Last 15 minutes, Last 24 hours, etc.) OR
3. Click **Absolute** and type exact timestamps

### Finding the November 12 Test Events
To see the validated SQLi/XSS/LFI detections at 17:47:51 UTC:

1. Set time range: `2026-11-12 17:00:00` → `2026-11-12 18:00:00`
2. The Attack Investigation dashboard will show 12 events

---

## 7. Using KQL Filters

Kibana Query Language (KQL) allows precise filtering. Use the search bar at the top of any dashboard.

### Useful KQL Queries

```kql
# All SENTINEL-X alerts
rule.groups: "sentinel-x"

# SQL Injection only
rule.groups: "sql_injection"

# XSS only
rule.groups: "xss"

# Critical alerts
rule.level >= 12

# Specific rule
rule.id: "100020"

# WAF blocked requests
rule.groups: "waf_block" OR rule.groups: "waf"

# Multiple rules
rule.id: ("100020" OR "100021" OR "100022" OR "100023")

# Exclude internal/SCA events (show only WAF events)
rule.groups: "sentinel-x" AND NOT rule.groups: "sca"
```

---

## 8. Data View Configuration

**Data View Name:** wazuh-alerts-*  
**Data View ID:** `1c0ea900-67d7-4919-b6a2-5972824a42a8`  
**Backing Index:** `.ds-wazuh-alerts-2026.11.12-2026.11.12-000001`  
**Time Field:** `@timestamp`

### Key Searchable Fields

| Field | Type | Description |
|-------|------|-------------|
| `@timestamp` | date | Event timestamp |
| `rule.id` | keyword | Wazuh rule ID (e.g., "100020") |
| `rule.level` | long | Severity 1-15 |
| `rule.description` | keyword | Human-readable rule description |
| `rule.groups` | keyword | Rule category tags |
| `rule.mitre_tactics` | keyword | MITRE ATT&CK tactic |
| `decoder.name` | keyword | Decoder that processed the event |

---

## 9. Discover Tab — Raw Event Investigation

For complete JSON inspection of individual events:

1. Navigate to **Analytics → Discover**
2. Select data view: **wazuh-alerts-***
3. Set the desired time range
4. Apply filter: `rule.id: "100020"` (or any rule ID)
5. Click any document row to expand full JSON

### Finding the Three Validation Alerts (17:47:51 UTC)

```kql
rule.id: ("100020" OR "100021" OR "100023") AND @timestamp >= "2026-11-12T17:47:00"
```

This returns exactly 3 documents:
- Rule 100020 — SQL Injection detected and blocked (level 12)
- Rule 100021 — XSS attempt detected and blocked (level 11)
- Rule 100023 — CRITICAL RCE attempt detected and blocked (level 14)

---

## 10. Alert Investigation Workflow

Follow these 5 steps to investigate a suspicious alert:

### Step 1 — Find the Alert
- Open the **Alert Investigation** dashboard
- Set the time range to the incident window
- Identify the rule ID and timestamp in the events table

### Step 2 — Inspect the Full Event
- Go to **Discover**
- Filter: `rule.id: "<id>" AND @timestamp >= "<incident time>"`
- Expand the document to see all fields

### Step 3 — Identify the Source
- Look at `data.remote_addr` or `data.transaction.client_ip` in the raw event JSON for the source IP
- Check `data.transaction.request.uri` for the attacked endpoint
- Review `data.transaction.request.method` for the HTTP method

### Step 4 — Understand the Rule
- Note `rule.id`, `rule.level`, `rule.groups`, `rule.description`
- Cross-reference with `docs/DETECTION_ENGINEERING.md` for the full rule definition
- Check `rule.mitre_tactics` and `rule.mitre_techniques` for ATT&CK mapping

### Step 5 — Search for Related Events
To find all events from the same attack session:

```kql
# Find all events near the same time
@timestamp >= "2026-11-12T17:47:00" AND @timestamp <= "2026-11-12T17:48:00"
```

---

## 11. Known Limitations

| Limitation | Detail |
|------------|--------|
| srcip empty in alerts | Custom decoders not loaded; `data.remote_addr` and `data.transaction.client_ip` contain the IP in the raw event but are not extracted as `srcip` for the `$(srcip)` macro |
| Single-day data stream | wazuh-alerts data stream rolls over daily; queries spanning multiple days need a wildcard pattern like `wazuh-alerts-*` |
| No TLS on Kibana | HTTP only; use on trusted local network |
| Wazuh internal alerts visible | SCA, rootcheck, and Wazuh system events also appear in wazuh-alerts-*; use `rule.groups: "sentinel-x"` to filter to WAF events only |

---

## 12. Wazuh Official Dashboard (Phase 4)

A second dashboard is available at port 5602 — the official Wazuh Dashboard 4.9.2.

### Accessing the Wazuh Dashboard

Navigate to: **https://localhost:5602**

> Accept the self-signed certificate warning.

**Credentials:**
- Username: `admin`
- Password: `SecretPassword`

> ⚠️ Lab credentials. Rotate before any shared deployment.

### Landing Page

After login you are redirected to `/app/wz-home` — the Wazuh Overview page. This is the correct route for Wazuh Dashboard 4.9.2. If you see "APPLICATION NOT FOUND", clear the browser cache and revisit; the app registers `wz-home`, not `wazuh`.

### Key Pages

| Page | URL path | Purpose |
|------|----------|---------|
| Overview | `/app/wz-home` | Wazuh event summary and agent health |
| Security Events | `/app/wz-home#/overview/?tab=general` | All security events, charts and table |
| Threat Intelligence | `/app/wz-home#/overview/?tab=mitre` | MITRE ATT&CK heatmap |
| Vulnerabilities | `/app/wz-home#/overview/?tab=vuls` | Vulnerability detection |
| Agent Inventory | `/app/endpoints-summary` | List of registered agents |
| Dev Tools | `/app/dev_tools` | OpenSearch REST API console |

### Data in Wazuh Dashboard

The Wazuh Dashboard reads from `wazuh-indexer` (port 9200 internal). This is a separate store from Elasticsearch (the Kibana backend). As of 2026-11-13, wazuh-indexer contains **572 alert documents** in index `wazuh-alerts-4.x-2026.11.12`.

### Wazuh Agent Note

The only registered Wazuh agent is the manager itself (agent ID `000`, name `fa8783d606c8`). The NGINX WAF events are shipped via ModSecurity → manager log → Filebeat, not via a traditional Wazuh agent. This is correct behavior for this architecture.
