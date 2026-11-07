# Lab 4 · Búsqueda (Search V2) con OpenSearch

[English](GUIDE.md) · **Español**

**Punto de partida:** Lab 1 terminado (los Labs 2 y 3 son independientes de este).

**⏱ Tiempo estimado: ~10 minutos.**

| Paso | Tiempo |
|---|---|
| 1 · Certificados y secrets | segundos |
| 2 · Instalar `hcl-dx-search` (OpenSearch, Search Middleware, File Processor) | ~2 min |
| 3 · `helm upgrade` de DX con Search V2 (reinicia el Web Engine) | ~5 min |
| Comprobar · `99-verify.sh --crawl` (lanza los rastreadores y espera 90 s) | ~3 min |

> Tiempos de ejecución medidos en el clúster de referencia de los labs (k3s, 3 workers de 14 CPU / 20 GiB), sin
> contar las explicaciones. La primera vez en un clúster nuevo hay que sumar la descarga de las
> imágenes de HCL desde `hclcr.io`, que depende de la red.

**Objetivo:** instalar el backend de búsqueda de HCL (**OpenSearch** + **Search Middleware**) y
activar **Search V2** en DX Compose: el Search Center de Practitioner Studio, la búsqueda de WCM,
DAM y portal, y su API REST.

Documentación de HCL:
[Enabling Search V2 (DX Compose CF239)](https://help.hcl-software.com/digital-experience/dx-compose/CF239/deploy_dx/manage/cfg_dx_compose/enable_search/) ·
[Installing the Search V2 backend (CF239)](https://help.hcl-software.com/digital-experience/9.5/CF239/deployment/install/container/helm_deployment/preparation/optional_tasks/optional_install_new_search/)

> En DX Compose **no** existe el Remote Search de DX Core: la búsqueda es siempre Search V2 sobre
> OpenSearch ([Limitations](https://help.hcl-software.com/digital-experience/dx-compose/CF239/getting_started/product_overview/limitations/)).

```
 Navegador ─► HAProxy de DX ─► /dx/api/search, /dx/ui/search ─► dx-search-search-middleware-query
                                                                         │  (API, UI, ACL)
   Web Engine (WCM, JCR, portal) ◄── rastreadores cada 15 min ───────────┤
   DAM ─────────────── push de activos (pushadmin) ──────────────────────┤
                                                                         ▼
                                                   dx-search-open-search-manager-0 (OpenSearch)
```

| Componente | Namespace | Chart |
|---|---|---|
| OpenSearch, Search Middleware y File Processor | **`dx-demo`** | `hcl-dx-search` **2.37.0** (CF239) de HCL |

`hcl-dx-search` es software de HCL y, además, **tiene que estar en el mismo namespace que DX**:
HAProxy enruta a `<servicio>.<namespace de DX>`, la búsqueda localiza el HAProxy de DX para
comprobar permisos (ACL) y los dos charts comparten la credencial *push-admin*.

```bash
cd hcl-dx-compose-labs && source ./env.sh
```

### Requisitos de los nodos

OpenSearch necesita en **cada nodo** `vm.max_map_count ≥ 262144` y `nofile ≥ 65536`. En el
clúster de referencia ya están (1048576). Para comprobarlo:

```bash
kubectl -n dx-demo run sysctl-check --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c 'echo vm.max_map_count=$(cat /proc/sys/vm/max_map_count) nofile=$(ulimit -n)'
```

Si no, en cada nodo: `sysctl -w vm.max_map_count=262144` (y persistirlo en `/etc/sysctl.d/`).
En OpenShift se hace con un `Tuned` o un `MachineConfig`.

---

## Paso 1 · Certificados

```bash
lab4-opensearch/01-certs.sh
```

OpenSearch y el Search Middleware se comunican por **TLS mutuo**. HCL pide tres certificados
firmados por la misma CA:

| Certificado | CN | Uso |
|---|---|---|
| `admin` | `admin` (libre) | Administración de OpenSearch. Su DN va en `adminDN` |
| `node` | **`opensearch-node`** (preconfigurado) | Comunicación entre nodos de OpenSearch |
| `client` | **`opensearch-client`** (preconfigurado) | El Search Middleware como cliente |

Con las extensiones X.509 que exige HCL:

```
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
```

El script crea una CA del laboratorio, los tres certificados (claves PKCS#8 sin cifrar) y los
secrets con los nombres que espera el chart:

| Secret | Contenido |
|---|---|
| `search-admin-cert` | `admin.pem`, `admin-key.pem`, `root-ca.pem` |
| `search-node-cert` | `node.pem`, `node-key.pem`, `root-ca.pem` |
| `search-client-cert` | `client.pem`, `client-key.pem`, `root-ca.pem` |

**El `adminDN`** (novedad de CF233-CF235). OpenSearch solo acepta como administrador el
certificado cuyo DN coincide **exactamente** con `configuration.openSearch.security.adminDN`, en
formato **RFC 2253** (orden inverso al de `openssl -subj`: CN primero). El script lo extrae del
certificado y lo deja en `admin-dn.rendered.yaml`:

```yaml
configuration:
  openSearch:
    security:
      adminDN: 'CN=admin,OU=DX Compose Labs,O=EUROPESIP,C=ES'
```

> HCL recomienda ponerlo en un fichero de values (entre comillas simples) y **no** con `--set`:
> los DN con comas o caracteres especiales rompen el esquema.

> **CA corporativa.** En una empresa, los tres certificados se firman con su PKI (con los mismos
> CN y extensiones) y se crean los mismos secrets. El `adminDN` es el del certificado admin que
> emita la empresa ([Using in-house CA or PKI for Search V2](https://help.hcl-software.com/digital-experience/9.5/CF239/deployment/install/container/helm_deployment/preparation/optional_tasks/optional_new_search_ca_certificates/)).

## Paso 2 · Instalar el backend de búsqueda

Lee [custom-search-values.yaml](custom-search-values.yaml):

| Valor | Para qué |
|---|---|
| `images.repository: hclcr.io` + `regcred` | Imágenes de CF239 (`dx-compose/dx-opensearch`, `dx-search-middleware`) |
| `volumes.openSearchManager.data.storageClassName` | El chart trae `manual` por defecto: hay que cambiarlo. El script pone `SC_RWO` de `env.sh` |
| `applications.fileProcessor: true` | Extrae el texto de documentos de DAM (Office, PDF) para indexarlo. El chart lo trae a `false`, pero sin él el Search Middleware registra `Could not connect to file processor` cada 3 s |
| `security.pushAdministration.deploymentReleaseName` | Release de DX con la que comparte la credencial *push-admin* (`DX_RELEASE`, la pone el script) |
| `configuration.automatedSetup.dxDeploymentName` | Release de DX (`DX_RELEASE`). Crea solas las fuentes de contenido (WCM, JCR, portal, DAM) y sus rastreadores |
| `configuration.automatedSetup.haproxyProtocol: https` | **Imprescindible.** Los rastreadores y las comprobaciones de permisos llaman al HAProxy de DX; por defecto usan `http` (puerto 80), pero HAProxy solo escucha en 443 con TLS: sin esto, *timeout* y 0 documentos |
| `automatedSetup.people.enabled: false` | People Service no está instalado en estos labs |

```bash
lab4-opensearch/02-search-install.sh
```

```bash
helm upgrade --install dx-search charts/hcl-dx-search-2.37.0.tgz -n dx-demo \
  -f lab4-opensearch/custom-search-values.yaml -f lab4-opensearch/admin-dn.rendered.yaml --wait
```

> **El nombre de la release importa: `dx-search`.** El chart de DX busca la credencial
> *push-admin* de la búsqueda en `<searchReleaseName>-...` (por defecto `dx-search`) y el de
> búsqueda la de DX en `<deploymentReleaseName>-...` (por defecto `dx-deployment`). Con esos
> nombres y el mismo namespace, **los dos charts convergen solos en la misma contraseña** y no hay
> que crear secrets de credenciales a mano.

Pods que aparecen:

| Pod | Función |
|---|---|
| `dx-search-open-search-manager-0` | OpenSearch (con `splitDeployment: false`, gestor y datos en el mismo pod) |
| `dx-search-search-middleware-query-*` | API y UI de búsqueda, comprobación de permisos, rastreadores |
| `dx-search-file-processor-*` | Extracción de texto de documentos |

## Paso 3 · Activar Search V2 en DX

[custom-values.search.yaml](custom-values.search.yaml):

```yaml
networking:
  searchMiddlewareService: "dx-search-search-middleware-query"   # <release>-search-middleware-query
configuration:
  searchMiddleware:
    enabled: true          # Search V2 en DX Compose
    searchReleaseName: "dx-search"
    damIndexing: true      # DAM empuja sus activos al índice
```

```bash
lab4-opensearch/03-dx-enable-search.sh
```

`helm upgrade` de DX con la nueva capa: HAProxy empieza a enrutar `/dx/api/search/` y
`/dx/ui/search/` al Search Middleware y el Web Engine activa Search V2.

> **Las fuentes de contenido y los rastreadores se crean una sola vez**, en la primera
> instalación, y se guardan en el propio índice de OpenSearch. Cambiar después
> `automatedSetup` (por ejemplo `haproxyProtocol`) no los modifica: hay que desinstalar
> `dx-search`, borrar su PVC (`data-dx-search-open-search-manager-0`) e instalar de nuevo.

## Comprobar

```bash
lab4-opensearch/99-verify.sh --crawl Woodburn
```

Usa la API REST de búsqueda (`https://$DX_HOST/dx/api/search/v2`, entrando por HAProxy de DX):

1. Comprueba los valores de DX y que el *explorer* de la API responde.
2. Pide un token de administración (`/admin/authenticate`) con las credenciales de `searchadmin`
   que generó el chart (secret `dx-search-search-middleware-admin`).
3. Lista las **fuentes de contenido** y los **rastreadores** que creó el *automated setup*.
4. Con `--crawl`, **lanza ahora todos los rastreadores** (`/crawlers/{id}/trigger`) en lugar de
   esperar a los 15 minutos de su programación, y espera 90 s.
5. Busca el texto indicado como **wpsadmin** con `/mysearch`, que aplica los permisos del usuario.

Resultado real en el laboratorio (los mensajes de los scripts están en inglés):

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

El número de resultados crece mientras termina el primer rastreo de WCM (en el laboratorio: 20 a
los 90 s y 52 unos minutos después; repite `./99-verify.sh Woodburn` sin `--crawl`). Tras el
primer rastreo hay unos 750 documentos (WCM ≈500, portal ≈190, JCR ≈60). DAM aparece con
0 hasta que se suben activos: DAM no se rastrea, **empuja** cada activo al índice
(`damIndexing: true`) con la credencial *push-admin*.

> Durante el rastreo de WCM pueden aparecer en el log del Search Middleware avisos
> `Unable to retrieve subcomponents for document ...`: afectan a elementos sueltos del contenido
> de ejemplo y no impiden indexar el resto.

En el navegador, como wpsadmin:

- **Search Center:** *Practitioner Studio → Web Content → Search*, o
  `https://$DX_HOST/wps/myportal/Practitioner/SearchCenter`
- **API:** `https://$DX_HOST/dx/api/search/v2/explorer`

> Los rastreadores de WCM, JCR y portal se ejecutan **cada 15 minutos** (`crawlerSchedule`): justo
> después de instalar, las búsquedas pueden no devolver nada todavía.


> **Herramientas.** Si algo falla y tienes que abrir un case con HCL Support:
> `common/collect-support-data.sh --case <número>` ([datos para soporte](../docs/support.es.md)). Para
> empezar la instalación de cero: `common/99-cleanup.sh` ([limpieza](../docs/cleanup.es.md)).

---

**Volver al:** [README](../README.es.md) · **Para empezar de cero:** [docs/cleanup.es.md](../docs/cleanup.es.md)
