# HCL DX Compose desde cero en Kubernetes (CF238)

[English](README.md) · **Español** · [Asistente de configuración (opcional, experimental)](https://europesip.github.io/hcl-dx-compose-labs/about.html?lang=es)

Laboratorios prácticos para **instalar HCL Digital Experience Compose paso a paso**, a modo de
prueba de concepto (PoC). Se parte de un clúster Kubernetes u OpenShift ya existente, sin DX, y se
construye la plataforma en cuatro laboratorios, cada uno sobre el anterior.

> **Por dónde empezar.** Lo ideal es **empezar por el Lab 1**, sobre un clúster Kubernetes u
> OpenShift **ya instalado** que cumpla los [requisitos base](docs/requirements.es.md) (recursos,
> dos StorageClasses, un Ingress o router y DNS), en local o en la nube.
> El Lab 0 **no** forma parte de ese camino: ver *¿Sin clúster?* debajo de la tabla.

| Lab | Qué se hace | ⏱ Ejecución |
|---|---|---|
| ▶ [Lab 1 · DX base](lab1-dx-base/GUIDE.es.md) · **empieza aquí** | El inicio de la instalación: una **instalación base mínima y funcional** de DX Compose. Comprueba los requisitos base y cubre namespaces, secrets, el Helm chart desde el Harbor de HCL, la instalación y el acceso externo. El resto de labs se construye sobre ella | ~10 min |
| [Lab 2 · LDAP y PostgreSQL](lab2-ldap-postgres/GUIDE.es.md) | **2A**: autenticación contra un OpenLDAP. **2B**: transferencia de la base de datos del Web Engine de Derby a PostgreSQL | ~27 min (2A ~10 · 2B ~17) |
| ↳ [Lab 2 · rama empresarial](lab2-ldap-postgres/GUIDE-enterprise.es.md) *(opcional)* | Las mismas iteraciones contra **Active Directory** (con `configOverrideFiles`) y **Oracle** (TCPS), habituales en empresas corporativas | referencia |
| [Lab 3 · IQ con OpenRouter](lab3-iq-openrouter/GUIDE.es.md) | **3A**: asistente de IA de DX (IQ) usando LiteLLM como proxy hacia OpenRouter (Claude) en lugar de AWS Bedrock. **3B**: MCP Server propio de EUROPESIP (servicios, soporte, laboratorios y la herramienta figma&web-to-dx) | ~13 min (3A ~10 · 3B ~3) |
| [Lab 4 · Búsqueda con OpenSearch](lab4-opensearch/GUIDE.es.md) | Search V2: OpenSearch + Search Middleware (`hcl-dx-search` 2.36.0), certificados y `adminDN`, rastreo de WCM, portal y JCR y búsqueda por API | ~10 min |
| | **Total de ejecución** (Labs 1 a 4) | **~60 min** |

> **¿Sin clúster? Lab 0 (opcional).** Solo si **no tienes un entorno Kubernetes ya desplegado**
> donde hacer la PoC y quieres **emularlo en tu propio PC**: el [Lab 0 · PoC en tu
> PC](lab0-poc-wsl/GUIDE.es.md) monta un k3s de un nodo en una distro nueva de WSL2 (Windows 10/11),
> con las StorageClasses simuladas, el Ingress y recursos reducidos (~10 min). Después se sigue con el
> Lab 1 como todos los demás. Es un entorno de PoC simplificado, no de referencia: si puedes usar un
> clúster real, sáltatelo.

> ⚠️ **Laboratorios para aprender, no para producción.** Al terminar los labs se obtiene una
> instalación de HCL DX Compose **funcional**, pero están pensados como **PoC**: para entender y
> practicar los pasos de una instalación real. En un entorno productivo hay **muchos ajustes de
> *tuning* y de parametrización** (dimensionado de recursos y réplicas, alta disponibilidad,
> almacenamiento, rendimiento de la JVM y de las bases de datos, caché, seguridad, TLS interno,
> copias de seguridad, monitorización...) que permiten sacar el máximo partido al sistema y que,
> para no complicar los labs, **se han omitido**. Para un proyecto real, recomendamos contar
> siempre con un **partner de HCL** o con los **servicios especializados de HCL**.

Versiones: **HCL DX Compose 9.5 CF238**, charts `hcl-dx-deployment` **2.49.0**, `hcl-dx-iq`
**1.0.2** y `hcl-dx-search` **2.36.0**. Documentación oficial:
[Installing DX Compose (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/install/kubernetes_deployment/install/).

---

### Planificar las sesiones

Los labs sirven para una sesión en directo (webinar), un taller práctico o un curso de varios días.
Los tiempos son de **ejecución**, medidos en tres instalaciones completas desde cero en el clúster
de referencia de los labs. Tenlos en cuenta al planificar:

- **Casi todo el tiempo es espera de Helm**: cada `helm upgrade` de DX reinicia el Web Engine
  (~5 min) y la transferencia del Lab 2B tarda ~14 min. Es el momento de explicar la teoría de la
  siguiente iteración.
- **Primera instalación en un clúster nuevo**: hay que sumar la descarga de las imágenes de HCL
  desde `hclcr.io`, que depende de la red. Para la sesión en directo conviene haber hecho antes una
  instalación de prueba (o una descarga previa) para que los nodos ya tengan las imágenes.
- **Labs independientes**: el 3 y el 4 solo necesitan el Lab 1. Si hay poco tiempo, el Lab 2B
  (el más largo) puede quedar como ejercicio para después.
- Con explicaciones y preguntas, calcula aproximadamente el doble del tiempo de ejecución.

## Entorno de referencia de los labs

Todo funciona en **Kubernetes estándar** y en **OpenShift** (ver
[docs/kubernetes-vs-openshift.es.md](docs/kubernetes-vs-openshift.es.md)). Los labs se han construido y
validado sobre:

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

- **`dx-demo`**: solo lo que instalan los charts de HCL (DX Compose, IQ y la búsqueda). Es lo que
  soporta HCL.
- **`dx-shared`**: hemos creado este namespace **para todas las herramientas externas a HCL** que
  añadimos en los labs. En un cliente suelen ser infraestructura corporativa ya existente;
  separarlas deja claro qué es de DX y qué no, permite dar permisos distintos y reutilizarlas.

| En `dx-shared` | Lab | Por qué no es de HCL y qué hemos hecho |
|---|---|---|
| **OpenLDAP** | 2A | Directorio de usuarios de laboratorio (chart comunitario). En un cliente sería su LDAP o Active Directory |
| **PostgreSQL 18** (operador CloudNativePG) | 2B | HCL distribuye un PostgreSQL **16** (el *Persistence Node*), que se instala como persistencia de **DAM**. Para el Web Engine hemos preferido **nuestra propia versión, PostgreSQL 18**: por usar una más moderna y para ponernos en el caso de una instalación que **ya tuviera su PostgreSQL** |
| **LiteLLM** | 3A | **HCL no lo suministra**, aunque recomienda usarlo como proxy entre IQ y los modelos de IA. Usamos el **chart oficial de LiteLLM** (BerriAI) |
| **MCP Server de EUROPESIP** | 3B | Es **nuestro propio** servidor MCP, no el que viene con HCL (ese, `dx-iq-mcp-server`, va con IQ en `dx-demo`). Por eso corre en el namespace aparte |

Los nombres de namespaces y releases, las StorageClasses, el nombre de host y las contraseñas son
variables de `env.sh`: los de arriba son solo los valores de referencia.

## Cómo usar este repositorio

### Paso 1 · Clonar el repositorio

Para usar estos labs, primero clona el repositorio y trabaja desde su carpeta raíz:

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
```

### Paso 2 · Elegir cómo hacer los labs

Hay dos formas. Las dos instalan exactamente lo mismo.

#### Forma 1 · A mano, siguiendo las guías (recomendada)

Es el camino principal de los labs y el mejor para aprender.

1. **Crea tu configuración** `env.sh` (**nunca** se sube a git: está en `.gitignore`) y cárgala:

   ```bash
   cp env.example.sh env.sh        # tu configuración
   vi env.sh                       # rellena las variables marcadas con  # <<<
                                   # (por defecto todas las contraseñas del lab son EuropeS1P)
   source ./env.sh
   ```

2. **Haz cada lab en orden** ([Lab 1](lab1-dx-base/GUIDE.es.md), después [Lab 2](lab2-ldap-postgres/GUIDE.es.md),
   [Lab 3](lab3-iq-openrouter/GUIDE.es.md) y [Lab 4](lab4-opensearch/GUIDE.es.md)). Abre su guía y ejecuta
   sus scripts numerados uno a uno, siempre desde la raíz del repositorio. Por ejemplo, el Lab 1:

   ```bash
   common/00-check-prereqs.sh       # comprobar los requisitos (solo lectura)
   common/01-namespaces.sh          # namespaces
   common/02-pull-hcl-charts.sh     # charts de HCL desde hclcr.io
   lab1-dx-base/01-secrets.sh       # secrets
   lab1-dx-base/02-install-dx.sh    # instalar DX
   lab1-dx-base/03-expose.sh        # acceso externo
   lab1-dx-base/99-verify.sh        # comprobar
   ```

   Cada script se puede leer antes de ejecutarlo, y la guía explica qué hace y el comando
   equivalente a mano. Los scripts cargan `env.sh` por sí solos.

#### Forma 2 · Con el asistente de configuración (opcional, experimental)

El [asistente de configuración](https://europesip.github.io/hcl-dx-compose-labs/about.html?lang=es)
es una página web **opcional** (inglés / español) que pregunta tu plataforma, nombre de host,
StorageClasses, namespaces y los labs que quieres hacer (rellenos con los valores del entorno de
referencia de los labs) y te facilita las cosas de una de estas dos maneras:

- **Prepara la configuración para la vía manual**:
  - **Opción A · solo `env.sh`**: te saltas el paso 1 de la Forma 1 y sigues con los labs.
  - **Opción B · `env.sh` + `RUNBOOK.md`**: lo mismo, más una guía personalizada con los scripts que
    hay que ejecutar en orden y los comandos equivalentes con tus valores.
- **O automatiza mucho más la instalación**:
  - **Opción C · instalación directa** (carpeta `dx-install/`): todos los ficheros ya rellenos con tus
    valores y un `install.sh` que ejecuta todos los pasos de los labs elegidos, mostrando el lab y la
    fase en la que está. Ni siquiera necesita este repositorio, así que se puede enviar a alguien que
    no tenga nada más (solo hay que copiar a mano `setup-postgres-dx.sql`, para el Lab 2B). Lleva
    credenciales en claro: guárdala en privado.

    ```bash
    unzip dx-compose-labs-install.zip && cd dx-install && ./install.sh   # --list, --verify, --from <paso>
    ```

La [página de presentación](https://europesip.github.io/hcl-dx-compose-labs/about.html?lang=es#opciones)
compara las tres opciones lado a lado.

> ⚠️ **El asistente está en desarrollo (WIP) y debe tratarse como algo experimental.** Hoy la vía
> recomendada es la **Forma 1, a mano**. Es una opción simplificada y específica de estos labs;
> EUROPESIP tiene otro asistente desarrollado internamente, con funciones avanzadas y más opciones
> de personalización, disponible bajo demanda.

**Tus credenciales siguen siendo tuyas, y puedes comprobarlo.** El asistente es un único
`index.html` (más `about.html` con las explicaciones) con HTML, CSS y JavaScript sencillos (**sin
frameworks, sin compilación, sin dependencias**). Funciona **por completo en tu navegador**: una
Content-Security-Policy (`connect-src 'none'`) le impide enviar nada a ningún sitio, y nunca habla
con tu clúster. Úsalo en línea en [GitHub Pages](https://europesip.github.io/hcl-dx-compose-labs/?lang=es)
o descárgalo y ábrelo en local (funciona sin conexión). Código fuente: [docs/](docs/) y su propio
repositorio, [europesip/hcl-dx-compose-labs-wizard](https://github.com/europesip/hcl-dx-compose-labs-wizard).

### Qué hay en el repositorio

```
lab0-poc-wsl/              Lab 0 (opcional): PoC de un nodo con k3s en WSL2
common/                    pasos comunes y utilidades
  00-check-prereqs.sh        comprueba herramientas, clúster, StorageClasses, DNS y credenciales
  01-namespaces.sh           crea dx-demo y dx-shared (con anotaciones SCC si es OpenShift)
  02-pull-hcl-charts.sh      login en hclcr.io y descarga de los charts de CF238
  dx-helm.sh                 el ÚNICO helm install/upgrade de DX: base + capas de cada lab
  collect-logs.sh            recogida de logs para diagnóstico
  99-cleanup.sh              borra todo para repetir los labs desde cero
lab1-dx-base/              Lab 1
lab2-ldap-postgres/        Lab 2 (a-ldap/ y b-postgres/; enterprise/ = Active Directory y Oracle)
lab3-iq-openrouter/        Lab 3 (06-iq-chat-test.sh: pregunta a IQ desde la terminal; custom-mcp/ = 3B)
lab4-opensearch/           Lab 4 (Search V2 con OpenSearch)
docs/                      requisitos, Kubernetes vs OpenShift, problemas frecuentes, limpieza
                           (y el asistente de configuración, servido por GitHub Pages)
tools/                     mantenimiento (mantiene el asistente sincronizado con los labs, ver CONTRIBUTING.es.md)
```

Cada guía existe en inglés (`GUIDE.md`) y en español (`GUIDE.es.md`); los comentarios y mensajes
de los scripts están en inglés.

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

> **¿No puedes acceder a ningún clúster Kubernetes, ni en local ni en la nube?** Solo en ese caso,
> empieza por el [Lab 0 · PoC en tu PC](lab0-poc-wsl/GUIDE.es.md): monta k3s de un nodo en una distro
> nueva de WSL2 (Windows 10/11, también Home), sin tocar tus otras distros, y permite hacer los
> cuatro labs. Es un entorno **simplificado y "trucado"** (StorageClasses simuladas y recursos
> rebajados) cuyo único objetivo es comprobar los pasos de la instalación.

Resumen (detalle en [docs/requirements.es.md](docs/requirements.es.md)):

- **Cuenta en el Harbor de HCL** (`hclcr.io`) con derecho a DX Compose: usuario y *CLI secret*.
- **Clúster** Kubernetes 1.26 a 1.36 o OpenShift, x86-64, con ~8 CPU y ~16 GiB libres para los labs.
- **StorageClasses** RWO y RWX (aquí `dx-deploy-rwo` y `dx-deploy-rwx`).
- **DNS** para el FQDN de DX apuntando al Ingress o al router.
- **Estación de trabajo** con `kubectl`, `helm` (3.8+ o 4.x), `openssl`, `envsubst`, `curl` y `python3`.
- **Lab 3**: una API key de [OpenRouter](https://openrouter.ai) con crédito.

## Avisos

- **PoC, no producción.** Ver el aviso del principio: instalación funcional, sin el *tuning* ni la
  parametrización de un entorno productivo. Para un proyecto real, un partner de HCL o los servicios
  especializados de HCL.
- **Material licenciado.** Los charts e imágenes de HCL no están en este repositorio: cada asistente
  los descarga con su cuenta. `charts/` y los `.tgz` están en `.gitignore`.
- **Web Engine sobre PostgreSQL (Lab 2B) no está soportado todavía por HCL en CF238** (sí DB2,
  Oracle y SQL Server). HCL lo está validando; el lab sirve para aprender el proceso de
  transferencia.
- **OpenRouter no está validado por HCL** (LiteLLM sí). Las guías de HCL usan AWS Bedrock; el Lab 3
  explica por qué usamos OpenRouter y las desviaciones.
- El OpenLDAP, el PostgreSQL, LiteLLM y el MCP propio de `dx-shared` están dimensionados para un laboratorio (una
  réplica, sin TLS interno y sin copias de seguridad).

## Contribuir y licencia

Código abierto bajo la [Apache License 2.0](LICENSE): puedes usar, modificar y redistribuir estos
labs y contribuir mejoras, conservando el fichero [NOTICE](NOTICE) y la atribución a
[EUROPESIP](https://www.europesip.com) como autor original. Los charts e imágenes de HCL no están
incluidos y mantienen su propia licencia. Cómo contribuir, y cómo mantener el asistente sincronizado
con los labs (`tools/sync-wizard-templates.py`): [CONTRIBUTING.es.md](CONTRIBUTING.es.md).
