# Lab 5 · ÓRBITA, una aplicación avanzada sobre DX Compose *(avanzado, opcional)*

[English](GUIDE.md) · **Español**

> **Lab avanzado.** No hace falta para la instalación de DX Compose (Labs 1 a 4). Sirve para ver cómo es una
> **aplicación real** sobre DX Compose que combina **Script Applications, un microservicio, persistencia e integración
> con IA**, todo desplegado con **un solo chart de Helm**.

**ÓRBITA** es una suite de intranet de EUROPESIP: fichaje, vacaciones y ausencias, gastos y viajes, aprobaciones, una
página de inicio y un quiosco de fichaje. Código, chart y documentación:
[github.com/europesip/orbita](https://github.com/europesip/orbita) (licencia libre MIT). La interfaz está en español e inglés, en el idioma del perfil de DX de cada usuario.

| Pieza | Qué muestra | En ÓRBITA |
|---|---|---|
| **Script Applications** | La forma nativa de construir aplicaciones propias en DX Compose (sin portlets Java), varias apps desde un chart | Seis apps React subidas a WCM con DXClient (subchart [hcl-dx-scriptapp](https://github.com/europesip/hcl-dx-scriptapp-helm) 0.2.0), cada una en su página bajo *Home* |
| **Microservicio** | La lógica de negocio fuera de DX, junto a él, en el host de DX | `orbita-api`: Open Liberty con una API REST (`/orbita-api/v1`, Ingress en el host de DX) |
| **Inicio de sesión único** | El microservicio no guarda usuarios ni contraseñas | La API reenvía la cookie de sesión de DX del usuario a la API de perfil de DX: **DX dice quién es** |
| **Persistencia** | Una base de datos propia y cambios de esquema sin perder datos | PostgreSQL (dependencias externas): base y usuario creados por un Job, tablas con migraciones **Flyway** |
| **Integración con IA** | Un asistente que actúa en tu aplicación, y tu aplicación dentro de HCL DX IQ | Su **propio asistente de IA** a través de LiteLLM, con 26 herramientas que actúan **como el usuario que pregunta**; las mismas herramientas como **servidor MCP** para **HCL DX IQ** (opcional) |
| **Theme y DAM** | Un theme propio y sus imágenes desplegados por el mismo chart | Un theme de ejemplo (copia de Portal 8.5, solo en las páginas de ÓRBITA) con el logo de la empresa, *Powered by HCL Software* y un botón «✨ Pregúntale a ÓRBITA»; logos e imágenes en una colección del **DAM** (`theme.enabled: false` para mantener tu theme) |

```
 Navegador ── https://<host de DX> ──┬── /wps/myportal/Home/...  páginas de DX con las 6 Script Applications (WCM)
                                     └── /orbita-api/v1           Ingress ──► orbita-api (dx-shared)
                                                                              ├─ ¿quién es? ── LtpaToken2 ──► DX
                                                                              ├─ asistente de IA ──► LiteLLM (dx-shared)
                                                                              └─ PostgreSQL dx-pg: base "orbita"
 Integrator de IQ (dx-demo) ── cookies de DX del usuario ──► orbita-api :9081 /mcp (NetworkPolicy: solo el Integrator)
```

## Antes de empezar

| Necesita | Por qué |
|---|---|
| **Lab 1** | DX, su nombre de host y su certificado |
| **PostgreSQL** ([dependencias externas](../external-deps/GUIDE.es.md), `external-deps/02-postgres.sh`) | ÓRBITA 2.x necesita PostgreSQL; el chart crea su propia base `orbita` con el Secret de superusuario `dx-pg-superuser` |
| **Lab 2A** (OpenLDAP) | Los usuarios de la demo (`patricia`, `andres`, `macarena`…) son los del OpenLDAP |
| **LiteLLM** (Lab 3A, o `external-deps/03-litellm.sh`) | El asistente de IA propio de ÓRBITA (sin él, ÓRBITA se instala sin asistente) |
| **Lab 3A** *(opcional, paso 3)* | ÓRBITA dentro del chat de HCL DX IQ |

El chart y las imágenes son **públicos** (`ghcr.io/europesip`): no hace falta iniciar sesión en el registro. ⏱ ~3 min
(más la primera vez, mientras los nodos descargan las imágenes).

## Paso 1 · Instalar ÓRBITA

DXClient pide aceptar su licencia, como en el Lab 1B (`DXCLIENT_ACCEPT_LICENSE=yes` en `env.sh`). Después:

```bash
lab5-orbita/01-orbita-install.sh
```

Crea dos secrets en `dx-shared` (`orbita-dx`: el administrador de DX para DXClient; `orbita-dx-ca`: la CA del
certificado de DX) y ejecuta:

```bash
helm upgrade --install orbita oci://ghcr.io/europesip/charts/hcl-dx-orbita --version 3.1.1 -n dx-shared \
  --set dx.host=$DX_HOST --set dx.caSecret=orbita-dx-ca \
  --set database.host=$PG_HOST --set database.create.superuserSecret=dx-pg-superuser \
  --set scriptapps.dx.host=$DX_HOST --set scriptapps.dx.credentialsSecret=orbita-dx \
  --set scriptapps.dx.caSecret=orbita-dx-ca --set scriptapps.dxclient.acceptLicense=true \
  --set assistant.litellm.url=http://litellm.dx-shared.svc.cluster.local:4000
```

Qué hace el chart, por orden:

1. **Job `orbita-db`** (antes de instalar): crea el usuario y la base `orbita` en PostgreSQL.
2. **`orbita-api`**: Deployment, Service, Ingress en `/orbita-api` del host de DX y NetworkPolicy del puerto del MCP.
   Al arrancar, Flyway crea las tablas y se cargan los datos de la demo.
3. **Job `orbita-scriptapps-push`** (después de instalar): sube las seis Script Applications con DXClient y crea sus
   páginas con XMLAccess.

## Paso 2 · Usarla

Entra en DX con un usuario de la demo (contraseña: `LDAP_USERS_PASSWORD` del `env.sh`) y abre
`https://<host de DX>/wps/myportal/Home/mi-intranet`. La historia de la demo va por papeles, que hacen los usuarios
del Lab 2A:

| Usuario | Rol en ÓRBITA | Prueba |
|---|---|---|
| `macarena` | Comercial | Fichar, pedir vacaciones, añadir un gasto a una nota y enviarla |
| `andres` | Responsable de Ventas | *Aprobaciones*: aprobar o rechazar; *Fichaje › Equipo*: quién está trabajando |
| `german` | Administración | *Gastos › Pagos*: pagar las notas aprobadas |
| `patricia` | RRHH | *Fichaje › Informes*: el registro de toda la plantilla; restaurar los datos de la demo |

Otro reparto de papeles: valor `demo.people` del chart (ver el README de ÓRBITA).

**Idioma.** Cada usuario ve ÓRBITA en el idioma de su perfil de DX. En el Lab 2A todos tienen español, salvo `andres`
y `justo` (inglés): entra como `andres` para verla en inglés.

**El asistente de IA.** El botón «✨ Pregúntale a ÓRBITA» de cada aplicación abre el asistente propio de ÓRBITA. **Se
puede preguntar en español o en inglés**: responde en el idioma de la pregunta.

- «¿Cuántos días de vacaciones me quedan?» · «Pídeme vacaciones del 9 al 11 de diciembre»
- «¿He fichado hoy?» · «Ficha mi entrada en teletrabajo» · «¿Qué días de este mes no cerré el fichaje?»
- «¿Cuánto me deben de gastos?» · «Crea una nota "Visita a Sevilla" y añade una comida de ayer de 42,80 €»
- Como `andres`: «¿Qué tengo que aprobar?» · «¿Quién de mi equipo está trabajando ahora?» · «Aprueba las vacaciones de macarena»

Más de 60 preguntas: [preguntas-ia.md](https://github.com/europesip/orbita/blob/main/docs/preguntas-ia.md). Las
herramientas actúan como el usuario que pregunta (identificado por su sesión de DX); lo que cambia datos pide
confirmación antes. Usa el alias de modelo `iq-general-purpose` de LiteLLM, el mismo que IQ (valor `assistant.model`
del chart para otro).

**Ajustes de cada aplicación.** Como `wpsadmin`, activa el modo edición de la página en DX: cada aplicación de ÓRBITA
muestra «⚙ Ajustes de esta aplicación» (partes de la cabecera, pie e idioma solo para esa página).

## Paso 3 · ÓRBITA en HCL DX IQ (opcional, necesita el Lab 3A)

```bash
lab5-orbita/02-orbita-iq.sh
```

Añade `http://orbita-api.dx-shared.svc.cluster.local:9081` a la **lista de servidores MCP** del Integrator de IQ y lo
reinicia. Hace falta un parche por el mismo bug de IQ que en el Lab 3B (caso CS1479102, [issues.es.md](../issues.es.md)):
la variable documentada no tiene efecto y la lista está en el ConfigMap `dx-iq-integrator`. El `04-iq-install.sh` del
Lab 3 vuelve a añadir ÓRBITA después de cada upgrade de IQ.

Después, el chat de IQ (el botón ✨ de DX) también puede responder y actuar en ÓRBITA, mezclado con las herramientas
de HCL DX (WCM, DAM, páginas): las mismas preguntas de arriba. IQ está pensado para los profesionales de DX; para la
plantilla, el asistente propio de ÓRBITA gasta muchos menos tokens por pregunta.

**Tamaño del prompt.** Cada definición de herramienta va en cada llamada al modelo: las 26 de ÓRBITA son unos 4.700
tokens. Para publicar menos (en los dos asistentes), `--set 'mcp.tools.enabled={vacaciones,fichaje}'` o
`--set mcp.tools.readOnly=true` en el paso 1 (ver el README de ÓRBITA).

## Comprobar

```bash
lab5-orbita/99-verify.sh
```

## Conviene saber

- **Desinstalar**: `helm -n dx-shared uninstall orbita`. Se quedan la base de datos, las Script Applications y las
  páginas; `common/99-cleanup.sh` lo borra todo con los namespaces.
- **Las páginas aparecen bajo *Home* para cualquier usuario con sesión**: desinstala ÓRBITA antes de una sesión en la
  que no quieras que salgan.
- El microservicio **no guarda credenciales de DX**: solo DXClient (el Job del push) usa el administrador de DX.
