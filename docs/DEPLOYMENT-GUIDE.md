# SENTINEL-X – Deployment Guide

## Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Docker Desktop | 4.x (WSL2 backend) | Latest |
| RAM (Docker) | 8 GB | 12 GB |
| Disk space | 10 GB | 20 GB |
| CPU cores | 4 | 8 |
| OS | Windows 11 | Windows 11 |

---

## Step 1 – Install Docker Desktop

If Docker Desktop is not installed:

```
winget install Docker.DockerDesktop
```

After installation:
1. Open Docker Desktop
2. Go to Settings → Resources → Advanced
3. Set Memory to at least 8192 MB (8 GB)
4. Enable WSL2 integration
5. Click "Apply & Restart"

---

## Step 2 – WSL2 Virtual Memory

Elasticsearch requires a higher `vm.max_map_count` than the default WSL2 setting.
The `setup.ps1` script handles this automatically, or run manually:

```powershell
wsl -e sudo sysctl -w vm.max_map_count=262144
# To persist across WSL restarts:
wsl -e bash -c "echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf"
```

---

## Step 3 – Clone / Download the Project

Place the project at: `C:\Prime Kosova\WORK\SENTINEL-X`

---

## Step 4 – Configuration

```powershell
cd "C:\Prime Kosova\WORK\SENTINEL-X"
.\scripts\setup.ps1
```

This creates `.env` from `.env.example`. **Edit `.env` and change all passwords:**

```env
ELASTIC_PASSWORD=your_strong_password_here
KIBANA_PASSWORD=your_kibana_password_here
WAZUH_API_PASSWORD=your_wazuh_api_password
WAZUH_REGISTRATION_PASSWORD=your_registration_password
```

Minimum password requirements: 8+ characters, mixed case recommended.

---

## Step 5 – Start the Stack

```powershell
.\scripts\start.ps1
```

Expected startup sequence and timings:

| Service | Typical startup time |
|---------|---------------------|
| webapp | ~10s |
| nginx-waf | ~20s |
| elasticsearch | 60–90s |
| wazuh-manager | 60–90s |
| kibana | 90–120s |
| filebeat | after elasticsearch healthy |

---

## Step 6 – First-Run Elasticsearch Setup

Run **once** after the first `docker compose up`:

```powershell
.\scripts\init-elasticsearch.ps1
```

This sets the `kibana_system` password, creates the ILM policy, and registers the index template.

---

## Step 7 – Kibana Setup (First Access)

1. Open `http://localhost:5601`
2. Login: `elastic` / value from `ELASTIC_PASSWORD` in `.env`
3. Navigate to **Stack Management → Index Patterns**
4. Create index pattern: `wazuh-alerts-*` with time field `@timestamp`
5. Navigate to **Dashboards** to view security events

---

## Step 8 – Run the Security Test Suite

```powershell
.\scripts\validate.ps1
```

---

## Stopping the Stack

```powershell
# Stop containers — preserves all data
.\scripts\stop.ps1

# Start again later
.\scripts\start.ps1
```

**Important:** `docker compose down` stops containers and preserves named volumes.
`docker compose down -v` **destroys all persistent data** (Elasticsearch indices, Wazuh alerts, Kibana dashboards).

---

## Enabling WAF Blocking Mode

By default, ModSecurity runs in `DetectionOnly` mode — attacks are logged but not blocked.

To enable blocking:
```env
# .env
MODSEC_RULE_ENGINE=On
```
```powershell
docker compose up -d nginx-waf
```

To verify:
```powershell
curl "http://localhost/api/users?id=1' OR '1'='1"
# Expected: HTTP 403 Forbidden
```

---

## Resource Usage Reference

| Container | CPU (idle) | CPU (peak) | RAM |
|-----------|-----------|-----------|-----|
| elasticsearch | 0.1% | 50% | 1–2 GB |
| wazuh-manager | 0.5% | 20% | 256–512 MB |
| kibana | 0.1% | 10% | 256–512 MB |
| filebeat | 0.0% | 5% | 64–128 MB |
| nginx-waf | 0.0% | 5% | 64–128 MB |
| webapp | 0.0% | 1% | 32–64 MB |
| **Total** | | | **~2–3.5 GB** |

---

## Port Reference

| Port | Service | Binding | Purpose |
|------|---------|---------|---------|
| 80 | nginx-waf | 0.0.0.0 | Web application (WAF gateway) |
| 9200 | elasticsearch | 127.0.0.1 | Elasticsearch API |
| 5601 | kibana | 127.0.0.1 | Security dashboards |
| 55000 | wazuh-manager | 0.0.0.0 | Wazuh REST API |

Internal ports (not exposed to host): 8080 (webapp), 1514 (Wazuh agent listener), 1515 (Wazuh enroll), 9300 (ES transport).
