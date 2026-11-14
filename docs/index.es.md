# HCL DX Compose desde cero en Kubernetes (CF239)

[English](index.md) · **Español**

Laboratorios prácticos de EUROPESIP para **instalar HCL Digital Experience Compose paso a paso**, a modo de prueba de
concepto (PoC). Se parte de un clúster Kubernetes u OpenShift ya existente, sin DX, y se construye la plataforma en
cuatro laboratorios, cada uno sobre el anterior. Un Lab 5 avanzado despliega después una aplicación completa encima
(Script Applications, un microservicio, persistencia e IA). Software libre (Apache License 2.0).

> Esta página es el resumen para el portal del desarrollador. La guía completa (los pasos, la arquitectura, los avisos)
> es el [README en GitHub](https://github.com/europesip/hcl-dx-compose-labs/blob/main/README.es.md), y cada lab tiene su
> propia guía en su carpeta (`GUIDE.es.md` en español, `GUIDE.md` en inglés).

## Para quién es

- Para quien quiera **entender y practicar los pasos de una instalación real** de HCL DX Compose: en una sesión en
  directo (webinar), un taller práctico o un curso de varios días.
- Es una **PoC, no producción**: una instalación funcional, sin el *tuning* ni la parametrización de un entorno
  productivo (dimensionado, alta disponibilidad, rendimiento de la JVM y de las bases de datos, seguridad, copias de
  seguridad, monitorización...). Para un proyecto real, un partner de HCL o los servicios especializados de HCL.

## Los laboratorios

Lo ideal es **empezar por el Lab 1**, sobre un clúster Kubernetes u OpenShift ya instalado que cumpla los
[requisitos base](requirements.es.md). Los tiempos son de ejecución, medidos en el clúster de referencia de los labs.

| Lab | Qué se hace | ⏱ Ejecución |
|---|---|---|
| [Dependencias externas](https://github.com/europesip/hcl-dx-compose-labs/blob/main/external-deps/GUIDE.es.md) *(antes del Lab 1)* | El software de terceros que usan algunos labs, instalado primero en el namespace compartido: OpenLDAP (Lab 2A), PostgreSQL (apéndice del Lab 3), LiteLLM (Lab 3A) y el MCP Server de EUROPESIP (Lab 3B) | ~3-7 min |
| ▶ [Lab 1 · DX base](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab1-dx-base/GUIDE.es.md) · **el único obligatorio** | Una instalación base mínima y funcional: comprobación de requisitos, namespaces, secrets, el Helm chart desde el Harbor de HCL, la instalación y el acceso externo | ~10 min |
| ↳ [Lab 1B · Script Application de ejemplo](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab1b-scriptapp/GUIDE.es.md) *(opcional)* | **Hello DX**, una Script Application en React desplegada con un chart de Helm (un Job que ejecuta DXClient) | ~1 min |
| [Lab 2 · LDAP y PostgreSQL](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab2-ldap-postgres/GUIDE.es.md) | **2A**: autenticación contra un OpenLDAP. **2B**: la base de datos del Web Engine (Derby por defecto; la transferencia a PostgreSQL necesita un script que aún no se suministra) | ~27 min |
| ↳ [Lab 2 · rama empresarial](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab2-ldap-postgres/GUIDE-enterprise.es.md) *(opcional)* | Las mismas iteraciones contra Active Directory (con `configOverrideFiles`) y Oracle (TCPS) | referencia |
| [Lab 3 · IQ con OpenRouter](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab3-iq-openrouter/GUIDE.es.md) | **3A**: el asistente de IA de DX (IQ) con LiteLLM como proxy hacia OpenRouter en lugar de AWS Bedrock. **3B**: el MCP Server propio de EUROPESIP | ~13 min |
| [Lab 4 · Búsqueda con OpenSearch](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab4-opensearch/GUIDE.es.md) | Search V2: OpenSearch + Search Middleware (`hcl-dx-search`), certificados, rastreo de WCM, portal y JCR, búsqueda por API | ~10 min |
| | **Total de ejecución** (Labs 1 a 4) | **~60 min** |
| ★ [Lab 5 · ÓRBITA, una aplicación avanzada](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab5-orbita/GUIDE.es.md) *(avanzado, opcional)* | Una suite de intranet desplegada con un chart de Helm: seis Script Applications, un microservicio, persistencia en PostgreSQL e IA (su propio asistente y un servidor MCP para HCL DX IQ). Necesita el Lab 1, PostgreSQL y el Lab 2A | ~3 min |

**¿Sin clúster?** Solo entonces, el [Lab 0 · PoC en tu PC](https://github.com/europesip/hcl-dx-compose-labs/blob/main/lab0-poc-wsl/GUIDE.es.md)
monta un k3s de un nodo en una distro nueva de WSL2 (Windows 10/11), un entorno simplificado para comprobar los pasos de
la instalación (~10 min). **¿Poco tiempo?** `common/demo-fast.sh` instala todo lo que elegiste en el orden más rápido.

Versiones: **HCL DX Compose 9.5 CF239**, charts `hcl-dx-deployment` **2.50.0**, `hcl-dx-iq` **1.0.3** y
`hcl-dx-search` **2.37.0**. Documentación oficial:
[Installing DX Compose (CF239)](https://help.hcl-software.com/digital-experience/dx-compose/CF239/deploy_dx/install/kubernetes_deployment/install/).

## Requisitos

Resumen (detalle en [Requisitos](requirements.es.md)):

- **Cuenta en el Harbor de HCL** (`hclcr.io`) con derecho a DX Compose: usuario y *CLI secret*.
- **Clúster**: Kubernetes 1.26 a 1.36 u OpenShift, x86-64, con ~8 CPU y ~16 GiB libres para los labs
  ([Kubernetes frente a OpenShift](kubernetes-vs-openshift.es.md)).
- **StorageClasses** RWO y RWX, y **DNS** del FQDN de DX apuntando al Ingress o al router.
- **Puesto de trabajo** con `kubectl`, `helm` (3.8+ o 4.x), `openssl`, `envsubst`, `curl` y `python3`.
- **Lab 3**: una API key de [OpenRouter](https://openrouter.ai) con saldo.

## Cómo empezar

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
cp env.example.sh env.sh        # tu configuración (nunca se sube): rellena las variables marcadas con  # <<<
source ./env.sh
```

Después, haz cada lab en orden: abre su guía y ejecuta sus scripts numerados uno a uno, desde la raíz del repositorio
(el Lab 1 empieza con `common/00-check-prereqs.sh`). DX se configura **por capas**: un `custom-values.yaml` base y un
fichero de valores pequeño por iteración, todos aplicados por `common/dx-helm.sh`.

El [asistente de configuración](https://europesip.github.io/hcl-dx-compose-labs/about.html?lang=es), opcional y
experimental, prepara `env.sh` (y un `RUNBOOK.md` personalizado) o una carpeta `dx-install/` lista para ejecutar; el
[DX Installer Wizard](https://github.com/europesip/hcl-dx-compose-installer) hace lo mismo con una interfaz paso a
paso, servida por un contenedor. El camino recomendado sigue siendo a mano, siguiendo las guías.

## Cuando algo falla

- [Problemas frecuentes](troubleshooting.es.md): los problemas habituales y cómo se resuelven.
- [Datos para HCL Support](support.es.md): `common/collect-support-data.sh --case <número>` recoge lo que pide HCL.
- [Empezar de cero](cleanup.es.md): `common/99-cleanup.sh` lo borra todo (recoge antes los datos de soporte).
- Desviaciones respecto a la documentación de HCL:
  [issues.es.md](https://github.com/europesip/hcl-dx-compose-labs/blob/main/issues.es.md).

## Enlaces

- Código y guías: [GitHub](https://github.com/europesip/hcl-dx-compose-labs) ·
  [Roadmap](https://github.com/orgs/europesip/projects/4) · [Cómo trabajamos](workflow.es.md) ·
  [Cómo contribuir](https://github.com/europesip/hcl-dx-compose-labs/blob/main/CONTRIBUTING.es.md).
- Presentación del webinar *Deploy HCL DX Compose in Minutes* (12 de noviembre de 2026):
  [PDF](https://github.com/europesip/hcl-dx-compose-labs/blob/main/webinar/deploy-dx-compose-in-minutes-2026-11-12.pdf).

Licencia: [Apache License 2.0](https://github.com/europesip/hcl-dx-compose-labs/blob/main/LICENSE) (conservando el
fichero [NOTICE](https://github.com/europesip/hcl-dx-compose-labs/blob/main/NOTICE)). Los charts y las imágenes de HCL
no están en el repositorio: cada usuario los descarga con su propia cuenta de HCL.
