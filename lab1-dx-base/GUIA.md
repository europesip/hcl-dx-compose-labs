# Lab 1 · DX Compose base

**Objetivo:** instalar HCL DX Compose CF238 en el namespace `dx-demo` desde el Harbor oficial de
HCL y acceder al portal en `https://$DX_HOST/wps/portal`.

**Duración:** ~40 minutos, de los que ~25 son de espera mientras arrancan los pods.

Documentación de HCL:
[Installing DX Compose (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/install/) ·
[Preparation](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/preparation/)

```
 Paso 0  requisitos ──► Paso 1  namespaces ──► Paso 2  charts ──► Paso 3  secrets
                                                                      │
 Paso 6  comprobar ◄── Paso 5  Ingress/Route ◄── Paso 4  helm install ┘
```

Todos los comandos se lanzan **desde la raíz del repositorio** y con `env.sh` cargado:

```bash
cd hcl-dx-compose-labs
source ./env.sh
```

---

## Paso 0 · Requisitos

```bash
common/00-check-prereqs.sh
```

Comprueba herramientas, acceso al clúster, nodos, las StorageClasses `dx-deploy-rwo` y
`dx-deploy-rwx`, la IngressClass, el DNS de `DX_HOST` y que hay credenciales de Harbor. No cambia
nada. Si algo sale en `FALLO`, ver [docs/requisitos.md](../docs/requisitos.md).

## Paso 1 · Namespaces

```bash
common/01-namespaces.sh
```

Crea `dx-demo` (software de HCL) y `dx-shared` (software de terceros, se usa en los Labs 2 y 3).

| Plataforma | Qué hace |
|---|---|
| **Kubernetes (k3s)** | `kubectl create namespace dx-demo` y `dx-shared`. No hace falta nada más |
| **OpenShift** | Aplica `common/openshift/namespaces.yaml`: el namespace de DX lleva las anotaciones SCC que pide HCL para que los pods corran con UID 1000-1001 |

El porqué de esa diferencia está en [docs/kubernetes-vs-openshift.md](../docs/kubernetes-vs-openshift.md).

## Paso 2 · Charts desde el Harbor de HCL

```bash
common/02-pull-hcl-charts.sh
```

Equivale a:

```bash
printf '%s' "$HCL_HARBOR_TOKEN" | helm registry login hclcr.io -u "$HCL_HARBOR_USER" --password-stdin
helm pull oci://hclcr.io/dx-compose/hcl-dx-deployment --version 2.49.0 -d charts/
helm pull oci://hclcr.io/dx/hcl-dx-iq --version 1.0.2 -d charts/          # para el Lab 3
helm show values charts/hcl-dx-deployment-2.49.0.tgz > charts/values-dx-default-2.49.0.yaml
```

- Se podría instalar directamente desde `oci://`, pero descargarlo permite **ver qué trae el chart**
  (`tar xzf charts/hcl-dx-deployment-2.49.0.tgz`) y fijar la versión exacta.
- `charts/values-dx-default-2.49.0.yaml` son los ~3000 valores por defecto. **No se edita**: nuestra
  configuración es un fichero aparte con solo lo que cambia (paso 4). HCL no soporta cambios en
  las plantillas del chart, solo en los values.

## Paso 3 · Secrets

```bash
lab1-dx-base/01-secrets.sh
```

Crea en `dx-demo` los tres secrets que referencia `custom-values.yaml`:

| Secret | Tipo | Para qué |
|---|---|---|
| `regcred` | `docker-registry` | Que los nodos descarguen las imágenes de `hclcr.io` |
| `dx-tls-cert` | `tls` | Certificado que sirve HAProxy. Autofirmado con SAN = `DX_HOST`, salvo que exportes `TLS_CERT`/`TLS_KEY` |
| `web-engine-secret` | `generic` | Usuario `wpsadmin` y su contraseña (`WPSADMIN_PASSWORD`, por defecto `EuropeS1P`) |

Equivale a:

```bash
kubectl -n dx-demo create secret docker-registry regcred --docker-server=hclcr.io \
  --docker-username="$HCL_HARBOR_USER" --docker-password="$HCL_HARBOR_TOKEN"
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout dx-tls.key -out dx-tls.crt \
  -subj "/CN=$DX_HOST" -addext "subjectAltName=DNS:$DX_HOST"
kubectl -n dx-demo create secret tls dx-tls-cert --cert=dx-tls.crt --key=dx-tls.key
kubectl -n dx-demo create secret generic web-engine-secret \
  --from-literal=username=wpsadmin --from-literal=password="$WPSADMIN_PASSWORD"
```

> **Certificado corporativo:** concatena servidor → intermedia → raíz en un solo fichero
> (`cat server.crt intermediate.crt root.crt > full-chain.pem`) y exporta
> `TLS_CERT=full-chain.pem TLS_KEY=server.key` antes del script. La clave no puede tener contraseña.

## Paso 4 · Instalar DX

Primero, lee [custom-values.yaml](custom-values.yaml): es corto y cada bloque está comentado.

| Bloque | Qué decide |
|---|---|
| `images` | Registro `hclcr.io` y pull secret `regcred`. Nombres y tags de CF238 vienen en el chart |
| `volumes` | StorageClass y tamaño de cada PVC (RWX solo para DAM) |
| `applications` | DX Compose = `webEngine: true`, `core: false`. Sin OpenLDAP ni Remote Search de DX |
| `networking` | HAProxy como `ClusterIP` y su certificado. El host lo pone el script desde `DX_HOST` |
| `security.webEngine` | Credenciales de wpsadmin desde `web-engine-secret` (usuario/contraseña en claro a `null`) |

```bash
lab1-dx-base/02-install-dx.sh
```

Llama a `common/dx-helm.sh`, que muestra y ejecuta:

```bash
helm upgrade --install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
  -f lab1-dx-base/custom-values.yaml \
  --set-string networking.webEngine.host=$DX_HOST --timeout 30m --wait
```

> **Helm 4 y `--wait`.** En Helm 4, `--wait` usa la estrategia `watcher`, que **aborta** en cuanto un
> pod aparece como fallido. DAM falla de forma normal durante los primeros minutos (reintenta hasta
> que su PostgreSQL está listo), así que con Helm 4 hay que usar **`--wait=legacy`**, que espera
> hasta el `--timeout` como Helm 3. Los scripts lo eligen solos según la versión (`common/lib.sh`).

Mientras espera, en otra terminal:

```bash
kubectl -n dx-demo get pods -w
kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
```

Qué se va levantando:

| Pod | Función |
|---|---|
| `dx-deployment-web-engine-0` | **DX Compose**: portal, WCM, Practitioner Studio (Open Liberty). El más lento: ~10-15 min |
| `dx-deployment-haproxy-*` | Único punto de entrada; enruta a Web Engine, DAM, Ring API... |
| `dx-deployment-persistence-node-0`, `-connection-pool-*` | PostgreSQL interno de DAM y su pool |
| `dx-deployment-digital-asset-management-0`, `-image-processor-*` | DAM |
| `dx-deployment-ring-api-*`, `-content-composer-*`, `-runtime-controller-*` | API de DX, Content Composer, orquestación |

Al terminar, Helm muestra `STATUS: deployed`.

> **Reinicios normales al arrancar.** DAM puede pasar por `Error`/`CrashLoopBackOff`
> (`ECONNREFUSED ...:5432`) y el `persistence-connection-pool` reiniciarse una vez: arrancan antes
> que el Persistence Node y reintentan solos. En ~3 minutos quedan `Running`.

## Paso 5 · Acceso externo

```bash
lab1-dx-base/03-expose.sh
```

| Plataforma | Recurso |
|---|---|
| **Kubernetes** | [ingress-dx.yaml](ingress-dx.yaml): Ingress `nginx` que termina TLS con `dx-tls-cert` y re-cifra hacia `dx-deployment-haproxy:443`. Publica `/` entero |
| **OpenShift** | [route-dx-openshift.yaml](route-dx-openshift.yaml): Route `passthrough`; el TLS lo termina HAProxy |

Sin DNS o sin Ingress se puede probar con un port-forward:

```bash
kubectl -n dx-demo port-forward svc/dx-deployment-haproxy 8443:443
# https://localhost:8443/wps/portal
```

## Paso 6 · Comprobar

```bash
lab1-dx-base/99-verify.sh
```

Abre `https://$DX_HOST/wps/portal` y entra con **wpsadmin** / **EuropeS1P** (o tu `WPSADMIN_PASSWORD`).

- Portal y WCM: `https://$DX_HOST/wps/portal`
- Admin Center: `https://$DX_HOST/adminCenter`

> **Para el Lab 2:** crea ahora una página o un contenido de prueba (por ejemplo una página
> "Webinar"). En el Lab 2B comprobaremos que sobrevive a la transferencia de Derby a PostgreSQL.

---

**Siguiente:** [Lab 2 · LDAP y PostgreSQL](../lab2-ldap-postgres/GUIA.md)
