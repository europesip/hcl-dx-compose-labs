# Lab 5 · ÓRBITA, an advanced application on DX Compose *(advanced, optional)*

**English** · [Español](GUIDE.es.md)

> **Advanced lab.** It is not needed for the installation of DX Compose (Labs 1 to 4). It shows what a **real
> application** on DX Compose looks like when it combines **Script Applications, a microservice, persistence and AI
> integration**, all of it deployed with **one Helm chart**.

**ÓRBITA** is an intranet suite by EUROPESIP: time tracking, time off, expenses and travel, approvals, a home page and
a time clock kiosk. Source, chart and documentation: [github.com/europesip/orbita](https://github.com/europesip/orbita)
(free software licence MIT). The interface is in English and Spanish, in the language of each user's DX profile.

| Piece | What it shows | In ÓRBITA |
|---|---|---|
| **Script Applications** | The native way to build your own apps on DX Compose (no Java portlets), several apps from one chart | Six React apps pushed to WCM with DXClient (subchart [hcl-dx-scriptapp](https://github.com/europesip/hcl-dx-scriptapp-helm) 0.2.0), each on its own page under *Home* |
| **Microservice** | Business logic outside DX, next to it, on the DX host | `orbita-api`: Open Liberty with a REST API (`/orbita-api/v1`, Ingress on the DX host) |
| **Single sign-on** | The microservice does not store users or passwords | The API forwards the user's DX session cookie to the DX profile API: **DX says who the user is** |
| **Persistence** | A database of its own and schema upgrades without losing data | PostgreSQL (external dependencies): database and user created by a Job, tables by **Flyway** migrations |
| **AI integration** | An assistant that acts on your application, and your application inside HCL DX IQ | Its **own AI assistant** through LiteLLM, with 26 tools that act **as the user asking**; the same tools as an **MCP server** for **HCL DX IQ** (optional) |
| **Theme and DAM** | A custom theme and its images deployed by the same chart | An example theme (a copy of Portal 8.5, on the ÓRBITA pages only) with the company logo, *Powered by HCL Software* and an «✨ Ask ÓRBITA» button; logos and images in a **DAM** collection (`theme.enabled: false` to keep your theme) |

```
 Browser ── https://<DX host> ──┬── /wps/myportal/Home/...  DX pages with the 6 Script Applications (WCM)
                                └── /orbita-api/v1           Ingress ──► orbita-api (dx-shared)
                                                                         ├─ who is it? ── LtpaToken2 ──► DX
                                                                         ├─ AI assistant ──► LiteLLM (dx-shared)
                                                                         └─ PostgreSQL dx-pg: database "orbita"
 IQ Integrator (dx-demo) ── user's DX cookies ──► orbita-api :9081 /mcp (NetworkPolicy: only the Integrator)
```

## Before you start

| Needs | Why |
|---|---|
| **Lab 1** | DX, its host name and its certificate |
| **PostgreSQL** ([external dependencies](../external-deps/GUIDE.md), `external-deps/02-postgres.sh`) | ÓRBITA 2.x requires PostgreSQL; the chart creates its own database `orbita` with the superuser Secret `dx-pg-superuser` |
| **Lab 2A** (OpenLDAP) | The demo users (`patricia`, `andres`, `macarena`…) are the OpenLDAP ones |
| **LiteLLM** (Lab 3A, or `external-deps/03-litellm.sh`) | ÓRBITA's own AI assistant (without it, ÓRBITA installs without the assistant) |
| **Lab 3A** *(optional, step 3)* | ÓRBITA inside the HCL DX IQ chat |

The chart and the images are **public** (`ghcr.io/europesip`): no registry login. ⏱ ~3 min (more the first time, while
the nodes download the images).

## Step 1 · Install ÓRBITA

DXClient asks you to accept its license, as in Lab 1B (`DXCLIENT_ACCEPT_LICENSE=yes` in `env.sh`). Then:

```bash
lab5-orbita/01-orbita-install.sh
```

It creates two secrets in `dx-shared` (`orbita-dx`: the DX administrator for DXClient; `orbita-dx-ca`: the CA of the
DX certificate) and runs:

```bash
helm upgrade --install orbita oci://ghcr.io/europesip/charts/hcl-dx-orbita --version 3.1.0 -n dx-shared \
  --set dx.host=$DX_HOST --set dx.caSecret=orbita-dx-ca \
  --set database.host=$PG_HOST --set database.create.superuserSecret=dx-pg-superuser \
  --set scriptapps.dx.host=$DX_HOST --set scriptapps.dx.credentialsSecret=orbita-dx \
  --set scriptapps.dx.caSecret=orbita-dx-ca --set scriptapps.dxclient.acceptLicense=true \
  --set assistant.litellm.url=http://litellm.dx-shared.svc.cluster.local:4000
```

What the chart does, in order:

1. **Job `orbita-db`** (before the install): creates the user and the database `orbita` in PostgreSQL.
2. **`orbita-api`**: Deployment, Service, Ingress on `/orbita-api` of the DX host and NetworkPolicy of the MCP port. At
   start-up Flyway creates the tables and the demo data are loaded.
3. **Job `orbita-scriptapps-push`** (after the install): pushes the six Script Applications with DXClient and creates
   their pages with XMLAccess.

## Step 2 · Use it

Sign in to DX as a demo user (password: `LDAP_USERS_PASSWORD` of `env.sh`) and open
`https://<DX host>/wps/myportal/Home/mi-intranet`. The demo story is written by roles, played by the Lab 2A users:

| User | Role in ÓRBITA | Try |
|---|---|---|
| `macarena` | Sales | Clock in, ask for holidays, add an expense to a report and send it |
| `andres` | Sales manager | *Aprobaciones*: approve or reject; *Fichaje › Equipo*: who is working |
| `german` | Accounting | *Gastos › Pagos*: pay the approved reports |
| `patricia` | HR | *Fichaje › Informes*: time records of everybody; restore the demo data |

Another role assignment: chart value `demo.people` (see the ÓRBITA README).

**Language.** Each user sees ÓRBITA in the language of their DX profile. In Lab 2A every user has Spanish, except
`andres` and `justo` (English): sign in as `andres` to see it in English.

**The AI assistant.** The «✨ Ask ÓRBITA» button of every app opens ÓRBITA's own assistant. **Ask in English or in
Spanish**: it answers in the language of the question.

- «How many days of holiday do I have left?» · «Book me holidays from 9 to 11 December»
- «Have I clocked in today?» · «Clock me in, working from home» · «Which days this month did I not clock out?»
- «How much am I owed in expenses?» · «Create a report "Visit to Seville" and add a €42.80 lunch from yesterday»
- As `andres`: «What do I have to approve?» · «Who in my team is working right now?» · «Approve macarena's holidays»

More than 60 questions: [ai-questions.md](https://github.com/europesip/orbita/blob/main/docs/ai-questions.md) (in
Spanish: [preguntas-ia.md](https://github.com/europesip/orbita/blob/main/docs/preguntas-ia.md)). The tools act as the
user asking (identified by their DX session); anything that changes data asks for confirmation first. It uses the
LiteLLM model alias `iq-general-purpose`, the same as IQ (chart value `assistant.model` for another one).

**Settings of each application.** As `wpsadmin`, switch on the page edit mode in DX: every ÓRBITA app shows «⚙
Settings of this application» (header parts, footer and language for that page only).

## Step 3 · ÓRBITA in HCL DX IQ (optional, needs Lab 3A)

```bash
lab5-orbita/02-orbita-iq.sh
```

It adds `http://orbita-api.dx-shared.svc.cluster.local:9081` to the **MCP server list** of the IQ Integrator and
restarts it. A patch is needed because of the same IQ bug as in Lab 3B (case CS1479102, [issues.md](../issues.md)):
the documented variable has no effect and the list lives in the ConfigMap `dx-iq-integrator`. Lab 3
`04-iq-install.sh` adds ÓRBITA back after every IQ upgrade.

Then the IQ chat (the ✨ button of DX) can also answer and act on ÓRBITA, mixed with the HCL DX tools (WCM, DAM,
pages): the same questions as above. IQ is meant for the DX practitioners; for the employees, ÓRBITA's own assistant
uses far fewer tokens per question.

**Prompt size.** Every tool definition goes into every call to the model: the 26 ÓRBITA tools are about 4,700 tokens.
To publish fewer (in both assistants), `--set 'mcp.tools.enabled={vacaciones,fichaje}'` or `--set mcp.tools.readOnly=true`
in step 1 (see the ÓRBITA README).

## Check

```bash
lab5-orbita/99-verify.sh
```

## Good to know

- **Uninstall**: `helm -n dx-shared uninstall orbita`. The database, the Script Applications and the pages stay;
  `common/99-cleanup.sh` removes everything with the namespaces.
- **The pages appear under *Home* for every signed-in user**: uninstall ÓRBITA before a session where you do not want
  them.
- The microservice holds **no DX credentials**: only DXClient (the push Job) uses the DX administrator.
