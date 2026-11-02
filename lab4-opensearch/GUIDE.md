# Lab 4 · Search (Search V2) with OpenSearch

**English** · [Español](GUIDE.es.md)

**Starting point:** Lab 1 finished (Labs 2 and 3 are independent of this one).

**⏱ Estimated time: ~10 minutes.**

| Step | Time |
|---|---|
| 1 · Certificates and secrets | seconds |
| 2 · Install `hcl-dx-search` (OpenSearch, Search Middleware, File Processor) | ~2 min |
| 3 · DX `helm upgrade` with Search V2 (restarts the Web Engine) | ~5 min |
| Check · `99-verify.sh --crawl` (triggers the crawlers and waits 90 s) | ~3 min |

> Run times measured on the reference lab cluster (k3s, 3 workers with 14 CPU / 20 GiB), without
> the explanations. The first time on a new cluster, add the download of the HCL images from
> `hclcr.io`, which depends on the network.

**Goal:** install the HCL search backend (**OpenSearch** + **Search Middleware**) and enable
**Search V2** in DX Compose: the Practitioner Studio Search Center, search over WCM, DAM and
portal, and its REST API.

HCL documentation:
[Enabling Search V2 (DX Compose CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_dx_compose/enable_search/) ·
[Installing the Search V2 backend (CF238)](https://help.hcl-software.com/digital-experience/9.5/CF238/deployment/install/container/helm_deployment/preparation/optional_tasks/optional_install_new_search/)

> DX Compose does **not** have the DX Core Remote Search: search is always Search V2 on OpenSearch
> ([Limitations](https://help.hcl-software.com/digital-experience/dx-compose/CF238/getting_started/product_overview/limitations/)).

```
 Browser ─► DX HAProxy ─► /dx/api/search, /dx/ui/search ─► dx-search-search-middleware-query
                                                                    │  (API, UI, ACL)
   Web Engine (WCM, JCR, portal) ◄── crawlers every 15 min ─────────┤
   DAM ─────────────── asset push (pushadmin) ──────────────────────┤
                                                                    ▼
                                              dx-search-open-search-manager-0 (OpenSearch)
```

| Component | Namespace | Chart |
|---|---|---|
| OpenSearch, Search Middleware and File Processor | **`dx-demo`** | HCL `hcl-dx-search` **2.36.0** (CF238) |

`hcl-dx-search` is HCL software and, moreover, **it has to be in the same namespace as DX**:
HAProxy routes to `<service>.<DX namespace>`, search locates the DX HAProxy to check permissions
(ACL) and both charts share the *push-admin* credential.

```bash
cd hcl-dx-compose-labs && source ./env.sh
```

### Node requirements

OpenSearch needs on **every node** `vm.max_map_count ≥ 262144` and `nofile ≥ 65536`. On the
reference cluster they are already set (1048576). To check:

```bash
kubectl -n dx-demo run sysctl-check --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c 'echo vm.max_map_count=$(cat /proc/sys/vm/max_map_count) nofile=$(ulimit -n)'
```

If not, on every node: `sysctl -w vm.max_map_count=262144` (and persist it in `/etc/sysctl.d/`).
On OpenShift it is done with a `Tuned` or a `MachineConfig`.

---

## Step 1 · Certificates

```bash
lab4-opensearch/01-certs.sh
```

OpenSearch and the Search Middleware communicate over **mutual TLS**. HCL asks for three
certificates signed by the same CA:

| Certificate | CN | Use |
|---|---|---|
| `admin` | `admin` (free) | OpenSearch administration. Its DN goes in `adminDN` |
| `node` | **`opensearch-node`** (preconfigured) | Communication between OpenSearch nodes |
| `client` | **`opensearch-client`** (preconfigured) | The Search Middleware as a client |

With the X.509 extensions HCL requires:

```
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
```

The script creates a lab CA, the three certificates (unencrypted PKCS#8 keys) and the secrets with
the names the chart expects:

| Secret | Content |
|---|---|
| `search-admin-cert` | `admin.pem`, `admin-key.pem`, `root-ca.pem` |
| `search-node-cert` | `node.pem`, `node-key.pem`, `root-ca.pem` |
| `search-client-cert` | `client.pem`, `client-key.pem`, `root-ca.pem` |

**The `adminDN`** (new in CF233-CF235). OpenSearch only accepts as administrator the certificate
whose DN matches **exactly** `configuration.openSearch.security.adminDN`, in **RFC 2253** format
(reverse order compared to `openssl -subj`: CN first). The script extracts it from the certificate
and writes it into `admin-dn.rendered.yaml`:

```yaml
configuration:
  openSearch:
    security:
      adminDN: 'CN=admin,OU=DX Compose Labs,O=EUROPESIP,C=ES'
```

> HCL recommends putting it in a values file (in single quotes) and **not** with `--set`: DNs
> with commas or special characters break the schema.

> **Corporate CA.** In a company, the three certificates are signed with its PKI (with the same CNs
> and extensions) and the same secrets are created. The `adminDN` is that of the admin certificate
> the company issues ([Using in-house CA or PKI for Search V2](https://help.hcl-software.com/digital-experience/9.5/CF238/deployment/install/container/helm_deployment/preparation/optional_tasks/optional_new_search_ca_certificates/)).

## Step 2 · Install the search backend

Read [custom-search-values.yaml](custom-search-values.yaml):

| Value | What for |
|---|---|
| `images.repository: hclcr.io` + `regcred` | CF238 images (`dx-compose/dx-opensearch`, `dx-search-middleware`) |
| `volumes.openSearchManager.data.storageClassName` | The chart default is `manual`: it has to be changed. The script sets `SC_RWO` from `env.sh` |
| `applications.fileProcessor: true` | Extracts the text of DAM documents (Office, PDF) to index it. The chart ships it as `false`, but without it the Search Middleware logs `Could not connect to file processor` every 3 s |
| `security.pushAdministration.deploymentReleaseName` | DX release it shares the *push-admin* credential with (`DX_RELEASE`, set by the script) |
| `configuration.automatedSetup.dxDeploymentName` | DX release (`DX_RELEASE`). It creates the content sources (WCM, JCR, portal, DAM) and their crawlers by itself |
| `configuration.automatedSetup.haproxyProtocol: https` | **Essential.** The crawlers and the permission checks call the DX HAProxy; by default they use `http` (port 80), but HAProxy only listens on 443 with TLS: without this, *timeout* and 0 documents |
| `automatedSetup.people.enabled: false` | People Service is not installed in these labs |

```bash
lab4-opensearch/02-search-install.sh
```

```bash
helm upgrade --install dx-search charts/hcl-dx-search-2.36.0.tgz -n dx-demo \
  -f lab4-opensearch/custom-search-values.yaml -f lab4-opensearch/admin-dn.rendered.yaml --wait
```

> **The release name matters: `dx-search`.** The DX chart looks for the search *push-admin*
> credential in `<searchReleaseName>-...` (`dx-search` by default) and the search chart looks for
> the DX one in `<deploymentReleaseName>-...` (`dx-deployment` by default). With those names and
> the same namespace, **both charts converge on the same password by themselves** and no
> credential secrets have to be created by hand.

Pods that appear:

| Pod | Function |
|---|---|
| `dx-search-open-search-manager-0` | OpenSearch (with `splitDeployment: false`, manager and data in the same pod) |
| `dx-search-search-middleware-query-*` | Search API and UI, permission checks, crawlers |
| `dx-search-file-processor-*` | Text extraction from documents |

## Step 3 · Enable Search V2 in DX

[custom-values.search.yaml](custom-values.search.yaml):

```yaml
networking:
  searchMiddlewareService: "dx-search-search-middleware-query"   # <release>-search-middleware-query
configuration:
  searchMiddleware:
    enabled: true          # Search V2 in DX Compose
    searchReleaseName: "dx-search"
    damIndexing: true      # DAM pushes its assets to the index
```

```bash
lab4-opensearch/03-dx-enable-search.sh
```

DX `helm upgrade` with the new layer: HAProxy starts routing `/dx/api/search/` and
`/dx/ui/search/` to the Search Middleware and the Web Engine enables Search V2.

> **Content sources and crawlers are created only once**, on the first installation, and stored
> in the OpenSearch index itself. Changing `automatedSetup` afterwards (for example
> `haproxyProtocol`) does not modify them: uninstall `dx-search`, delete its PVC
> (`data-dx-search-open-search-manager-0`) and install again.

## Check

```bash
lab4-opensearch/99-verify.sh --crawl Woodburn
```

It uses the search REST API (`https://$DX_HOST/dx/api/search/v2`, through the DX HAProxy):

1. Checks the DX values and that the API *explorer* answers.
2. Requests an administration token (`/admin/authenticate`) with the `searchadmin` credentials
   generated by the chart (secret `dx-search-search-middleware-admin`).
3. Lists the **content sources** and **crawlers** created by the *automated setup*.
4. With `--crawl`, **triggers every crawler now** (`/crawlers/{id}/trigger`) instead of waiting
   for their 15-minute schedule, and waits 90 s.
5. Searches for the given text as **wpsadmin** with `/mysearch`, which applies the user
   permissions.

Real result in the lab:

```
==> Content sources (created by automatedSetup)
  dam      dam_default_content_source
  wcm      wcm_default_content_source
  portal   portal_default_content_source
  jcr      jcr_default_content_source
==> Crawlers
  wcm     scheduled "*/15 * * * *"
  jcr     scheduled "*/15 * * * *"
  portal  scheduled "*/15 * * * *"
==> Search as wpsadmin (with their permissions): "Woodburn"
  results: 52
   - [Portal] Themes and Skins - Themes and Skins
   - [com.ibm.workplace.wcm.api.SiteArea] Hero-Carousel
   by type: com.ibm.workplace.wcm.api.sitearea = 28
   by type: com.ibm.workplace.wcm.api.content = 22
   by type: portal = 2
```

The number of results grows while the first WCM crawl finishes (in the lab: 20 after 90 s and 52
a few minutes later; repeat `./99-verify.sh Woodburn` without `--crawl`). After the first crawl
there are about 750 documents (WCM ≈500, portal ≈190, JCR ≈60). DAM shows 0 until assets are
uploaded: DAM is not crawled, it **pushes** every asset to the index (`damIndexing: true`) with the
*push-admin* credential.

> During the WCM crawl the Search Middleware log may show `Unable to retrieve subcomponents for
> document ...` warnings: they affect individual items of the sample content and do not prevent
> indexing the rest.

In the browser, as wpsadmin:

- **Search Center:** *Practitioner Studio → Web Content → Search*, or
  `https://$DX_HOST/wps/myportal/Practitioner/SearchCenter`
- **API:** `https://$DX_HOST/dx/api/search/v2/explorer`

> The WCM, JCR and portal crawlers run **every 15 minutes** (`crawlerSchedule`): right after the
> installation, searches may not return anything yet.


> **Tools.** If something fails and you need to open a case with HCL Support:
> `common/collect-support-data.sh --case <number>` ([support data](../docs/support.md)). To start the
> installation again from scratch: `common/99-cleanup.sh` ([cleanup](../docs/cleanup.md)).

---

**Back to the:** [README](../README.md) · **To start from scratch:** [docs/cleanup.md](../docs/cleanup.md)
