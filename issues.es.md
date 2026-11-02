# Problemas conocidos encontrados al montar los labs

[English](issues.md) · **Español**

Problemas encontrados al preparar esta PoC con HCL DX Compose CF238 (`hcl-dx-deployment` 2.49.0,
`hcl-dx-iq` 1.0.2, `hcl-dx-search` 2.36.0), qué ocurre y cómo los resuelven los labs.

## Problemas reportados a HCL Support

| Case | Abierto | Problema | Estado |
|---|---|---|---|
| **CS1479102** | 2026-11-02 | IQ: la lista de servidores MCP configurada como dice la documentación se ignora | Abierto, HCL lo está reproduciendo |
| **CS1479139** | 2026-11-02 | IQ: el *system prompt* describe una memoria RAG activa aunque el RAG está desactivado | Abierto |
| **CS1479178** | 2026-11-02 | IQ: las peticiones al LLM no pueden usar *prompt caching*, así que cada llamada paga a precio completo un prefijo de ~30.000 tokens | Abierto |

### CS1479102 · IQ ignora `MCP_SERVER_LIST`

- **Problema.** La documentación de HCL («Deploying IQ services») dice que el IQ Integrator lee su
  lista de servidores MCP de `MCP_SERVER_LIST`, definida en `environment.pod.integrator`. La variable
  llega al Deployment del Integrator, pero el chart genera además el ConfigMap `<release>-integrator`
  con su propia lista fija (`dx.config.integrator.mcp_server_list` = solo el MCP Server de HCL), sea
  cual sea el valor configurado, y esa es la lista que usa el Integrator. No se pueden añadir
  servidores MCP adicionales, y ni siquiera funciona el uso documentado (apuntar al MCP Server de una
  release con otro nombre).
- **Solución en los labs (workaround).** Después de instalar o actualizar IQ se parchea esa clave del
  ConfigMap con los dos servidores y se reinicia el Integrator
  (`lab3-iq-openrouter/custom-mcp/03-iq-register.sh`; `04-iq-install.sh` lo vuelve a aplicar tras cada upgrade).
- **Efecto secundario con Helm 4.** Helm 4 aplica los objetos con *server-side apply*: una vez
  parcheada la clave, el siguiente `helm upgrade` de IQ falla con `conflict with "kubectl-patch"`. Los
  labs usan `--force-conflicts` con Helm 4 (`HELM_FORCE_CONFLICTS` en `common/lib.sh`) y vuelven a parchear la clave.

### CS1479139 · Directiva de RAG en el *prompt* con el RAG desactivado

- **Problema.** El Integrator registra `RAG_ENABLED=false` al arrancar, pero cada petición que envía al
  modelo (vista en el log de LiteLLM en modo *debug*) incluye una sección «PERSISTENT CROSS-SESSION
  MEMORY DIRECTIVE (pgvector RAG)» que afirma que hay una memoria RAG activa, que el modelo nunca debe
  decir que no tiene memoria y que los textos etiquetados como «Past conversation note:» o «CRITICAL
  SYSTEM MEMORY HISTORY» deben tratarse como verdad absoluta. Riesgos: respuestas que aseguran recordar
  cosas que no existen, una posible vía de inyección de *prompts*, ~250 tokens de más por petición y el
  estado del RAG registrado como `ERROR`. El case pide además documentación del RAG (configuración, qué
  se guarda, retención, aislamiento entre usuarios, datos enviados al proveedor de *embeddings*).
- **Solución en los labs.** Ninguna de momento: no bloquea IQ y la sección forma parte del *prompt* del
  producto. Pendiente de HCL.

### CS1479178 · Las peticiones de IQ no pueden usar *prompt caching*

- **Problema.** Todas las peticiones del Integrator llevan el mismo prefijo fijo y grande: las
  definiciones de las herramientas MCP y el *system prompt*. Medido en el log de LiteLLM en modo
  *debug* (58 herramientas, CF238): **29.654 tokens de 30.046** en una pregunta de una frase. Claude
  solo guarda en caché un prefijo cuando la petición marca dónde acaba (`cache_control`), y el
  Integrator nunca pone esa marca: la petición llega a LiteLLM sin ningún `cache_control`. Así que, tal
  como la genera IQ, todo el prefijo se cobra a precio completo de entrada en cada llamada al modelo.
  El *prompt* en sí está bien construido para la caché (la parte fija primero, la pregunta al final,
  sin fechas ni datos del usuario): solo falta la marca.
- **Impacto en coste** (Claude Sonnet 4.6, precios de Anthropic: entrada 3 $/MTok, escritura en
  caché 3,75 $/MTok, lectura de caché 0,30 $/MTok). Una pregunta que usa una herramienta hace 2
  llamadas al modelo, las dos con el prefijo:

  | | Coste del prefijo por pregunta |
  |---|---|
  | Sin caché (tal como lo envía IQ) | 2 × 29.654 tokens × 3 $ ≈ **0,18 $** |
  | Con caché, ya creada | 2 × 29.654 × 0,30 $ ≈ **0,018 $** |
  | Con caché, primera llamada tras 5 min sin uso | ≈ 0,11 $ (escritura) + 0,009 $ (lectura) |

  Alrededor de un 90 % menos en la parte de entrada. Por ejemplo, 1.000 preguntas al día pasan de
  unos 180 $ a unos 20 $ diarios (≈ 4.800 $ al mes de ahorro). La caché dura 5 minutos, así que el
  ahorro depende del tráfico: con un uso muy esporádico casi todas las llamadas pagan la escritura
  (+25 %), y con uso continuo casi todas leen. Los precios y las reglas de caché de Claude en Bedrock
  son parecidos, y la configuración de referencia de HCL (LiteLLM + Bedrock) debería tener el mismo problema
  si la pasarela no añade la marca (sin probar).
  Evidencia enviada con el case (LiteLLM sin el workaround): 2 preguntas desde 2 sesiones de IQ
  distintas, 4 llamadas al modelo, el mismo prefijo de ~30.000 tokens y `cache_read_input_tokens=0` en todas.
- **Solución en los labs (workaround).** LiteLLM inyecta la marca al final del mensaje de sistema en
  los dos modelos (`cache_control_injection_points: [{location: message, role: system}]` en
  `lab3-iq-openrouter/litellm-values.yaml`). Las herramientas y el *system prompt* van antes, así que
  se guarda todo el prefijo. Comprobado en el log de LiteLLM: primera llamada
  `cache_creation_input_tokens=29654`, segunda `cache_read_input_tokens=29654`. El historial de la
  conversación, que va después del *system prompt*, no se guarda; es una parte pequeña de cada petición.
- **Reportado como defecto** por su impacto en el negocio: el coste excesivo de cada llamada de IQ.
  El case pide a HCL que el Integrator marque el prefijo cacheable en sus peticiones y, mientras tanto,
  que documente la configuración de la pasarela.

## Problemas no reportados (sin case abierto)

### HCL lo conoce: previsto para una versión futura

| Problema | Solución en los labs |
|---|---|
| **El Web Engine sobre PostgreSQL no está soportado en CF238** (sí DB2, Oracle y SQL Server). HCL está validando PostgreSQL para el Web Engine (sus pruebas funcionan con PostgreSQL 18). En nuestras pruebas, el Web Engine (OpenJPA) genera `LIKE … ESCAPE '\'` (estilo DB2/Oracle), que PostgreSQL rechaza con «invalid escape string» con su configuración por defecto | El Lab 2B se presenta como ejercicio de aprendizaje, no como configuración soportada. El script de preparación de PostgreSQL pone `standard_conforming_strings = off` (y `escape_string_warning = off`) en `dx_core` |

### IQ (hcl-dx-iq 1.0.2)

| Problema | Solución en los labs | ¿Case? |
|---|---|---|
| **`LITELLM_BASE_URL` no está documentada pero es imprescindible.** Con solo el valor documentado `configuration.litellm.liteLlmUrl`, el adaptador LLM del Integrator no envía las peticiones a nuestro LiteLLM | `LITELLM_BASE_URL` en `environment.pod.integrator` con la misma URL (`custom-iq-values.yaml`) | Candidato a case |
| **`LITELLM_URL` y `LITELLM_API_KEY` no se pueden sobrescribir** con `environment.pod.integrator`: el chart las vuelve a definir | La URL va en `configuration.litellm.liteLlmUrl` (+ `LITELLM_BASE_URL`); la clave, en el secret `iq-litellm-api-secret` | Pendiente de añadir como comentario al CS1479102 |
| **Los nombres de las herramientas MCP llevan puntos** (`dam.mime-type…`), que las APIs de Anthropic y OpenAI rechazan (solo `[a-zA-Z0-9_-]`): con un proveedor que no los adapte, la petición entera falla con HTTP 400 | LiteLLM usa su proveedor `anthropic/` contra el endpoint compatible con Anthropic de OpenRouter, que adapta los nombres. HCL recomienda `enableDam: false` con modelos que no sean Claude | No (petición de mejora) |
| **El Integrator solo lee las herramientas MCP al arrancar.** Si arranca antes de que el MCP Server esté listo (lo normal en una instalación nueva), se queda sin herramientas hasta que se reinicia | La instalación espera al MCP Server y después reinicia el Integrator (`04-iq-install.sh`) | No |
| **OpenRouter no está validado por HCL** (las guías de HCL usan AWS Bedrock) | Documentado en el Lab 3: se usa OpenRouter a través de LiteLLM para evitar preparar una cuenta de AWS Bedrock | No (decisión de diseño) |

### Search V2 (hcl-dx-search 2.36.0)

| Problema | Solución en los labs | ¿Case? |
|---|---|---|
| **Con DX publicado mediante un Ingress o una Route, los rastreadores usan `http` e indexan 0 documentos.** `automatedSetup.haproxyProtocol` viene vacío por defecto, y entonces el chart elige el protocolo según el tipo del Service del HAProxy de DX: `https` si es `LoadBalancer` (el valor por defecto del chart de DX) y `http` en cualquier otro caso. No mira `networking.haproxy.ssl`, que es lo que decide si HAProxy usa TLS. Con los valores por defecto de los dos charts funciona. Pero publicar DX con un Ingress (Kubernetes) o una Route (OpenShift) implica `serviceType: ClusterIP`, normalmente con el SSL activado: Search llama entonces al HAProxy por el puerto 80, donde no escucha nadie, y los rastreadores agotan el tiempo. La regla solo aparece en un comentario del `values.yaml` del chart de Search; la página de HCL «Installing the Search V2 backend» no la menciona | `haproxyProtocol: https` en `custom-search-values.yaml`, que conviene fijar siempre de forma explícita cuando el HAProxy es `ClusterIP` o `NodePort` con SSL | No (configuración nuestra; como mucho, una sugerencia de documentación) |
| **El File Processor viene desactivado por defecto**, pero el Search Middleware lo busca igualmente y registra «Could not connect to file processor» cada 3 segundos | `applications.fileProcessor: true` | Candidato a case |

### Instalación con Helm 4

| Problema | Solución en los labs | ¿Case? |
|---|---|---|
| **`--wait` aborta la instalación de DX.** Helm 4 usa la estrategia `watcher`, que falla en cuanto un pod falla; DAM falla de forma normal mientras arranca su PostgreSQL (Persistence Node), así que la release acaba en `failed` aunque DX terminaría arrancando | `--wait=legacy` con Helm 4 (`HELM_WAIT` en `common/lib.sh`), que espera hasta el *timeout* como Helm 3 | No (antes, comprobar si Helm 4 está soportado oficialmente) |

### Configuración de DX (detalles de la documentación)

| Problema | Solución en los labs | ¿Case? |
|---|---|---|
| `security.webEngine.webEngineAdminGroup: <grupo LDAP>` no usa el grupo del LDAP: crea un grupo con ese nombre en el registro básico, y con el repositorio federado dos grupos con el mismo nombre pueden hacer fallar Liberty («multiple entities found») | Los permisos de administrador se dan al grupo del LDAP en el portal (Permisos de recursos), o se añaden usuarios del LDAP a `wpsadmins` con un override (Lab 2A, paso 4) | No |
| XMLAccess y WebDAV están restringidos al grupo de administración del registro básico (`DX_ADMIN_GROUP`) | El mismo override, si los administradores del LDAP necesitan esas herramientas | No (decisión de diseño) |
| El chart de DX despliega su propio OpenLDAP por defecto (`applications.openLdap: true`) | `openLdap: false` en los values del Lab 1; en el Lab 2 se usa un LDAP externo | No |

### Componentes de terceros (no de HCL)

| Problema | Solución en los labs |
|---|---|
| OpenLDAP (`openldap-stack-ha`): un LDIF propio sin la entrada raíz hace fallar el primer `ldapadd` y el LDAP arranca vacío | `demo-users.ldif` incluye `dn: dc=dxdemo,dc=com` |
| El `local-path` de k3s no admite ReadWriteMany (DAM lo necesita) | Lab 0: StorageClass estática con un volumen `hostPath` |
| Los volúmenes `hostPath` ignoran el `fsGroup` del pod: DAM (uid 1000/gid 1001) no puede escribir (`EACCES`) | Lab 0: `01-storage.sh` deja el directorio como `1000:1001` |
| Los modelos de razonamiento de OpenAI (gpt-5.x) inyectan `reasoning_effort` y rompen las herramientas de IQ | Documentado en `litellm-values.yaml`: usar Claude |
