# SENTINEL-X — Interview Guide

Technical explanation scripts and Q&A for a cybersecurity interview.
All answers are based on the actual implementation — no idealized descriptions.

---

## 60-Second Explanation

"I built a local security monitoring stack using Docker Compose. HTTP traffic enters through NGINX, which runs OWASP ModSecurity in blocking mode — that's the WAF. If a request looks malicious, ModSecurity blocks it and writes a JSON audit log. NGINX also writes an access log for every request.

Wazuh, an open-source SIEM, reads both logs and applies custom detection rules I wrote. When a rule fires, Wazuh generates a structured JSON alert and writes it to an alert file.

Two separate Filebeat pipelines pick up those alerts. One forwards them to Elasticsearch, where Kibana can visualize them. The other forwards them to Wazuh Indexer — that's the official Wazuh storage backend, which the Wazuh Dashboard reads for its native SOC views.

The result is a complete threat detection pipeline: a WAF that blocks attacks, a SIEM that classifies them, and two analytics platforms that let you investigate them."

---

## 3-Minute Technical Explanation

"The project is called SENTINEL-X. It demonstrates a web application monitoring architecture using Docker Compose with 9 containers.

**Layer 1: The WAF.** Traffic hits NGINX on port 80. ModSecurity is loaded as an NGINX module and operates in blocking mode. I configured the OWASP Core Rule Set v4.30.0 — that's 856 rules covering SQLi, XSS, LFI, RCE patterns, scanner detection and protocol anomalies. At Paranoia Level 1, ModSecurity uses an anomaly scoring system: each matching rule adds to a score, and when the inbound total exceeds 5, the request is blocked with HTTP 403. The web application runs on an internal Docker network — it's not reachable from outside Docker without going through the WAF.

**Layer 2: The SIEM.** Wazuh Manager reads the NGINX access log and the ModSecurity audit log from shared Docker volumes. The logcollector daemon detects new log entries and passes them to analysisd, which applies a 15-rule custom ruleset I wrote. Rules 100020–100023 map to specific OWASP CRS families: SQLi on CRS 942xxx, XSS on 941xxx, LFI on 930xxx, RCE patterns on 932xxx. Each rule assigns a severity level and MITRE ATT&CK technique. Matching events become structured alerts in a JSON file.

**Layer 3: Storage.** Two Filebeat processes read from the same alert file independently. The first, running Filebeat 8.15.3, sends to Elasticsearch 8.15.3 using the ECS 8.0.0 schema. The second, running Filebeat-OSS 7.10.2, sends to Wazuh Indexer using Wazuh's own indexing template. Both maintain separate state files in separate Docker volumes so they don't interfere.

**Layer 4: Analytics.** Kibana 8.15.3 at port 5601 connects to Elasticsearch — that's the standard ELK stack analytics interface. Wazuh Dashboard at port 5602 connects to Wazuh Indexer — that's the official Wazuh UI with pre-built MITRE ATT&CK, compliance and agent dashboards. I also built four custom OpenSearch Dashboards: Executive Overview, Threat Detection, MITRE ATT&CK, and Infrastructure.

The architecture deliberately includes both storage systems. Wazuh Indexer is required because the Wazuh Dashboard only reads from its own OpenSearch-based backend. Elasticsearch is a requirement from the assignment. Both receive the same event stream and serve different interface consumers — this isn't redundancy, it's separation of concerns."

---

## Design Decision Q&A

**Why NGINX?**
NGINX is the industry-standard reverse proxy. It acts as the single ingress point, ensuring all traffic passes through the WAF before reaching the application. It's also the host for the ModSecurity module. The application container has no host port mapping — NGINX is the only way in.

**Why ModSecurity and OWASP CRS?**
ModSecurity is the most widely deployed WAF engine — it runs as a module in NGINX, Apache and IIS, and is the reference implementation for WAF rules. The OWASP Core Rule Set is the community standard ruleset: actively maintained, mapped to OWASP Top 10, and battle-tested in production. CRS v4 introduced the paranoia level system and improved anomaly scoring. This combination — ModSecurity + OWASP CRS — is what most commercial WAFs are built on.

**Why Wazuh?**
Wazuh is an open-source SIEM that includes a log analysis engine, decoder framework, rule engine, and agent-based monitoring. For this project specifically: it natively reads log files from Docker volumes, has a built-in JSON decoder, and allows custom detection rules in an XML format that maps directly to MITRE ATT&CK. It also ships a complete SOC dashboard. Compared to the full Elastic Stack with ECS Watcher, Wazuh requires far less configuration to get a working detection pipeline.

**Why does Wazuh use Wazuh Indexer?**
The Wazuh Dashboard is the official Wazuh SOC UI. It was built on OpenSearch Dashboards and has a Wazuh plugin that requires the Wazuh Indexer (OpenSearch-based) as its backend. It cannot connect to commercial Elasticsearch. So deploying the full Wazuh stack means you deploy the Wazuh Indexer alongside it — this is not optional.

**Why is Elasticsearch also present?**
The assignment explicitly requires Elasticsearch for Storage & Analytics. Beyond that requirement, Elasticsearch offers advantages over Wazuh Indexer for general analytics: standard ECS field mapping, compatibility with standard Kibana dashboards, and the full Elastic Stack ecosystem including Machine Learning. So both systems coexist: Wazuh Indexer for the native Wazuh UI, Elasticsearch for general analytics.

**Why does Filebeat forward alerts to Elasticsearch?**
Filebeat is the standard log shipping agent for the Elastic Stack. It reads Wazuh's `alerts.json` file — which is a plain JSON-lines log file — and forwards each event to Elasticsearch as a structured document, adding ECS-compatible metadata like `@timestamp`, `agent.*`, and `ecs.version`. This is the standard integration pattern for Wazuh + Elasticsearch.

**Why is Logstash unnecessary here?**
Logstash would add pipeline transformation between Filebeat and Elasticsearch. In this architecture, Wazuh already does the log parsing and enrichment — by the time an event reaches `alerts.json`, it already has rule IDs, MITRE ATT&CK mappings, severity levels, and decoded fields. There's no transformation needed that Filebeat processors can't handle. Adding Logstash would add a 500MB container, an extra network hop, and configuration complexity with no benefit.

**What is the difference between OpenSearch and Elasticsearch?**
OpenSearch is the AWS-maintained fork of Elasticsearch, created after Elastic changed the license from Apache 2.0 to SSPL in 2021. As of Elasticsearch 7.10 (the last Apache-licensed version), OpenSearch and Elasticsearch share the same query API. After that point they diverged in features, security model, and ML capabilities. Wazuh Indexer is OpenSearch-based because Wazuh adopted the open-source fork. Kibana dashboards designed for Elasticsearch generally work on OpenSearch with minor adjustments, and vice versa.

**How does a SQL injection request get detected and blocked?**
1. Client sends `GET /search?q=1+OR+1=1--` to port 80
2. NGINX receives the request and passes it to ModSecurity
3. ModSecurity runs the request through OWASP CRS rules
4. CRS rule 942100 uses libinjection to analyze the `q` parameter — libinjection fingerprints `1 OR 1=1--` as a SQL injection pattern
5. Rule 942100 adds 5 points to the anomaly score; together with rule 920350 (IP address in Host header, +3 points), total = 8
6. Rule 949110 fires: total score 8 ≥ threshold 5 → request is interrupted
7. NGINX returns HTTP 403 Forbidden to the client
8. ModSecurity writes a JSON audit record to `/var/log/modsecurity/audit/modsec_audit.log`
9. NGINX writes a JSON access log entry with `status: 403` to `/var/log/nginx/access_json.log`
10. Wazuh logcollector detects new content in the ModSec audit log
11. The JSON decoder processes the event; custom rule 100020 matches on `"ruleId":"942`
12. Wazuh generates a level-12 alert with MITRE T1190 and writes it to `alerts.json`
13. Both Filebeat pipelines pick up the alert within 5 seconds
14. Alert appears in both Elasticsearch and Wazuh Indexer within ~60 seconds of the request

**How can a SOC analyst investigate the alert?**
In Wazuh Dashboard (port 5602): navigate to Threat Detection & WAF dashboard, find the event in the Blocked Requests table, click to expand the alert, see client IP, URI, matched CRS rules, timestamp.

In Kibana Discover (port 5601): select `wazuh-alerts-*` data view, filter `rule.id: 100020`, expand the event document to see all fields including the full request and ModSec message chain.

For retrospective analysis: query `data.transaction.client_ip` to see all requests from the same source IP. Query by time range to identify scan activity. Pivot to `rule.groups: blocked` to see all blocked events.

**What would need to change before production deployment?**
1. **Credentials:** Rotate all passwords — Elasticsearch `elastic`, Kibana `kibana_system`, Wazuh Indexer `admin`. Never use `changeme_elastic_lab` or `SecretPassword` in production.
2. **TLS:** Enable HTTPS on Elasticsearch (`xpack.security.http.ssl.enabled: true`). Add valid TLS on NGINX (currently HTTP only). Remove self-signed certs and use trusted CA.
3. **Port binding:** Change ES/Indexer ports from `0.0.0.0:9200` to `127.0.0.1:9200` or remove host exposure entirely.
4. **Restart policies:** Change `filebeat` and `filebeat-wazuh` to `restart: always` or add healthchecks.
5. **Private key permissions:** Enforce 600 on key files (not possible on Windows NTFS; native Linux deployment resolves this).
6. **Resource limits:** Adjust JVM heap settings based on actual alert volume.
7. **Log retention:** Add Elasticsearch ILM policies for alert retention (e.g., keep 90 days).
8. **Network exposure:** Restrict Kibana and Wazuh Dashboard to VPN or internal network only.
9. **Secret management:** Replace `.env` file with Docker secrets or a secrets manager (HashiCorp Vault, AWS Secrets Manager).
10. **Flask app:** Replace the development Flask server with a production WSGI server (Gunicorn). Current setup is intentionally a test application.

---

## 20 Interview Questions and Answers

**1. What is the purpose of this project?**
To build a local security monitoring stack that demonstrates the full threat detection pipeline: WAF blocking, SIEM detection, alert forwarding, and analytics visualization.

**2. What does NGINX do in this architecture?**
NGINX is the reverse proxy and WAF host. It receives all external HTTP traffic, runs the ModSecurity WAF module on each request, and proxies legitimate requests to the Flask application on the internal Docker network.

**3. What is ModSecurity?**
ModSecurity is an open-source web application firewall engine that runs as a module in web servers (NGINX, Apache). It evaluates HTTP requests against a ruleset and can block, allow, or log requests. In this project it runs in blocking mode with the OWASP Core Rule Set.

**4. What is the OWASP Core Rule Set?**
The OWASP CRS is a community-maintained set of ModSecurity rules covering the OWASP Top 10 and other web attack categories. Version 4 uses an anomaly scoring model: each matching rule adds points, and the request is blocked when the total score exceeds a configurable threshold.

**5. How does anomaly scoring work?**
Each CRS rule assigns a severity-based score when it matches. The scores accumulate per-request. If the total inbound score exceeds the threshold (5 in this project), the final evaluation rule (949110) blocks the request. This reduces false positives compared to blocking on any single rule match.

**6. What is Wazuh?**
Wazuh is an open-source security platform that combines a SIEM engine, intrusion detection, log analysis, compliance monitoring, and vulnerability detection. It uses a manager-agent model but can also run as an agentless log analyzer, which is how it's used here.

**7. How does Wazuh receive the logs in this project?**
Wazuh Manager mounts the same Docker volumes that NGINX and ModSecurity write to. The `logcollector` daemon monitors both log file paths and feeds new events to `analysisd` for rule matching.

**8. What is a Wazuh decoder?**
A decoder defines how Wazuh extracts fields from a log line. The JSON decoder handles both NGINX access logs and ModSecurity audit logs (both are JSON format). Custom decoders use regex to extract specific fields like source IP from the ModSec JSON structure.

**9. How do Wazuh detection rules work?**
Rules are XML files that define matching conditions. When a decoded event matches a rule's conditions (via `<match>`, `<field>`, `<if_sid>`), Wazuh fires the rule. Each rule has an ID, severity level (0–15), description, and optional MITRE ATT&CK mappings. Rules can be hierarchical: a child rule requires the parent to have already fired.

**10. What is Filebeat?**
Filebeat is a lightweight log shipping agent. It monitors log files, reads new lines, optionally processes them, and forwards them to a destination (Elasticsearch, Logstash, or other outputs). In this project, two Filebeat instances both read `alerts.json` and ship to different backends.

**11. Why are there two Filebeat instances?**
One (`sentinel_filebeat`, v8.15.3) sends to Elasticsearch for Kibana analytics. The other (`sentinel_filebeat_wazuh`, v7.10.2 OSS) uses Wazuh's official Filebeat module to send to Wazuh Indexer in the format expected by the Wazuh Dashboard. Both read the same source file independently.

**12. What is the difference between Wazuh Indexer and Elasticsearch?**
Wazuh Indexer is based on OpenSearch, the Apache-licensed fork of Elasticsearch. The query API is compatible, but the security model, feature set, and future roadmap differ. Wazuh ships its own Indexer because the Wazuh Dashboard plugin requires it. Elasticsearch (commercial version, still open-core) cannot be used as a Wazuh Dashboard backend.

**13. Why is Logstash not used here?**
Wazuh already performs log parsing and enrichment. By the time events reach `alerts.json`, they have rule IDs, MITRE mappings, severity levels, and decoded fields. Filebeat processors handle the minor transformations needed (timestamp normalization). There is no transformation requirement that justifies Logstash's overhead.

**14. How does TLS work in this stack?**
Wazuh Indexer, Wazuh Manager, and Wazuh Dashboard communicate over TLS using self-signed certificates in `infrastructure/wazuh-stack/certs/`. Wazuh Manager's internal Filebeat uses mutual TLS with client certificates. Elasticsearch does not use TLS in this lab (HTTP only) — documented as a known limitation, acceptable for localhost-only operation.

**15. What would you change about this architecture for production?**
Rotate all credentials, enable TLS on Elasticsearch, restrict port exposure, change Filebeat restart policies to `always`, replace Docker bind mounts of keys with Docker secrets, add Elasticsearch ILM policies for log retention, and deploy on Linux to enforce proper file permissions.

**16. What is the MITRE ATT&CK framework and how is it used here?**
MITRE ATT&CK is a knowledge base of adversary tactics and techniques. Each Wazuh custom rule is mapped to one or more ATT&CK technique IDs. For example, rule 100020 (SQLi) maps to T1190 (Exploit Public-Facing Application). The MITRE ATT&CK dashboard visualizes which tactics have been seen across all alerts, giving a threat posture overview.

**17. How would you investigate a security alert in this system?**
In Wazuh Dashboard: navigate to the SOC dashboard, find the alert in the Threat Detection view, expand the event to see client IP, URI, matched rules, and timestamp. In Kibana: use Discover with `rule.id: 100020` or filter by time range and source IP to find related events.

**18. What is the alert flow from HTTP request to Kibana?**
HTTP request → NGINX → ModSecurity → HTTP 403 response + audit log entry → Wazuh logcollector → analysisd → custom rule fires → alerts.json → Filebeat (8.15.3) → Elasticsearch → Kibana Discover. Total latency: typically under 60 seconds.

**19. How does Docker Compose networking isolate the web application?**
The webapp container is only on `application_net`, which is defined with `internal: true` in Docker Compose. Internal networks have no default gateway — containers cannot initiate connections to the host network or the internet. The webapp is reachable only by NGINX-WAF, which is on both `frontend_net` and `application_net`.

**20. What limitations does this project have as a production system?**
(1) Lab credentials throughout. (2) HTTP-only Elasticsearch. (3) Self-signed TLS certs. (4) No log retention policies (data grows indefinitely). (5) No high availability — all services are single instances. (6) Flask development server. (7) No agent-based monitoring of the host OS. (8) filebeat/filebeat-wazuh containers have no healthchecks and may exit silently. (9) Private keys are world-readable on Windows NTFS. (10) No secrets management — credentials in .env file.
