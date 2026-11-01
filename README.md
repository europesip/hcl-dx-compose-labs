# HCL DX Compose from scratch on Kubernetes (CF238)

**English** · [Español](README.es.md) · [Configuration wizard (optional)](https://europesip.github.io/hcl-dx-compose-labs/)

Hands-on labs to **install HCL Digital Experience Compose step by step**, as a proof of concept
(PoC). You start from an empty cluster and build the platform in four labs, each one on top of the
previous one:

| Lab | What you do | ⏱ Run time |
|---|---|---|
| [Lab 0 · PoC on your PC](lab0-poc-wsl/GUIDE.md) *(optional)* | **Only if you cannot access any Kubernetes cluster**, local or in the cloud: single-node k3s in a new WSL2 distro, with simulated StorageClasses, the Ingress and reduced resources. A PoC environment, not a reference one | ~10 min |
| [Lab 1 · Base DX](lab1-dx-base/GUIDE.md) | Requirements, namespaces, secrets, Helm chart from the HCL Harbor, installation and external access | ~10 min |
| [Lab 2 · LDAP and PostgreSQL](lab2-ldap-postgres/GUIDE.md) | **2A**: authentication against OpenLDAP. **2B**: transfer of the Web Engine database from Derby to PostgreSQL | ~27 min (2A ~10 · 2B ~17) |
| ↳ [Lab 2 · enterprise branch](lab2-ldap-postgres/GUIDE-enterprise.md) *(optional)* | The same iterations against **Active Directory** (with `configOverrideFiles`) and **Oracle** (TCPS), common in corporate environments | reference |
| [Lab 3 · IQ with OpenRouter](lab3-iq-openrouter/GUIDE.md) | **3A**: the DX AI assistant (IQ) using LiteLLM as a proxy to OpenRouter (Claude) instead of AWS Bedrock. **3B**: EUROPESIP custom MCP Server (services, support, labs and the figma&web-to-dx tool) | ~13 min (3A ~10 · 3B ~3) |
| [Lab 4 · Search with OpenSearch](lab4-opensearch/GUIDE.md) | Search V2: OpenSearch + Search Middleware (`hcl-dx-search` 2.36.0), certificates and `adminDN`, crawling of WCM, portal and JCR, and search through the API | ~10 min |
| | **Total run time** | **~60 min** |

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

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
```

Then create your `env.sh` (it is **never** committed: it is in `.gitignore`) in one of two ways.
Both produce the same result and the scripts work the same way:

**A. By hand** (what the guides describe):

```bash
cp env.example.sh env.sh        # your configuration
vi env.sh                       # fill in the variables marked with  # <<<
                                # (by default every lab password is EuropeS1P)
source ./env.sh
```

**B. With the optional [configuration wizard](https://europesip.github.io/hcl-dx-compose-labs/)**:
a static web page (English / Spanish) that asks for your platform, host name, StorageClasses,
namespaces and the labs you want, and downloads a ZIP with:

- `env.sh`: only your values; it then loads `env.example.sh` for every other default.
- `RUNBOOK.md`: your personalised, read-only list of steps with the scripts to run and the
  equivalent `kubectl` / `helm` commands with your values.

The wizard runs **entirely in your browser**: nothing you type is sent anywhere, and secrets
(Harbor token, OpenRouter key, passwords) can be left empty and filled in later in `env.sh`. The
scripts are still what installs everything; the wizard never talks to your cluster.

After that, follow the guides in order. Every step is a numbered script you can read before
running it; the guides explain what each one does and the equivalent command by hand.

```
lab0-poc-wsl/              Lab 0 (optional): single-node PoC with k3s on WSL2
common/                    common steps and utilities
  00-check-prereqs.sh        checks tools, cluster, StorageClasses, DNS and credentials
  01-namespaces.sh           creates dx-demo and dx-shared (with SCC annotations on OpenShift)
  02-pull-hcl-charts.sh      login to hclcr.io and download of the CF238 charts
  dx-helm.sh                 the ONLY DX helm install/upgrade: base + the layers of each lab
  collect-logs.sh            log collection for diagnostics
  99-cleanup.sh              deletes everything to repeat the labs from scratch
lab1-dx-base/              Lab 1
lab2-ldap-postgres/        Lab 2 (a-ldap/ and b-postgres/; enterprise/ = Active Directory and Oracle)
lab3-iq-openrouter/        Lab 3 (06-iq-chat-test.sh: ask IQ from the terminal; custom-mcp/ = 3B)
lab4-opensearch/           Lab 4 (Search V2 with OpenSearch)
docs/                      requirements, Kubernetes vs OpenShift, troubleshooting, cleanup
                           (and docs/index.html: the configuration wizard, served by GitHub Pages)
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
