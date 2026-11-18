# SENTINEL-X Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

---

## [1.0.0] – 2026-11-12

### Added
- Initial SENTINEL-X release.
- `docker-compose.yml` with six services: nginx-waf, webapp, wazuh-manager, filebeat, elasticsearch, kibana.
- Four isolated Docker bridge networks (frontend, application, monitoring, analytics).
- 15 named persistent volumes.
- NGINX + OWASP ModSecurity CRS v4 configuration with JSON structured access logging.
- ModSecurity audit log in JSON format for clean decoder parsing.
- Custom NGINX security headers (X-Content-Type-Options, X-Frame-Options, CSP, Referrer-Policy).
- Python Flask test application (intentional WAF-trigger endpoints, no real vulnerabilities).
- Wazuh Manager 4.9.2 with direct log volume monitoring (`ossec.conf` localfile blocks).
- Custom Wazuh decoders for NGINX JSON access logs and ModSecurity JSON audit logs.
- 11 custom Wazuh detection rules (rule IDs 100001–100040) covering:
  - SQL injection, XSS, LFI, path traversal, RCE detection
  - WAF block events, anomaly threshold exceeded
  - Brute-force and persistent attack correlation
  - MITRE ATT&CK technique mappings
- Filebeat 8.15.3 configured to ship Wazuh alerts to Elasticsearch.
- Elasticsearch 8.15.3 with custom index template and ILM policy.
- Kibana 8.15.3 with security analyst configuration.
- 8 PowerShell operational scripts (setup, start, stop, health-check, validate, init-elasticsearch, backup, cleanup).
- 10-test automated security validation suite (`validate.ps1`).
- Complete technical documentation (README, DATA-FLOW, TECHNICAL-DECISIONS, DEPLOYMENT-GUIDE, INCIDENT-RESPONSE).
- `.env.example` credential template.
- `.gitignore` excluding credentials and large log files.

### Architecture decisions
- TD-01: Wazuh Manager reads logs directly (no separate Agent container) — see `docs/TECHNICAL-DECISIONS.md`
- TD-02: Elasticsearch security enabled, TLS disabled for lab
- TD-03: ModSecurity DetectionOnly mode by default
- TD-04: Filebeat without Wazuh Filebeat module (direct JSON ingestion)
- TD-05: OWASP ModSecurity CRS official Docker image
- TD-06: Elasticsearch 8.x Elastic License 2.0
- TD-07: Four-network segmentation model
