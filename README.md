# HCL DX Compose desde cero en Kubernetes (CF238)

Laboratorios del webinar **"Instalar HCL Digital Experience Compose paso a paso"**. Se parte de un
clúster vacío y se construye la plataforma en tres laboratorios, cada uno sobre el anterior:

| Lab | Qué se hace | ⏱ Ejecución |
|---|---|---|
| [Lab 1 · DX base](lab1-dx-base/GUIA.md) | Requisitos, namespaces, secrets, Helm chart desde el Harbor de HCL, instalación y acceso externo | ~10 min |
| [Lab 2 · LDAP y PostgreSQL](lab2-ldap-postgres/GUIA.md) | **2A**: autenticación contra un OpenLDAP. **2B**: transferencia de la base de datos del Web Engine de Derby a PostgreSQL | ~27 min (2A ~10 · 2B ~17) |
| ↳ [Lab 2 · rama empresarial](lab2-ldap-postgres/GUIA-empresa.md) *(opcional)* | Las mismas iteraciones contra **Active Directory** (con `configOverrideFiles`) y **Oracle** (TCPS), habituales en empresas corporativas | referencia |
| [Lab 3 · IQ con OpenRouter](lab3-iq-openrouter/GUIA.md) | **3A**: asistente de IA de DX (IQ) usando LiteLLM como proxy hacia OpenRouter (Claude). **3B**: MCP Server propio de EUROPESIP (servicios, soporte, laboratorios y la herramienta figma&web-to-dx) | ~13 min (3A ~10 · 3B ~3) |
| [Lab 4 · Búsqueda con OpenSearch](lab4-opensearch/GUIA.md) | Search V2: OpenSearch + Search Middleware (`hcl-dx-search` 2.36.0), certificados y `adminDN`, rastreo de WCM, portal y JCR y búsqueda por API | ~10 min |
| | **Total de ejecución** | **~60 min** |

Versiones: **HCL DX Compose 9.5 CF238**, charts `hcl-dx-deployment` **2.49.0**, `hcl-dx-iq`
**1.0.2** y `hcl-dx-search` **2.36.0**. Documentación oficial:
[Installing DX Compose (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/install/).

---

### Planificar el webinar

Los tiempos son de **ejecución**, medidos en tres instalaciones completas desde cero en el clúster
del webinar. Tenlos en cuenta al preparar la sesión:

- **Casi todo el tiempo es espera de Helm**: cada `helm upgrade` de DX reinicia el Web Engine
  (~5 min) y la transferencia del Lab 2B tarda ~14 min. Es el momento de explicar la teoría de la
  siguiente iteración.
- **Primera instalación en un clúster nuevo**: hay que sumar la descarga de las imágenes de HCL
  desde `hclcr.io`, que depende de la red. Para la sesión en directo conviene haber hecho antes una
  instalación de prueba (o una descarga previa) para que los nodos ya tengan las imágenes.
- **Labs independientes**: el 3 y el 4 solo necesitan el Lab 1. Si hay poco tiempo, el Lab 2B
  (el más largo) puede quedar como ejercicio para después.
- Con explicaciones y preguntas, calcula aproximadamente el doble del tiempo de ejecución.

## Entorno del webinar

Todo funciona en **Kubernetes estándar** y en **OpenShift** (ver
[docs/kubernetes-vs-openshift.md](docs/kubernetes-vs-openshift.md)). La demo se hace sobre:

| | |
|---|---|
| Distribución | **k3s v1.35** (3 masters + 3 workers, Ubuntu 24.04, x86-64) gestionado con Rancher |
| Almacenamiento | **Longhorn 1.12**: StorageClasses `dx-deploy-rwo` (RWO) y `dx-deploy-rwx` (RWX) |
| Entrada | **ingress-nginx** con MetalLB y DNS comodín `*.apps.promox.europesip-lab.com` |
| Imágenes y charts | **Harbor oficial de HCL** (`hclcr.io`), sin registro intermedio |
| Acceso a DX | `https://dx-demo.apps.promox.europesip-lab.com/wps/portal` |

## Arquitectura: dos namespaces

```
 ┌──────────────── dx-demo (software de HCL) ────────────────┐   ┌──── dx-shared (terceros) ────┐
 │                                                           │   │                              │
 │  Ingress ─► HAProxy ─► Web Engine (DX Compose) ───────────┼──►│  OpenLDAP          (Lab 2A)  │
 │                │            │                             │   │                              │
 │                │            └────── JDBC ─────────────────┼──►│  PostgreSQL 18     (Lab 2B)  │
 │                │                                          │   │   (operador CloudNativePG)   │
 │                ├─► DAM, Image Processor, Ring API...      │   │                              │
 │                │   Persistence Node (PostgreSQL de DAM)   │   │                              │
 │                │                                          │   │                              │
 │                ├─► IQ Integrator ─► IQ MCP Server         │   │                              │
 │                │        │                     (Lab 3)     │   │                              │
 │                │        └─────────────────────────────────┼──►│  LiteLLM ─► OpenRouter       │
 │                │        └─────────────────────────────────┼──►│  MCP propio        (Lab 3B)  │
 │                │                                          │   │                              │
 │                └─► Search Middleware ─► OpenSearch        │   │                              │
 │                         (Lab 4, hcl-dx-search)            │   │                              │
 └───────────────────────────────────────────────────────────┘   └──────────────────────────────┘
```

- **`dx-demo`**: solo lo que instalan los charts de HCL (DX Compose e IQ). Es lo que soporta HCL.
- **`dx-shared`**: infraestructura común que no es de HCL (directorio, base de datos, proxy de IA).
  En un cliente suele ser infraestructura corporativa ya existente; separarla deja claro qué es
  de DX y qué no, permite dar permisos distintos y reutilizarla entre entornos.

## Cómo usar este repositorio

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
cp env.example.sh env.sh        # tu configuración: env.sh NO se sube a git
vi env.sh                       # rellena las variables marcadas con  # <<<
                                # (por defecto todas las contraseñas del lab son EuropeS1P)
source ./env.sh
```

Después sigue las guías en orden. Cada paso es un script numerado que se puede leer antes de
ejecutarlo; las guías explican qué hace cada uno y el comando equivalente a mano.

```
common/                    pasos comunes y utilidades
  00-check-prereqs.sh        comprueba herramientas, clúster, StorageClasses, DNS y credenciales
  01-namespaces.sh           crea dx-demo y dx-shared (con anotaciones SCC si es OpenShift)
  02-pull-hcl-charts.sh      login en hclcr.io y descarga de los charts de CF238
  dx-helm.sh                 el ÚNICO helm install/upgrade de DX: base + capas de cada lab
  collect-logs.sh            recogida de logs para diagnóstico
  99-cleanup.sh              borra todo para repetir los labs desde cero
lab1-dx-base/              Lab 1
lab2-ldap-postgres/        Lab 2 (a-ldap/ y b-postgres/; empresa/ = Active Directory y Oracle)
lab3-iq-openrouter/        Lab 3 (06-iq-chat-test.sh: pregunta a IQ desde la terminal; mcp-propio/ = 3B)
lab4-opensearch/           Lab 4 (Search V2 con OpenSearch)
docs/                      requisitos, Kubernetes vs OpenShift, problemas frecuentes, limpieza
```

### La configuración de DX va por capas

Nunca se edita a mano el `values.yaml` del chart ni se usa `--reuse-values`. Hay un
`custom-values.yaml` base (Lab 1) y cada iteración añade su fichero pequeño:

```
helm upgrade --install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
  -f lab1-dx-base/custom-values.yaml                          # Lab 1: base
  -f lab2-ldap-postgres/a-ldap/custom-values.ldap.yaml         # Lab 2A: LDAP
  -f lab2-ldap-postgres/b-postgres/custom-values.postgres.yaml # Lab 2B: BD externa
  -f lab3-iq-openrouter/custom-values.iq.yaml                  # Lab 3: IQ
```

`common/dx-helm.sh` monta ese comando según lo que ya esté preparado en el clúster y lo muestra
antes de ejecutarlo. Cada capa se puede leer de un vistazo y explica exactamente qué cambia.

## Requisitos

Resumen (detalle en [docs/requisitos.md](docs/requisitos.md)):

- **Cuenta en el Harbor de HCL** (`hclcr.io`) con derecho a DX Compose: usuario y *CLI secret*.
- **Clúster** Kubernetes 1.26 a 1.36 o OpenShift, x86-64, con ~8 CPU y ~16 GiB libres para los tres labs.
- **StorageClasses** RWO y RWX (aquí `dx-deploy-rwo` y `dx-deploy-rwx`).
- **DNS** para el FQDN de DX apuntando al Ingress o al router.
- **Estación de trabajo** con `kubectl`, `helm` (3.8+ o 4.x), `openssl`, `envsubst`, `curl` y `python3`.
- **Lab 3**: una API key de [OpenRouter](https://openrouter.ai) con crédito.

## Avisos

- **Material licenciado.** Los charts e imágenes de HCL no están en este repositorio: cada asistente
  los descarga con su cuenta. `charts/` y los `.tgz` están en `.gitignore`.
- **Web Engine sobre PostgreSQL (Lab 2B) no está soportado todavía por HCL en CF238** (sí DB2,
  Oracle y SQL Server). HCL lo está validando; el lab sirve para aprender el proceso de
  transferencia.
- **OpenRouter no está validado por HCL** (LiteLLM sí). El Lab 3 explica las desviaciones.
- Los LDAP, PostgreSQL y LiteLLM de `dx-shared` están dimensionados para un laboratorio (una
  réplica, sin TLS interno y sin copias de seguridad).
