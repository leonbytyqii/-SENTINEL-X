# SENTINEL-X — Interview Preparation & Learning Programme

**Last Updated:** 2026-11-12 (Phase 3)  
**Language:** Albanian explanations with English cybersecurity terminology

---

## Si të përdorësh këtë dokument

Çdo mësim ka:
- Shpjegim në shqip
- Termat teknikë në anglisht (siç do t'i gjesh në intervistë)
- Pyetje praktike nga SENTINEL-X

Mësimi 10 është **Interview Simulation** — lexo vetëm pyetjet, përgjigjiu vetë, pastaj kontrollo.

---

# MËSIMI 1 — Docker dhe Docker Compose

## Çfarë është Docker?

**Docker** është një platformë që mundëson ekzekutimin e aplikacioneve brenda **container**-ave.
Një container është si një "kutie" e izoluar — ka sistemin e vet të skedarëve, variablat e mjedisit
dhe proceset e veta, por ndan **kernel**-in me host-in.

Dallimi nga **virtual machine (VM)**:
- VM emulon hardware të plotë, ka OS të plotë brenda — është i rëndë (~GB RAM, minuta boot)
- Container ndan kernel-in e host-it — është i lehtë (~MB, sekonda boot)

## Termat kyç

| Term | Shpjegim |
|------|----------|
| **Image** | Skema statike e container-it (read-only). P.sh. `wazuh/wazuh-manager:4.9.2` |
| **Container** | Instance i drejtuar i një image. Mundet shumë container nga një image |
| **Dockerfile** | Instruksionet për ndërtimin e një image |
| **Docker Compose** | Mjet për menaxhimin e shumë container-ave si një stack |
| **Volume** | Ruajtje e qëndrueshme e dhënave jashtë container-it |
| **Network** | Rrjet virtual mes container-ave |
| **Registry** | Depo e image-ve (Docker Hub, ghcr.io) |
| **Port binding** | Lidhja e portit të container-it me portin e host-it (p.sh. `80:80`) |
| **Environment variable** | Variabla konfigurimi të kaluar te container-i (skedari `.env`) |
| **Health check** | Komandë që Docker ekzekuton periodikisht për të verifikuar shëndetin e container-it |

## Docker Compose në SENTINEL-X

SENTINEL-X ka **6 container** të menaxhuar nga Docker Compose:

```yaml
services:
  nginx-waf:      # WAF + Reverse Proxy
  webapp:         # Flask test application
  wazuh-manager:  # SIEM
  filebeat:       # Log shipper
  elasticsearch:  # Search/storage
  kibana:         # Dashboards
```

Komandat bazë:
```powershell
docker compose up -d          # Nis të gjitha container-at
docker compose down           # Ndalon (ruan volum-et)
docker ps                     # Listo container-at aktiv
docker logs sentinel_wazuh_manager --tail 20   # Shiko log-et
docker exec -it sentinel_nginx_waf sh          # Hyr brenda container-it
docker stats --no-stream      # Shiko burimet (CPU, RAM, rrjet)
```

**KURRË mos ekzekuto:** `docker compose down -v` — fshin të gjitha volum-et dhe të dhënat!

## Pyetje praktike

1. Si e kontrollon nëse të gjitha container-at janë `healthy`?
2. Çfarë ndryshimi ka mes `docker stop` dhe `docker rm`?
3. Si e ruan të dhënat kur rinison container-in?

---

# MËSIMI 2 — Docker Networking

## Konceptet bazë

**Docker network** është një rrjet virtual i izoluar ku container-at mund të komunikojnë.
Çdo container mund të jetë në **shumë network** njëkohësisht.

Llojet:
- **bridge**: default — container-at në të njëjtin host komunikojnë
- **internal**: nuk ka rrugë jashtë host-it (izolim i plotë)
- **host**: container-i ndan interface-in e rrjetit me host-in

## Rrjetet e SENTINEL-X

```
                    HOST (Windows)
                         │
                   management_net (172.20.4.0/24) — NON-internal
                   ┌─────┴──────┐
              Elasticsearch   Kibana
                   │               │
              ─────────────────────────────────
              monitoring_net (172.20.3.0/24) — internal
              ┌────────────────────────────────┐
         Elasticsearch  Kibana  Filebeat  Wazuh
         ─────────────────────────────────────
              logging_net (172.20.2.0/24) — internal
              ┌────────────────────────────────┐
              Wazuh      Filebeat
              ─────────────────────────────────
              application_net (172.20.1.0/24) — internal
              ┌────────────────────────────────┐
              nginx-waf     webapp
```

## Pse `internal: true`?

Kur një network ka `internal: true`, container-at në të nuk mund të dalin në internet
dhe host-i nuk mund t'i aksesojë direkt ato porta. Kjo parandalon:
- **lateral movement** — nëse sulmues komprometon webapp-in, nuk mund të dalë nga rrjeti
- **data exfiltration** — ES nuk mund të dërgojë të dhëna jashtë nëse komprometohet

**Problem i gjetur:** Docker Desktop në Windows nuk publikon porta kur container-i është vetëm
në rrjete `internal`. Zgjidhja: u shtua `management_net` (non-internal) te ES dhe Kibana.

## DNS në Docker

Docker ofron **automatic DNS resolution** — çdo container mund të arrihet me emrin e shërbimit.
P.sh. Filebeat i dërgon alert-et te `http://elasticsearch:9200` — nuk duhet IP adresë.

## Pyetje praktike

1. Pse `webapp` nuk ka port të publikuar te host?
2. Si komunikon Filebeat me Elasticsearch?
3. Çfarë do të ndodhte nëse heqim `management_net` nga Kibana?

---

# MËSIMI 3 — WAF: ModSecurity dhe OWASP CRS

## Çfarë është WAF?

**Web Application Firewall (WAF)** është një mekanizëm mbrojtjeje që inspekton
kërkesat HTTP dhe bllokon sulmet para se të arrijnë te aplikacioni.

SENTINEL-X përdor:
- **ModSecurity v3** — WAF engine (libmodsecurity3)
- **ModSecurity-nginx connector v1.0.4** — integrim me NGINX
- **OWASP CRS v4.30.0** — rregullat (51 skedarë, 856 rregulla)

## Anomaly Scoring — Mënyra si funksionon OWASP CRS

CRS nuk bllokon menjëherë kur aktivizon një rregull. Çdo rregull i shtoni
**pikë anomalie (anomaly score)** kërkesës. Kur totali kalon **pragun (threshold)**,
rregulla `949110` aktivizohet dhe NGINX kthen **HTTP 403**.

```
Kërkesë: GET /search?q=1' OR '1'='1--
  → CRS 942160 (SQL Injection) aktivizohet → score += 5
  → Total = 5, prag = 5
  → 949110 aktivizohet → HTTP 403 BLOCKED
```

```
Kërkesë: GET /api/users
  → Asnjë rregull nuk aktivizohet → score = 0
  → HTTP 200 ALLOWED
```

## Familjet kryesore të rregullave CRS

| ID Range | Kategoria | Shembull |
|----------|----------|---------|
| 913xxx | Scanner Detection | `User-Agent: sqlmap` |
| 920xxx | Protocol Enforcement | Content-Type i gabuar |
| 930xxx | LFI / Path Traversal | `../../etc/passwd` |
| 932xxx | Remote Code Execution | `; ls -la` |
| 941xxx | XSS | `<script>alert(1)</script>` |
| 942xxx | SQL Injection | `1' OR '1'='1` |
| 949110 | Anomaly Block | (fires when score ≥ threshold) |

## Paranoia Level

**Paranoia Level (PL)** kontrollon sa agresiv është CRS:
- **PL1 (default)**: pak false positives, të gjitha sulmet bazë blloken
- **PL2**: rregulla shtesë — disa forma legjitime mund të bllokohen
- **PL3-4**: shumë strikt — vetëm për mjedise të larta sigurie

SENTINEL-X përdor **PL1** — balancë mes sigurisë dhe disponueshmërisë.

## ModSecurity Audit Log — JSON format

Çdo kërkesë e bllokuar shkruan një rresht JSON te `/var/log/modsecurity/audit/modsec_audit.log`:

```json
{
  "transaction": {
    "client_ip": "172.20.0.1",
    "request": { "method": "GET", "uri": "/search?q=1'..." },
    "response": { "http_code": 403 },
    "messages": [
      { "ruleId": "942160", "message": "SQL Injection" },
      { "ruleId": "949110", "message": "Anomaly Score Exceeded (5)" }
    ]
  }
}
```

Ky log lexohet nga Wazuh për të gjeneruar alert-et.

## Pyetje praktike

1. Çfarë do të ndodhte nëse vendosim anomaly threshold në 10?
2. Pse payload `../../etc/passwd` aktivizon rregullat **RCE** (932xxx) jo vetëm **LFI** (930xxx)?
3. Si e verifikon që `SecRuleEngine` është `On` dhe jo `DetectionOnly`?

---

# MËSIMI 4 — Wazuh SIEM

## Çfarë është SIEM?

**Security Information and Event Management (SIEM)** mbledh log-et nga shumë burime,
i analizon ato me rregulla, dhe gjeneron **alert**-e kur zbulon aktivitet të dyshimtë.

Wazuh është një **open-source SIEM** me:
- **Manager**: analizon event-et, aplikon rregullat
- **Agent**: instalohet te sistemi i monitoruar — dërgon event-e te manager
- **Decoder**: parsojnë formatin e log-eve
- **Rules**: kushtet për të gjeneruar alert

## Arkitektura e Wazuh në SENTINEL-X

SENTINEL-X përdor **log file monitoring** (jo agent) sepse ModSecurity dhe NGINX
janë brenda container-ave Alpine ku agentët nuk instaloheshin lehtë.

```
modsec_audit.log ──► logcollector ──► JSON decoder ──► rules ──► alerts.json
nginx access_json.log ──► logcollector ──► JSON decoder ──► rules ──► alerts.json
```

## Decoders — Si parsojnë log-et

**Decoder** lexon rreshtin e log-ut dhe nxjerr fushat (fields). Ka dy lloje:
- **Built-in decoders**: vijnë me Wazuh (JSON plugin decoder, syslog, Windows Event Log)
- **Custom decoders**: shkruhen nga ne — skedarë XML në `etc/decoders/`

**Problem kyç:** Për event-et `log_format:json`, JSON plugin decoder parsojnë të dhënat
dhe i ruajnë në `data.*` fields. Por kushtet `<field name="data.X">` në rregulla
**NUK funksionojnë**. Vetëm `<match>` kundër tekstit raw JSON funksionon.

## Rules — Si gjenerohen alert-et

**Rules** janë kushte XML që verifikojnë nëse një event përputhet me një sulm:

```xml
<rule id="100020" level="12">
  <if_sid>100011</if_sid>
  <match>"ruleId":"942</match>
  <description>SQL Injection detected and blocked</description>
  <group>modsecurity,waf,blocked,sql_injection,</group>
</rule>
```

Elementet kryesore:
- `id`: numri unik i rregullës (100001-199999 për custom)
- `level`: ashpërsia (0-15; ≥7 gjeneron alert, ≥12 = shumë kritike)
- `if_sid`: aktivizohet vetëm nëse rregulla prind ka aktivizuar
- `match`: string që duhet të gjendet në log-un raw
- `group`: etiketat për filtrim në Kibana

## Deepest Child Rule Wins

**Rregulla kryesore e Wazuh:** Kur aktivizohet një zinxhir rregullash, **rregulla më e thellë** (deepest child) del në alert, jo prindi.

```
100011 (lvl8) → parent: ModSec block
  └─ 100020 (lvl12) → child: SQL Injection  ← KJO del në alert
```

Kjo ishte **arsyeja kryesore e problemit** me rregullën 100040: ishte fëmijë i 100020/100021/100022,
kështu që dukej në çdo alert sesa rregullat specifike të sulmit. Zgjidhja: fshirja e rregullës 100040.

## `rule_dir` nuk skanon nën-direktori

`<rule_dir>etc/rules</rule_dir>` ngarkon vetëm skedarët `.xml` nga ajo direktori DIREKT —
nuk skanon nën-direktoritë rekursivisht. Skedari `etc/rules/sentinel-x/sentinel_x_rules.xml`
ishte injoruar silentisht! Zgjidhja:

```xml
<rule_dir>etc/rules</rule_dir>
<rule_dir>etc/rules/sentinel-x</rule_dir>  <!-- REQUIRED -->
```

## Rregullat e SENTINEL-X (100001-100030)

| Rule ID | Level | Përshkrim |
|---------|-------|-----------|
| 100001 | 0 | Base: NGINX access log (silent) |
| 100003 | 6 | NGINX 403 — WAF block konfirmuar |
| 100007 | 8 | Security scanner: sqlmap/nikto/dirbuster |
| 100010 | 0 | Base: ModSec audit event (silent) |
| 100011 | 8 | ModSec BLOCKED request |
| 100012 | 10 | CRS anomaly threshold exceeded (949110) |
| 100020 | 12 | **SQL Injection** (CRS 942xxx) |
| 100021 | 11 | **XSS** (CRS 941xxx) |
| 100022 | 11 | **LFI** (CRS 930xxx) |
| 100023 | 14 | **CRITICAL: RCE** (CRS 932xxx) |
| 100030 | 13 | Persistent attack: 5+ blocks/120s |

## Pyetje praktike

1. Pse `../../etc/passwd` gjeneron rregullën 100023 (RCE) jo 100022 (LFI)?
2. Si e verifikon se rregullat custom janë ngarkuar?
3. Çfarë do të thotë `level 0` në kontekstin e Wazuh?

---

# MËSIMI 5 — Filebeat (Log Shipping)

## Çfarë është Filebeat?

**Filebeat** është një **log shipper** i lehtë nga Elastic Stack.
Lexon skedarë log-esh dhe i dërgon te Elasticsearch, Logstash ose output tjetër.

## Si funksionon Filebeat

```
1. Filebeat hap skedarin (alerts.json)
2. Lexon rreshtat e rinj (follow mode)
3. Ruan pozicionin e fundit të lexuar në registry
4. Dërgon batch-et te Elasticsearch
5. Rinis nga pozicioni i ruajtur nëse restartojnë
```

**Registry** parandalon dërgimin e dyfisht të event-eve — edhe nëse Filebeat ristarton,
vazhdon nga aty ku la.

## Konfigurimi i Filebeat në SENTINEL-X

```yaml
filebeat.inputs:
  - type: log
    paths:
      - /var/ossec/logs/alerts/alerts.json
    json.keys_under_root: true       # Fushat JSON në root të dokumentit
    json.add_error_key: true
    
output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  username: "elastic"
  index: "wazuh-alerts-%{+yyyy.MM.dd}"

setup.ilm.enabled: false             # Data stream manual, jo ILM auto
setup.template.enabled: false        # Template manual
```

## Verifikimi i Filebeat

```powershell
# Shiko nëse Filebeat dërgon event-e
docker logs sentinel_filebeat --tail 20 2>&1

# Kërko "Events published"
# Kërko "output.elasticsearch"
# Nëse sheh "connection established" — OK
# Nëse sheh "connection refused" — ES nuk është gati
```

## Pyetje praktike

1. Çfarë ndodh nëse Filebeat ristarton gjatë dërgimit të alert-eve?
2. Si e shohim indexin ku Filebeat dërgon të dhënat?
3. Pse ka dy Filebeat në SENTINEL-X (internal Wazuh + external)?

---

# MËSIMI 6 — Elasticsearch

## Çfarë është Elasticsearch?

**Elasticsearch** është një **search and analytics engine** i bazuar në Apache Lucene.
Ruan dokumente JSON, i indekson automatikisht, dhe lejon **full-text search** dhe analitikë
në kohë reale.

Konceptet kryesore:
- **Index**: koleksion dokumentesh të tipit të njëjtë
- **Data stream**: seri indeksesh të lidhura kronologjikisht (p.sh. log-et)
- **Document**: një record JSON (p.sh. një Wazuh alert)
- **Shard**: ndarje e indeksit (shpejtësi + replikacion)
- **Mapping**: skema e fushave — tipi i secilës fushë (keyword, text, date, integer)
- **Cluster**: grup node-sh ES (SENTINEL-X ka 1 node — single-node)

## Data Stream në SENTINEL-X

Filebeat dërgon alert-et te data stream `wazuh-alerts-2026.11.12`.
Backing index: `.ds-wazuh-alerts-2026.11.12-2026.11.12-000001`

```
Data stream: wazuh-alerts-*
  ├── wazuh-alerts-2026.11.12 (sot)
  ├── wazuh-alerts-2026.11.11 (dje)
  └── ...
```

## Queries REST API

```powershell
# Numer total i dokumenteve
curl -s -u elastic:changeme_elastic_lab "http://localhost:9200/wazuh-alerts-*/_count"

# Kërko SQL Injection alerts
curl -s -u elastic:changeme_elastic_lab "http://localhost:9200/wazuh-alerts-*/_search" `
  -H "Content-Type: application/json" `
  -d '{"query":{"term":{"rule.id":"100020"}}}'

# Statusi i cluster-it
curl -s -u elastic:changeme_elastic_lab "http://localhost:9200/_cluster/health"
```

## Problemi i RAM (99.66% memory)

ES është konfiguruar me `mem_limit: 2g` dhe JVM heap `1g`.
Gjatë auditit u zbulua se ES po përdorte **1.993 GiB** — 99.66% e limitit.

Risk: **OOM kill** — sistemi operativ mund të vrasë procesin kur rritet memoria.

Zgjidhja: Ndrysho `mem_limit: 4g` dhe `ES_JAVA_OPTS: "-Xms2g -Xmx2g"` në `docker-compose.yml`.

## Pyetje praktike

1. Si e verifikojmë nëse cluster-i ES është `GREEN`, `YELLOW` apo `RED`?
2. Çfarë do të thotë `GREEN` vs `YELLOW` vs `RED`?
3. Pse RAM e lartë e ES është rrezik operacional?

---

# MËSIMI 7 — Kibana

## Çfarë është Kibana?

**Kibana** është interfaceja vizuale e Elastic Stack. Lejon:
- **Discover**: kërko dhe eksploro dokumente raw
- **Dashboards**: pamje të kombinuara vizualizimesh
- **Lens**: ndërtues vizualizimesh drag-and-drop
- **Alerts**: rregulla alarmesh bazuar në të dhëna ES
- **Maps**: vizualizim gjeografik

## Data View (Index Pattern)

Kibana nuk akseson ES direkt — ka nevojë për një **Data View** (index pattern) që tregon
cilën indeks/data stream të lexojë.

SENTINEL-X: `wazuh-alerts-*` (ID: `1c0ea900-67d7-4919-b6a2-5972824a42a8`)
Time field: `@timestamp`

## KQL — Kibana Query Language

**KQL (Kibana Query Language)** është gjuha e kërkimit në Kibana:

```kql
# Kërko sipas vlerës exacte
rule.id: "100020"

# Kërko sipas grup-it
rule.groups: "sentinel-x"

# Kërko sipas nivelit (≥ 10)
rule.level >= 10

# Kombino
rule.groups: "sentinel-x" AND rule.level >= 12

# Sulmet e fundit 5 minuta
rule.groups: "waf" AND @timestamp >= "now-5m"
```

## Dashboards e SENTINEL-X

| Dashboard | URL | Çfarë tregon |
|-----------|-----|--------------|
| SOC Overview | `/app/dashboards#/view/sx-dashboard-overview` | Totalet, timeline, shpërndarja e sulmeve |
| Threat Detection | `/app/dashboards#/view/sx-dashboard-threats` | SQLi/XSS/RCE count, stacked chart |
| Alert Investigation | `/app/dashboards#/view/sx-dashboard-investigation` | Tabelë detajesh, filtrim sipas rregullës |

Hyr me: `elastic` / `changeme_elastic_lab` te `http://localhost:5601`

## Pyetje praktike

1. Si filtron vetëm alert-et e SENTINEL-X (jo ato të brendshme të Wazuh si SCA)?
2. Si e ndryshon time range-in për të parë alert-et e 1 orës së fundit?
3. Çfarë sheh nëse klikon mbi një alert në Discover?

---

# MËSIMI 8 — SOC Investigation Workflow

## Çfarë bën një SOC Analyst?

**Security Operations Center (SOC)** analyst monitoron alert-et e sigurisë, i triage-on
(klasifikon sipas prioritetit) dhe i investigon ato, duke vendosur:
- **True Positive**: sulm real
- **False Positive**: alarm i rremë
- **True Negative**: aktivitet normal, nuk u alarmua (saktë)
- **False Negative**: sulm real, nuk u alarmua (rrezik!)

## Workflow-i i Investigimit (5 hapa)

### Hapi 1: Zbulimi (Detection)
Kibana SOC Overview tregon një spike në alert-et e nivelit të lartë.
KQL: `rule.level >= 12 AND @timestamp >= "now-15m"`

### Hapi 2: Triage
Prioritizo bazuar në level:
- Level 14 (RCE): **KRITIKE** — vepro menjëherë
- Level 12-13 (SQLi/Persistent): **LARTË** — investigo brenda 15 min
- Level 11 (XSS/LFI): **MESATAR** — investigo brenda 1 ore
- Level 6-10: **I ULËT** — rishiko gjatë shift-it

### Hapi 3: Investigimi
Klikimi mbi alert-in në Discover tregon:
- `rule.id`: cila rregullë aktivizoi
- `rule.description`: çfarë sulmi u zbulua
- `data.transaction.client_ip`: IP e sulmuesit
- `data.transaction.request.uri`: URL e synuar
- `data.transaction.messages`: rregullat CRS që aktivizuan
- `@timestamp`: koha exacte

### Hapi 4: Korrelimi
A ka sulme të tjera nga e njëjta IP?
```kql
data.transaction.client_ip: "192.168.1.100" AND @timestamp >= "now-1h"
```

A ka rule 100030 (Persistent Attack) aktivizuar? — 5+ bllokim nga e njëjta IP.

### Hapi 5: Reagimi
- Nëse rule 100030 aktivizoi → shto IP-në në blocklist
- Nëse është false positive → dokuemento dhe shto exclusion në CRS
- Nëse është sulm real → eskaloje tek Incident Response

## Pyetje praktike

1. Si dallon True Positive nga False Positive?
2. Çfarë bën kur sheh shumë alert 100003 (NGINX 403) por asnjë 100020/100021/100023?
3. Pse rule 100030 (Persistent Attack) ka level 13?

---

# MËSIMI 9 — Incident Response

## Fazat e Incident Response (NIST SP 800-61)

**1. Preparation (Përgatitja)**
- SENTINEL-X i siguron çdo gjë: WAF, SIEM, dashboard
- Politikat, procedurat, mjetet janë gati

**2. Detection & Analysis (Zbulimi dhe Analiza)**
- Wazuh gjeneron alert-in
- SOC analyst investigon (Mësimi 8)
- Konfirmohet si True Positive

**3. Containment (Izolimi)**
- **Afatshkurtër**: blloko IP-në e sulmuesit (rregulli i nginx-it ose firewall)
- **Afatgjatë**: patch-o aplikacionin nëse ka vulnerability

**4. Eradication (Heqja)**
- Hiq causat: vuln-at e pashpallta, konfigurimin e gabuar
- Verifikimi se sulmi nuk ka lënë backdoor

**5. Recovery (Rimëkëmbja)**
- Rinis shërbimin e kompromisuar
- Monitorimi i intensifikuar pas incidentit

**6. Post-Incident Activity (Raportimi)**
- Shkruaj **Incident Report**: çfarë ndodhi, impakti, si u korrigjua
- Lessons Learned: çfarë mësojmë, çfarë ndryshojmë

## Evidence Collection (Mbledhja e Provave)

Gjatë investigimit, dokumento:
- **Timestamp**: koha exacte e sulmit
- **Source IP**: IP e sulmuesit
- **Attack payload**: payload-i i saktë
- **CRS Rule IDs**: cilat rregulla aktivizuan
- **HTTP status code**: 403 = u bllokua, 200 = kaloi
- **Wazuh rule ID dhe level**: klasifikimi

SENTINEL-X ka `docs/EVIDENCE_REGISTER.md` si regjistër zyrtar.

## Pyetje praktike

1. Cilat fazat e NIST janë mbuluar nga SENTINEL-X automatikisht?
2. Si do ta documentoje një SQL Injection incident me SENTINEL-X?
3. Çfarë do të bëje nëse sulmuesi ndërroi IP?

---

# MËSIMI 10 — INTERVIEW SIMULATION

## Si të përdosh këtë mësim

**Procedura:**
1. Lexo pyetjen
2. **Përgjigju vetë me zë** (ose shkruaj) para se të lexosh materialet e mëparshme
3. Pastaj kontrollo përgjigjen me mësimet 1-9 dhe dokumentacionin e SENTINEL-X
4. Nëse nuk dije — shëno dhe rishiko atë mësim

**Gjatë intervistës:** Fol me siguri. Nëse diçka nuk shkon plotësisht, thuaj:
*"Gjatë zhvillimit hasëm këtë problem — ja çfarë mësuam dhe si e zgjidhëm."*
Ky nivel ndershmërie tregon maturitet.

---

## Blloku A — Pyetje Teknike SENTINEL-X

**A1.** Përshkruaj arkitekturën e SENTINEL-X në 60 sekonda.

**A2.** Çfarë bën ModSecurity kur zbulon një SQL Injection? Hap pas hapi.

**A3.** Pse payload `/?file=../../etc/passwd` gjeneron rregullën 100023 (RCE) dhe jo 100022 (LFI)?

**A4.** Çfarë do të thotë `rule_dir` dhe si ndryshon nga `rule_file` në Wazuh?

**A5.** Shpjego pse rregulla 100040 u fshi. Çfarë bënte dhe pse ishte problem?

**A6.** Si e konfirmojmë se një alert nga Wazuh është ruajtur saktë në Elasticsearch?

**A7.** Çfarë është `anomaly scoring` dhe pse OWASP CRS e përdor sesa bllokimin direkt?

**A8.** Si verifikojmë që 6690 rregulla janë ngarkuar (dhe jo 6676 pa custom)?

**A9.** Çfarë ndodh nëse Elasticsearch ka 99%+ RAM? Çfarë bëjmë?

**A10.** Kibana Data View ka `time field: @timestamp`. Pse është i rëndësishëm ky field?

---

## Blloku B — Pyetje SOC/Blueteam

**B1.** Erdhi një alert level 14. Cilat janë hapat e parë?

**B2.** Sheh 50 alert 100003 (NGINX 403) nga e njëjta IP brenda 2 minutave. Çfarë nënkupton kjo?

**B3.** WAF bllokoi kërkesën por rule 100020 nuk doli — doli 100012 (anomaly threshold). Pse?

**B4.** Dallimi mes True Positive dhe False Positive. Si i dallon?

**B5.** Çfarë janë fazat NIST të Incident Response? Cilat mbulojmë me SENTINEL-X?

---

## Blloku C — Pyetje Konfigurimi/Debug

**C1.** Wazuh po shfaqet `unhealthy` në `docker ps`. Cilat janë hapat e parë të debug?

**C2.** Po dërgojmë sulme SQLi por nuk shohim asnjë alert në Kibana. Debug hap pas hapi.

**C3.** Si testohet një rregullë e re Wazuh pa dërguar traffic real?

**C4.** Çfarë bën komanda: `docker exec sentinel_wazuh_manager /var/ossec/bin/wazuh-control restart`?

**C5.** Cilat skedarë konfiguracioni KURRË nuk duhen fshirë ose modifikuar pa backup?

---

## Blloku D — Pyetje Hardening/Security

**D1.** Cilat janë 3 problemet kryesore të sigurisë të SENTINEL-X si laborator?

**D2.** Pse Elasticsearch dhe Kibana janë në `management_net` (non-internal)? A është kjo siguri e mirë?

**D3.** Çfarë është `no-new-privileges: true` dhe pse e shtojmë te container-at?

**D4.** Çfarë nënkupton `read_only: true` te container-i webapp?

**D5.** Nëse do ta deplojonim SENTINEL-X në prodhim, cilat janë 5 ndryshimet e para të detyrueshme?

---

## Modeli i përgjigjes (si të strukturosh)

Gjatë intervistës, përgjigjet teknike duhet të kenë strukturën **STAR** ose **PPT**:

**PPT (Problem → Process → Takeaway):**
```
"Problemi ishte [X]. Ne bëmë [Y hapa]. 
Mësuam/Arritëm [Z]."
```

**Shembull i mirë:**
> "Gjatë auditit zbuluam se rregullat custom nuk po aktivizoheshin — zero alert. Debuguam
> duke shikuar numrin e rregullave të ngarkuara: 6676 sesa 6690 të pritshme. Mësuam se
> `rule_dir` nuk skanon nën-direktoritë rekursivisht. Zgjidhja ishte shtimi explicit i
> `<rule_dir>etc/rules/sentinel-x</rule_dir>` në ossec.conf."

---

## Termat kyç anglisht — fjalor i shpejtë

| Anglisht | Shqip |
|---------|-------|
| Web Application Firewall (WAF) | Mur zjarri i aplikacionit web |
| Security Information and Event Management (SIEM) | Menaxhim informacionesh dhe eventesh sigurie |
| Intrusion Detection System (IDS) | Sistem zbulimi ndërhyrjesh |
| Anomaly scoring | Vlerësim anomalie |
| False positive | Alarm i rremë pozitiv |
| False negative | Alarm i rremë negativ |
| Log shipper | Dërgues log-esh |
| Data stream | Rrjedhë e dhënave |
| Incident response | Reagim ndaj incidenteve |
| Lateral movement | Lëvizje anësore (brenda rrjetit) |
| Payload | Ngarkesa sulmuese |
| Anomaly threshold | Prag anomalie |
| Alert triage | Klasifikim alertash |
| True positive | Alarm i vërtetë pozitiv |
| Containment | Izolim/kufizim |
| Eradication | Heqje/eliminim |
| Hardening | Forcim sigurie |
| Attack surface | Sipërfaqe sulmi |
| Privilege escalation | Rritje privilegjesh |
| Defense in depth | Mbrojtje e shtresëzuar |
