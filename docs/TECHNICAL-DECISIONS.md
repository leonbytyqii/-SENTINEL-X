# SENTINEL-X – Technical Decisions

## TD-01: Wazuh Manager reads logs directly (no separate Agent container)

**Decision:** Configure Wazuh Manager with `<localfile>` blocks pointing to shared Docker volumes, rather than deploying a separate Wazuh Agent container.

**Alternatives considered:**
- `wazuh/wazuh-agent` Docker container: requires agent–manager TLS enrollment, generates certificate management overhead, and the official container is primarily designed for host-level monitoring (kernel, syscall), not file-based log collection.
- Filebeat only (no Wazuh): loses the SIEM correlation layer entirely.

**Rationale:**
In containerised environments, Wazuh's own documentation recommends mounting log directories directly when the manager and log sources share a Docker host. The agent–manager architecture becomes essential when monitoring separate machines or cloud workloads; for a single-host lab it adds complexity with no benefit.

**Risk:** None in a single-host lab. The agent–manager architecture is documented and can be re-introduced for multi-host deployments.

---

## TD-02: Elasticsearch security enabled, TLS disabled

**Decision:** `xpack.security.enabled: true` (username/password auth) but `xpack.security.http.ssl.enabled: false`.

**Alternatives considered:**
- Full TLS: requires certificate generation, Kibana trust store configuration, Filebeat TLS config — significant operational overhead for a lab with no external exposure.
- Security disabled entirely: provides no authentication at all.

**Rationale:**
The Elasticsearch API is bound to `127.0.0.1` only (not `0.0.0.0`). No external network can reach it. Username/password authentication is maintained so credentials are still exercised. TLS is omitted to reduce first-run friction.

**Risk:** Credentials are transmitted in plaintext on `localhost`. Acceptable for a local lab. Enable TLS before exposing any port to a network.

---

## TD-03: ModSecurity starts in DetectionOnly mode

**Decision:** `MODSEC_RULE_ENGINE=DetectionOnly` as the default.

**Rationale:**
CRS at Paranoia Level 1 still generates false positives against some normal traffic patterns. Starting in DetectionOnly allows the operator to verify which rules fire on legitimate traffic before enabling blocking. This is standard CRS deployment practice.

**How to enable blocking:**
```
# .env
MODSEC_RULE_ENGINE=On
```
Then: `docker compose up -d nginx-waf`

---

## TD-04: Filebeat without Wazuh Filebeat module

**Decision:** Configure Filebeat directly to read `alerts.json` with JSON decoding, rather than installing the official Wazuh Filebeat module.

**Alternatives considered:**
- Wazuh Filebeat module: official, provides pre-built Kibana dashboards. Requires downloading the Wazuh Filebeat tar.gz and running setup commands inside the Filebeat container, which complicates the Docker image.

**Rationale:**
Direct JSON ingestion produces the same field structure in Elasticsearch. Custom index templates and Kibana index patterns provide equivalent functionality. This avoids a custom Filebeat Dockerfile and reduces build time and complexity.

**Trade-off:** Pre-built Wazuh Kibana dashboards are not automatically available. Custom dashboards must be created or imported manually.

---

## TD-05: OWASP ModSecurity CRS official Docker image

**Decision:** Use `owasp/modsecurity-crs:nginx-alpine` as the WAF image base.

**Rationale:**
- Maintained by the OWASP CRS project
- Bundles ModSecurity v3 (libmodsecurity) + nginx + CRS in a tested combination
- Configuration via environment variables reduces boilerplate
- Alpine-based for minimal attack surface

**Version note:** The `nginx-alpine` tag tracks the latest stable CRS release. For reproducible production deployments, pin to a digest: `owasp/modsecurity-crs@sha256:<digest>`.

---

## TD-06: Elasticsearch 8.x Elastic License

**Decision:** Use Elasticsearch 8.15.3 (Elastic License 2.0).

**Alternatives considered:**
- OpenSearch 2.x (Apache 2.0): open source, Wazuh Indexer is based on it, but the directive explicitly requires Elasticsearch.

**Rationale:**
Elastic License 2.0 permits free use for internal development, testing, and monitoring own infrastructure. This lab deployment qualifies. OpenSearch remains a viable alternative for production deployments requiring strict open-source licensing.

---

## TD-07: Network isolation approach

**Decision:** Four dedicated Docker bridge networks with `internal: true` for non-ingress nets.

| Network | Contains | External access |
|---------|----------|----------------|
| `frontend_net` | nginx-waf | Yes (port 80) |
| `application_net` | nginx-waf, webapp | No |
| `monitoring_net` | wazuh-manager | No |
| `analytics_net` | wazuh-manager, filebeat, elasticsearch, kibana | Localhost only (127.0.0.1 binding) |

**Rationale:** Prevents lateral movement between security zones. The webapp cannot directly reach Elasticsearch. The WAF cannot directly reach the Wazuh manager.
