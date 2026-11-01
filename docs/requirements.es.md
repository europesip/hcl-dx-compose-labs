# Requisitos previos

[English](requirements.md) · **Español**

> ⚠️ Estos labs dejan una instalación **funcional** de HCL DX Compose, pero son una **PoC** para
> aprender los pasos, no una instalación de producción: el *tuning* y la parametrización de un
> entorno productivo se han omitido. Para un proyecto real, recomendamos un **partner de HCL** o los
> **servicios especializados de HCL**.

Lo que tiene que estar listo **antes** del Lab 1. Casi todo es responsabilidad del administrador del
clúster; `common/00-check-prereqs.sh` lo comprueba sin modificar nada.

## 1. Estación de trabajo

Linux, macOS o WSL2 con acceso de red al API del clúster y a Internet (hclcr.io, ghcr.io,
openrouter.ai, repositorios de charts):

| Herramienta | Para qué |
|---|---|
| `kubectl` (y `oc` en OpenShift) | gestionar el clúster |
| `helm` 3.8+ o 4.x (probado con 4.3.1) | instalar los charts (soporte OCI) |
| `openssl` | generar el certificado TLS autofirmado |
| `envsubst` (paquete `gettext`) | rellenar las plantillas con las variables de `env.sh` |
| `curl`, `python3` | pruebas y comprobaciones |
| opcionales: `jq`, `stern`, `k9s` | diagnóstico |

## 2. Clúster

> **Solo si no es viable acceder a un entorno Kubernetes**, ni en local ni en la nube: el
> [Lab 0 · PoC en tu PC](../lab0-poc-wsl/GUIDE.es.md) monta un clúster de un nodo (k3s) en una distro de
> WSL2 con todo lo de esta página resuelto. Es un entorno **de PoC**, con las StorageClasses
> simuladas y los recursos rebajados, pensado solo para comprobar los pasos; no sirve como
> referencia de una instalación real.

- **Kubernetes 1.26 a 1.36** (CF238), certificado CNCF, o **Red Hat OpenShift**. Nodos **x86-64**.
- **Recursos libres** (requests medidos con los values de este repositorio):

  | Iteración | CPU | Memoria |
  |---|---|---|
  | Lab 1 · DX base | ~5 | ~11 GiB |
  | Lab 2 · OpenLDAP + PostgreSQL | +0,5 | +1 GiB |
  | Lab 3 · IQ + LiteLLM | +0,5 | +1,5 GiB |

  Con los límites, el pico de arranque ronda 8 CPU y 14 GiB. Repartido en varios nodos funciona.
- **Acceso de administrador** para crear namespaces. En OpenShift, si instala un usuario
  restringido, ver `common/openshift/rbac-dx-installer.yaml`.

## 3. StorageClasses

DX necesita una StorageClass **RWO** y otra **RWX**:

| Nombre en los labs | Modo | Quién la usa |
|---|---|---|
| `dx-deploy-rwo` | ReadWriteOnce | Web Engine (customization y log), Persistence Node, License Manager, PostgreSQL (CNPG), OpenLDAP |
| `dx-deploy-rwx` | ReadWriteMany | Binarios de DAM, compartidos entre pods |

Crearlas es tarea del administrador (NFS, Longhorn, ODF, Ceph, discos cloud...). En el clúster de
referencia de los labs son de Longhorn: [common/storageclasses-longhorn.yaml](../common/storageclasses-longhorn.yaml).
Si las tuyas tienen otro nombre, basta con indicarlo en `env.sh` (`SC_RWO` y `SC_RWX`, o en el
asistente de configuración): los scripts lo pasan a todos los charts.

## 4. Imágenes y charts: Harbor de HCL

Usamos directamente el registro oficial **`hclcr.io`**. El clúster descarga las imágenes con un
`imagePullSecret` (`regcred`) y la estación de trabajo descarga los charts con `helm pull` OCI:

| Artefacto | Ruta OCI |
|---|---|
| Chart DX Compose | `oci://hclcr.io/dx-compose/hcl-dx-deployment` (2.49.0) |
| Chart IQ | `oci://hclcr.io/dx/hcl-dx-iq` (1.0.2) |
| Imágenes | `hclcr.io/dx-compose/...` (los nombres y tags de CF238 vienen en el chart) |

Credenciales: el e-mail de tu cuenta HCL y el **CLI secret** de tu perfil en https://hclcr.io
(*User Profile → CLI secret*). Van en `env.sh` (`HCL_HARBOR_USER`, `HCL_HARBOR_TOKEN`).

> **Clústeres sin Internet (air-gapped).** Hay que copiar las imágenes y charts a un registro
> interno (por ejemplo con `skopeo copy` o el paquete de HCL Software Downloads), cambiar
> `images.repository` en los values y crear `regcred` contra ese registro. Fuera del alcance de estos labs.

## 5. DNS y certificado

- Un **FQDN** para DX (`DX_HOST`) que resuelva al Ingress Controller (Kubernetes) o al router de
  OpenShift. En el clúster de referencia hay un DNS comodín `*.apps.promox.europesip-lab.com`.
- **Certificado TLS**: el Lab 1 genera uno autofirmado (el navegador avisará). Para uno corporativo
  basta con exportar `TLS_CERT` (cadena completa: servidor, intermedia, raíz) y `TLS_KEY` (sin
  contraseña) antes de `lab1-dx-base/01-secrets.sh`.

## 6. Lab 2B: base de datos externa del Web Engine

En la demo, el PostgreSQL lo desplegamos nosotros en `dx-shared` con CloudNativePG y su preparación
va dentro del propio Lab 2B ([GUIDE.es.md](../lab2-ldap-postgres/GUIDE.es.md), paso 3), así que **no hay que
preparar nada antes**.

En un cliente real, en cambio, la base de datos suele existir ya y la gestiona un DBA, que debe
tenerla preparada **antes** de la transferencia, igual que la StorageClass o el DNS:

| Base de datos | Qué debe dejar preparado el DBA | Referencia |
|---|---|---|
| PostgreSQL | BD `dx_core` (UTF8), usuario `dxuser`, tablespaces del JCR, `max_prepared_transactions > 0`, y ejecutar `setup-postgres-dx.sql` (esquemas, roles, permisos, parámetros) | [GUIDE.es.md · 2B paso 3](../lab2-ldap-postgres/GUIDE.es.md) |
| Oracle 19c/21c | PDB en AL32UTF8, y ejecutar `setup-oracle-dx.sql` (usuarios, esquemas, roles, tablespaces) | [GUIDE-enterprise.es.md · ORA-1](../lab2-ldap-postgres/GUIDE-enterprise.es.md) |

En los dos casos **las tablas no se crean a mano**: las crea el Web Engine durante la
transferencia desde Derby.

## 7. Lab 3: OpenRouter

Una API key de https://openrouter.ai (`sk-or-v1-...`) con crédito. Con el prompt caching activado,
una conversación típica de IQ con Claude Sonnet cuesta céntimos. Las guías de HCL usan AWS Bedrock;
el [Lab 3](../lab3-iq-openrouter/GUIDE.es.md#por-qué-openrouter-y-no-aws-bedrock) explica por qué en estos
labs usamos OpenRouter (no hace falta cuenta de AWS).
