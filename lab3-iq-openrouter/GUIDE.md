# Lab 3 · HCL DX IQ with LiteLLM and OpenRouter

**English** · [Español](GUIDE.es.md)

**Starting point:** Lab 1 finished (Lab 2 is optional for this lab, except for the appendix).

**⏱ Estimated time: ~13 minutes** (3A ~10 min · 3B ~3 min).

| Step | Time |
|---|---|
| 1-3 · Secrets, LiteLLM and its test with OpenRouter | ~1 min |
| 4 · Install IQ (Integrator and MCP Server) | ~2 min |
| 5 · DX `helm upgrade` with IQ (restarts HAProxy, Web Engine and Persistence Node) | ~5 min |
| Check · `99-verify.sh` and `06-iq-chat-test.sh` (each question, 5-11 s) | ~1 min |
| 3B · Custom MCP: deploy, test and register | ~3 min |

> Run times measured on the reference lab cluster (k3s, 3 workers with 14 CPU / 20 GiB), without
> the explanations. The first time on a new cluster, add the download of the HCL images from
> `hclcr.io`, which depends on the network.

**Goal:** enable **IQ**, the DX AI assistant, using **Claude** through **OpenRouter** (instead of
the AWS Bedrock of the HCL guides, see below), with a **LiteLLM** proxy in `dx-shared`.

HCL documentation: [IQ installation (CF238)](https://help.hcl-software.com/digital-experience/9.5/CF238/build_sites/iq/installation/)

```
 Browser ─► DX HAProxy ─► /dx/ui/iq, /dx/api/iq/v1 ─► dx-iq-integrator ─┬─► dx-iq-mcp-server ─► DX APIs
                                                         (dx-demo)        │      (WCM and DAM tools)
                                                                          │
                         dx-shared: litellm:4000 ◄────────────────────────┘
                               │  iq-general-purpose -> Claude Sonnet 4.6
                               │  iq-summary         -> Claude Haiku 4.5
                               └─► https://openrouter.ai/api
```

| Component | Namespace | Provided by |
|---|---|---|
| HCL IQ Integrator and MCP Server | `dx-demo` | HCL `hcl-dx-iq` 1.0.2 chart |
| LiteLLM | **`dx-shared`** | **Not supplied by HCL**: official LiteLLM chart (BerriAI) |
| EUROPESIP MCP Server (3B) | **`dx-shared`** | Our own MCP server |
| Models | Internet | OpenRouter (`OPENROUTER_API_KEY`) |

As in the other labs, everything that **is not HCL** goes in **`dx-shared`**, the namespace we
created for tools outside HCL; `dx-demo` only has the HCL charts.

IQ always asks for two logical models, `iq-general-purpose` and `iq-summary`; LiteLLM decides
which provider and real model they go to. Changing the model does not require touching IQ.

## Why OpenRouter and not AWS Bedrock

The official HCL guides install IQ with **LiteLLM in front of AWS Bedrock** (the Claude models
served by Amazon). These labs use **OpenRouter** instead, only to avoid the complexity of setting
up an AWS Bedrock account, which adds nothing to what you want to learn (installing and
connecting IQ):

| To use Bedrock you need... | With OpenRouter |
|---|---|
| An **AWS account** with billing enabled (card, sometimes company approval) | Sign up with an e-mail and a few dollars of **prepaid credit** |
| An **IAM** user or role with `bedrock:InvokeModel*` permissions, and its access keys (or IRSA on EKS) stored in the cluster | **A single API key** (`sk-or-v1-...`) in a secret |
| Choosing a **region** where the models are available (or cross-region inference profiles) | No regions: one endpoint, `https://openrouter.ai/api` |
| **Requesting access** to the Anthropic models in the Bedrock console (use-case form), which can take time | The models are available immediately |
| Checking the **quotas** (tokens per minute), low by default on new accounts | Limits large enough for a lab; **spend limit per key** |
| Repeating it **for every attendee** of a course, or sharing AWS credentials | One key per attendee, revocable when the course ends |

Why OpenRouter is a good choice for this:

- **The same models HCL validates**: Claude Sonnet 4.6 (`iq-general-purpose`) and Claude Haiku 4.5
  (`iq-summary`), from Anthropic.
- **Endpoint compatible with the Anthropic API**, so LiteLLM uses its `anthropic/` provider, which
  adapts the HCL MCP tool names and supports *prompt caching* (step 2).
- **Spend control**: prepaid credit, a limit per key and a dashboard
  ([openrouter.ai/activity](https://openrouter.ai/activity)) with every request, its tokens and its cost.
- **Changing the model is changing an ID** in `litellm-values.yaml`: IQ is not touched.
- **What you learn is the same**: IQ, the Integrator, the MCP Server, LiteLLM and its configuration
  are identical. Only the LiteLLM model list changes.

**In production**, the usual choice is a provider contracted by the company (Bedrock, Azure OpenAI,
Google Vertex, Anthropic directly...) and reviewing where the data is processed: with OpenRouter
the requests go through one more intermediary. Moving to Bedrock only changes `litellm-values.yaml`:

```yaml
    - model_name: iq-general-purpose
      litellm_params:
        model: bedrock/<Bedrock model or inference profile ID>
        aws_region_name: os.environ/AWS_REGION
        # credentials: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the litellm-env secret, or IRSA
```

> **Support.** HCL validates LiteLLM with Bedrock, OpenAI, etc., but **not OpenRouter**. This
> configuration works with two undocumented settings explained in the *Deviations* section at the
> end.

```bash
cd hcl-dx-compose-labs && source ./env.sh      # with OPENROUTER_API_KEY set
```

---

## Step 1 · Secrets

```bash
lab3-iq-openrouter/01-secrets.sh
```

| Secret | Namespace | Content |
|---|---|---|
| `litellm-env` | `dx-shared` | `OPENROUTER_API_KEY` and `PROXY_MASTER_KEY` (LiteLLM master key, starts with `sk-`) |
| `iq-litellm-api-secret` | `dx-demo` | `virtualKey`: the key IQ uses to call LiteLLM |

LiteLLM runs without a database (the HCL "quick start"), so there are no virtual keys and IQ uses
the master key. Each secret lives in the namespace of whoever reads it.

## Step 2 · LiteLLM

```bash
lab3-iq-openrouter/02-litellm-install.sh
```

> **LiteLLM is not supplied by HCL.** The `hcl-dx-iq` chart only deploys the HCL Integrator and
> MCP Server. HCL **recommends using LiteLLM as the proxy** between IQ and the AI models (and
> documents how to install it), but does not ship it: we use the **official LiteLLM chart**
> (BerriAI, `oci://ghcr.io/berriai/litellm-helm`). That is why it goes in **`dx-shared`**, and its
> version, patches and configuration are our responsibility, not HCL support's.

It installs `oci://ghcr.io/berriai/litellm-helm` 1.106.5 in `dx-shared` with
[litellm-values.yaml](litellm-values.yaml). The important part:

```yaml
proxy_config:
  model_list:
    - model_name: iq-general-purpose
      litellm_params:
        model: anthropic/anthropic/claude-sonnet-4.6   # anthropic/ provider + OpenRouter id
        api_base: https://openrouter.ai/api            # Anthropic-compatible endpoint
        api_key: os.environ/OPENROUTER_API_KEY
        cache_control_injection_points:                # prompt caching
          - { location: message, role: system }
  litellm_settings:
    drop_params: true                                  # HCL: essential
```

- **`anthropic/` and not `openrouter/`**: the HCL MCP Server has tools with dots in their names
  (`dam.mime-type...`). The `anthropic/` provider adapts them to the format Claude accepts; with
  `openrouter/` (OpenAI format) Claude rejects the whole request with HTTP 400.
- **Prompt caching**: every IQ request sends ~50 tools and a long system prompt that barely
  change. Marking them as cacheable makes the following questions much cheaper.
- `db.deployStandalone: false`: without the PostgreSQL the chart would install by default.

## Step 3 · Test LiteLLM before installing IQ

```bash
lab3-iq-openrouter/03-litellm-test.sh
```

It opens a local port-forward, lists the models and sends one request to each. Both must answer
`ready` (LiteLLM returns the logical model name; the real one, Sonnet 4.6 or Haiku 4.5, is shown at
https://openrouter.ai/activity). If it fails here, the problem is the OpenRouter key or credit, not
IQ.

## Step 4 · Install IQ

Read [custom-iq-values.yaml](custom-iq-values.yaml). The main values:

| Value | What for |
|---|---|
| `configuration.dx.releaseName` / `externalHost` | Which DX to use (`dx-deployment`) and its FQDN; the script passes them from `env.sh` |
| `configuration.litellm.liteLlmUrl` | `http://litellm.dx-shared.svc.cluster.local:4000`: **FQDN** because it is in another namespace. The script sets `LITELLM_URL_INTERNAL` from `env.sh` |
| `environment.pod.integrator` → `LITELLM_BASE_URL` | Same URL. Undocumented but essential in 1.0.2 (see below) |
| `configuration.mcpServer.enableWcm` / `enableDam` | Tools IQ can use on WCM and DAM |
| `configuration.database.enabled: false` | Sessions in in-memory SQLite (lost on restart). See the appendix |

```bash
lab3-iq-openrouter/04-iq-install.sh
```

```bash
helm upgrade --install dx-iq charts/hcl-dx-iq-1.0.2.tgz -n dx-demo -f lab3-iq-openrouter/custom-iq-values.yaml \
  --set-string configuration.dx.releaseName=dx-deployment --set-string configuration.dx.externalHost=$DX_HOST
```

Then it restarts the MCP Server and the Integrator (Helm does not do it if only secrets change).

## Step 5 · Enable IQ in DX

```bash
lab3-iq-openrouter/05-dx-enable-iq.sh
```

It adds the [custom-values.iq.yaml](custom-values.iq.yaml) layer to the DX `helm upgrade`:

```yaml
networking:
  dxIqService: "dx-iq-integrator"     # <IQ release>-integrator
```

HAProxy starts routing `/dx/api/iq/v1/` and `/dx/ui/iq/` to the Integrator and the IQ button
appears. HAProxy, the Web Engine and also the Persistence Node, its pool and the Runtime Controller
restart: when IQ is enabled, the chart prepares the `iqdb` database in the Persistence Node (used
if IQ sessions move to the internal PostgreSQL). About 5 minutes.

## Check

```bash
lab3-iq-openrouter/99-verify.sh
```

It checks the effective LiteLLM URL, the key, that the Integrator loaded the MCP Server tools, the
`dx-demo → dx-shared` connectivity and the HAProxy routing.

### End-to-end test from the terminal

```bash
lab3-iq-openrouter/06-iq-chat-test.sh
lab3-iq-openrouter/06-iq-chat-test.sh "How many WCM libraries are there?"
```

(`IQ_LANG` is the language IQ answers in; `en` by default, e.g. `IQ_LANG=es`.)

It does the same as the browser: logs in to DX as `wpsadmin` (or `IQ_USER`/`IQ_PASSWORD`), opens
the IQ WebSocket (`wss://$DX_HOST/dx/api/iq/v1/ws`, JSON-RPC 2.0) and shows every MCP tool IQ uses
and its final answer. Example:

```
  [  3.6s] tool_call: get_all_libraries_from_WCM  Getting all libraries...
---- final IQ answer (5.6s) ----
1. Blog Solo Template v70
...
19. poc-transfer                   <- the test library created before Lab 2B, now in PostgreSQL
```

### From the browser

At `https://$DX_HOST/wps/myportal`, as wpsadmin, click the IQ ✨ button (HCL requirement:
Practitioner Studio enabled, which is the normal case in DX Compose) and try:

- "Which content libraries are there in WCM?"
- "Summarise the content of the PoC page"
- "Search DAM for PNG images"

---

## 3B · Adding a custom MCP Server

IQ is not limited to the HCL tools. An **MCP Server** (*Model Context Protocol*) is a service that
publishes **tools**: functions with a name, a description and parameters that the LLM can decide to
call. The HCL MCP Server publishes 53 (WCM and DAM). Here we add our own with information the model
cannot know: **who EUROPESIP is and which services it offers**, its support hours, where these labs
are... and a tool, **figma&web-to-dx**, that presents the EUROPESIP solution to generate DX
components from designs.

```
                                ┌─► dx-iq-mcp-server:3000            (HCL, dx-demo)      53 tools
 IQ Integrator ── tools/list ───┤
   (dx-demo)                    └─► europesip-mcp.dx-shared:3000     (custom, dx-shared)  5 tools
```

**Why in `dx-shared`?** IQ already ships an MCP Server, the HCL one (`dx-iq-mcp-server`), which the
`hcl-dx-iq` chart installs next to the Integrator in `dx-demo`. The one we add here is **a new MCP
Server, our own**, not the one that comes with HCL: that is why it runs in a separate namespace,
`dx-shared`, with the other tools outside HCL. The Integrator reaches it by its full service name
(`europesip-mcp.dx-shared.svc.cluster.local`).

> **Support.** HCL documents `MCP_SERVER_LIST` for its own MCP Server; adding custom servers is
> neither documented nor supported in IQ 1.0.2. It works with the procedure below.

### The server

[custom-mcp/server.py](custom-mcp/server.py): about 240 lines of commented Python with the official MCP SDK
(`FastMCP`). Its source code and its image are published in
[europesip/hcl-dx-iq-europesip-mcp](https://github.com/europesip/hcl-dx-iq-europesip-mcp), as a
skeleton to build your own MCP Server: its README explains how, with example questions and ideas
to extend it. It publishes five tools:

| Tool | IQ uses it when the user... | Returns |
|---|---|---|
| `europesip_services()` | asks who EUROPESIP is or which services it offers | A company specialised in HCL and IBM products, with broad experience in portals and Domino, strong AI knowledge (its own tools that make AI easier to use and speed up development) and an emphasis on digital sovereignty. Refers to https://www.europesip.com |
| `europesip_faq(topic)` | asks about support, AI, digital sovereignty, the labs, the website or contact | The requested topic. For "labs", the link to this repository (https://github.com/europesip/hcl-dx-compose-labs) |
| `figma_web_to_dx(source)`, shown as **figma&web-to-dx** | wants to create a WCM / Blueprint page or component from Figma, a screenshot or a site URL | That EUROPESIP has an MCP tool integrated with HCL DX IQ to speed up building Blueprint components from Figma URLs, screenshots or site URLs, and to contact EUROPESIP |
| `europesip_whoami()` | asks who they are or which user they are logged in as | **Who the user asking is**, read from DX with that user's own session (see *Using the user's DX session* below) |
| `europesip_echo(text)` | explicitly asks to test the echo | Diagnostics |

The server answers in English; IQ translates the answer to the user's language when it replies.

```python
mcp = FastMCP("europesip-kb", stateless_http=True, json_response=True, ...)

@mcp.tool(name="figma_web_to_dx", title="figma&web-to-dx")
def figma_web_to_dx(source: str = "") -> str:
    """figma&web-to-dx: designs web pages or HCL DX WCM / Blueprint components from a Figma
    design, a screenshot or the URL of an external site. Use it when the user wants to create a
    DX component, template or page from a design, an image or a website."""
    ...
```

Two details worth explaining:

- **Technical name versus display name.** IQ (and Claude) only accept tool names with
  `[a-zA-Z0-9_-]`, so `figma&web-to-dx` cannot be the name: the tool is called `figma_web_to_dx`
  and its display name (`title`) and description say `figma&web-to-dx`.
- **Stopping the model from making things up.** With company data, the model tends to
  "embellish" (in the tests it wrote "official partner" or services we had not given it). Every
  server answer ends with an instruction to stick to that information and refer to the website for
  the rest. IQ answers then stick to the data.

What it has to comply with for IQ to use it:

| Requirement | In the server |
|---|---|
| MCP over *streamable* HTTP at `POST /mcp`, without sessions | `stateless_http=True`, `json_response=True` (like the HCL MCP) |
| `GET /probe/ready` → 200 | The Integrator calls it before asking for the tools |
| Tool names `[a-zA-Z0-9_-]` | `figma_web_to_dx`, with the display name in `title` (the Integrator adds a per-server prefix: `562b68ed_...`) |
| **A good description** | It is the only thing the model reads to decide whether to use it. Short and precise: it travels in every request |

### Step 3B-1 · Deploy

```bash
lab3-iq-openrouter/custom-mcp/01-mcp-deploy.sh
```

Deployment with the public image `ghcr.io/europesip/hcl-dx-iq-europesip-mcp:1.0.1` (the server and
its dependencies, amd64 and arm64) + Service `europesip-mcp:3000`, in `dx-shared`
([europesip-mcp.yaml](custom-mcp/europesip-mcp.yaml)).

### Step 3B-2 · Test it before connecting it to IQ

```bash
lab3-iq-openrouter/custom-mcp/02-mcp-test.sh
```

From a pod in `dx-demo` it speaks MCP as the Integrator will: `initialize`, `tools/list` (the 5
tools) and `tools/call` of `europesip_faq(topic="support")`, which returns the support hours.

### Step 3B-3 · Register it in IQ

```bash
lab3-iq-openrouter/custom-mcp/03-iq-register.sh
```

The Integrator reads the list of MCP Servers from the `dx.config.integrator.mcp_server_list` key
of the `dx-iq-integrator` ConfigMap. Chart 1.0.2 generates it with only the HCL one and offers no
value to extend it (the `MCP_SERVER_LIST` variable has no effect either: the ConfigMap overrides
it). The script patches that key and restarts the Integrator:

```
http://dx-iq-mcp-server:3000,http://europesip-mcp.dx-shared.svc.cluster.local:3000
```

In the Integrator log:

```
Fetched 53 tools from http://dx-iq-mcp-server:3000
Fetched 5 tools from http://europesip-mcp.dx-shared.svc.cluster.local:3000
Total tools: 58
```

> Every IQ `helm upgrade` regenerates the ConfigMap. `04-iq-install.sh` adds the custom server back
> automatically if the `europesip-mcp` service exists in `dx-shared`.

### Check

```bash
lab3-iq-openrouter/06-iq-chat-test.sh "What are the EUROPESIP support hours?"
lab3-iq-openrouter/06-iq-chat-test.sh "Which services does EUROPESIP offer?"
lab3-iq-openrouter/06-iq-chat-test.sh "Is there a lab to install HCL DX Compose from scratch?"
lab3-iq-openrouter/06-iq-chat-test.sh "I want to create a Blueprint component from this Figma design: https://www.figma.com/file/abc123/landing"
```

Result (tool chosen by IQ and total time):

| Question | Tool | Time |
|---|---|---|
| Support hours | `europesip_faq` (topic `support`) | ~6 s |
| EUROPESIP services | `europesip_services` | ~9 s |
| Digital sovereignty | `europesip_faq` (topic `sovereignty`) | ~10 s |
| DX Compose labs | `europesip_faq` (topic `labs`) → link to the repository | ~11 s |
| Component from Figma | `figma_web_to_dx` (figma&web-to-dx) | ~10 s |

Example:

```
  [  3.0s] tool_call: 562b68ed_europesip_faq  Looking up the EUROPESIP knowledge base...
---- final IQ answer (7.5s) ----
EUROPESIP support for HCL DX:
- Days: Monday to Friday
- Hours: 9:00 – 18:00 (Madrid time)
- Contact: soporte@europesip.com
```

And in the custom server log (`kubectl -n dx-shared logs deploy/europesip-mcp`), the call:

```
REQ POST /mcp ... cookies=-                                              <- tools/list (discovery)
REQ POST /mcp ... cookies=['DxSessionAffinity', 'JSESSIONID', 'LtpaToken2']   <- tools/call
TOOL europesip_faq topic='support'
```

> **Security: the Integrator forwards the user's DX session.** On every `tools/call`, the server
> receives the DX session cookies (`LtpaToken2`...) of the user asking. That lets a custom MCP call
> the DX APIs **with that user's identity and permissions**, but it also means a custom MCP is
> trusted code: review what it does, do not log their values (this one only logs the names) and
> protect access to it.

#### Using the user's DX session: `europesip_whoami`

`europesip_whoami` shows how a custom MCP can act **as the user asking**:

1. It reads the `LtpaToken2` cookie that the Integrator forwards on the `tools/call`
   (in FastMCP, `ctx.request_context.request.cookies`).
2. It calls DX inside the cluster, through the DX HAProxy (`DX_URL` in
   [europesip-mcp.yaml](custom-mcp/europesip-mcp.yaml)), with that cookie:
   `GET /wps/mycontenthandler/um/secure/currentuser/profile` (DX User Management REST API).
3. DX answers with the profile of **that** user, so the tool only sees what the user is allowed to
   see. It returns the distinguished name, `uid`, name and e-mail, and never the `password`
   attribute (DX includes the LDAP hash in the profile). The token itself is never logged.

```bash
IQ_USER=macarena IQ_PASSWORD=EuropeS1P lab3-iq-openrouter/06-iq-chat-test.sh "Who am I?"
```

```
  [  1.9s] tool_call: 562b68ed_europesip_whoami ...
---- final IQ answer (6.6s) ----
Hi, Macarena! ... uid: macarena · Macarena Demo · uid=macarena,ou=users,dc=dxdemo,dc=com
```

Each user gets their own identity (try it with `andres` and with `macarena`). The same technique
lets a custom MCP read or change DX content **with the permissions of the user asking**, instead
of an administrative account.

> **Cost.** The added tools travel in every request (these five, about 3,000 characters ≈ 800-900
> tokens) and changing the list invalidates the prompt cache until the next request.

To remove it: `kubectl -n dx-shared delete deploy/europesip-mcp svc/europesip-mcp`
and `lab3-iq-openrouter/04-iq-install.sh` (regenerates the list with only the HCL MCP).

## Deviations from the HCL documentation (IQ 1.0.2)

(Besides replacing AWS Bedrock with OpenRouter, explained at the beginning.)

1. **`LITELLM_BASE_URL` is mandatory.** The Integrator LLM adapter uses this variable, not
   `litellm.liteLlmUrl`. Without it, it calls an internal HCL URL. It is defined in
   `environment.pod.integrator` with the same value.
2. **`LITELLM_URL` and `LITELLM_API_KEY` cannot be set as environment variables**: the chart
   redefines them afterwards. The key goes in `iq-litellm-api-secret`.
3. **OpenRouter through the LiteLLM `anthropic/` provider** (see step 2).

## Appendix · IQ sessions in PostgreSQL (requires Lab 2B)

With in-memory SQLite the history is lost when the pod restarts and the Integrator cannot be
scaled. To use the `dx-shared` PostgreSQL:

```bash
lab3-iq-openrouter/A1-iq-database.sh                                   # iqdb database + secret in dx-demo
lab3-iq-openrouter/04-iq-install.sh -f custom-iq-values.db-external.yaml
```

The `dx_iq_db_user` role was already created by CNPG in Lab 2B. IQ creates its tables when it
starts: after opening a chat they appear in `iqdb`.

## Cost

The OpenRouter account pays. With prompt caching enabled, the first question of a session is the
most expensive one (it creates the tools and system prompt cache) and the following ones read from
the cache at ~10 % of the price. Measured in the lab with two identical requests of ~4000 prompt
tokens:

| Request | Tokens written to cache | Tokens read from cache |
|---|---|---|
| 1st | 4017 | 0 |
| 2nd | 0 | 4017 |

The https://openrouter.ai/activity dashboard shows every request and its cost.

> **Tools.** If something fails and you need to open a case with HCL Support:
> `common/collect-support-data.sh --case <number>` ([support data](../docs/support.md)). To start the
> installation again from scratch: `common/99-cleanup.sh` ([cleanup](../docs/cleanup.md)).
