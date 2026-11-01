# Lab 3 · HCL DX IQ con LiteLLM y OpenRouter

**Punto de partida:** Lab 1 terminado (el Lab 2 es opcional para este lab, salvo el apéndice).

**Objetivo:** activar **IQ**, el asistente de IA de DX, usando **Claude** a través de
**OpenRouter**, con un proxy **LiteLLM** en `dx-shared`.

Documentación de HCL: [IQ installation (CF238)](https://help.hcl-software.com/digital-experience/9.5/CF238/build_sites/iq/installation/)

```
 Navegador ─► HAProxy de DX ─► /dx/ui/iq, /dx/api/iq/v1 ─► dx-iq-integrator ─┬─► dx-iq-mcp-server ─► APIs de DX
                                                              (dx-demo)        │      (herramientas WCM y DAM)
                                                                               │
                              dx-shared: litellm:4000 ◄────────────────────────┘
                                    │  iq-general-purpose -> Claude Sonnet 4.6
                                    │  iq-summary         -> Claude Haiku 4.5
                                    └─► https://openrouter.ai/api
```

| Componente | Namespace | Quién lo da |
|---|---|---|
| IQ Integrator y MCP Server | `dx-demo` | Chart `hcl-dx-iq` 1.0.2 de HCL |
| LiteLLM | `dx-shared` | Chart público de BerriAI (HCL lo trata como requisito previo) |
| Modelos | Internet | OpenRouter (clave `OPENROUTER_API_KEY`) |

IQ siempre pide dos modelos lógicos, `iq-general-purpose` e `iq-summary`; LiteLLM decide a qué
proveedor y modelo real van. Cambiar de modelo no requiere tocar IQ.

> **Soporte.** HCL valida LiteLLM con Bedrock, OpenAI, etc., pero **no OpenRouter**. Esta
> configuración funciona con dos ajustes no documentados que se explican en el apartado final.

```bash
cd hcl-dx-compose-labs && source ./env.sh      # con OPENROUTER_API_KEY definida
```

---

## Paso 1 · Secrets

```bash
lab3-iq-openrouter/01-secrets.sh
```

| Secret | Namespace | Contenido |
|---|---|---|
| `litellm-env` | `dx-shared` | `OPENROUTER_API_KEY` y `PROXY_MASTER_KEY` (master key de LiteLLM, empieza por `sk-`) |
| `iq-litellm-api-secret` | `dx-demo` | `virtualKey`: la clave con la que IQ llama a LiteLLM |

LiteLLM va sin base de datos (el "quick start" de HCL), así que no hay virtual keys y IQ usa la
master key. Cada secret está en el namespace de quien lo lee.

## Paso 2 · LiteLLM

```bash
lab3-iq-openrouter/02-litellm-install.sh
```

Instala `oci://ghcr.io/berriai/litellm-helm` 1.106.5 en `dx-shared` con
[litellm-values.yaml](litellm-values.yaml). Lo importante:

```yaml
proxy_config:
  model_list:
    - model_name: iq-general-purpose
      litellm_params:
        model: anthropic/anthropic/claude-sonnet-4.6   # proveedor anthropic/ + id de OpenRouter
        api_base: https://openrouter.ai/api            # endpoint compatible con Anthropic
        api_key: os.environ/OPENROUTER_API_KEY
        cache_control_injection_points:                # prompt caching
          - { location: message, role: system }
  litellm_settings:
    drop_params: true                                  # HCL: imprescindible
```

- **`anthropic/` y no `openrouter/`**: el MCP Server de HCL tiene herramientas con puntos en el
  nombre (`dam.mime-type...`). El proveedor `anthropic/` las adapta al formato que acepta Claude;
  con `openrouter/` (formato OpenAI) Claude rechaza toda la petición con HTTP 400.
- **Prompt caching**: cada petición de IQ envía ~50 herramientas y un system prompt largo que
  apenas cambian. Marcarlos como cacheables abarata mucho las preguntas siguientes.
- `db.deployStandalone: false`: sin el PostgreSQL que el chart instalaría por defecto.

## Paso 3 · Probar LiteLLM antes de instalar IQ

```bash
lab3-iq-openrouter/03-litellm-test.sh
```

Abre un port-forward local, lista los modelos y hace una petición a cada uno. Los dos deben
responder `listo` (LiteLLM devuelve el nombre lógico del modelo; el real, Sonnet 4.6 o Haiku 4.5,
se ve en https://openrouter.ai/activity). Si falla aquí, el problema es la clave o el crédito de
OpenRouter, no IQ.

## Paso 4 · Instalar IQ

Lee [custom-iq-values.yaml](custom-iq-values.yaml). Lo principal:

| Valor | Para qué |
|---|---|
| `configuration.dx.releaseName` / `externalHost` | Qué DX usar (`dx-deployment`) y su FQDN; los pasa el script desde `env.sh` |
| `configuration.litellm.liteLlmUrl` | `http://litellm.dx-shared.svc.cluster.local:4000`: **FQDN** porque está en otro namespace |
| `environment.pod.integrator` → `LITELLM_BASE_URL` | Misma URL. No documentada pero imprescindible en 1.0.2 (ver abajo) |
| `configuration.mcpServer.enableWcm` / `enableDam` | Herramientas que IQ puede usar sobre WCM y DAM |
| `configuration.database.enabled: false` | Sesiones en SQLite en memoria (se pierden al reiniciar). Ver apéndice |

```bash
lab3-iq-openrouter/04-iq-install.sh
```

```bash
helm upgrade --install dx-iq charts/hcl-dx-iq-1.0.2.tgz -n dx-demo -f lab3-iq-openrouter/custom-iq-values.yaml \
  --set-string configuration.dx.releaseName=dx-deployment --set-string configuration.dx.externalHost=$DX_HOST
```

Después reinicia el MCP Server y el Integrator (Helm no lo hace si solo cambian secrets).

## Paso 5 · Habilitar IQ en DX

```bash
lab3-iq-openrouter/05-dx-enable-iq.sh
```

Añade la capa [custom-values.iq.yaml](custom-values.iq.yaml) al `helm upgrade` de DX:

```yaml
networking:
  dxIqService: "dx-iq-integrator"     # <release de IQ>-integrator
```

HAProxy empieza a enrutar `/dx/api/iq/v1/` y `/dx/ui/iq/` al Integrator y aparece el botón de IQ.
Se reinician HAProxy, el Web Engine y también el Persistence Node, su pool y el Runtime
Controller: al habilitar IQ, el chart prepara en el Persistence Node la base de datos `iqdb`
(se usará si las sesiones de IQ pasan a PostgreSQL interno). Unos 5 minutos.

## Comprobar

```bash
lab3-iq-openrouter/99-verify.sh
```

Revisa la URL efectiva de LiteLLM, la clave, que el Integrator ha cargado las herramientas del MCP
Server, la conectividad `dx-demo → dx-shared` y el enrutado de HAProxy.

### Prueba de extremo a extremo desde la terminal

```bash
lab3-iq-openrouter/06-iq-chat-test.sh
lab3-iq-openrouter/06-iq-chat-test.sh "¿Cuántas bibliotecas de WCM hay?"
```

Hace lo mismo que el navegador: entra en DX como `wpsadmin` (o `IQ_USER`/`IQ_PASSWORD`), abre el
WebSocket de IQ (`wss://$DX_HOST/dx/api/iq/v1/ws`, JSON-RPC 2.0) y muestra cada herramienta MCP que
usa IQ y su respuesta final. Ejemplo real:

```
  [  3.6s] tool_call: get_all_libraries_from_WCM  Obteniendo todas las bibliotecas...
---- respuesta final de IQ (5.6s) ----
1. Blog Solo Template v70
...
19. webinar-transferencia          <- la biblioteca creada en el Lab 2, ya en PostgreSQL
```

### Desde el navegador

En `https://$DX_HOST/wps/myportal`, como wpsadmin, pulsa el botón ✨ de IQ (requisito de HCL:
Practitioner Studio habilitado, que es lo normal en DX Compose) y prueba:

- "¿Qué bibliotecas de contenido hay en WCM?"
- "Resume el contenido de la página Webinar"
- "Busca en DAM imágenes de tipo PNG"

---

## 3B · Añadir un MCP Server propio

IQ no está limitado a las herramientas de HCL. Un **MCP Server** (*Model Context Protocol*) es un
servicio que publica **herramientas**: funciones con nombre, descripción y parámetros que el LLM
puede decidir llamar. El MCP Server de HCL publica 53 (WCM y DAM). Aquí añadimos uno propio con
información que el modelo no puede saber: la base de conocimiento de EUROPESIP, por ejemplo **el
horario de soporte**.

```
                                ┌─► dx-iq-mcp-server:3000            (HCL, dx-demo)    53 herramientas
 IQ Integrator ── tools/list ───┤
   (dx-demo)                    └─► europesip-mcp.dx-shared:3000     (propio, dx-shared) 2 herramientas
```

Es software propio, no de HCL, así que va en **`dx-shared`**.

> **Soporte.** HCL documenta `MCP_SERVER_LIST` para su propio MCP Server; añadir servidores propios
> no está documentado ni soportado en IQ 1.0.2. Funciona con el procedimiento de abajo.

### El servidor

[mcp-propio/server.py](mcp-propio/server.py): unas 80 líneas de Python con el SDK oficial de MCP
(`FastMCP`). Lo esencial:

```python
mcp = FastMCP("europesip-kb", stateless_http=True, json_response=True, ...)

@mcp.tool()
def consultar_faq_europesip(tema: str) -> str:
    """Consulta la base de conocimiento interna de EUROPESIP (empresa partner de HCL).
    Úsala cuando el usuario pregunte por el soporte de EUROPESIP, su laboratorio o cómo
    tiene configurado IQ. Temas disponibles: soporte, laboratorio, iq."""
    ...
```

Lo que tiene que cumplir para que IQ lo use:

| Requisito | En el servidor |
|---|---|
| MCP sobre HTTP *streamable* en `POST /mcp`, sin sesiones | `stateless_http=True`, `json_response=True` (como el MCP de HCL) |
| `GET /probe/ready` → 200 | El Integrator lo consulta antes de pedir las herramientas |
| Nombres de herramienta `[a-zA-Z0-9_-]` | `consultar_faq_europesip` (el Integrator le antepone un prefijo por servidor: `562b68ed_...`) |
| **Una buena descripción** | Es lo único que lee el modelo para decidir si la usa. Corta y precisa: viaja en cada petición |

### Paso 3B-1 · Desplegar

```bash
lab3-iq-openrouter/mcp-propio/01-mcp-deploy.sh
```

ConfigMap con `server.py` + Deployment `python:3.12-slim` (instala `mcp` al arrancar) + Service
`europesip-mcp:3000`, en `dx-shared` ([europesip-mcp.yaml](mcp-propio/europesip-mcp.yaml)).

### Paso 3B-2 · Probarlo antes de conectarlo a IQ

```bash
lab3-iq-openrouter/mcp-propio/02-mcp-test.sh
```

Desde un pod de `dx-demo` habla MCP como lo hará el Integrator: `initialize`, `tools/list` (las 2
herramientas) y `tools/call` de `consultar_faq_europesip(tema="soporte")`, que devuelve el horario.

### Paso 3B-3 · Registrarlo en IQ

```bash
lab3-iq-openrouter/mcp-propio/03-iq-register.sh
```

El Integrator lee la lista de MCP Servers de la clave `dx.config.integrator.mcp_server_list` del
ConfigMap `dx-iq-integrator`. El chart 1.0.2 la genera con solo el de HCL y no ofrece ningún valor
para ampliarla (la variable `MCP_SERVER_LIST` tampoco tiene efecto: el ConfigMap la sobrescribe).
El script parchea esa clave y reinicia el Integrator:

```
http://dx-iq-mcp-server:3000,http://europesip-mcp.dx-shared.svc.cluster.local:3000
```

En el log del Integrator:

```
Fetched 53 tools from http://dx-iq-mcp-server:3000
Fetched 2 tools from http://europesip-mcp.dx-shared.svc.cluster.local:3000
Total tools: 55
```

> Cada `helm upgrade` de IQ regenera el ConfigMap. `04-iq-install.sh` vuelve a añadir el servidor
> propio automáticamente si existe el servicio `europesip-mcp` en `dx-shared`.

### Comprobar

```bash
lab3-iq-openrouter/06-iq-chat-test.sh "¿Cuál es el horario de soporte de EUROPESIP?"
```

```
  [  3.0s] tool_call: 562b68ed_consultar_faq_europesip  Consultando la base de conocimiento de EUROPESIP...
---- respuesta final de IQ (7.5s) ----
El horario de soporte de EUROPESIP para HCL DX es el siguiente:
- Días: Lunes a viernes
- Horario: 9:00 – 18:00 (hora de Madrid)
- Contacto: soporte@europesip.com
```

Y en el log del servidor propio (`kubectl -n dx-shared logs deploy/europesip-mcp`), la llamada:

```
REQ POST /mcp ... cookies=-                                              <- tools/list (descubrimiento)
REQ POST /mcp ... cookies=['DxSessionAffinity', 'JSESSIONID', 'LtpaToken2']   <- tools/call
TOOL consultar_faq_europesip tema='soporte'
```

> **Seguridad: el Integrator reenvía la sesión de DX del usuario.** En cada `tools/call`, el
> servidor recibe las cookies de sesión de DX (`LtpaToken2`...) del usuario que pregunta. Eso
> permite que un MCP propio llame a las APIs de DX **con la identidad y los permisos de ese
> usuario**, pero también significa que un MCP propio es código de confianza: revisa qué hace, no
> registres sus valores (este solo registra los nombres) y protege su acceso.

> **Coste.** Las herramientas añadidas viajan en todas las peticiones (estas dos, unos 250 tokens)
> y cambiar la lista invalida la caché de prompts hasta la siguiente petición.

Para quitarlo: `kubectl -n dx-shared delete deploy/europesip-mcp svc/europesip-mcp cm/europesip-mcp-code`
y `lab3-iq-openrouter/04-iq-install.sh` (regenera la lista con solo el MCP de HCL).

## Desviaciones respecto a la documentación de HCL (IQ 1.0.2)

1. **`LITELLM_BASE_URL` es obligatoria.** El adaptador LLM del Integrator usa esta variable, no
   `litellm.liteLlmUrl`. Sin ella llama a una URL interna de HCL. Se define en
   `environment.pod.integrator` con el mismo valor.
2. **`LITELLM_URL` y `LITELLM_API_KEY` no se pueden poner como variables de entorno**: el chart
   las redefine después. La clave va en `iq-litellm-api-secret`.
3. **OpenRouter a través del proveedor `anthropic/` de LiteLLM** (ver paso 2).

## Apéndice · Sesiones de IQ en PostgreSQL (requiere el Lab 2B)

Con SQLite en memoria el historial se pierde al reiniciar el pod y no se puede escalar el
Integrator. Para usar el PostgreSQL de `dx-shared`:

```bash
lab3-iq-openrouter/A1-iq-database.sh                                   # BD iqdb + secret en dx-demo
lab3-iq-openrouter/04-iq-install.sh -f custom-iq-values.db-external.yaml
```

El rol `dx_iq_db_user` ya lo creó CNPG en el Lab 2B. IQ crea sus tablas al arrancar: tras abrir un
chat aparecen en `iqdb`.

## Coste

Lo paga la cuenta de OpenRouter. Con el prompt caching activado, la primera pregunta de una sesión
es la más cara (crea la caché de herramientas y system prompt) y las siguientes leen de la caché
a ~10 % del precio. Medido en el laboratorio con dos peticiones iguales de ~4000 tokens de prompt:

| Petición | Tokens escritos en caché | Tokens leídos de caché |
|---|---|---|
| 1ª | 4017 | 0 |
| 2ª | 0 | 4017 |

El panel de https://openrouter.ai/activity muestra cada petición y su coste.
