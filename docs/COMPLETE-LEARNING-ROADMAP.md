# SENTINEL-X — Complete Learning Roadmap

A structured curriculum from fundamentals to advanced security engineering.
Each level builds directly on what SENTINEL-X uses.

---

## How to Use This Roadmap

Work through levels in order. Before moving to the next level, answer the questions at the end of each section. If you cannot answer them, re-read the material. Practice with the SENTINEL-X lab while learning each level — theory + hands-on is the fastest way to retain knowledge.

---

## LEVEL 1 — Foundations

### Why This Level Matters for SENTINEL-X
Every component in SENTINEL-X communicates over HTTP. ModSecurity works at the HTTP layer. Wazuh processes IP addresses and ports. Kibana runs as a web server. Without this foundation, nothing else makes sense.

### Topics

**Linux Fundamentals**  
SENTINEL-X runs inside Linux containers (even on Windows). Wazuh, NGINX, and Elasticsearch all run on Linux. You need to read log files, navigate directories, and run commands.

What to learn:
- File system hierarchy (`/var/log`, `/etc`, `/usr`, `/opt`)
- Basic commands: `ls`, `cd`, `cat`, `grep`, `tail -f`, `chmod`, `chown`
- Text processing: `grep`, `awk`, `sed`, pipes (`|`)
- Process management: `ps`, `kill`, `systemctl`
- File permissions: read/write/execute, `chmod 600`, `chmod 755`
- Environment variables: `export`, `$PATH`, `.bashrc`

Practical exercise with SENTINEL-X:
```bash
docker exec -it sentinel_wazuh_manager bash
ls /var/ossec/
tail -f /var/ossec/logs/alerts/alerts.json
grep "100020" /var/ossec/logs/alerts/alerts.json | tail -5
```

Questions you should be able to answer:
- What does `chmod 600` mean and why do private keys need it?
- What is `/var/log/` for?
- How do you read the last 20 lines of a file continuously?

Resources:
- https://www.linux.org/docs/index.html
- https://linuxcommand.org/lc3_learning_the_shell.php
- https://overthewire.org/wargames/bandit/ (free interactive Linux practice)

---

**Networking Fundamentals**

What to learn:
- OSI model (focus on Layer 3 Network, Layer 4 Transport, Layer 7 Application)
- IP addresses (IPv4: 192.168.1.1, subnets: 172.20.0.0/24)
- Ports (80=HTTP, 443=HTTPS, 9200=Elasticsearch, 5601=Kibana)
- TCP handshake (SYN, SYN-ACK, ACK)
- UDP vs TCP
- NAT (how Docker port mapping works)
- Firewall concepts (allow/deny by IP, port, protocol)

Practical exercise:
```powershell
# See what ports SENTINEL-X exposes
docker ps --format "{{.Ports}}"
# Shows 0.0.0.0:80->8080/tcp etc.

# Test connectivity
curl -v http://localhost/health
# See the TCP connection, HTTP headers, response
```

Questions:
- What does `0.0.0.0:9200->9200/tcp` mean in `docker ps`?
- What is the difference between port 9200 (Elasticsearch) and port 9201 (Wazuh Indexer)?
- Why can't the webapp container be reached directly from the host?

Resources:
- https://www.cloudflare.com/learning/network-layer/what-is-the-network-layer/
- https://www.cloudflare.com/learning/ddos/glossary/open-systems-interconnection-model-osi/

---

**HTTP and HTTPS**

This is THE most important foundation topic for SENTINEL-X.

What to learn:
- HTTP request structure: method, URL, headers, body
- HTTP methods: GET, POST, PUT, DELETE
- HTTP status codes: 200 OK, 403 Forbidden, 404 Not Found, 500 Server Error
- HTTP headers: Host, Content-Type, User-Agent, Cookie, Authorization
- Query strings: `?key=value&key2=value2`
- URL encoding: `%20` = space, `%2F` = `/`, `+` = space in query string
- HTTPS: TLS handshake, certificates, encryption

Practical exercise:
```bash
curl -v http://localhost/search?q=hello
# -v shows request AND response headers
# See: > GET /search?q=hello HTTP/1.1
#      < HTTP/1.1 200 OK
#      < X-Content-Type-Options: nosniff   ← your custom header
```

Questions:
- Why does ModSecurity inspect query parameters?
- What is URL encoding and why does CRS need to decode it before matching?
- What is the difference between HTTP 403 and HTTP 404?

Resources:
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Overview
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
- https://portswigger.net/web-security/learning-paths

---

## LEVEL 2 — Docker Infrastructure

### Why This Level Matters for SENTINEL-X
SENTINEL-X IS Docker. You can't maintain, troubleshoot, or rebuild it without understanding Docker.

**Docker Architecture**

What to learn:
- Docker Engine (daemon + CLI)
- Images: `docker pull`, `docker images`, layers
- Containers: `docker run`, `docker ps`, `docker stop`, `docker rm`
- Registries: Docker Hub, `docker.elastic.co`, `wazuh`
- Dockerfile: `FROM`, `RUN`, `COPY`, `EXPOSE`, `CMD`, `ENTRYPOINT`
- Building images: `docker build -t myimage:tag .`

Practical exercise:
```powershell
# Inspect the Flask app image
docker inspect sentinel_webapp
docker history sentinel_webapp  # see the layers

# See the Dockerfile
Get-Content "C:\Prime Kosova\WORK\SENTINEL-X\applications\vulnerable-lab\Dockerfile"
```

**Docker Compose**

What to learn:
- `docker-compose.yml` structure: version, services, networks, volumes
- `services:` block: image, container_name, ports, environment, volumes, networks
- `depends_on` with `condition: service_healthy`
- `restart:` policies: `no`, `always`, `unless-stopped`, `on-failure`
- `healthcheck:` block: test, interval, retries, start_period
- `volumes:` named vs bind mounts
- `networks:` driver, internal flag

Practical exercise:
```powershell
# Start/stop the whole stack
cd "C:\Prime Kosova\WORK\SENTINEL-X"
docker compose ps                   # see status
docker compose logs sentinel_filebeat --tail 30  # view logs
docker compose restart sentinel_filebeat  # restart one service
```

**Volumes and Networking**

Key concepts for SENTINEL-X:
- Named volumes vs bind mounts: named volumes are managed by Docker, persist data; bind mounts link host directories
- `internal: true` networks: containers can communicate but not reach outside Docker
- Container DNS: containers resolve each other by service name (`elasticsearch`, `webapp`, etc.)

Practical exercise:
```powershell
docker volume ls                    # see all 16 volumes
docker volume inspect sentinel_elasticsearch_data  # see where data lives
docker network ls                   # see all 6 networks
docker network inspect sentinel_application_net    # see which containers are on it
```

Questions:
- What is the difference between `docker compose down` and `docker compose down -v`?
- Why do we use `service_healthy` in `depends_on` rather than just `service_started`?
- What does `internal: true` on a Docker network mean for the webapp container?

Resources:
- https://docs.docker.com/get-started/
- https://docs.docker.com/compose/
- https://docs.docker.com/network/
- https://docs.docker.com/storage/volumes/

---

## LEVEL 3 — Web Security

### Why This Level Matters for SENTINEL-X
SENTINEL-X is specifically designed to detect OWASP Top 10 attacks. You need to understand what these attacks are to understand why the WAF detects them.

**NGINX and Reverse Proxies**

What to learn:
- `server { }` block structure
- `location / { }` routing
- `proxy_pass` directive
- `upstream` block
- Request and response headers manipulation
- `access_log` and `error_log`
- Load balancing basics

Resources:
- https://nginx.org/en/docs/beginners_guide.html
- https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/

**OWASP Top 10 (2021)**

The 10 most critical web application security risks. Know all of them:

1. **A01:2021 — Broken Access Control** (most common)
2. **A02:2021 — Cryptographic Failures** (data exposure, weak TLS)
3. **A03:2021 — Injection** ← SQL injection, OS command injection — SENTINEL-X detects this
4. **A04:2021 — Insecure Design**
5. **A05:2021 — Security Misconfiguration**
6. **A06:2021 — Vulnerable and Outdated Components**
7. **A07:2021 — Identification and Authentication Failures**
8. **A08:2021 — Software and Data Integrity Failures**
9. **A09:2021 — Security Logging and Monitoring Failures** ← SENTINEL-X solves this
10. **A10:2021 — Server-Side Request Forgery (SSRF)**

Resources:
- https://owasp.org/Top10/
- https://portswigger.net/web-security (best free hands-on training)

**SQL Injection**

What to learn:
- How SQL works: `SELECT * FROM users WHERE id = {input}`
- Classic injection: `1 OR 1=1--`
- Union-based injection
- Error-based injection
- Blind injection (Boolean and time-based)
- How prepared statements prevent SQLi
- How libinjection fingerprints SQL

Practice:
```bash
# Your SENTINEL-X lab:
curl -v "http://localhost/search?q=1 OR 1=1--"
# See 403. Then look at Kibana for rule.id: 100020
```

Resources:
- https://portswigger.net/web-security/sql-injection
- https://owasp.org/www-community/attacks/SQL_Injection

**XSS — Cross-Site Scripting**

What to learn:
- Reflected XSS vs Stored XSS vs DOM-based XSS
- Why `<script>alert(1)</script>` is the standard test payload
- How HTML encoding prevents XSS
- Content Security Policy (CSP)
- How the browser executes injected JavaScript

Practice:
```bash
curl -v "http://localhost/search?q=<script>alert(1)</script>"
# 403. Check Kibana for rule.id: 100021
```

Resources:
- https://portswigger.net/web-security/cross-site-scripting

**Path Traversal / LFI**

What to learn:
- Directory traversal: `../../../etc/passwd`
- URL encoding evasion: `..%2F..%2F`
- Double encoding: `..%252F` (browser decodes once, server decodes again)
- File inclusion vulnerabilities in PHP/Python
- `/etc/passwd`, `/etc/shadow`, `/proc/self/environ`

Practice:
```bash
curl -v "http://localhost/?file=../../../etc/passwd"
curl -v "http://localhost/?file=..%2F..%2F..%2Fetc%2Fpasswd"
# Both 403. Check Kibana for rule.id: 100022
```

Resources:
- https://portswigger.net/web-security/file-path-traversal
- https://owasp.org/www-community/attacks/Path_Traversal

---

## LEVEL 4 — WAF Engineering

**ModSecurity**

What to learn:
- SecRule syntax: `SecRule TARGET OPERATOR [ACTIONS]`
- Targets: `ARGS`, `REQUEST_HEADERS`, `REQUEST_URI`, `RESPONSE_BODY`
- Operators: `@rx` (regex), `@pm` (phrase match), `@detectSQLi`, `@detectXSS`
- Actions: `deny`, `pass`, `log`, `setvar`, `chain`
- SecRuleEngine modes: `On`, `DetectionOnly`, `Off`
- Phase 1–5 request processing

Your SENTINEL-X config file: `infrastructure\modsecurity\modsecurity-override.conf`

Resources:
- https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v3.x)
- https://www.modsecurity.org/

**OWASP CRS**

What to learn:
- CRS rule file naming: `REQUEST-942-APPLICATION-ATTACK-SQLI.conf`
- Anomaly scoring model vs traditional matching
- Paranoia levels 1–4
- How to identify which CRS rule triggered a block: look at `ruleId` in audit log
- How to write a CRS exclusion rule

Resources:
- https://owasp.org/www-project-modsecurity-core-rule-set/
- https://github.com/coreruleset/coreruleset
- https://coreruleset.org/docs/concepts/anomaly_scoring/
- https://coreruleset.org/docs/paranoia_levels/

**False Positives**

What to learn:
- What is a false positive (legitimate request blocked)
- How to identify: check audit log for `ruleId` and `data` field
- How to write exclusions in `REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf`
- Balance: too many exclusions = miss real attacks; too few = block legitimate users

---

## LEVEL 5 — SIEM and Blue Team

**SIEM Fundamentals**

What to learn:
- What a SIEM does: collect, normalize, correlate, alert
- Log sources: web server logs, auth logs, firewall logs, endpoint logs
- Correlation rules: "if 10 failed logins from same IP in 60s, alert"
- Alert triage: false positive vs true positive
- IOC: Indicator of Compromise (IP, hash, domain)

**Wazuh Architecture**

What to learn:
- Manager vs Agent architecture (we use agentless)
- Logcollector: `<localfile>` configuration, inotify
- Analysisd: event pipeline, decoder chain, rule evaluation
- Wazuh rule XML syntax: `id`, `level`, `if_sid`, `match`, `regex`, `field`, `description`, `mitre`
- Alert levels: 0–15 scale
- `frequency` and `timeframe` for correlation rules

Your rule file: `infrastructure\wazuh\rules\sentinel_x_rules.xml`

Resources:
- https://documentation.wazuh.com/current/user-manual/index.html
- https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/rules.html
- https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/decoders.html

**Writing Custom Rules**

Practice in SENTINEL-X: Add a new rule to detect scanner user agents:
```xml
<rule id="100040" level="7">
  <if_sid>100001</if_sid>
  <match type="pcre2">(?i)nessus|openvas|nmap</match>
  <description>SENTINEL-X: Vulnerability scanner detected</description>
  <group>nginx,scanner,</group>
  <mitre><id>T1595</id></mitre>
</rule>
```

After adding, reload Wazuh rules:
```bash
docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart
```

**MITRE ATT&CK**

What to learn:
- Tactics (the WHY): Initial Access, Execution, Persistence, Privilege Escalation, Defense Evasion, Credential Access, Discovery, Lateral Movement, Collection, Exfiltration, Command & Control
- Techniques (the HOW): specific methods within each tactic
- T1190: Exploit Public-Facing Application
- T1595: Active Scanning
- T1059: Command and Scripting Interpreter

Resources:
- https://attack.mitre.org/
- https://attack.mitre.org/techniques/T1190/

---

## LEVEL 6 — Logging and Data Engineering

**Filebeat**

What to learn:
- Input types: `log`, `filestream`, `container`
- `json.keys_under_root`: true vs false behavior
- Output types: `elasticsearch`, `logstash`, `opensearch`
- Processors: add_fields, rename, drop_fields
- Registry file: how position tracking works
- Troubleshooting: `filebeat test config`, `filebeat test output`

Your config: `infrastructure\ingestion\config\filebeat.yml`

Resources:
- https://www.elastic.co/guide/en/beats/filebeat/current/index.html

**Elasticsearch**

What to learn:
- Documents, indices, data streams
- PUT, GET, POST, DELETE REST verbs
- Query DSL: `match`, `term`, `range`, `bool`, `must`, `filter`
- Aggregations: `terms`, `date_histogram`, `avg`, `sum`
- Index mappings: `keyword`, `text`, `date`, `long`, `ip`
- ILM: Index Lifecycle Management (rollover, delete policies)
- ECS: Elastic Common Schema (standardized field names)

Practical exercises using your lab:
```powershell
# Count by rule level
curl -s -u elastic:changeme_elastic_lab -X POST "http://localhost:9200/.ds-wazuh-alerts-*/_search" -H "Content-Type: application/json" -d "{\"aggs\":{\"by_level\":{\"terms\":{\"field\":\"rule.level\"}}},\"size\":0}"

# Find events from last hour
curl -s -u elastic:changeme_elastic_lab -X POST "http://localhost:9200/.ds-wazuh-alerts-*/_search" -H "Content-Type: application/json" -d "{\"query\":{\"range\":{\"@timestamp\":{\"gte\":\"now-1h\"}}},\"size\":5}"
```

Resources:
- https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- https://www.elastic.co/guide/en/ecs/current/index.html

**OpenSearch**

Same as Elasticsearch but maintained by AWS. API is compatible with ES up to v7.10. Wazuh Indexer is based on OpenSearch.

Resources:
- https://opensearch.org/docs/latest/

**Kibana**

What to learn:
- Discover: KQL syntax, field filtering, time range
- Dashboard: panels, visualizations, drilldowns
- Dev Tools: run Elasticsearch queries from browser
- Lens: drag-and-drop visualization builder
- Creating a dashboard from scratch

Resources:
- https://www.elastic.co/guide/en/kibana/current/index.html
- https://www.elastic.co/guide/en/kibana/current/kuery-query.html

---

## LEVEL 7 — Advanced Security Engineering

**Detection Engineering**

What to learn:
- Detection lifecycle: hypothesis → rule → test → tune → monitor
- Writing detection rules (Sigma format — vendor-neutral)
- Alert fatigue: how too many alerts hide real threats
- True positive vs false positive rates
- SIEM use cases: brute force, lateral movement, data exfiltration

Resources:
- https://github.com/SigmaHQ/sigma
- https://detection.fyi/

**TLS and Cryptography**

What to learn:
- Symmetric vs asymmetric encryption
- TLS handshake: certificate, key exchange, cipher suite
- x.509 certificates: CN, SAN, CA, certificate chain
- Self-signed vs CA-signed certificates
- PKI: Public Key Infrastructure

Your SENTINEL-X TLS: `infrastructure\wazuh-stack\certs\`  
How it was generated: `infrastructure\wazuh-stack\gen-certs.sh`

Resources:
- https://www.cloudflare.com/learning/ssl/what-is-tls/
- https://www.cloudflare.com/learning/ssl/what-is-an-ssl-certificate/

**Docker Security**

What to learn:
- Principle of least privilege: `no-new-privileges`
- Read-only filesystems: `read_only: true`
- Rootless containers
- Image scanning: `docker scout`, Trivy
- Secrets management: Docker Secrets vs .env files
- Network segmentation: `internal: true` networks

Your SENTINEL-X security features: see `docs\DOCKER-INFRASTRUCTURE.md`

**Secrets Management**

What to learn:
- Why .env files are risky (accidental git commits)
- Docker Secrets (swarm mode)
- HashiCorp Vault
- Environment variable injection patterns
- Credential rotation

**Incident Response**

What to learn:
- NIST IR lifecycle: Preparation, Detection, Containment, Eradication, Recovery, Lessons Learned
- Evidence preservation (never modify original logs)
- Chain of custody
- Timeline reconstruction
- IOC extraction and sharing

Resources:
- https://www.nist.gov/publications/computer-security-incident-handling-guide
- Your file: `docs\INCIDENT-RESPONSE.md`

**Production Architecture**

What to learn:
- High availability: multiple replicas, load balancers
- Elasticsearch cluster: primary + replica shards
- Wazuh cluster: master + worker nodes
- Kubernetes vs Docker Compose for production
- Monitoring the monitoring system (meta-monitoring)
- Log retention and storage costs

---

## Study Plan (Recommended Order)

If you have 3 months:

**Month 1 — Foundations**
- Week 1–2: Linux + Networking + HTTP
- Week 3: Docker + Docker Compose
- Week 4: OWASP Top 10 + PortSwigger labs

**Month 2 — SENTINEL-X Stack**
- Week 1: NGINX + ModSecurity + CRS
- Week 2: Wazuh + custom rule development
- Week 3: Elasticsearch + Kibana queries
- Week 4: Filebeat + log pipeline debugging

**Month 3 — Advanced**
- Week 1: Detection engineering (write 5 new rules)
- Week 2: TLS + Docker security hardening
- Week 3: Threat hunting in Kibana/Wazuh Dashboard
- Week 4: Production architecture design exercise

---

## Certifications to Target

After completing this roadmap:
1. **CompTIA Security+** — Foundational security concepts
2. **Elastic Certified Analyst** — Kibana and ES query skills
3. **Wazuh Certification** — https://wazuh.com/training/
4. **eJPT (eLearnSecurity)** — Practical penetration testing
5. **Blue Team Labs Online** — https://blueteamlabs.online (free tiers)
