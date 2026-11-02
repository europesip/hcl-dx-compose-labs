# Problemas frecuentes

[English](troubleshooting.md) · **Español**

Si tienes que abrir un case con HCL Support: `common/collect-support-data.sh --case <número>` recoge todo lo que piden en un `.tar.gz` (ver [support.es.md](support.es.md)).

## Lab 1

| Síntoma | Causa probable | Solución |
|---|---|---|
| DAM en `Error`/`CrashLoopBackOff` (`ECONNREFUSED ...:5432`) y `persistence-connection-pool` con 1 reinicio durante los primeros minutos | **Normal.** DAM y PgPool arrancan antes que el Persistence Node; se reintentan solos | Esperar: en ~3 minutos quedan `Running` (en el clúster de referencia, 5 reinicios de DAM) |
| `Error: resource StatefulSet/.../dx-deployment-digital-asset-management not ready. status: Failed` y la release en `failed` | **Helm 4**: `--wait` usa la estrategia `watcher`, que aborta ante el primer fallo, y DAM falla de forma normal al arrancar | Los scripts ya usan `--wait=legacy` con Helm 4 (`common/lib.sh`). Si lo lanzaste a mano, repite el comando con `--wait=legacy`: `upgrade --install` completa la release sin borrar nada |
| `ErrImagePull` / `ImagePullBackOff` con `unauthorized` | `regcred` con credenciales erróneas o cuenta sin derecho a DX Compose | Revisa `HCL_HARBOR_USER`/`HCL_HARBOR_TOKEN` (es el *CLI secret*, no la contraseña web) y vuelve a ejecutar `lab1-dx-base/01-secrets.sh` |
| `helm pull` → `unauthorized` | Falta el login en hclcr.io | `common/02-pull-hcl-charts.sh` hace el login; comprueba las credenciales |
| `The secret 'web-engine-secret' ... could not be found` | Se instaló antes de crear los secrets o en otro namespace | `lab1-dx-base/01-secrets.sh` y repetir |
| PVC en `Pending` | No existe la StorageClass, o RWX sin soporte (Longhorn necesita `nfs-common` en los nodos) | `kubectl describe pvc ...`; ver docs/requirements.es.md |
| Pods en `Pending` por `Insufficient cpu/memory` | Faltan recursos | `kubectl describe pod ...`; libera recursos o añade nodos |
| `helm` termina por timeout pero los pods siguen arrancando | La primera descarga de imágenes es lenta | Espera a que estén `Running` y repite `common/dx-helm.sh` (es idempotente) |
| 502/503 en el navegador | Web Engine aún arrancando | `kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log` |
| 404 en `/adminCenter` u otra ruta | Ingress que solo publica algunas rutas | Usa el de `lab1-dx-base/ingress-dx.yaml` (publica `/`) |

## Lab 2A · LDAP

| Síntoma | Causa probable | Solución |
|---|---|---|
| Los usuarios del LDAP no pueden entrar, wpsadmin sí | Bind incorrecto o LDAP inalcanzable | `./02-ldap-test.sh`; revisa `dx-ldap-bind` y busca `CWIML` en `kubectl -n dx-demo logs dx-deployment-web-engine-0 -c system-out-log` |
| `02-ldap-test.sh` → `No such object (32)` y `openldap-0` con 1 reinicio (exit 123) | El LDIF propio no incluye la entrada raíz y el primer `ldapadd` falla | `demo-users.ldif` ya trae `dn: dc=dxdemo,dc=com`; si lo cambias, mantenla. Reinstala como en la fila siguiente |
| El LDAP arranca sin los usuarios de demo | El LDIF solo se carga en el primer arranque, con el PVC vacío | `helm -n dx-shared uninstall openldap`, borra el PVC `data-openldap-0` y vuelve a `./01-ldap-install.sh` |
| Usuarios OK pero sin grupos | Grupos con otra objectClass | El chart de DX busca `groupOfUniqueNames` / `uniqueMember` |

## Lab 2B · PostgreSQL

| Síntoma | Causa probable | Solución |
|---|---|---|
| `kubectl get cluster` devuelve otra cosa | En Rancher, `cluster` es de Cluster API | Usa `kubectl get clusters.postgresql.cnpg.io` |
| La transferencia falla con errores de XA / prepared transactions | `max_prepared_transactions` a 0 | Viene a 500 en `cluster-dx-pg.yaml`; compruébalo con `./99-verify.sh` |
| `ERROR: invalid escape string` en `WCM_USER_SHORTCUT` | `standard_conforming_strings=on` en `dx_core` (OpenJPA usa `ESCAPE '\\'`) | `setup-postgres-dx.sql` ya lo pone a `off`. En un cluster creado antes: `ALTER DATABASE dx_core SET standard_conforming_strings = off` y reinicia el Web Engine |
| Avisos `DSRA8020E: ... property 'driverType' does not exist ... org.postgresql` | Liberty aplica una propiedad propia de DB2 al datasource | **Normal**, es un aviso (`W`): se ignora |
| `password authentication failed for user "dxuser"` | Contraseña distinta en el secret de CNPG y en las properties | Mismo `DXUSER_PASSWORD` en `02-secrets-postgres.sh` y `04-secrets-webengine.sh` (repite ambos y reinicia el Web Engine) |
| La transferencia no se repite tras un error | El Web Engine ya registró un intento | Corrige la causa; si dx_core quedó con tablas, `dropDatabaseTables: true` solo para ese upgrade y vuelve a `false` |

## Lab 3 · IQ

| Síntoma | Causa probable | Solución |
|---|---|---|
| No aparece el botón de IQ | Falta `networking.dxIqService` | `./05-dx-enable-iq.sh` |
| IQ responde "error" a todo | LiteLLM no responde u OpenRouter rechaza la clave | `./03-litellm-test.sh` y `./99-verify.sh` |
| HTTP 400 de Claude con nombres de herramienta | Modelo configurado con el proveedor `openrouter/` | Usa `anthropic/<id>` con `api_base: https://openrouter.ai/api` (ver `litellm-values.yaml`) |
| El Integrator llama a una URL de HCL desconocida | Falta `LITELLM_BASE_URL` | Está en `custom-iq-values.yaml` (`environment.pod.integrator`) |
| `fetch failed` hacia `litellm.dx-shared` | NetworkPolicy que aísla namespaces (habitual en OpenShift) | Permite el tráfico de `dx-demo` a `dx-shared` puerto 4000 |

## Lab 4 · Búsqueda

| Síntoma | Causa probable | Solución |
|---|---|---|
| Los rastreadores terminan con 0 documentos o por *timeout* | `haproxyProtocol` en `http`: el HAProxy de DX solo escucha en 443 | `automatedSetup.haproxyProtocol: https` (ya en `custom-search-values.yaml`) |
| `Could not connect to file processor` cada 3 s | File Processor desactivado (valor por defecto del chart) | `applications.fileProcessor: true` (ya en `custom-search-values.yaml`) |
| OpenSearch rechaza al administrador | `adminDN` no está en formato RFC 2253 | Lo genera `./01-certs.sh` en `admin-dn.rendered.yaml`; no lo pases con `--set` |

Más detalle en la guía de cada lab.
