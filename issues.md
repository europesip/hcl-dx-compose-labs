# Known issues found while building the labs

Issues found while preparing this PoC with HCL DX Compose CF238 (`hcl-dx-deployment` 2.49.0,
`hcl-dx-iq` 1.0.2, `hcl-dx-search` 2.36.0), what happens and how the labs deal with them.
**Re-checked on CF239** (`hcl-dx-deployment` 2.50.0, `hcl-dx-iq` 1.0.3, `hcl-dx-search` 2.37.0)
with a clean installation of all the labs on 2026-11-04: each issue says whether it is still present.
**CF239 documentation checked on 2026-11-07** (published after the re-check; full review in the next section): none of the issues below
appears as fixed. The only related change is that cross-session memory (RAG) is now documented and can
be enabled, see CS1479139.

## CF239 documentation review: where the labs deviate and why (2026-11-07)

The labs follow the HCL documentation as closely as possible. This section lists every place where they
do something different, because following the page as written fails or is not possible, with the test
that shows it. Checked against the CF239 pages as published on 2026-11-07, with the charts of CF239
(`hcl-dx-deployment` 2.50.0, `hcl-dx-iq` 1.0.3, `hcl-dx-search` 2.37.0) and `litellm-helm` 1.106.5.
The LiteLLM page was followed literally (Quick start) in a separate namespace with a Bedrock API key.

### "Deploying LiteLLM" (IQ > Installation, page dated 2026-10-14)

| # | The documentation says | What happens (tested) | What the labs do |
|---|---|---|---|
| L1 | `helm repo add litellm https://ghcr.io/berriai/litellm-helm`, then install `litellm/litellm` | `helm repo add` fails: *"not a valid chart repository … index.yaml: 404 Not Found"* (ghcr.io is an OCI registry, not a classic Helm repository). The install then fails: *"repo litellm not found"* | `helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm --version 1.106.5` (no repository needed; version pinned) |
| L2 | Sonnet 4.6 model ID `bedrock/us.anthropic.claude-sonnet-4-6-20250514-v1:0` | With the values of the page as they are: *"BedrockException - The provided model identifier is invalid"* (20250514 is the date of Claude Sonnet 4). Haiku 4.5 works | `us.anthropic.claude-sonnet-4-6` (no date) |
| L3 | No `aws_region_name` in the models | The `us.` inference profiles only exist in US regions: called from `eu-west-1` they give *"The provided model identifier is invalid"*. Without a region, LiteLLM uses its own default region, which is not under your control | `aws_region_name` set in each model (`us-east-1` as the page implies, or the `eu.` profiles with `eu-west-1` to keep the data in the EU) |
| L4 | Image `ghcr.io/berriai/litellm:main-latest` (Quick start); `ghcr.io/berriai/litellm-database:1.45.0` (Production) | `main-latest` exists but is a floating tag (it changes with every LiteLLM build, so two installations are never the same). `litellm-database:1.45.0` **does not exist** (HTTP 404 in ghcr.io; the tag is `main-v1.45.0`, a 2024 release), so the Production values cannot pull the image | Image pinned to `1.106.5`, the `appVersion` of the chart version used |
| L5 | Check the pods with `kubectl get pods -l app=litellm` and `kubectl wait … -l app=litellm` | The chart labels the pods `app.kubernetes.io/name=litellm`: *"No resources found"* and *"error: no matching resources found"*, although LiteLLM is running | `kubectl rollout status deployment/litellm` (or `-l app.kubernetes.io/name=litellm`) |
| L6 | Production example: probes with `enabled:` and `httpGet:` | Those keys do not exist in the chart (it uses `livenessProbe.path`, etc.): they are ignored. It works by chance, because the chart defaults have the same paths | Chart default probes (no change needed) |
| L7 | "By default, LiteLLM requests 100m CPU and 512Mi Memory" | The chart (1.106.5) sets no resources by default, and the Quick start values set none either | Requests and limits set explicitly (the values of the Production example: 100m/512Mi, 1 CPU/2Gi) |
| L8 | Create `litellm-masterkey` **and** a `litellm-env` with the same `PROXY_MASTER_KEY` ("to reduce the number of secrets, combine… into a single litellm-env secret"), but the values point `masterkeySecretName` to `litellm-masterkey` | Works only while both secrets hold the same key; if they diverge, the one from `masterkeySecretName` wins | A single `litellm-env` secret, also used as `masterkeySecretName`, as the text recommends |
| L9 | Production example: an Ingress with host `litellm.dxns.svc.cluster.local` | An Ingress host is an external name; IQ reaches LiteLLM through its Service, never through that Ingress | No Ingress (IQ uses `http://litellm.<namespace>.svc.cluster.local:4000`) |
| L10 | Nothing about prompt caching | Every IQ call pays full price for a ~32,500-token prefix (CS1479178) | `cache_control_injection_points` on the system message |
| L11 | LiteLLM in the DX namespace | Works | LiteLLM in `dx-shared`, with the other third-party tools (only HCL software in `dx-demo`); the URL in the IQ values changes accordingly. A design choice, not an error |
| L12 | Bedrock prerequisites: only "valid credentials" | Also needed, and not mentioned: the Anthropic use case form (once per account), an AWS Marketplace subscription to the model with a valid payment method, and, on the first call, a principal allowed to `aws-marketplace:Subscribe`/`ViewSubscriptions` (an IAM user limited to `bedrock:InvokeModel`, as a Bedrock API key normally is, gets *"Model access is denied…"*) | Documented in the installer; the lab uses OpenRouter or Claude directly |

### "Deploying IQ services", "Preparing LiteLLM access" and "IQ environment variables"

| # | The documentation says | What happens (tested) | What the labs do |
|---|---|---|---|
| I1 | The LiteLLM URL in `configuration.litellm.liteLlmUrl` | Not enough. Re-tested today: with exactly that (removing only `LITELLM_BASE_URL`), IQ answers *"The LLM service is temporarily unavailable"* (`LLM_ERROR_SERVICE_UNAVAILABLE`) and LiteLLM receives no request; with it back, IQ answers again. **Not a namespace issue** (tested 2026-11-08): with a second LiteLLM in the DX namespace and `liteLlmUrl` pointing to it (`http://litellm.dx-demo.svc.cluster.local:4000` or `http://litellm:4000`), IQ still fails and neither LiteLLM receives a request; adding `LITELLM_BASE_URL` makes the same LiteLLM answer | `LITELLM_BASE_URL` (undocumented) in `environment.pod.integrator`, same URL |
| I2 | "Deploying IQ services" sets `LITELLM_API_KEY` and `LITELLM_URL` in `environment.pod.integrator` | Contradicts the other two pages (key in the `iq-litellm-api-secret` secret, URL in `liteLlmUrl`). Rendering the chart with the values of the page: both variables appear **twice** in the Integrator, and the chart's own definitions (secret and ConfigMap) come last and win | Secret `iq-litellm-api-secret` + `liteLlmUrl`, as in "Preparing LiteLLM access" and "IQ environment variables" |
| I3 | `LITELLM_URL`: "A valid HTTPS URL" | The LiteLLM page gives `http://litellm.<ns>.svc.cluster.local:4000` as the endpoint, and HTTP works inside the cluster | `http://…:4000` (in-cluster Service) |
| I4 | `MCP_SERVER_LIST` must be set, because the default points to `dx-ai-mcp-server`; a wrong value causes CrashLoopBackOff. The example uses `https://`, the warning `http://` | Chart 1.0.3 already writes the right URL in its ConfigMap (`<release>-mcp-server:3000`, `https` or `http` from `mcpServer.httpsEnabled`), and that is the list the Integrator uses; the environment variable is ignored (CS1479102) | `MCP_SERVER_LIST` not set |
| I5 | Example values with `mcpServer.httpsEnabled: true` and `tlsCertSecret: dx-tls-cert` | **Works** (tested today: the Integrator connects to `https://dx-iq-mcp-server:3000` and IQ uses the MCP tools) | **Aligned (2026-11-08)**: `httpsEnabled: true` and `tlsCertSecret: dx-tls-cert`, as documented. Checked with the custom MCP Server of Lab 3B (HTTP) in the same list: the Integrator loads the tools of both |
| I6 | Chart from a URL (`https://<repository>/<chart>.tgz`, Artifactory) | DX Compose customers get it from HCL Harbor | `helm pull oci://hclcr.io/dx/hcl-dx-iq --version 1.0.3` |
| — | (observation, not a deviation) | The Integrator logs that `NODE_TLS_REJECT_UNAUTHORIZED=0` is set (it comes from the image, not from the chart): certificate verification is disabled for all its outgoing TLS connections | Nothing (product behaviour); worth raising with HCL |

### Search V2 ("Installing the Search V2 backend", page dated 2026-08-27, unchanged)

| # | The documentation says | What happens (checked in chart 2.37.0) | What the labs do |
|---|---|---|---|
| S1 | Nothing about enabling the File Processor (only its image and the allowed file types); "Validating the setup" lists a `dx-search-file-processor` pod | `applications.fileProcessor: false` by default, but the Search Middleware ConfigMap always sets `fileprocessor_host: <release>-file-processor` (no condition), so the middleware keeps looking for it ("Could not connect to file processor" every 3 seconds) | `applications.fileProcessor: true` |
| S2 | Nothing about `configuration.automatedSetup.haproxyProtocol` | Empty by default: the chart then picks `https` only if the DX HAProxy Service is `LoadBalancer`, `http` otherwise. With DX behind an Ingress or a Route (`ClusterIP`, SSL still on) it uses `http`, and the HAProxy Service only exposes 443 (checked in the lab: `ClusterIP haproxy:443`), so the crawlers index 0 documents | `haproxyProtocol: https` |

### DX Compose (installation, LDAP, external database)

| # | The documentation says | What happens | What the labs do |
|---|---|---|---|
| D1 | Supported external databases: Derby, DB2, Oracle ("Limitations") | PostgreSQL is not supported yet for the Web Engine (HCL is validating it) | Lab 3 / stage 3 is presented as a learning exercise with the early-release table script from HCL, and `standard_conforming_strings = off` (see "HCL is aware" below) |
| D2 | The LDAP page explains `ldap.type: other` | The chart deploys its own OpenLDAP by default (`applications.openLdap: true`) | `openLdap: false`; an external OpenLDAP is used |
| D3 | `helm install` without `--wait` (Helm 3 style) | With Helm 4, `--wait` aborts the installation while DAM waits for its database | `--wait=legacy` with Helm 4 |
| D4 | Sample file `values-samples/webEngine/webEngine-sample.yaml` | The folder in chart 2.50.0 is `value-samples/` | Not used (minor typo) |

### SSL to the external database, LDAPS and LDAP sign-in (tested 2026-11-10)

Tested on a fresh installation (`hcl-dx-deployment` 2.50.0) with PostgreSQL 18 (CloudNativePG) that only accepts SSL
(`hostnossl all all all reject`) and an OpenLDAP that requires TLS, each server certificate signed by its own corporate
root CA, both CAs uploaded with `configuration.webEngine.customTruststoreSecrets`. Reported to HCL by e-mail (no case yet).

| # | What we tried | What happens (tested) | What the labs do |
|---|---|---|---|
| S1 | `DbUrl` with two parameters: `?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory` | Works at runtime, but the **database transfer fails** on the first domain: `SAXParseException: Element type "database" must be followed by either attribute specifications, ">" or "/>"` in `templates/db/postgresql/release/dbt_release.xml`. The URL is written into that XML file without escaping `&`, so no second parameter can be used (client certificate, timeouts, `ApplicationName`...) | One parameter only: `?sslmode=verify-full` |
| S2 | `DbUrl` with `?sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory` | The Web Engine never starts (CrashLoopBackOff): the tools that run before Liberty (`initStatusTable.sh`, `getLibertyStatus.sh`) use the default JDK truststore, not the CAs of `customTruststoreSecrets`: `PKIX path building failed`, then `Error extracting DB_TRANSFER_DONE status` | Not used |
| S3 | `DbUrl` with `?sslrootcert=<CA mounted from the truststore secret>` | Works (transfer of 465 tables, TLS 1.3) but the certificate is **not validated**: with the wrong CA it still connects (the driver stays on `sslmode=prefer`) | Not used |
| S4 | `DbUrl` with `?sslmode=verify-full` | **Works and validates**: transfer, pre-start tools and runtime over TLS 1.3. Without the database CA in `customTruststoreSecrets`: `PKIX path building failed`; with the service IP instead of the certificate host name: `The hostname … could not be verified by hostnameverifier PgjdbcHostnameVerifier` | The form used by the labs and the webinar |
| S5 | A database transfer that failed, then a corrected `helm upgrade` | The Web Engine pod never becomes ready and the StatefulSet does not replace it (`currentRevision ≠ updateRevision`) | Delete the pod by hand after fixing the values |
| S6 | IQ (`hcl-dx-iq` 1.0.3) with `configuration.database.dbTlsEnabled: true` | The value reaches the ConfigMap (`dx.config.integrator.db_tls_enabled: "true"`) but the Integrator still connects without SSL, and a server that requires SSL rejects it (`no encryption`) | `pg_hba` exception for the IQ database only (`host iqdb dx_iq_db_user all scram-sha-256`) |
| S7 | Sign in with the e-mail (`andres@europesip.com`) | The native LDAP block hard-codes `userFilter="(&(uid=%v)(objectclass=inetOrgPerson))"` (`_web-engine-ldap-config.tpl`) and no value changes it | `configOverrideFiles` extending `ldapRegistry id="ldap"` with `<loginProperty name="uid"/>` and `<loginProperty name="mail"/>` (the element form: the text form gives `CWWKG0075E`), plus a Web Engine restart |
| S8 | LDAPS (`port: 636`, `sslEnabled: true`) without the directory CA | `CWPKI0823E SSL HANDSHAKE FAILURE` / `PKIX path building failed`: nobody can sign in | The directory CA in `customTruststoreSecrets` |
| S9 | *Configuring LDAP* (configuration changes using overrides) | The AD SSL sample uses `sslRef="customSSLConfig"`, never defined on the page (it is generated when `customTruststoreSecrets` is set); e-mail login with `loginProperty` is not documented; both AD samples miss a closing parenthesis: `userFilter="(&(sAMAccountName=%v)(objectcategory=user)"` | Documentation feedback sent to HCL |

## Issues reported to HCL Support

| Case | Opened | Issue | Status |
|---|---|---|---|
| **CS1479102** | 2026-11-02 | IQ: the MCP server list set as documented is ignored | Open, being reproduced by HCL. **Still present in IQ 1.0.3** |
| **CS1479139** | 2026-11-02 | IQ: the system prompt describes an active RAG memory while RAG is disabled | Open. **Partly changed in IQ 1.0.3**: the directive is softer, but still sent with RAG disabled. **RAG now documented in CF239** (tested, see below) |
| **CS1479178** | 2026-11-02 | IQ: requests to the LLM cannot use prompt caching, so every call pays full price for a ~30,000-token prefix | Open. **Still present in IQ 1.0.3** (prefix now ~32,500 tokens) |

### CS1479102 · IQ ignores `MCP_SERVER_LIST`

- **Problem.** The HCL documentation ("Deploying IQ services") says the IQ Integrator reads its MCP
  server list from `MCP_SERVER_LIST`, set in `environment.pod.integrator`. The variable does reach the
  Integrator Deployment, but the chart also generates the ConfigMap `<release>-integrator` with its
  own fixed list (`dx.config.integrator.mcp_server_list` = only the HCL MCP Server), whatever value is
  configured, and that is the list the Integrator uses. So no additional MCP server can be added, and
  even the documented use (pointing to the MCP Server of another release name) does not work.
- **Solution in the labs (workaround).** After installing or upgrading IQ, the ConfigMap key is
  patched with both servers and the Integrator is restarted (`lab3-iq-openrouter/custom-mcp/03-iq-register.sh`;
  `04-iq-install.sh` reapplies it after every upgrade).
- **Side effect with Helm 4.** Helm 4 applies objects with server-side apply: once the key has been
  patched, the next `helm upgrade` of IQ fails with `conflict with "kubectl-patch"`. The labs use
  `--force-conflicts` with Helm 4 (`HELM_FORCE_CONFLICTS` in `common/lib.sh`) and patch the key again.
- **CF239 / IQ 1.0.3: still present.** The chart still generates `mcp_server_list` with only the HCL
  MCP Server, and there is still no value to extend it. New in 1.0.3: an `[MCP Watchdog]` asks the
  servers in the list for their tools again every 10 minutes, so a server that was not ready at
  start-up is picked up without a restart. But the list itself is only read at start-up: in our test,
  removing a server from the ConfigMap had no effect until the Integrator was restarted.

### CS1479139 · RAG directive in the prompt while RAG is disabled

- **Problem.** The Integrator logs `RAG_ENABLED=false` at start-up, but every request it sends to the
  model (seen in the LiteLLM debug log) includes a "PERSISTENT CROSS-SESSION MEMORY DIRECTIVE (pgvector
  RAG)" section stating that a RAG memory is active, that the model must never say it lacks memory, and
  that text labelled "Past conversation note:" or "CRITICAL SYSTEM MEMORY HISTORY" must be treated as
  absolute truth. Risks: answers claiming memories that do not exist, a possible prompt-injection
  vector, ~250 extra tokens per request, and the RAG status logged at `ERROR` level. The case also asks
  for documentation of the RAG feature (configuration, what is stored, retention, isolation between
  users, data sent to the embedding provider).
- **Solution in the labs.** None for now: it does not block IQ, and the section is part of the product
  prompt. Waiting for HCL.
- **CF239 / IQ 1.0.3: partly changed.** The `RAG_ENABLED=false` lines at `ERROR` level are no longer
  logged, and the directive has been rewritten: it no longer says "absolute truth", no longer names
  the "Past conversation note:" / "CRITICAL SYSTEM MEMORY HISTORY" labels or other sessions, and adds
  that users who want their history deleted must ask their administrator. But it is **still sent
  with RAG disabled**, and still states "You have access to injected historical context from prior
  conversations" and that this context is "authoritative". The documentation request is still open.
- **CF239 documentation (2026-11-07): the RAG feature is now documented** ("Configuring cross-session
  memory"): `RAG_ENABLED=true` in `environment.pod.integrator`, PostgreSQL with **pgvector**, two
  LiteLLM embedding aliases (`iq-multilingual-embed` / `iq-embed`), `EMBEDDING_DIMENSIONS` (1024),
  chunking and retrieval settings, retention and per-user deletion with SQL (nothing is deleted
  automatically). That answers most of the documentation request; the directive sent with RAG
  disabled is still not mentioned.
- **Tested on the lab cluster (IQ 1.0.3, 2026-11-07)**, with `baai/bge-m3` through OpenRouter (1024
  dimensions; Cohere v4, the model HCL validates, is not on OpenRouter) and `CREATE EXTENSION vector`
  in `iqdb` (the CNPG `standard` image includes pgvector 0.8.7). Results:
  - It works: a fact told in one conversation was answered in a new one. Another user (`andres`) did
    not get it: memory is per user.
  - RAG starts on the first question, not at start-up (no `[RAG]` lines until then). The defaults it
    logs (`topK=10, minSimilarity=0.35`) are not the ones of the RAG page (5 and 0); the environment
    variables page says 5 and 0.35.
  - **Bug: the memory is lost on every Integrator restart.** At start-up the Integrator creates or
    "synchronises" `rag_chunks` with `embedding` as `text`; on the first question the pgvector backend
    converts it to `vector(1024)` (`[pgvector] embedding column converted from text to vector(1024)`).
    That happens on **every** start, and the stored embeddings do not survive it. Measured: 26 chunks,
    2 with embedding → after a restart, 26 and **0** with embedding (column type `text`) → after one
    question, `vector(1024)` again with only the new chunk. The text of past conversations stays in
    the table, but without embeddings it can never be retrieved. So the memory only works until the
    next `helm upgrade` or pod restart. **Not reported yet**: worth a new case.
  - Each question also calls the embedding model (a few tokens, very cheap).
  - **It breaks prompt caching when memory is retrieved**: the context is injected into the system
    prompt, so the prefix changes. Measured: questions without retrieved memory read ~37,000 tokens
    from the cache; the one that retrieved memory wrote the whole prefix again (`cache_creation_input_tokens=37352`,
    `cache_read_input_tokens=0`), at 1.25× the input price. See CS1479178.

### CS1479178 · IQ requests cannot use prompt caching

- **Problem.** Every request from the Integrator carries the same large fixed prefix: the MCP tool
  definitions and the system prompt. Measured in the LiteLLM debug log (58 tools, CF238): **29,654
  tokens out of 30,046** in a one-sentence question. Claude only caches a prefix when the request
  marks where it ends (`cache_control`), and the Integrator never adds that mark: the request arrives
  at LiteLLM without any `cache_control`. So, sent as IQ produces it, the whole prefix is billed at
  the full input price on every model call. The prompt itself is well built for caching (fixed part
  first, the question at the end, no dates or per-user data in it): only the mark is missing.
- **Cost impact** (Claude Sonnet 4.6, Anthropic list prices: input $3/MTok, cache write $3.75/MTok,
  cache read $0.30/MTok). A question that uses one tool makes 2 model calls, both with the prefix:

  | | Prefix cost per question |
  |---|---|
  | Without caching (as IQ sends it) | 2 × 29,654 tokens × $3 ≈ **$0.18** |
  | With caching, cache already warm | 2 × 29,654 × $0.30 ≈ **$0.018** |
  | With caching, first call after 5 min idle | ≈ $0.11 (write) + $0.009 (read) |

  About 90 % less on the input side. For example, 1,000 questions a day go from about $180 to about
  $20 a day (≈ $4,800 a month saved). The cache lives 5 minutes, so the saving depends on traffic:
  with very sparse use most calls pay the write (+25 %), and with steady use almost all read.
  Bedrock prices and caching rules for Claude are similar, and the HCL reference configuration
  (LiteLLM + Bedrock) should have the same problem unless the gateway adds the mark (not tested).
  Evidence sent with the case (LiteLLM without the workaround): 2 questions from 2 different IQ
  sessions, 4 model calls, identical ~30,000-token prefix, `cache_read_input_tokens=0` on every call.
- **Solution in the labs (workaround).** LiteLLM injects the mark at the end of the system message
  for both models (`cache_control_injection_points: [{location: message, role: system}]` in
  `lab3-iq-openrouter/litellm-values.yaml`). Tools and system prompt go before it, so the whole
  prefix is cached. Verified in the LiteLLM log: first call `cache_creation_input_tokens=29654`,
  second call `cache_read_input_tokens=29654`. The conversation history after the system prompt is
  not cached; that is a small part of each request.
- **Reported as a defect** because of its business impact: the excessive cost of every IQ call. The
  case asks HCL to mark the cacheable prefix in the Integrator requests and, until then, to document
  the gateway configuration.
- **CF239 / IQ 1.0.3: still present.** With the LiteLLM workaround removed, 5 model calls from 2
  questions all returned `cache_read_input_tokens=0` and `cache_creation_input_tokens=0`. The prefix
  has grown to **~32,500 tokens** (60 tools; system prompt of 18,912 characters instead of 14,068).
  With the workaround, the second call read 32,157 tokens from the cache.
- **With RAG enabled (CF239, 2026-11-07)** the workaround only helps when no memory is retrieved: the
  retrieved context goes into the system prompt, before the cache mark, so those calls write the whole
  prefix again (~37,000 tokens with 86 tools). Placing the memory after the fixed prefix (for example
  in a separate message) would keep it cacheable.

## Issues not reported (no case opened)

### HCL is aware: expected in a future release

| Issue | Solution in the labs |
|---|---|
| **The Web Engine on PostgreSQL is not supported in CF238** (DB2, Oracle and SQL Server are). HCL is validating PostgreSQL for the Web Engine (its tests work with PostgreSQL 18). In our tests, the Web Engine (OpenJPA) generates `LIKE … ESCAPE '\'` (DB2/Oracle style), which PostgreSQL rejects with "invalid escape string" with its default settings | Lab 2B is presented as a learning exercise, not as a supported configuration. The PostgreSQL preparation script sets `standard_conforming_strings = off` (and `escape_string_warning = off`) on `dx_core` |

### IQ (hcl-dx-iq 1.0.2; re-checked on 1.0.3)

| Issue | Solution in the labs | Case? |
|---|---|---|
| **`LITELLM_BASE_URL` is undocumented but required.** With only the documented `configuration.litellm.liteLlmUrl`, the Integrator's LLM adapter does not send the requests to our LiteLLM | `LITELLM_BASE_URL` set in `environment.pod.integrator` with the same URL (`custom-iq-values.yaml`). **Still required in 1.0.3**: without it, IQ answers "The LLM service is temporarily unavailable" | Candidate for a case |
| **`LITELLM_URL` and `LITELLM_API_KEY` cannot be overridden** through `environment.pod.integrator`: the chart defines them again | The URL goes in `configuration.litellm.liteLlmUrl` (+ `LITELLM_BASE_URL`); the key in the `iq-litellm-api-secret` secret. **Same in 1.0.3** | To be added as a comment to CS1479102 |
| **MCP tool names contain dots** (`dam.mime-type…`), which the Anthropic and OpenAI APIs reject (`[a-zA-Z0-9_-]` only): with a provider that does not adapt them, the whole request fails with HTTP 400 | LiteLLM uses its `anthropic/` provider against the Anthropic-compatible endpoint of OpenRouter, which sanitises the names. HCL recommends `enableDam: false` with non-Claude models. **Fixed in 1.0.3**: the 55 tools have valid names (`get_collection_from_DAM`...), and the Integrator adds a prefix per server (`tool61b8b48c_...`) | No (improvement request) |
| **The Integrator reads the MCP tools only when it starts.** If it starts before the MCP Server is ready (normal on a fresh install), it has no tools until it is restarted | The install waits for the MCP Server and then restarts the Integrator (`04-iq-install.sh`). **Mitigated in 1.0.3**: a watchdog re-reads the tools every 10 minutes (tested: the tools of a server started later appeared after 10 minutes) | No |
| **OpenRouter is not validated by HCL** (the HCL guides use AWS Bedrock) | Documented in Lab 3: OpenRouter is used through LiteLLM to avoid the AWS Bedrock account set-up | No (by design) |

### Search V2 (hcl-dx-search 2.36.0; both still present in 2.37.0)

| Issue | Solution in the labs | Case? |
|---|---|---|
| **With DX published through an Ingress or a Route, the crawlers use `http` and index 0 documents.** `automatedSetup.haproxyProtocol` is empty by default, and the chart then chooses the protocol from the type of the DX HAProxy Service: `https` if it is `LoadBalancer` (the DX chart default), `http` otherwise. It does not look at `networking.haproxy.ssl`, which is what decides whether HAProxy uses TLS. With the defaults of both charts it works. But publishing DX through an Ingress (Kubernetes) or a Route (OpenShift) means `serviceType: ClusterIP`, normally with SSL still on: Search then calls HAProxy on port 80, where nothing listens, and the crawlers time out. The rule is only in a comment of the Search chart `values.yaml`; the HCL page "Installing the Search V2 backend" does not mention it | `haproxyProtocol: https` in `custom-search-values.yaml`, always set explicitly when HAProxy is `ClusterIP` or `NodePort` with SSL | No (our configuration; at most a documentation suggestion) |
| **The File Processor is an undocumented dependency.** The Search chart disables it by default (`applications.fileProcessor: false`), but always configures the Search Middleware to use it (`fileprocessor_host: <release>-file-processor` in its ConfigMap, with no condition), so the middleware looks for it anyway and logs "Could not connect to file processor" every 3 seconds. The HCL page "Installing the Search V2 backend" (CF238) never says it has to be enabled: it only gives its image and the allowlist of file types, while the expected output in "Validating the setup" lists a `dx-search-file-processor` pod that the default values do not deploy | `applications.fileProcessor: true` | Candidate for a case (documentation, or chart defaults inconsistent with the middleware) |

### Installation with Helm 4

| Issue | Solution in the labs | Case? |
|---|---|---|
| **`--wait` aborts the DX installation.** Helm 4 uses the `watcher` strategy, which fails as soon as a pod fails; DAM fails normally while its PostgreSQL (Persistence Node) starts, so the release ends `failed` although DX would come up | `--wait=legacy` with Helm 4 (`HELM_WAIT` in `common/lib.sh`), which waits up to the timeout like Helm 3 | No (first check whether Helm 4 is officially supported) |

### DX configuration (documentation gotchas)

| Issue | Solution in the labs | Case? |
|---|---|---|
| `security.webEngine.webEngineAdminGroup: <LDAP group>` does not use the LDAP group: it creates a group with that name in the basic registry, and with the federated repository two groups with the same name can make Liberty fail ("multiple entities found") | Administrator rights are given to the LDAP group in the portal (Resource Permissions), or LDAP users are added to `wpsadmins` with an override (Lab 2A, step 4) | No |
| XMLAccess and WebDAV are restricted to the basic-registry administration group (`DX_ADMIN_GROUP`) | Same override as above, if LDAP administrators need those tools | No (by design) |
| The DX chart deploys its own OpenLDAP by default (`applications.openLdap: true`) | `openLdap: false` in the Lab 1 values; an external LDAP is used in Lab 2 | No |

### LiteLLM with AWS Bedrock (CF239 documentation, "Deploying LiteLLM")

Checked on 2026-11-07 with a Bedrock API key (`AWS_BEARER_TOKEN_BEDROCK`), as the documentation recommends.

| Issue | What works | Case? |
|---|---|---|
| The model ID given for Sonnet 4.6, `us.anthropic.claude-sonnet-4-6-20250514-v1:0`, does not exist: Bedrock answers "The provided model identifier is invalid" (20250514 is the date of Claude Sonnet 4) | `us.anthropic.claude-sonnet-4-6` (no date). The Haiku 4.5 ID of the documentation, `us.anthropic.claude-haiku-4-5-20251001-v1:0`, is correct | Not yet |
| The example sets no region (`aws_region_name`), and the `us.` inference profiles only work from US regions | `aws_region_name: us-east-1` in each model (or the `eu.` profiles with `eu-west-1`, which keep the data in the EU) | Not yet |
| Anthropic models need the "use case details" form once per AWS account (not mentioned): until it is submitted, Bedrock answers "Model use case details have not been submitted for this account" | Submit it once in the Bedrock console or with `aws bedrock put-use-case-for-model-access` | No (AWS requirement) |

### Third-party components (not HCL)

| Issue | Solution in the labs |
|---|---|
| OpenLDAP (`openldap-stack-ha`): a custom LDIF without the root entry makes the first `ldapadd` fail and the LDAP starts empty | `demo-users.ldif` includes `dn: dc=dxdemo,dc=com` |
| k3s `local-path` does not support ReadWriteMany (DAM needs it) | Lab 0: static StorageClass with a `hostPath` volume |
| `hostPath` volumes ignore the pod `fsGroup`: DAM (uid 1000/gid 1001) cannot write (`EACCES`) | Lab 0: `01-storage.sh` sets the directory owner to `1000:1001` |
| OpenAI reasoning models (gpt-5.x) inject `reasoning_effort` and break the IQ tools | Documented in `litellm-values.yaml`: use Claude |
