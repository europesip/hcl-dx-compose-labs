# HCL DX Compose from scratch on Kubernetes (CF238)

**English** · [Español](README.es.md) · [Configuration wizard (optional, experimental)](https://europesip.github.io/hcl-dx-compose-labs/about.html)

Hands-on labs to **install HCL Digital Experience Compose step by step**, as a proof of concept
(PoC). You start from an existing Kubernetes or OpenShift cluster, without DX, and build the platform
in four labs, each one on top of the previous one.

> **Where to start.** The ideal path is to **start with Lab 1**, on a Kubernetes or OpenShift
> cluster that is **already installed** and meets the [base requirements](docs/requirements.md)
> (resources, two StorageClasses, an Ingress or router and DNS), local or in the cloud.
> Lab 0 is **not** part of that path: see *No cluster?* below the table.

| Lab | What you do | ⏱ Run time |
|---|---|---|
| ▶ [Lab 1 · Base DX](lab1-dx-base/GUIDE.md) · **start here** | The start of the installation: a **minimal, working base installation** of DX Compose. It checks the base requirements and covers namespaces, secrets, the Helm chart from the HCL Harbor, the installation and external access. The other labs are built on top of it | ~10 min |
| [Lab 2 · LDAP and PostgreSQL](lab2-ldap-postgres/GUIDE.md) | **2A**: authentication against OpenLDAP. **2B**: transfer of the Web Engine database from Derby to PostgreSQL | ~27 min (2A ~10 · 2B ~17) |
| ↳ [Lab 2 · enterprise branch](lab2-ldap-postgres/GUIDE-enterprise.md) *(optional)* | The same iterations against **Active Directory** (with `configOverrideFiles`) and **Oracle** (TCPS), common in corporate environments | reference |
| [Lab 3 · IQ with OpenRouter](lab3-iq-openrouter/GUIDE.md) | **3A**: the DX AI assistant (IQ) using LiteLLM as a proxy to OpenRouter (Claude) instead of AWS Bedrock. **3B**: EUROPESIP custom MCP Server (services, support, labs and the figma&web-to-dx tool) | ~13 min (3A ~10 · 3B ~3) |
| [Lab 4 · Search with OpenSearch](lab4-opensearch/GUIDE.md) | Search V2: OpenSearch + Search Middleware (`hcl-dx-search` 2.36.0), certificates and `adminDN`, crawling of WCM, portal and JCR, and search through the API | ~10 min |
| | **Total run time** (Labs 1 to 4) | **~60 min** |

> **No cluster? Lab 0 (optional).** Only if you have **no Kubernetes environment already deployed**
> where you can do the PoC and you want to **emulate one on your own PC**: [Lab 0 · PoC on your
> PC](lab0-poc-wsl/GUIDE.md) builds a single-node k3s in a new WSL2 distro (Windows 10/11), with
> simulated StorageClasses, the Ingress and reduced resources (~10 min). Then you continue with Lab 1
> as everybody else. It is a simplified PoC environment, not a reference one: if you can use a real
> cluster, skip it.

> ⚠️ **Labs for learning, not for production.** At the end of the labs you have a **working**
> HCL DX Compose installation, but they are designed as a **PoC**: to understand and practise the
> steps of a real installation. A production environment needs **a lot of tuning and
> parameterisation** (sizing of resources and replicas, high availability, storage, JVM and
> database performance, caching, security, internal TLS, backups, monitoring...) to get the most
> out of the system, which **has been left out** to keep the labs simple. For a real project we
> always recommend working with an **HCL partner** or with **HCL specialised services**.

Versions: **HCL DX Compose 9.5 CF238**, charts `hcl-dx-deployment` **2.49.0**, `hcl-dx-iq`
**1.0.2** and `hcl-dx-search` **2.36.0**. Official documentation:
[Installing DX Compose (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/install/).

---

### Planning the sessions

The labs work for a live session (webinar), a hands-on workshop or a multi-day course. The times
are **run times**, measured in three complete from-scratch installations on the reference lab
cluster. Keep them in mind when planning:

- **Most of the time is waiting for Helm**: every DX `helm upgrade` restarts the Web Engine
  (~5 min) and the Lab 2B transfer takes ~14 min. That is the moment to explain the theory of the
  next iteration.
- **First installation on a new cluster**: add the download of the HCL images from `hclcr.io`,
  which depends on the network. For a live session, run a test installation (or a pre-pull)
  beforehand so the nodes already have the images.
- **Independent labs**: Labs 3 and 4 only need Lab 1. If time is short, Lab 2B (the longest one)
  can be left as homework.
- With explanations and questions, plan roughly twice the run time.

## Reference lab environment

Everything works on **standard Kubernetes** and on **OpenShift** (see
[docs/kubernetes-vs-openshift.md](docs/kubernetes-vs-openshift.md)). The labs were built and
validated on:

| | |
|---|---|
| Distribution | **k3s v1.35** (3 masters + 3 workers, Ubuntu 24.04, x86-64) managed with Rancher |
| Storage | **Longhorn 1.12**: StorageClasses `dx-deploy-rwo` (RWO) and `dx-deploy-rwx` (RWX) |
| Ingress | **ingress-nginx** with MetalLB and a wildcard DNS `*.apps.promox.europesip-lab.com` |
| Images and charts | **Official HCL Harbor** (`hclcr.io`), no intermediate registry |
| DX access | `https://dx-demo.apps.promox.europesip-lab.com/wps/portal` |

## Architecture: two namespaces

```
 ┌──────────────── dx-demo (HCL software) ───────────────────┐   ┌──── dx-shared (3rd party) ───┐
 │                                                           │   │                              │
 │  Ingress ─► HAProxy ─► Web Engine (DX Compose) ───────────┼──►│  OpenLDAP          (Lab 2A)  │
 │                │            │                             │   │                              │
 │                │            └────── JDBC ─────────────────┼──►│  PostgreSQL 18     (Lab 2B)  │
 │                │                                          │   │   (CloudNativePG operator)   │
 │                ├─► DAM, Image Processor, Ring API...      │   │                              │
 │                │   Persistence Node (DAM PostgreSQL)      │   │                              │
 │                │                                          │   │                              │
 │                ├─► IQ Integrator ─► IQ MCP Server         │   │                              │
 │                │        │                     (Lab 3)     │   │                              │
 │                │        └─────────────────────────────────┼──►│  LiteLLM ─► OpenRouter       │
 │                │        └─────────────────────────────────┼──►│  Custom MCP        (Lab 3B)  │
 │                │                                          │   │                              │
 │                └─► Search Middleware ─► OpenSearch        │   │                              │
 │                         (Lab 4, hcl-dx-search)            │   │                              │
 └───────────────────────────────────────────────────────────┘   └──────────────────────────────┘
```

- **`dx-demo`**: only what the HCL charts install (DX Compose, IQ and search). This is what HCL
  supports.
- **`dx-shared`**: we created this namespace **for every tool outside HCL** that the labs add.
  At a customer they are usually existing corporate infrastructure; keeping them apart makes clear
  what belongs to DX and what does not, allows different permissions and lets you reuse them.

| In `dx-shared` | Lab | Why it is not HCL and what we did |
|---|---|---|
| **OpenLDAP** | 2A | Lab user directory (community chart). At a customer it would be their LDAP or Active Directory |
| **PostgreSQL 18** (CloudNativePG operator) | 2B | HCL ships a PostgreSQL **16** (the *Persistence Node*), installed as the **DAM** persistence. For the Web Engine we preferred **our own version, PostgreSQL 18**: to use a more modern one and to reproduce the case of an installation that **already had its own PostgreSQL** |
| **LiteLLM** | 3A | **HCL does not supply it**, although it recommends it as the proxy between IQ and the AI models. We use the **official LiteLLM chart** (BerriAI) |
| **EUROPESIP MCP Server** | 3B | It is **our own** MCP server, not the one that comes with HCL (that one, `dx-iq-mcp-server`, ships with IQ in `dx-demo`). That is why it runs in the other namespace |

Namespace and release names, StorageClasses, host name and passwords are all variables in
`env.sh`: the defaults above are only the reference values.

## How to use this repository

### Step 1 · Clone the repository

To use these labs, first clone the repository and work from its root folder:

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
```

### Step 2 · Choose how to do the labs

There are two ways. Both install exactly the same thing.

#### Way 1 · By hand, following the guides (recommended)

This is the main path of the labs and the best one to learn.

1. **Create your configuration** `env.sh` (it is **never** committed: it is in `.gitignore`) and load it:

   ```bash
   cp env.example.sh env.sh        # your configuration
   vi env.sh                       # fill in the variables marked with  # <<<
                                   # (by default every lab password is EuropeS1P)
   source ./env.sh
   ```

2. **Do each lab in order** ([Lab 1](lab1-dx-base/GUIDE.md), then [Lab 2](lab2-ldap-postgres/GUIDE.md),
   [Lab 3](lab3-iq-openrouter/GUIDE.md) and [Lab 4](lab4-opensearch/GUIDE.md)). Open its guide and run its
   numbered scripts one by one, always from the root of the repository. For example, Lab 1:

   ```bash
   common/00-check-prereqs.sh       # check the requirements (read-only)
   common/01-namespaces.sh          # namespaces
   common/02-pull-hcl-charts.sh     # HCL charts from hclcr.io
   lab1-dx-base/01-secrets.sh       # secrets
   lab1-dx-base/02-install-dx.sh    # install DX
   lab1-dx-base/03-expose.sh        # external access
   lab1-dx-base/99-verify.sh        # check
   ```

   Every script can be read before running it, and the guide explains what it does and the
   equivalent command by hand. The scripts load `env.sh` by themselves.

#### Way 2 · With the configuration wizard (optional, experimental)

The [configuration wizard](https://europesip.github.io/hcl-dx-compose-labs/about.html) is an
**optional** web page (English / Spanish) that asks for your platform, host name, StorageClasses,
namespaces and the labs you want (pre-filled with the values of the reference lab environment) and
makes things easier in one of two ways:

- **It prepares the configuration for the manual path**:
  - **Option A · only `env.sh`**: you skip step 1 of Way 1 and continue with the labs.
  - **Option B · `env.sh` + `RUNBOOK.md`**: the same, plus a personalised guide with the scripts to
    run in order and the equivalent commands with your values.
- **Or it automates much more of the installation**:
  - **Option C · direct installation** (`dx-install/` folder): every file already filled in with
    your values and an `install.sh` that runs all the steps of the labs you chose, showing the lab
    and step it is in. It does not even need this repository, so it can be sent to someone who
    has nothing else (only `setup-postgres-dx.sql`, for Lab 2B, is copied in by hand). It carries
    credentials in plain text: keep it private.

    ```bash
    unzip dx-compose-labs-install.zip && cd dx-install && ./install.sh   # --list, --verify, --from <step>
    ```

The [about page](https://europesip.github.io/hcl-dx-compose-labs/about.html#options) compares the
three options side by side.

> ⚠️ **The wizard is a work in progress and must be treated as experimental.** The recommended path
> today is **Way 1, by hand**. It is a simplified option specific to these labs; EUROPESIP has
> another wizard developed internally, with advanced features and more customisation options,
> available on demand.

**Your credentials stay yours, and you can check it.** The wizard is a single `index.html` (plus
`about.html` with the explanations) in plain HTML, CSS and JavaScript (**no frameworks, no build,
no dependencies**). It runs **entirely in your browser**: a Content-Security-Policy
(`connect-src 'none'`) stops it from sending anything anywhere, and it never talks to your cluster.
Use it online on [GitHub Pages](https://europesip.github.io/hcl-dx-compose-labs/), or download it
and open it locally (it works offline). Source code: [docs/](docs/) and its own repository,
[europesip/hcl-dx-compose-labs-wizard](https://github.com/europesip/hcl-dx-compose-labs-wizard).

### Support and cleanup tools

Two tools you can use at any time, whatever the lab you are in:

| I want to... | Run | Details |
|---|---|---|
| **Open a case with HCL Support** because something fails | `common/collect-support-data.sh --case <number>` | Read-only. Collects what HCL asks for (technote KB0094817) into a `.tar.gz`, with secrets masked. [docs/support.md](docs/support.md) |
| **Start again from scratch** | `common/99-cleanup.sh` | Deletes the releases, volumes and both namespaces (asks for confirmation). [docs/cleanup.md](docs/cleanup.md) |

If you need both, collect first: once deleted, the logs are gone.

### What is in the repository

```
lab0-poc-wsl/              Lab 0 (optional): single-node PoC with k3s on WSL2
common/                    common steps and utilities
  00-check-prereqs.sh        checks tools, cluster, StorageClasses, DNS and credentials
  01-namespaces.sh           creates dx-demo and dx-shared (with SCC annotations on OpenShift)
  02-pull-hcl-charts.sh      login to hclcr.io and download of the CF238 charts
  dx-helm.sh                 the ONLY DX helm install/upgrade: base + the layers of each lab
  collect-support-data.sh    collects the data for an HCL Support case (.tar.gz)
  99-cleanup.sh              deletes everything to repeat the labs from scratch
lab1-dx-base/              Lab 1
lab2-ldap-postgres/        Lab 2 (a-ldap/ and b-postgres/; enterprise/ = Active Directory and Oracle)
lab3-iq-openrouter/        Lab 3 (06-iq-chat-test.sh: ask IQ from the terminal; custom-mcp/ = 3B)
lab4-opensearch/           Lab 4 (Search V2 with OpenSearch)
docs/                      requirements, Kubernetes vs OpenShift, troubleshooting, support data, cleanup
                           (and the configuration wizard, served by GitHub Pages)
tools/                     maintenance (keeps the wizard in sync with the labs, see CONTRIBUTING.md)
```

Every guide exists in English (`GUIDE.md`) and Spanish (`GUIDE.es.md`).

### DX configuration goes in layers

The chart `values.yaml` is never edited by hand and `--reuse-values` is never used. There is a base
`custom-values.yaml` (Lab 1) and every iteration adds its own small file:

```
helm upgrade --install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
  -f lab1-dx-base/custom-values.yaml                          # Lab 1: base
  -f lab2-ldap-postgres/a-ldap/custom-values.ldap.yaml         # Lab 2A: LDAP
  -f lab2-ldap-postgres/b-postgres/custom-values.postgres.yaml # Lab 2B: external database
  -f lab3-iq-openrouter/custom-values.iq.yaml                  # Lab 3: IQ
```

`common/dx-helm.sh` builds that command from what is already prepared in the cluster and shows it
before running it. Each layer can be read at a glance and explains exactly what changes.

## Requirements

> **Can you not access any Kubernetes cluster, neither local nor in the cloud?** Only in that
> case, start with [Lab 0 · PoC on your PC](lab0-poc-wsl/GUIDE.md): it builds single-node k3s in
> a new WSL2 distro (Windows 10/11, Home included), without touching your other distros, and lets
> you do the four labs. It is a **simplified, "tweaked" environment** (simulated StorageClasses and
> reduced resources) whose only goal is to check the installation steps.

Summary (details in [docs/requirements.md](docs/requirements.md)):

- **Account in the HCL Harbor** (`hclcr.io`) entitled to DX Compose: user and *CLI secret*.
- **Cluster**: Kubernetes 1.26 to 1.36 or OpenShift, x86-64, with ~8 CPU and ~16 GiB free for the labs.
- **StorageClasses** RWO and RWX (here `dx-deploy-rwo` and `dx-deploy-rwx`).
- **DNS** for the DX FQDN pointing to the Ingress or the router.
- **Workstation** with `kubectl`, `helm` (3.8+ or 4.x), `openssl`, `envsubst`, `curl` and `python3`.
- **Lab 3**: an [OpenRouter](https://openrouter.ai) API key with credit.

## Notices

- **PoC, not production.** See the notice at the top: a working installation, without the tuning
  and parameterisation of a production environment. For a real project, an HCL partner or HCL
  specialised services.
- **Licensed material.** The HCL charts and images are not in this repository: every attendee
  downloads them with their own account. `charts/` and the `.tgz` files are in `.gitignore`.
- **Web Engine on PostgreSQL (Lab 2B) is not supported by HCL yet in CF238** (DB2, Oracle and
  SQL Server are). HCL is validating it; the lab is for learning the transfer process.
- **OpenRouter is not validated by HCL** (LiteLLM is). The HCL guides use AWS Bedrock; Lab 3
  explains why we use OpenRouter and the deviations.
- The OpenLDAP, PostgreSQL, LiteLLM and custom MCP in `dx-shared` are sized for a lab (one
  replica, no internal TLS and no backups).

## Contributing and licence

Open source under the [Apache License 2.0](LICENSE): you can use, modify and redistribute these labs
and contribute improvements, keeping the [NOTICE](NOTICE) file and the attribution to
[EUROPESIP](https://www.europesip.com) as the original author. HCL charts and images are not
included and keep their own licence. How to contribute, and how to keep the wizard in sync with the
labs (`tools/sync-wizard-templates.py`): [CONTRIBUTING.md](CONTRIBUTING.md).
