# Recoger datos para HCL Support

[English](support.md) · **Español**

Si algo falla y tienes que abrir un case con HCL Support, recoge los datos que te van a pedir
**antes** de cambiar o borrar nada:

```bash
common/collect-support-data.sh --case CS1234567
```

Es la gemela de [`common/99-cleanup.sh`](cleanup.es.md): una recoge y la otra borra. Es de **solo
lectura** (no cambia nada en el clúster) y deja un `container_mustgather_<case>_<fecha>.tar.gz` listo
para subirlo al case, siguiendo las *HTTPS and SFTP upload and download instructions* de HCL.

| Opción | Qué hace |
|---|---|
| `--case CS1234567` | Añade el número de case al nombre del fichero y al README |
| `--since 2h` | Solo los logs de las últimas 2 horas (por defecto, todos) |
| `--liberty-dump` | Además, un `server dump` de Liberty del Web Engine (logs, configuración, volcados de hilos) |
| `--out <dir>` | Dónde dejar el resultado (por defecto, la carpeta actual) |

## Qué recoge

Sigue la technote de HCL **«Collecting Data: HCL DX Containers on Kubernetes/OpenShift»
(KB0094817)**, con los mismos nombres de fichero para que HCL Support los reconozca, y con `oc` en
lugar de `kubectl` en OpenShift:

| Fichero | Contenido |
|---|---|
| `kube-version.txt`, `nodes.txt` | Versiones de Kubernetes y Helm, nodos |
| `pods.txt`, `describePods.txt`, `dx-resources.txt` | Pods, su `describe` y todos los objetos del namespace |
| `configmap.yaml`, `deployment.yaml` | ConfigMaps, Deployments y StatefulSets |
| `CRD.txt` | `describe` de las CRD relacionadas con los labs (la lista completa en `CRD-list.txt`) |
| `DX-PV.txt`, `DX-PVC.txt`, `core-pv.yaml`, `dam_pv.yaml` | Volúmenes; los del Web Engine y DAM los detecta solo |
| `event.txt` | Eventos del namespace |
| `currentLogs-<release>.txt` | Logs de cada release de Helm (`-l release=<release>`) |
| `non-running_pod*.txt` | Logs y `describe` de cualquier pod que no esté en marcha o listo |

Y lo que la technote no cubre para DX Compose:

- **Los logs de Open Liberty del Web Engine** (`web-engine/liberty-logs/`). La technote remite a
  `wpcollector`, pero esa herramienta es de DX Core sobre WebSphere: DX Compose ejecuta el Web Engine
  sobre Open Liberty y no la tiene.
- **Los logs de todos los contenedores**, del arranque actual y del anterior (`logs/`).
- **Las releases de Helm**: `helm ls`, los values del usuario y el historial (`helm/`).
- **El namespace de terceros** de los labs (PostgreSQL, OpenLDAP, LiteLLM, MCP propio), en una subcarpeta.

## Qué no recoge

- **Secrets**: solo sus nombres (`secret-names.txt`).
- **ConfigMaps sensibles**: el LDIF de demo (hashes de contraseñas) y el script de preparación de PostgreSQL.
- Antes de empaquetar, **enmascara** las contraseñas, claves y tokens de `env.sh`, la master key de
  LiteLLM y cualquier clave `sk-…`, valor de `LtpaToken2` o `Bearer`. El resultado se queda en una
  carpeta junto al `.tar.gz`: revísalo antes de enviarlo.

## Logs en modo debug

Para algunos problemas HCL Support necesita logs en modo debug, como explica la technote: sube el
nivel en el bloque `logging:` del componente en tus values (por ejemplo `api:server-v1:*=debug` para
DAM o IQ), ejecuta el `helm upgrade`, reproduce el problema y después recoge.
