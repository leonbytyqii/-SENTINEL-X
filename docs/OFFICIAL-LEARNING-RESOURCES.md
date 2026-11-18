# SENTINEL-X — Official Learning Resources

Curated links organized by topic. Prioritizes official documentation over third-party guides.

---

## Docker

| Resource | URL | Use |
|---|---|---|
| Docker Get Started | https://docs.docker.com/get-started/ | First introduction to containers |
| Docker Compose reference | https://docs.docker.com/compose/reference/ | All compose commands |
| docker-compose.yml syntax | https://docs.docker.com/compose/compose-file/ | Full file format reference |
| Docker networking | https://docs.docker.com/network/ | Networks, internal flag, DNS |
| Docker volumes | https://docs.docker.com/storage/volumes/ | Named volumes, bind mounts |
| Dockerfile reference | https://docs.docker.com/engine/reference/builder/ | Writing Dockerfiles |
| Docker healthcheck | https://docs.docker.com/engine/reference/builder/#healthcheck | Healthcheck syntax |

---

## NGINX

| Resource | URL | Use |
|---|---|---|
| Beginner's Guide | https://nginx.org/en/docs/beginners_guide.html | First read |
| ngx_http_core_module | https://nginx.org/en/docs/http/ngx_http_core_module.html | All directives |
| Reverse proxy | https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/ | proxy_pass, headers |
| Access logging | https://nginx.org/en/docs/http/ngx_http_log_module.html | log_format, access_log |
| Security headers | https://www.nginx.com/resources/wiki/start/topics/examples/server_blocks/ | add_header examples |

---

## ModSecurity

| Resource | URL | Use |
|---|---|---|
| ModSecurity Reference Manual v3 | https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v3.x) | Complete reference |
| SecRule syntax | https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v3.x)#SecRule | Rule writing |
| Audit log format | https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v3.x)#SecAuditLog | Log configuration |
| NGINX connector | https://github.com/SpiderLabs/ModSecurity-nginx | NGINX module documentation |

---

## OWASP CRS

| Resource | URL | Use |
|---|---|---|
| CRS Documentation | https://coreruleset.org/docs/ | Main docs hub |
| Anomaly Scoring | https://coreruleset.org/docs/concepts/anomaly_scoring/ | How scoring works |
| Paranoia Levels | https://coreruleset.org/docs/paranoia_levels/ | PL 1–4 explained |
| CRS Setup Guide | https://coreruleset.org/docs/deployment/install/ | Installation and config |
| False Positive Handling | https://coreruleset.org/docs/concepts/false_positives_tuning/ | Writing exclusions |
| Rule Tags Reference | https://coreruleset.org/docs/rules/metadata/ | CRS rule metadata |
| CRS GitHub | https://github.com/coreruleset/coreruleset | Source rules, issues |

---

## Wazuh

| Resource | URL | Use |
|---|---|---|
| Wazuh Documentation Home | https://documentation.wazuh.com/current/ | Main docs |
| Architecture Overview | https://documentation.wazuh.com/current/getting-started/architecture.html | How Wazuh works |
| Ruleset XML Syntax | https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/rules.html | Rule writing |
| Decoder Syntax | https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/decoders.html | Decoder writing |
| Custom Rules Guide | https://documentation.wazuh.com/current/user-manual/ruleset/custom.html | Adding custom rules |
| Log Collection | https://documentation.wazuh.com/current/user-manual/capabilities/log-data-collection/index.html | logcollector config |
| Alert Fields Reference | https://documentation.wazuh.com/current/user-manual/reference/ossec-conf/ | ossec.conf reference |
| MITRE ATT&CK | https://documentation.wazuh.com/current/user-manual/ruleset/mitre.html | MITRE mapping |
| Wazuh Training | https://wazuh.com/training/ | Official certification |
| Wazuh Blog | https://wazuh.com/blog/ | Use cases and tutorials |

---

## Elasticsearch

| Resource | URL | Use |
|---|---|---|
| Elasticsearch Guide | https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html | Complete reference |
| Getting Started | https://www.elastic.co/guide/en/elasticsearch/reference/current/getting-started.html | First introduction |
| REST API | https://www.elastic.co/guide/en/elasticsearch/reference/current/rest-apis.html | All REST endpoints |
| Query DSL | https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html | Writing queries |
| Aggregations | https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations.html | count/group/sum |
| Data Streams | https://www.elastic.co/guide/en/elasticsearch/reference/current/data-streams.html | Time-series indices |
| ILM | https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html | Retention policies |
| ECS Reference | https://www.elastic.co/guide/en/ecs/current/index.html | Field naming standard |

---

## Kibana

| Resource | URL | Use |
|---|---|---|
| Kibana Guide | https://www.elastic.co/guide/en/kibana/current/index.html | Complete reference |
| Discover | https://www.elastic.co/guide/en/kibana/current/discover.html | Searching events |
| KQL Syntax | https://www.elastic.co/guide/en/kibana/current/kuery-query.html | Kibana Query Language |
| Dashboard | https://www.elastic.co/guide/en/kibana/current/dashboard.html | Building dashboards |
| Lens | https://www.elastic.co/guide/en/kibana/current/lens.html | Visual chart builder |
| Data Views | https://www.elastic.co/guide/en/kibana/current/data-views.html | Index patterns |

---

## Filebeat

| Resource | URL | Use |
|---|---|---|
| Filebeat Guide | https://www.elastic.co/guide/en/beats/filebeat/current/index.html | Complete reference |
| Configuration Options | https://www.elastic.co/guide/en/beats/filebeat/current/configuring-howto-filebeat.html | filebeat.yml |
| Log Input | https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-input-log.html | Reading log files |
| Elasticsearch Output | https://www.elastic.co/guide/en/beats/filebeat/current/elasticsearch-output.html | ES configuration |
| Troubleshooting | https://www.elastic.co/guide/en/beats/filebeat/current/faq.html | Common issues |

---

## OpenSearch (Wazuh Indexer base)

| Resource | URL | Use |
|---|---|---|
| OpenSearch Documentation | https://opensearch.org/docs/latest/ | Complete reference |
| REST API | https://opensearch.org/docs/latest/api-reference/ | Queries and management |
| Security Plugin | https://opensearch.org/docs/latest/security/index/ | TLS and authentication |
| Dashboards | https://opensearch.org/docs/latest/dashboards/ | Wazuh Dashboard base |

---

## MITRE ATT&CK

| Resource | URL | Use |
|---|---|---|
| ATT&CK Enterprise | https://attack.mitre.org/ | Full technique catalog |
| T1190 — Exploit Public-Facing App | https://attack.mitre.org/techniques/T1190/ | Your main detection |
| T1595 — Active Scanning | https://attack.mitre.org/techniques/T1595/ | Scanner detection |
| T1059 — Command Interpreter | https://attack.mitre.org/techniques/T1059/ | RCE detection |
| T1083 — File Discovery | https://attack.mitre.org/techniques/T1083/ | LFI detection |
| Navigator | https://mitre-attack.github.io/attack-navigator/ | Visualize coverage |

---

## Web Security Training

| Resource | URL | Type | Cost |
|---|---|---|---|
| PortSwigger Web Security Academy | https://portswigger.net/web-security | Interactive labs | Free |
| OWASP Top 10 | https://owasp.org/Top10/ | Reference | Free |
| OWASP WebGoat | https://owasp.org/www-project-webgoat/ | Vulnerable app | Free |
| HackTheBox | https://www.hackthebox.com/ | CTF platform | Freemium |
| TryHackMe | https://tryhackme.com/ | Guided learning | Freemium |
| Blue Team Labs Online | https://blueteamlabs.online/ | Blue team focus | Freemium |

---

## Security Standards and Frameworks

| Resource | URL | Purpose |
|---|---|---|
| NIST SP 800-61 | https://csrc.nist.gov/publications/detail/sp/800-61/rev-2/final | Incident response guide |
| CIS Controls | https://www.cisecurity.org/controls | Security control framework |
| NIST Cybersecurity Framework | https://www.nist.gov/cyberframework | Risk management |
| CVE Database | https://cve.mitre.org/ | Vulnerability identifiers |
| NVD (NIST) | https://nvd.nist.gov/ | CVE details and scoring |

---

## Specific to Your SENTINEL-X Components

These resources are referenced directly in SENTINEL-X configuration:

| File | Documentation |
|---|---|
| `sentinel_x_rules.xml` | https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/rules.html |
| `modsecurity-override.conf` | https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-(v3.x) |
| `crs-setup-override.conf` | https://coreruleset.org/docs/ |
| `filebeat.yml` | https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-input-log.html |
| `elasticsearch.yml` | https://www.elastic.co/guide/en/elasticsearch/reference/current/settings.html |
| `kibana.yml` | https://www.elastic.co/guide/en/kibana/current/settings.html |
| `ossec.conf` | https://documentation.wazuh.com/current/user-manual/reference/ossec-conf/ |
