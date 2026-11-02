# Known issues found while building the labs

**English** · [Español](issues.es.md)

Issues found while preparing this PoC with HCL DX Compose CF238 (`hcl-dx-deployment` 2.49.0,
`hcl-dx-iq` 1.0.2, `hcl-dx-search` 2.36.0), what happens and how the labs deal with them.

## Issues reported to HCL Support

| Case | Opened | Issue | Status |
|---|---|---|---|
| **CS1479102** | 2026-11-02 | IQ: the MCP server list set as documented is ignored | Open, being reproduced by HCL |
| **CS1479139** | 2026-11-02 | IQ: the system prompt describes an active RAG memory while RAG is disabled | Open |

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
| **`automatedSetup.haproxyProtocol` defaults to `http`** (port 80), but the DX HAProxy only listens on 443 with TLS by default: the crawlers time out and index 0 documents | `haproxyProtocol: https` in `custom-search-values.yaml` | Candidate for a case |
| **The File Processor is disabled by default**, but the Search Middleware looks for it anyway and logs "Could not connect to file processor" every 3 seconds | `applications.fileProcessor: true` | Candidate (together with the previous one) |
| **The OpenSearch volume uses the StorageClass `manual` by default** | `volumes.openSearchManager.data.storageClassName` set to the RWO StorageClass | No |
| Content sources and crawlers are created only on the first installation: changing `automatedSetup` later has no effect | Documented in Lab 4: uninstall, delete the PVC and install again | No |

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
