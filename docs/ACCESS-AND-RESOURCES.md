# SENTINEL-X — Access and Resources

All local interfaces, credentials, and published artifacts.

---

## Local Interfaces

### 1. Web Application (through WAF)
**URL:** `http://localhost`  
**What you see:** The Flask test application, protected by ModSecurity.  
**Auth:** None required — public endpoint.  
**When to use:** To trigger WAF detections during demos and testing.  
**Key endpoints:**
- `http://localhost/health` → Health check (always 200)
- `http://localhost/search?q=...` → Search endpoint (SQLi/XSS detection target)
- `http://localhost/?file=...` → File endpoint (LFI detection target)
- `http://localhost/?cmd=...` → Command endpoint (RCE detection target)
- `http://localhost/admin` → Returns 403 (scanner detection target)

### 2. Kibana — Elasticsearch Analytics
**URL:** `http://localhost:5601`  
**What you see:** Standard ELK stack analytics. Discover, Dashboards, Dev Tools.  
**Username:** `elastic`  
**Password:** See `.env` → `ELASTIC_PASSWORD` (value: `changeme_elastic_lab`)  
**When to use:** To search and analyze security events in Elasticsearch. Best for ad-hoc queries and ECS-format exploration.  
**Key navigation:**
- Discover → Data View: "SENTINEL-X Wazuh Alerts" → 300+ events
- Filter: `rule.id: 100020` → SQLi events
- Filter: `rule.groups: blocked` → all blocked attacks

### 3. Elasticsearch REST API
**URL:** `http://localhost:9200`  
**What you see:** REST API for Elasticsearch — JSON responses.  
**Username:** `elastic`  
**Password:** See `.env` → `ELASTIC_PASSWORD`  
**When to use:** Direct API queries during troubleshooting or automated scripts.  
**Key endpoints:**
```
http://localhost:9200/_cluster/health          → Cluster status
http://localhost:9200/.ds-wazuh-alerts-*/_count → Event count
http://localhost:9200/.ds-wazuh-alerts-*/_search → Query events
```

### 4. Wazuh Dashboard — SOC Interface
**URL:** `https://localhost:5602`  
**Note:** Accept the self-signed certificate warning in your browser.  
**What you see:** Official Wazuh SOC interface with pre-built security dashboards.  
**Username:** `admin`  
**Password:** See `.env` → `WAZUH_API_PASSWORD` or `WAZUH_ADMIN_PASSWORD` (value: `SecretPassword`)  
**When to use:** SOC investigation view. Threat hunting, MITRE ATT&CK coverage, compliance.

**Custom dashboards inside Wazuh Dashboard:**

| Dashboard | Purpose |
|---|---|
| Executive Overview | KPI tiles: Critical/High/Medium/Low counts, alert timeline |
| Threat Detection & WAF | WAF-specific: blocked attacks by type, source IPs |
| MITRE ATT&CK Coverage | ATT&CK tactic distribution for all alerts |
| Infrastructure & Incidents | Agent inventory, service health |

**Navigation:** Menu → OpenSearch Dashboards → Dashboards → find the SENTINEL-X dashboards.

### 5. Wazuh Indexer REST API
**URL:** `https://localhost:9201`  
**Note:** Use `-k` flag with curl for self-signed cert.  
**Username:** `admin`  
**Password:** `SecretPassword`  
**When to use:** Direct OpenSearch API queries for Wazuh alert data.  
```powershell
curl -sk -u admin:SecretPassword "https://localhost:9201/wazuh-alerts-4.x-*/_count"
```

### 6. Wazuh Manager API
**URL:** `http://localhost:55000`  
**Username:** `wazuh-wui`  
**Password:** See `.env` → `WAZUH_API_PASSWORD`  
**When to use:** Programmatic control of Wazuh Manager — list agents, reload rules, check status.  
**Get a token first:**
```powershell
$token = (curl -s -u "wazuh-wui:<password>" -X GET "http://localhost:55000/security/user/authenticate?raw=true").Content
curl -H "Authorization: Bearer $token" "http://localhost:55000/"
```

---

## Kibana Saved Data View

**Data View name:** SENTINEL-X Wazuh Alerts  
**Index pattern:** `wazuh-alerts-*`  
**Time field:** `@timestamp`  
**ID:** `1c0ea900-67d7-4919-b6a2-5972824a42a8`  
This Data View already exists. Navigate to Kibana → Discover → select it from the dropdown.

---

## Published Artifacts (Claude.ai — Private Links)

These pages were created during the project. They are hosted at claude.ai and are private to your account. Share them using the Share button on each page.

| Artifact | URL | Contents |
|---|---|---|
| **Interview Prep** | https://claude.ai/artifact/6EUuwRCtX6EAJdDeejLzcR | Complete interview guide: credentials, demo script, 20 Q&A, verdict |
| **Final Audit Report** | https://claude.ai/artifact/5nkBeVRQFPrqydEB2d2SDG | 12-phase acceptance scorecard, READY WITH DOCUMENTED LIMITATIONS |
| **v1.0.0 Release Report** | https://claude.ai/artifact/3oHeuFdpNamfVGLBmcBafq | Pre-release 8-check verification |
| **Architecture Compliance Audit** | https://claude.ai/artifact/9TQ2WVMmQY3FMv36H8rcvX | ES integration evidence, 13-question compliance matrix |

---

## Credential Rotation — How To Do It Safely

When you need to change passwords (before production or before `git init`):

**Step 1 — Edit `.env`:**
```
ELASTIC_PASSWORD=your_new_strong_password
KIBANA_PASSWORD=your_new_kibana_password
WAZUH_API_PASSWORD=your_new_wazuh_api_password
```

**Step 2 — Rebuild Elasticsearch security (if changing elastic password):**
```powershell
docker compose down
docker compose up -d elasticsearch
# Wait for healthy, then:
docker exec sentinel_elasticsearch bin/elasticsearch-reset-password -u elastic --batch
```

**Step 3 — Restart all services:**
```powershell
docker compose down
docker compose up -d
```

**Step 4 — Update Kibana keystore (if Kibana password changed):**
```powershell
docker exec sentinel_kibana bin/kibana-keystore add elasticsearch.password
```

**For Wazuh passwords**, see `infrastructure\wazuh-stack\indexer\opensearch-security\internal_users.yml` and use the `run-securityadmin.sh` script.

---

## Documentation Files

All files are in `C:\Prime Kosova\WORK\SENTINEL-X\docs\`

| File | Purpose | When to open |
|---|---|---|
| MASTER-PROJECT-HANDBOOK.md | Project overview, quick start | First reference |
| COMPLETE-FILE-INVENTORY.md | Every file explained | When looking for a config file |
| ACCESS-AND-RESOURCES.md | This file | For URLs and credentials |
| ARCHITECTURE-DEEP-DIVE.md | Component explanations | To understand how it works |
| EVENT-FLOW-ANALYSIS.md | Attack traces through every layer | To understand the detection pipeline |
| CUSTOM-IMPLEMENTATION-REFERENCE.md | Your custom rules and configs | To understand what you built |
| COMPLETE-LEARNING-ROADMAP.md | 7-level curriculum | For studying |
| PRACTICAL-LAB-WORKBOOK.md | Hands-on exercises | For practice |
| OFFICIAL-LEARNING-RESOURCES.md | Curated resource links | For reading and studying |
| DEMO-RUNBOOK.md | Live demo commands | During interview/demo |
| INTERVIEW-GUIDE.md | 20 interview Q&A | Interview preparation |
| TROUBLESHOOTING_GUIDE.md | Fix common issues | When something breaks |

---

## GitHub (Future)

When you are ready to push to GitHub:
1. Run: `cd "C:\Prime Kosova\WORK\SENTINEL-X"` then `git init`
2. Check `.gitignore` excludes `.env` and `certs\*.key`
3. Replace literal passwords in docs with placeholders like `<ELASTIC_PASSWORD>`
4. Create the repo at github.com and push
5. Suggested tag: `git tag v1.0.0`
