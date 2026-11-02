# Lab 1 · Base DX Compose

**English** · [Español](GUIDE.es.md)

**Starting point:** a Kubernetes or OpenShift cluster already installed that meets the
[base requirements](../docs/requirements.md) (or the single-node PoC of [Lab 0](../lab0-poc-wsl/GUIDE.md),
only if you have no cluster). This is where the installation starts.

**Goal:** a **minimal, working base installation**: install HCL DX Compose CF238 in the `dx-demo` namespace from the official HCL Harbor and
access the portal at `https://$DX_HOST/wps/portal`.

**⏱ Estimated time: ~10 minutes** (+ the image download the first time).

| Step | Time |
|---|---|
| 0-3 · Requirements, namespaces, charts and secrets | ~2 min |
| 4 · DX `helm install` (almost all of it is waiting while the pods start) | ~5 min |
| 5-6 · External access and check | ~1 min |

> Run times measured on the reference lab cluster (k3s, 3 workers with 14 CPU / 20 GiB), without
> the explanations. The first time on a new cluster, add the download of the HCL images from
> `hclcr.io`, which depends on the network.

HCL documentation:
[Installing DX Compose (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/install/) ·
[Preparation](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/preparation/)

```
 Step 0  requirements ──► Step 1  namespaces ──► Step 2  charts ──► Step 3  secrets
                                                                        │
 Step 6  check ◄── Step 5  Ingress/Route ◄── Step 4  helm install ──────┘
```

Every command is run **from the repository root** with `env.sh` loaded:

```bash
cd hcl-dx-compose-labs
source ./env.sh
```

> If you generated `env.sh` with the [configuration wizard](https://europesip.github.io/hcl-dx-compose-labs/),
> its `RUNBOOK.md` repeats these steps with your values (namespaces, releases, host,
> StorageClasses). It is optional: the steps in this guide are the same.

---

## Step 0 · Requirements

```bash
common/00-check-prereqs.sh
```

It checks the tools, cluster access, nodes, the `SC_RWO` and `SC_RWX` StorageClasses
(`dx-deploy-rwo` and `dx-deploy-rwx` by default), the IngressClass, the `DX_HOST` DNS and that
there are Harbor credentials. It changes nothing. If something shows `FAIL`, see
[docs/requirements.md](../docs/requirements.md).

## Step 1 · Namespaces

```bash
common/01-namespaces.sh
```

It creates the two lab namespaces (`DX_NS` and `SHARED_NS` in `env.sh`):

| Namespace | What goes inside |
|---|---|
| `dx-demo` | **HCL software only**: DX Compose (this lab), IQ (Lab 3) and search (Lab 4) |
| `dx-shared` | **Every tool outside HCL** that the labs add: OpenLDAP (2A), **our PostgreSQL 18** (2B; HCL ships a PostgreSQL 16 only as the DAM persistence), **LiteLLM** (3A; HCL does not supply it, although it recommends it as the proxy) and **our own MCP Server** (3B) |

Keeping them apart makes clear what is HCL (and therefore what HCL supports) and what is your own
or corporate infrastructure. In this lab `dx-shared` stays empty: it is used from Lab 2 on.

| Platform | What it does |
|---|---|
| **Kubernetes (k3s)** | `kubectl create namespace dx-demo` and `dx-shared`. Nothing else is needed |
| **OpenShift** | Applies `common/openshift/namespaces.yaml`: the DX namespace gets the SCC annotations HCL asks for so that the pods run with UID 1000-1001 |

The reason for that difference is in [docs/kubernetes-vs-openshift.md](../docs/kubernetes-vs-openshift.md).

## Step 2 · Charts from the HCL Harbor

```bash
common/02-pull-hcl-charts.sh
```

Equivalent to:

```bash
printf '%s' "$HCL_HARBOR_TOKEN" | helm registry login hclcr.io -u "$HCL_HARBOR_USER" --password-stdin
helm pull oci://hclcr.io/dx-compose/hcl-dx-deployment --version 2.49.0 -d charts/
helm pull oci://hclcr.io/dx/hcl-dx-iq --version 1.0.2 -d charts/                # for Lab 3
helm pull oci://hclcr.io/dx-compose/hcl-dx-search --version 2.36.0 -d charts/   # for Lab 4
helm show values charts/hcl-dx-deployment-2.49.0.tgz > charts/values-dx-default-2.49.0.yaml
```

- You could install straight from `oci://`, but downloading it lets you **see what the chart
  contains** (`tar xzf charts/hcl-dx-deployment-2.49.0.tgz`) and pin the exact version.
- `charts/values-dx-default-2.49.0.yaml` holds the ~3000 default values. **It is not edited**: our
  configuration is a separate file with only what changes (step 4). HCL does not support changes
  to the chart templates, only to the values.

## Step 3 · Secrets

```bash
lab1-dx-base/01-secrets.sh
```

It creates in `dx-demo` the three secrets referenced by `custom-values.yaml`:

| Secret | Type | What for |
|---|---|---|
| `regcred` | `docker-registry` | So that the nodes pull the images from `hclcr.io` |
| `dx-tls-cert` | `tls` | Certificate served by HAProxy. Self-signed with SAN = `DX_HOST`, unless you export `TLS_CERT`/`TLS_KEY` |
| `web-engine-secret` | `generic` | User `wpsadmin` and its password (`WPSADMIN_PASSWORD`, `EuropeS1P` by default) |

Equivalent to:

```bash
kubectl -n dx-demo create secret docker-registry regcred --docker-server=hclcr.io \
  --docker-username="$HCL_HARBOR_USER" --docker-password="$HCL_HARBOR_TOKEN"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout dx-tls.key -out dx-tls.crt \
  -subj "/CN=$DX_HOST" -addext "subjectAltName=DNS:$DX_HOST"
kubectl -n dx-demo create secret tls dx-tls-cert --cert=dx-tls.crt --key=dx-tls.key
kubectl -n dx-demo create secret generic web-engine-secret \
  --from-literal=username=wpsadmin --from-literal=password="$WPSADMIN_PASSWORD"
```

> **Corporate certificate:** concatenate server → intermediate → root into a single file
> (`cat server.crt intermediate.crt root.crt > full-chain.pem`) and export
> `TLS_CERT=full-chain.pem TLS_KEY=server.key` before the script. The key cannot have a passphrase.

## Step 4 · Install DX

First, read [custom-values.yaml](custom-values.yaml): it is short and every block is commented.

| Block | What it decides |
|---|---|
| `images` | `hclcr.io` registry and `regcred` pull secret. The CF238 names and tags come in the chart |
| `volumes` | StorageClass and size of each PVC (RWX only for DAM). The script sets the StorageClass names from `SC_RWO`/`SC_RWX` |
| `applications` | DX Compose = `webEngine: true`, `core: false`. Without the DX OpenLDAP or Remote Search |
| `networking` | HAProxy as `ClusterIP` and its certificate. The script sets the host from `DX_HOST` |
| `security.webEngine` | wpsadmin credentials from `web-engine-secret` (plain-text user/password set to `null`) |

```bash
lab1-dx-base/02-install-dx.sh
```

It calls `common/dx-helm.sh`, which shows and runs:

```bash
helm upgrade --install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
  -f lab1-dx-base/custom-values.yaml \
  --set-string networking.webEngine.host=$DX_HOST \
  --set-string volumes.webEngine.customization.storageClassName=$SC_RWO ... \
  --timeout 30m --wait
```

> **Helm 4 and `--wait`.** In Helm 4, `--wait` uses the `watcher` strategy, which **aborts** as
> soon as a pod shows up as failed. DAM fails normally during the first minutes (it retries until
> its PostgreSQL is ready), so with Helm 4 you must use **`--wait=legacy`**, which waits up to the
> `--timeout` like Helm 3. The scripts choose it by themselves depending on the version
> (`common/lib.sh`).

While it waits, in another terminal:

```bash
kubectl -n dx-demo get pods -w
kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
```

What comes up:

| Pod | Function |
|---|---|
| `dx-deployment-web-engine-0` | **DX Compose**: portal, WCM, Practitioner Studio (Open Liberty). The slowest one: ~10-15 min |
| `dx-deployment-haproxy-*` | Single entry point; routes to the Web Engine, DAM, Ring API... |
| `dx-deployment-persistence-node-0`, `-connection-pool-*` | DAM internal PostgreSQL and its pool |
| `dx-deployment-digital-asset-management-0`, `-image-processor-*` | DAM |
| `dx-deployment-ring-api-*`, `-content-composer-*`, `-runtime-controller-*` | DX API, Content Composer, orchestration |

When it finishes, Helm shows `STATUS: deployed`.

> **Normal restarts while starting.** DAM may go through `Error`/`CrashLoopBackOff`
> (`ECONNREFUSED ...:5432`) and the `persistence-connection-pool` may restart once: they start
> before the Persistence Node and retry by themselves. In ~3 minutes they are `Running`.

## Step 5 · External access

```bash
lab1-dx-base/03-expose.sh
```

| Platform | Resource |
|---|---|
| **Kubernetes** | [ingress-dx.yaml](ingress-dx.yaml): `nginx` Ingress that terminates TLS with `dx-tls-cert` and re-encrypts towards `dx-deployment-haproxy:443`. It publishes the whole `/` |
| **OpenShift** | [route-dx-openshift.yaml](route-dx-openshift.yaml): `passthrough` Route; TLS is terminated by HAProxy |

Without DNS or Ingress you can test with a port-forward:

```bash
kubectl -n dx-demo port-forward svc/dx-deployment-haproxy 8443:443
# https://localhost:8443/wps/portal
```

## Step 6 · Check

```bash
lab1-dx-base/99-verify.sh
```

Open `https://$DX_HOST/wps/portal` and log in with **wpsadmin** / **EuropeS1P** (or your
`WPSADMIN_PASSWORD`).

- Portal and WCM: `https://$DX_HOST/wps/portal`
- Admin Center: `https://$DX_HOST/adminCenter`

> **For Lab 2:** create a test page or content now (for example a "PoC" page or a WCM library
> `poc-transfer`). In Lab 2B we will check that it survives the transfer from Derby to PostgreSQL.


> **Tools.** If something fails and you need to open a case with HCL Support:
> `common/collect-support-data.sh --case <number>` ([support data](../docs/support.md)). To start the
> installation again from scratch: `common/99-cleanup.sh` ([cleanup](../docs/cleanup.md)).

---

**Next:** [Lab 2 · LDAP and PostgreSQL](../lab2-ldap-postgres/GUIDE.md)
