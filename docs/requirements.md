# Prerequisites

**English** · [Español](requirements.es.md)

> ⚠️ These labs leave a **working** HCL DX Compose installation, but they are a **PoC** to learn
> the steps, not a production installation: the tuning and parameterisation of a production
> environment have been left out. For a real project we recommend an **HCL partner** or **HCL
> specialised services**.

What has to be ready **before** Lab 1. Almost everything is the cluster administrator's job;
`common/00-check-prereqs.sh` checks it without changing anything.

## 1. Workstation

Linux, macOS or WSL2 with network access to the cluster API and to the Internet (hclcr.io,
ghcr.io, openrouter.ai, chart repositories):

| Tool | What for |
|---|---|
| `kubectl` (and `oc` on OpenShift) | manage the cluster |
| `helm` 3.8+ or 4.x (tested with 4.3.1) | install the charts (OCI support) |
| `openssl` | generate the self-signed TLS certificate |
| `envsubst` (`gettext` package) | fill in the templates with the `env.sh` variables |
| `curl`, `python3` | tests and checks |
| optional: `jq`, `stern`, `k9s` | diagnostics |

## 2. Cluster

> **Only if you cannot access any Kubernetes environment**, local or in the cloud: [Lab 0 · PoC
> on your PC](../lab0-poc-wsl/GUIDE.md) builds a single-node cluster (k3s) in a WSL2 distro with
> everything on this page solved. It is a **PoC** environment, with simulated StorageClasses and
> reduced resources, meant only to check the steps; it is not a reference for a real installation.

- **Kubernetes 1.26 to 1.36** (CF239), CNCF certified, or **Red Hat OpenShift**. **x86-64** nodes.
- **Free resources** (requests measured with the values in this repository):

  | Iteration | CPU | Memory |
  |---|---|---|
  | Lab 1 · Base DX | ~5 | ~11 GiB |
  | Lab 2 · OpenLDAP + PostgreSQL | +0.5 | +1 GiB |
  | Lab 3 · IQ + LiteLLM | +0.5 | +1.5 GiB |

  With the limits, the start-up peak is around 8 CPU and 14 GiB. Spread over several nodes it works.
- **Administrator access** to create namespaces. On OpenShift, if a restricted user installs, see
  `common/openshift/rbac-dx-installer.yaml`.

## 3. StorageClasses

DX needs one **RWO** StorageClass and one **RWX** StorageClass:

| Name in the labs (`SC_RWO` / `SC_RWX`) | Mode | Used by |
|---|---|---|
| `dx-deploy-rwo` | ReadWriteOnce | Web Engine (customization and log), Persistence Node, License Manager, PostgreSQL (CNPG), OpenLDAP, OpenSearch |
| `dx-deploy-rwx` | ReadWriteMany | DAM binaries, shared between pods |

Creating them is the administrator's job (NFS, Longhorn, ODF, Ceph, cloud disks...). On the
reference lab cluster they are Longhorn: [common/storageclasses-longhorn.yaml](../common/storageclasses-longhorn.yaml).
If yours have other names, just set them in `env.sh` (`SC_RWO` and `SC_RWX`, or in the
configuration wizard): the scripts pass them to every chart.

## 4. Images and charts: HCL Harbor

We use the official **`hclcr.io`** registry directly. The cluster pulls the images with an
`imagePullSecret` (`regcred`) and the workstation downloads the charts with an OCI `helm pull`:

| Artefact | OCI path |
|---|---|
| DX Compose chart | `oci://hclcr.io/dx-compose/hcl-dx-deployment` (2.50.0) |
| IQ chart | `oci://hclcr.io/dx/hcl-dx-iq` (1.0.3) |
| Search chart (Lab 4) | `oci://hclcr.io/dx-compose/hcl-dx-search` (2.37.0) |
| Images | `hclcr.io/dx-compose/...` (the CF239 names and tags come in the chart) |

Credentials: the e-mail of your HCL account and the **CLI secret** of your profile at
https://hclcr.io (*User Profile → CLI secret*). They go in `env.sh` (`HCL_HARBOR_USER`,
`HCL_HARBOR_TOKEN`).

> **Clusters without Internet (air-gapped).** You have to copy the images and charts to an
> internal registry (for example with `skopeo copy` or the HCL Software Downloads package), change
> `images.repository` in the values and create `regcred` against that registry. Out of the scope of
> these labs.

## 5. DNS and certificate

- An **FQDN** for DX (`DX_HOST`) that resolves to the Ingress Controller (Kubernetes) or to the
  OpenShift router. The reference cluster has a wildcard DNS `*.apps.promox.europesip-lab.com`.
  Without DNS, a `nip.io` name (e.g. `dx.192.168.1.50.nip.io`) also works.
- **TLS certificate**: Lab 1 generates a self-signed one (the browser will warn). For a corporate
  one, export `TLS_CERT` (full chain: server, intermediate, root) and `TLS_KEY` (no passphrase)
  before `lab1-dx-base/01-secrets.sh`.

## 6. Lab 2B: external Web Engine database

In the labs we deploy PostgreSQL ourselves in `dx-shared` with CloudNativePG and its preparation is
part of Lab 2B itself ([GUIDE.md](../lab2-ldap-postgres/GUIDE.md), step 3), so **there is nothing
to prepare beforehand**.

At a real customer, however, the database usually already exists and is managed by a DBA, who must
have it ready **before** the transfer, just like the StorageClass or the DNS:

| Database | What the DBA must have ready | Reference |
|---|---|---|
| PostgreSQL | `dx_core` database (UTF8), `dxuser` user, JCR tablespaces, `max_prepared_transactions > 0`, and run `setup-postgres-dx.sql` (schemas, roles, grants, parameters) | [GUIDE.md · 2B step 3](../lab2-ldap-postgres/GUIDE.md) |
| Oracle 19c/21c | PDB in AL32UTF8, and run `setup-oracle-dx.sql` (users, schemas, roles, tablespaces) | [GUIDE-enterprise.md · ORA-1](../lab2-ldap-postgres/GUIDE-enterprise.md) |

In both cases **the tables are not created by hand**: the Web Engine creates them during the
transfer from Derby.

## 7. Lab 3: OpenRouter

An API key from https://openrouter.ai (`sk-or-v1-...`) with credit. With prompt caching enabled, a
typical IQ conversation with Claude Sonnet costs cents. The HCL guides use AWS Bedrock;
[Lab 3](../lab3-iq-openrouter/GUIDE.md#why-openrouter-and-not-aws-bedrock) explains why these labs
use OpenRouter (no AWS account needed).
