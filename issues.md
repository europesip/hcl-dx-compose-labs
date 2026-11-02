# Known issues found while building the labs

**English** · [Español](issues.es.md)

Issues found while preparing this PoC with HCL DX Compose CF238 (`hcl-dx-deployment` 2.49.0,
`hcl-dx-iq` 1.0.2, `hcl-dx-search` 2.36.0), what happens and how the labs deal with them.

## Issues reported to HCL Support

| Case | Opened | Issue | Status |
|---|---|---|---|
| **CS1479102** | 2026-11-02 | IQ: the MCP server list set as documented is ignored | Open, being reproduced by HCL |
| **CS1479139** | 2026-11-02 | IQ: the system prompt describes an active RAG memory while RAG is disabled | Open |
| **CS1479178** | 2026-11-02 | IQ: requests to the LLM cannot use prompt caching, so every call pays full price for a ~30,000-token prefix | Open |

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

## Issues not reported (no case opened)

### HCL is aware: expected in a future release

| Issue | Solution in the labs |
|---|---|
| **The Web Engine on PostgreSQL is not supported in CF238** (DB2, Oracle and SQL Server are). HCL is validating PostgreSQL for the Web Engine (its tests work with PostgreSQL 18). In our tests, the Web Engine (OpenJPA) generates `LIKE … ESCAPE '\'` (DB2/Oracle style), which PostgreSQL rejects with "invalid escape string" with its default settings | Lab 2B is presented as a learning exercise, not as a supported configuration. The PostgreSQL preparation script sets `standard_conforming_strings = off` (and `escape_string_warning = off`) on `dx_core` |

### IQ (hcl-dx-iq 1.0.2)

| Issue | Solution in the labs | Case? |
|---|---|---|
| **`LITELLM_BASE_URL` is undocumented but required.** With only the documented `configuration.litellm.liteLlmUrl`, the Integrator's LLM adapter does not send the requests to our LiteLLM | `LITELLM_BASE_URL` set in `environment.pod.integrator` with the same URL (`custom-iq-values.yaml`) | Candidate for a case |
| **`LITELLM_URL` and `LITELLM_API_KEY` cannot be overridden** through `environment.pod.integrator`: the chart defines them again | The URL goes in `configuration.litellm.liteLlmUrl` (+ `LITELLM_BASE_URL`); the key in the `iq-litellm-api-secret` secret | To be added as a comment to CS1479102 |
| **MCP tool names contain dots** (`dam.mime-type…`), which the Anthropic and OpenAI APIs reject (`[a-zA-Z0-9_-]` only): with a provider that does not adapt them, the whole request fails with HTTP 400 | LiteLLM uses its `anthropic/` provider against the Anthropic-compatible endpoint of OpenRouter, which sanitises the names. HCL recommends `enableDam: false` with non-Claude models | No (improvement request) |
| **The Integrator reads the MCP tools only when it starts.** If it starts before the MCP Server is ready (normal on a fresh install), it has no tools until it is restarted | The install waits for the MCP Server and then restarts the Integrator (`04-iq-install.sh`) | No |
| **OpenRouter is not validated by HCL** (the HCL guides use AWS Bedrock) | Documented in Lab 3: OpenRouter is used through LiteLLM to avoid the AWS Bedrock account set-up | No (by design) |

### Search V2 (hcl-dx-search 2.36.0)

| Issue | Solution in the labs | Case? |
|---|---|---|
| **With DX published through an Ingress or a Route, the crawlers use `http` and index 0 documents.** `automatedSetup.haproxyProtocol` is empty by default, and the chart then chooses the protocol from the type of the DX HAProxy Service: `https` if it is `LoadBalancer` (the DX chart default), `http` otherwise. It does not look at `networking.haproxy.ssl`, which is what decides whether HAProxy uses TLS. With the defaults of both charts it works. But publishing DX through an Ingress (Kubernetes) or a Route (OpenShift) means `serviceType: ClusterIP`, normally with SSL still on: Search then calls HAProxy on port 80, where nothing listens, and the crawlers time out. The rule is only in a comment of the Search chart `values.yaml`; the HCL page "Installing the Search V2 backend" does not mention it | `haproxyProtocol: https` in `custom-search-values.yaml`, always set explicitly when HAProxy is `ClusterIP` or `NodePort` with SSL | No (our configuration; at most a documentation suggestion) |
| **The File Processor is disabled by default**, but the Search Middleware looks for it anyway and logs "Could not connect to file processor" every 3 seconds | `applications.fileProcessor: true` | Candidate for a case |

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

### Third-party components (not HCL)

| Issue | Solution in the labs |
|---|---|
| OpenLDAP (`openldap-stack-ha`): a custom LDIF without the root entry makes the first `ldapadd` fail and the LDAP starts empty | `demo-users.ldif` includes `dn: dc=dxdemo,dc=com` |
| k3s `local-path` does not support ReadWriteMany (DAM needs it) | Lab 0: static StorageClass with a `hostPath` volume |
| `hostPath` volumes ignore the pod `fsGroup`: DAM (uid 1000/gid 1001) cannot write (`EACCES`) | Lab 0: `01-storage.sh` sets the directory owner to `1000:1001` |
| OpenAI reasoning models (gpt-5.x) inject `reasoning_effort` and break the IQ tools | Documented in `litellm-values.yaml`: use Claude |
