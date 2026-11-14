# HCL DX Compose from scratch on Kubernetes (CF239)

**English** · [Español](index.es.md)

Hands-on labs by EUROPESIP to **install HCL Digital Experience Compose step by step**, as a proof of concept (PoC).
You start from an existing Kubernetes or OpenShift cluster, without DX, and build the platform in four labs, each one
on top of the previous one. An advanced Lab 5 then deploys a complete application on top of it (Script Applications, a
microservice, persistence and AI). Open source (Apache License 2.0).

> This page is the summary for the developer portal. The full guide (the steps, the architecture, the notices) is the
> [README on GitHub](https://github.com/europesip/hcl-dx-compose-labs#readme), and every lab has its own guide in its
> folder (`GUIDE.md` in English, `GUIDE.es.md` in Spanish).

## Who it is for

- Anyone who wants to **understand and practise the steps of a real installation** of HCL DX Compose: in a live
  session (webinar), a hands-on workshop or a multi-day course.
- It is a **PoC, not production**: a working installation, without the tuning and parameterisation of a production
  environment (sizing, high availability, JVM and database performance, security, backups, monitoring...). For a real
  project, an HCL partner or HCL specialised services.

## The labs

The ideal path is to **start with Lab 1**, on a Kubernetes or OpenShift cluster that is already installed and meets the
[base requirements](requirements.md). Times are run times, measured on the reference lab cluster.

| Lab | What you do | ⏱ Run time |
|---|---|---|
| [External dependencies](https://github.com/europesip/hcl-dx-compose-labs/blob/main/external-deps/GUIDE.md) *(before Lab 1)* | The third-party software some labs use, installed first in the shared namespace: OpenLDAP (Lab 2A), PostgreSQL (Lab 3 appendix), LiteLLM (Lab 3A) and the EUROPESIP MCP Server (Lab 3B) | ~3-7 min |
| ▶ [Lab 1 · Base DX](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab1-dx-base/GUIDE.md) · **the only mandatory one** | A minimal, working base installation: requirements check, namespaces, secrets, the Helm chart from the HCL Harbor, the installation and external access | ~10 min |
| ↳ [Lab 1B · Sample Script Application](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab1b-scriptapp/GUIDE.md) *(optional)* | **Hello DX**, a React Script Application deployed with a Helm chart (a Job that runs DXClient) | ~1 min |
| [Lab 2 · LDAP and PostgreSQL](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab2-ldap-postgres/GUIDE.md) | **2A**: authentication against OpenLDAP. **2B**: the Web Engine database (Derby by default; the transfer to PostgreSQL needs a script that is not supplied yet) | ~27 min |
| ↳ [Lab 2 · enterprise branch](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab2-ldap-postgres/GUIDE-enterprise.md) *(optional)* | The same iterations against Active Directory (with `configOverrideFiles`) and Oracle (TCPS) | reference |
| [Lab 3 · IQ with OpenRouter](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab3-iq-openrouter/GUIDE.md) | **3A**: the DX AI assistant (IQ) with LiteLLM as a proxy to OpenRouter instead of AWS Bedrock. **3B**: the EUROPESIP custom MCP Server | ~13 min |
| [Lab 4 · Search with OpenSearch](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab4-opensearch/GUIDE.md) | Search V2: OpenSearch + Search Middleware (`hcl-dx-search`), certificates, crawling of WCM, portal and JCR, search through the API | ~10 min |
| | **Total run time** (Labs 1 to 4) | **~60 min** |
| ★ [Lab 5 · ÓRBITA, an advanced application](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab5-orbita/GUIDE.md) *(advanced, optional)* | An intranet suite deployed with one Helm chart: six Script Applications, a microservice, persistence in PostgreSQL and AI (its own assistant and an MCP server for HCL DX IQ). Needs Lab 1, PostgreSQL and Lab 2A | ~3 min |

**No cluster?** Only then, [Lab 0 · PoC on your PC](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab0-poc-wsl/GUIDE.md)
builds a single-node k3s in a new WSL2 distro (Windows 10/11), a simplified environment to check the installation steps
(~10 min). **Short on time?** `common/demo-fast.sh` installs everything you chose in the fastest order.

Versions: **HCL DX Compose 9.5 CF239**, charts `hcl-dx-deployment` **2.50.0**, `hcl-dx-iq` **1.0.3** and
`hcl-dx-search` **2.37.0**. Official documentation:
[Installing DX Compose (CF239)](https://help.hcl-software.com/digital-experience/dx-compose/CF239/deploy_dx/install/kubernetes_deployment/install/).

## Requirements

Summary (details in [Requirements](requirements.md)):

- **Account in the HCL Harbor** (`hclcr.io`) entitled to DX Compose: user and *CLI secret*.
- **Cluster**: Kubernetes 1.26 to 1.36 or OpenShift, x86-64, with ~8 CPU and ~16 GiB free for the labs
  ([Kubernetes vs OpenShift](kubernetes-vs-openshift.md)).
- **StorageClasses** RWO and RWX, and **DNS** for the DX FQDN pointing to the Ingress or the router.
- **Workstation** with `kubectl`, `helm` (3.8+ or 4.x), `openssl`, `envsubst`, `curl` and `python3`.
- **Lab 3**: an [OpenRouter](https://openrouter.ai) API key with credit.

## How to start

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
cp env.example.sh env.sh        # your configuration (never committed): fill in the variables marked with  # <<<
source ./env.sh
```

Then do each lab in order: open its guide and run its numbered scripts one by one, from the root of the repository
(Lab 1 starts with `common/00-check-prereqs.sh`). DX is configured **in layers**: a base `custom-values.yaml` and one
small values file per iteration, all applied by `common/dx-helm.sh`.

The optional, experimental [configuration wizard](https://europesip.github.io/hcl-dx-compose-labs/about.html) prepares
`env.sh` (and a personalised `RUNBOOK.md`) or a ready-to-run `dx-install/` folder; the
[DX Installer Wizard](https://github.com/europesip/hcl-dx-compose-installer) does the same with a step-by-step
interface, served by a container. The recommended path is still by hand, following the guides.

## When something fails

- [Troubleshooting](troubleshooting.md): frequent problems and their fixes.
- [Data for HCL Support](support.md): `common/collect-support-data.sh --case <number>` collects what HCL asks for.
- [Starting from scratch](cleanup.md): `common/99-cleanup.sh` deletes everything (collect the support data first).
- Deviations from the HCL documentation: [issues.md](https://github.com/europesip/hcl-dx-compose-labs/blob/main/issues.md).

## Links

- Source and guides: [GitHub](https://github.com/europesip/hcl-dx-compose-labs) ·
  [Roadmap](https://github.com/orgs/europesip/projects/4) · [How we work](workflow.md) ·
  [Contributing](https://github.com/europesip/hcl-dx-compose-labs/blob/main/CONTRIBUTING.md).
- Webinar slides *Deploy HCL DX Compose in Minutes* (12 November 2026):
  [PDF](https://github.com/europesip/hcl-dx-compose-labs/blob/main/webinar/deploy-dx-compose-in-minutes-2026-11-12.pdf).

Licence: [Apache License 2.0](https://github.com/europesip/hcl-dx-compose-labs/blob/main/LICENSE) (keep the
[NOTICE](https://github.com/europesip/hcl-dx-compose-labs/blob/main/NOTICE)). The HCL charts and images are not in the
repository: every user downloads them with their own HCL account.
