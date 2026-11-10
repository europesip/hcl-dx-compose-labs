# Problemas conocidos encontrados al montar los labs

[English](issues.md) · **Español**

Problemas encontrados al preparar esta PoC con HCL DX Compose CF238 (`hcl-dx-deployment` 2.49.0,
`hcl-dx-iq` 1.0.2, `hcl-dx-search` 2.36.0), qué ocurre y cómo los resuelven los labs.
**Revisados de nuevo en CF239** (`hcl-dx-deployment` 2.50.0, `hcl-dx-iq` 1.0.3, `hcl-dx-search`
2.37.0) con una instalación limpia de todos los labs el 2026-11-04: cada problema indica si sigue.

**Documentación de CF239 revisada el 2026-11-07** (publicada después de la nueva prueba): ninguno de los
problemas de abajo aparece como resuelto. El único cambio relacionado es que la memoria entre sesiones
(RAG) ya está documentada y se puede activar, ver CS1479139.

## Revisión de la documentación de CF239: dónde se apartan los labs y por qué (2026-11-07)

Los labs siguen la documentación de HCL tan de cerca como es posible. Esta sección recoge cada punto en el
que hacen algo distinto, porque seguir la página tal cual falla o no es posible, con la prueba que lo
demuestra. Comprobado con las páginas de CF239 publicadas a 2026-11-07, los charts de CF239
(`hcl-dx-deployment` 2.50.0, `hcl-dx-iq` 1.0.3, `hcl-dx-search` 2.37.0) y `litellm-helm` 1.106.5. La
página de LiteLLM se siguió al pie de la letra (Quick start) en un namespace aparte con una clave de API de Bedrock.

### «Deploying LiteLLM» (IQ > Installation, página del 2026-10-14)

| # | La documentación dice | Qué pasa (probado) | Qué hacen los labs |
|---|---|---|---|
| L1 | `helm repo add litellm https://ghcr.io/berriai/litellm-helm` y después instalar `litellm/litellm` | `helm repo add` falla: *«not a valid chart repository … index.yaml: 404 Not Found»* (ghcr.io es un registro OCI, no un repositorio Helm clásico). La instalación falla después: *«repo litellm not found»* | `helm upgrade --install litellm oci://ghcr.io/berriai/litellm-helm --version 1.106.5` (sin repositorio; versión fijada) |
| L2 | ID de Sonnet 4.6 `bedrock/us.anthropic.claude-sonnet-4-6-20250514-v1:0` | Con los values de la página tal cual: *«BedrockException - The provided model identifier is invalid»* (20250514 es la fecha de Claude Sonnet 4). Haiku 4.5 funciona | `us.anthropic.claude-sonnet-4-6` (sin fecha) |
| L3 | Sin `aws_region_name` en los modelos | Los perfiles de inferencia `us.` solo existen en regiones de EE. UU.: llamados desde `eu-west-1` dan *«The provided model identifier is invalid»*. Sin región, LiteLLM usa su propia región por defecto, que no controlas | `aws_region_name` en cada modelo (`us-east-1`, como da a entender la página, o los perfiles `eu.` con `eu-west-1` para mantener los datos en la UE) |
| L4 | Imagen `ghcr.io/berriai/litellm:main-latest` (Quick start); `ghcr.io/berriai/litellm-database:1.45.0` (Production) | `main-latest` existe pero es una etiqueta móvil (cambia con cada build de LiteLLM: dos instalaciones nunca son iguales). `litellm-database:1.45.0` **no existe** (HTTP 404 en ghcr.io; la etiqueta es `main-v1.45.0`, de 2024), así que los values de Production no pueden descargar la imagen | Imagen fijada a `1.106.5`, el `appVersion` de la versión del chart usada |
| L5 | Comprobar los pods con `kubectl get pods -l app=litellm` y `kubectl wait … -l app=litellm` | El chart etiqueta los pods con `app.kubernetes.io/name=litellm`: *«No resources found»* y *«error: no matching resources found»*, aunque LiteLLM está funcionando | `kubectl rollout status deployment/litellm` (o `-l app.kubernetes.io/name=litellm`) |
| L6 | Ejemplo Production: sondas con `enabled:` y `httpGet:` | Esas claves no existen en el chart (usa `livenessProbe.path`, etc.): se ignoran. Funciona de casualidad, porque los valores por defecto del chart tienen las mismas rutas | Sondas por defecto del chart (no hace falta cambiar nada) |
| L7 | «Por defecto, LiteLLM pide 100m de CPU y 512Mi de memoria» | El chart (1.106.5) no fija recursos por defecto, y los values del Quick start tampoco | Requests y limits explícitos (los del ejemplo Production: 100m/512Mi, 1 CPU/2Gi) |
| L8 | Crear `litellm-masterkey` **y** un `litellm-env` con el mismo `PROXY_MASTER_KEY` («para reducir el número de secrets, combínalos en un único litellm-env»), pero los values apuntan `masterkeySecretName` a `litellm-masterkey` | Solo funciona mientras los dos secrets tengan la misma clave; si divergen, gana la de `masterkeySecretName` | Un único secret `litellm-env`, usado también como `masterkeySecretName`, como recomienda el texto |
| L9 | Ejemplo Production: un Ingress con host `litellm.dxns.svc.cluster.local` | El host de un Ingress es un nombre externo; IQ llega a LiteLLM por su Service, nunca por ese Ingress | Sin Ingress (IQ usa `http://litellm.<namespace>.svc.cluster.local:4000`) |
| L10 | Nada sobre prompt caching | Cada llamada de IQ paga a precio completo un prefijo de ~32.500 tokens (CS1479178) | `cache_control_injection_points` en el mensaje de sistema |
| L11 | LiteLLM en el namespace de DX | Funciona | LiteLLM en `dx-shared`, con las demás herramientas de terceros (en `dx-demo` solo software de HCL); la URL de los values de IQ cambia en consecuencia. Decisión de diseño, no un error |
| L12 | Requisitos de Bedrock: solo «credenciales válidas» | Hacen falta además, y no se mencionan: el formulario de caso de uso de Anthropic (una vez por cuenta), la suscripción del modelo en AWS Marketplace con un método de pago válido y, en la primera llamada, un usuario con permiso `aws-marketplace:Subscribe`/`ViewSubscriptions` (un usuario IAM limitado a `bedrock:InvokeModel`, como suele estarlo una clave de API de Bedrock, recibe *«Model access is denied…»*) | Documentado en el instalador; el lab usa OpenRouter o Claude directo |

### «Deploying IQ services», «Preparing LiteLLM access» e «IQ environment variables»

| # | La documentación dice | Qué pasa (probado) | Qué hacen los labs |
|---|---|---|---|
| I1 | La URL de LiteLLM en `configuration.litellm.liteLlmUrl` | No basta. Vuelto a probar hoy: solo con eso (quitando únicamente `LITELLM_BASE_URL`), IQ responde *«The LLM service is temporarily unavailable»* (`LLM_ERROR_SERVICE_UNAVAILABLE`) y a LiteLLM no le llega ninguna petición; al volver a ponerla, IQ responde. **No es cuestión de namespace** (probado el 2026-11-08): con un segundo LiteLLM en el namespace de DX y `liteLlmUrl` apuntando a él (`http://litellm.dx-demo.svc.cluster.local:4000` o `http://litellm:4000`), IQ sigue fallando y ninguno de los dos LiteLLM recibe peticiones; al añadir `LITELLM_BASE_URL`, ese mismo LiteLLM responde | `LITELLM_BASE_URL` (no documentada) en `environment.pod.integrator`, con la misma URL |
| I2 | «Deploying IQ services» pone `LITELLM_API_KEY` y `LITELLM_URL` en `environment.pod.integrator` | Contradice las otras dos páginas (clave en el secret `iq-litellm-api-secret`, URL en `liteLlmUrl`). Renderizando el chart con los values de esa página, las dos variables aparecen **dos veces** en el Integrator, y las del propio chart (secret y ConfigMap) van al final y ganan | Secret `iq-litellm-api-secret` + `liteLlmUrl`, como en «Preparing LiteLLM access» e «IQ environment variables» |
| I3 | `LITELLM_URL`: «una URL HTTPS válida» | La página de LiteLLM da como endpoint `http://litellm.<ns>.svc.cluster.local:4000`, y HTTP funciona dentro del clúster | `http://…:4000` (Service interno) |
| I4 | Hay que fijar `MCP_SERVER_LIST`, porque por defecto apunta a `dx-ai-mcp-server`; un valor erróneo provoca CrashLoopBackOff. El ejemplo usa `https://`, el aviso `http://` | El chart 1.0.3 ya escribe la URL correcta en su ConfigMap (`<release>-mcp-server:3000`, `https` o `http` según `mcpServer.httpsEnabled`), y esa es la lista que usa el Integrator; la variable de entorno se ignora (CS1479102) | `MCP_SERVER_LIST` sin fijar |
| I5 | Values de ejemplo con `mcpServer.httpsEnabled: true` y `tlsCertSecret: dx-tls-cert` | **Funciona** (probado hoy: el Integrator conecta con `https://dx-iq-mcp-server:3000` e IQ usa las herramientas del MCP) | **Alineado (2026-11-08)**: `httpsEnabled: true` y `tlsCertSecret: dx-tls-cert`, como en la documentación. Comprobado con el MCP Server propio del Lab 3B (HTTP) en la misma lista: el Integrator carga las herramientas de los dos |
| I6 | Chart desde una URL (`https://<repositorio>/<chart>.tgz`, Artifactory) | Los clientes de DX Compose lo obtienen de HCL Harbor | `helm pull oci://hclcr.io/dx/hcl-dx-iq --version 1.0.3` |
| — | (observación, no es un desvío) | El Integrator avisa en el log de que tiene `NODE_TLS_REJECT_UNAUTHORIZED=0` (viene de la imagen, no del chart): desactiva la verificación de certificados en todas sus conexiones TLS salientes | Nada (comportamiento del producto); conviene comentarlo a HCL |

### Search V2 («Installing the Search V2 backend», página del 2026-08-27, sin cambios)

| # | La documentación dice | Qué pasa (comprobado en el chart 2.37.0) | Qué hacen los labs |
|---|---|---|---|
| S1 | Nada sobre activar el File Processor (solo su imagen y los tipos de fichero permitidos); «Validating the setup» muestra un pod `dx-search-file-processor` | `applications.fileProcessor: false` por defecto, pero el ConfigMap del Search Middleware fija siempre `fileprocessor_host: <release>-file-processor` (sin condición), así que el middleware lo busca igualmente («Could not connect to file processor» cada 3 segundos) | `applications.fileProcessor: true` |
| S2 | Nada sobre `configuration.automatedSetup.haproxyProtocol` | Vacío por defecto: el chart elige `https` solo si el Service del HAProxy de DX es `LoadBalancer`, y `http` en otro caso. Con DX detrás de un Ingress o una Route (`ClusterIP`, con SSL activo) usa `http`, y el Service del HAProxy solo expone el 443 (comprobado en el lab: `ClusterIP haproxy:443`), así que los crawlers indexan 0 documentos | `haproxyProtocol: https` |

### DX Compose (instalación, LDAP, base de datos externa)

| # | La documentación dice | Qué pasa | Qué hacen los labs |
|---|---|---|---|
| D1 | Bases de datos externas soportadas: Derby, DB2, Oracle («Limitations») | PostgreSQL aún no está soportado para el Web Engine (HCL lo está validando) | El lab 3 / etapa 3 se presenta como ejercicio de aprendizaje con el table script early release de HCL, y `standard_conforming_strings = off` (ver «HCL lo conoce» más abajo) |
| D2 | La página de LDAP explica `ldap.type: other` | El chart despliega su propio OpenLDAP por defecto (`applications.openLdap: true`) | `openLdap: false`; se usa un OpenLDAP externo |
| D3 | `helm install` sin `--wait` (estilo Helm 3) | Con Helm 4, `--wait` aborta la instalación mientras DAM espera a su base de datos | `--wait=legacy` con Helm 4 |
| D4 | Fichero de ejemplo `values-samples/webEngine/webEngine-sample.yaml` | En el chart 2.50.0 la carpeta es `value-samples/` | No se usa (errata menor) |

### SSL a la base de datos externa, LDAPS y login LDAP (probado el 2026-11-10)

Probado en una instalación limpia (`hcl-dx-deployment` 2.50.0) con un PostgreSQL 18 (CloudNativePG) que solo admite SSL
(`hostnossl all all all reject`) y un OpenLDAP que exige TLS, cada certificado de servidor firmado por su propia CA raíz
corporativa y las dos CAs subidas con `configuration.webEngine.customTruststoreSecrets`. Comunicado a HCL por correo (sin case todavía).

| # | Qué probamos | Qué pasa (probado) | Qué hacen los labs |
|---|---|---|---|
| S1 | `DbUrl` con dos parámetros: `?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory` | Funciona en ejecución, pero **la transferencia de base de datos falla** en el primer dominio: `SAXParseException: Element type "database" must be followed by either attribute specifications, ">" or "/>"` en `templates/db/postgresql/release/dbt_release.xml`. La URL se escribe en ese XML sin escapar el `&`, así que no se puede usar un segundo parámetro (certificado de cliente, timeouts, `ApplicationName`...) | Un solo parámetro: `?sslmode=verify-full` |
| S2 | `DbUrl` con `?sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory` | El Web Engine no llega a arrancar (CrashLoopBackOff): las herramientas que corren antes de Liberty (`initStatusTable.sh`, `getLibertyStatus.sh`) usan el truststore por defecto del JDK, no las CAs de `customTruststoreSecrets`: `PKIX path building failed` y después `Error extracting DB_TRANSFER_DONE status` | No se usa |
| S3 | `DbUrl` con `?sslrootcert=<CA montada desde el secret del truststore>` | Funciona (transferencia de 465 tablas, TLS 1.3) pero el certificado **no se valida**: con la CA equivocada también conecta (el driver se queda en `sslmode=prefer`) | No se usa |
| S4 | `DbUrl` con `?sslmode=verify-full` | **Funciona y valida**: transferencia, herramientas previas al arranque y ejecución por TLS 1.3. Sin la CA de la base de datos en `customTruststoreSecrets`: `PKIX path building failed`; con la IP del servicio en vez del nombre del certificado: `The hostname … could not be verified by hostnameverifier PgjdbcHostnameVerifier` | La forma que usan los labs y el webinar |
| S5 | Una transferencia fallida y después un `helm upgrade` corregido | El pod del Web Engine no llega a estar listo y el StatefulSet no lo sustituye (`currentRevision ≠ updateRevision`) | Borrar el pod a mano después de corregir los values |
| S6 | IQ (`hcl-dx-iq` 1.0.3) con `configuration.database.dbTlsEnabled: true` | El valor llega al ConfigMap (`dx.config.integrator.db_tls_enabled: "true"`) pero el Integrator sigue conectando sin SSL, y un servidor que exige SSL lo rechaza (`no encryption`) | Excepción en `pg_hba` solo para la base de datos de IQ (`host iqdb dx_iq_db_user all scram-sha-256`) |
| S7 | Login con el email (`andres@europesip.com`) | El bloque LDAP nativo fija `userFilter="(&(uid=%v)(objectclass=inetOrgPerson))"` (`_web-engine-ldap-config.tpl`) y ningún valor lo cambia | `configOverrideFiles` que amplía `ldapRegistry id="ldap"` con `<loginProperty name="uid"/>` y `<loginProperty name="mail"/>` (en forma de elemento: en forma de texto da `CWWKG0075E`), y reinicio del Web Engine |
| S8 | LDAPS (`port: 636`, `sslEnabled: true`) sin la CA del directorio | `CWPKI0823E SSL HANDSHAKE FAILURE` / `PKIX path building failed`: nadie puede entrar | La CA del directorio en `customTruststoreSecrets` |
| S9 | *Configuring LDAP* (configuration changes using overrides) | El ejemplo de AD con SSL usa `sslRef="customSSLConfig"`, que la página nunca define (se genera al usar `customTruststoreSecrets`); el login por email con `loginProperty` no está documentado; a los dos ejemplos de AD les falta un paréntesis de cierre: `userFilter="(&(sAMAccountName=%v)(objectcategory=user)"` | Comentarios de documentación enviados a HCL |

## Problemas reportados a HCL Support

| Case | Abierto | Problema | Estado |
|---|---|---|---|
| **CS1479102** | 2026-11-02 | IQ: la lista de servidores MCP configurada como dice la documentación se ignora | Abierto, HCL lo está reproduciendo. **Sigue en IQ 1.0.3** |
| **CS1479139** | 2026-11-02 | IQ: el *system prompt* describe una memoria RAG activa aunque el RAG está desactivado | Abierto. **Cambia en parte en IQ 1.0.3**: la directiva es más suave, pero se sigue enviando con el RAG desactivado. **El RAG ya está documentado en CF239** (probado, ver abajo) |
| **CS1479178** | 2026-11-02 | IQ: las peticiones al LLM no pueden usar *prompt caching*, así que cada llamada paga a precio completo un prefijo de ~30.000 tokens | Abierto. **Sigue en IQ 1.0.3** (prefijo de ~32.500 tokens) |

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
- **CF239 / IQ 1.0.3: sigue.** El chart sigue generando `mcp_server_list` solo con el MCP Server de
  HCL y sigue sin haber un valor para ampliarla. Novedad de 1.0.3: un `[MCP Watchdog]` vuelve a pedir
  sus herramientas a los servidores de la lista cada 10 minutos, así que un servidor que no estaba
  listo al arrancar se incorpora sin reiniciar. Pero la lista en sí solo se lee al arrancar: en
  nuestra prueba, quitar un servidor del ConfigMap no tuvo efecto hasta reiniciar el Integrator.

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
- **CF239 / IQ 1.0.3: cambia en parte.** Ya no se registran las líneas `RAG_ENABLED=false` con nivel
  `ERROR`, y la directiva se ha reescrito: ya no dice "absolute truth", no nombra las etiquetas "Past
  conversation note:" / "CRITICAL SYSTEM MEMORY HISTORY" ni otras sesiones, y añade que quien quiera
  borrar su historial debe pedírselo a su administrador. Pero **se sigue enviando con el RAG
  desactivado**, y sigue afirmando "You have access to injected historical context from prior
  conversations" y que ese contexto es "authoritative". La petición de documentación sigue abierta.
- **Documentación de CF239 (2026-11-07): la función de RAG ya está documentada** ("Configuring
  cross-session memory"): `RAG_ENABLED=true` en `environment.pod.integrator`, PostgreSQL con
  **pgvector**, dos alias de embeddings en LiteLLM (`iq-multilingual-embed` / `iq-embed`),
  `EMBEDDING_DIMENSIONS` (1024), ajustes de troceado y recuperación, retención y borrado por usuario
  con SQL (no se borra nada automáticamente). Responde a casi toda la petición de documentación; la
  directiva enviada con el RAG desactivado sigue sin mencionarse.
- **Probado en el clúster del lab (IQ 1.0.3, 2026-11-07)**, con `baai/bge-m3` a través de OpenRouter
  (1024 dimensiones; Cohere v4, el modelo que valida HCL, no está en OpenRouter) y
  `CREATE EXTENSION vector` en `iqdb` (la imagen `standard` de CNPG incluye pgvector 0.8.7). Resultados:
  - Funciona: un dato contado en una conversación se respondió en otra nueva. Otro usuario (`andres`)
    no lo obtuvo: la memoria es por usuario.
  - El RAG arranca con la primera pregunta, no al iniciar (no hay líneas `[RAG]` hasta entonces). Los
    valores por defecto que registra (`topK=10, minSimilarity=0.35`) no son los de la página del RAG
    (5 y 0); la página de variables de entorno dice 5 y 0,35.
  - **Bug: la memoria se pierde en cada reinicio del Integrator.** Al arrancar, el Integrator crea o
    "sincroniza" `rag_chunks` con `embedding` como `text`; con la primera pregunta el backend de
    pgvector la convierte en `vector(1024)` (`[pgvector] embedding column converted from text to
    vector(1024)`). Eso ocurre en **cada** arranque, y los *embeddings* guardados no lo sobreviven.
    Medido: 26 fragmentos, 2 con *embedding* → tras un reinicio, 26 y **0** con *embedding* (columna de
    tipo `text`) → tras una pregunta, otra vez `vector(1024)` solo con el fragmento nuevo. El texto de
    las conversaciones sigue en la tabla, pero sin *embeddings* no se puede recuperar nunca. Así que la
    memoria solo funciona hasta el siguiente `helm upgrade` o reinicio del pod. **Sin reportar todavía**:
    merece un case nuevo.
  - Cada pregunta llama además al modelo de embeddings (pocos tokens, muy barato).
  - **Rompe el prompt caching cuando recupera memoria**: el contexto se inyecta en el *system prompt*,
    así que el prefijo cambia. Medido: las preguntas sin memoria recuperada leyeron ~37.000 tokens de
    la caché; la que recuperó memoria volvió a escribir todo el prefijo
    (`cache_creation_input_tokens=37352`, `cache_read_input_tokens=0`), a 1,25× el precio de entrada.
    Ver CS1479178.

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
- **CF239 / IQ 1.0.3: sigue.** Sin el workaround de LiteLLM, 5 llamadas al modelo de 2 preguntas
  devolvieron todas `cache_read_input_tokens=0` y `cache_creation_input_tokens=0`. El prefijo ha
  crecido a **~32.500 tokens** (60 herramientas; *system prompt* de 18.912 caracteres en vez de
  14.068). Con el workaround, la segunda llamada leyó 32.157 tokens de la caché.
- **Con el RAG activado (CF239, 2026-11-07)** el workaround solo ayuda cuando no se recupera memoria:
  el contexto recuperado va en el *system prompt*, antes de la marca de caché, así que esas llamadas
  vuelven a escribir todo el prefijo (~37.000 tokens con 86 herramientas). Colocar la memoria después
  del prefijo fijo (por ejemplo, en un mensaje aparte) la mantendría cacheable.

## Problemas no reportados (sin case abierto)

### HCL lo conoce: previsto para una versión futura

| Problema | Solución en los labs |
|---|---|
| **El Web Engine sobre PostgreSQL no está soportado en CF238** (sí DB2, Oracle y SQL Server). HCL está validando PostgreSQL para el Web Engine (sus pruebas funcionan con PostgreSQL 18). En nuestras pruebas, el Web Engine (OpenJPA) genera `LIKE … ESCAPE '\'` (estilo DB2/Oracle), que PostgreSQL rechaza con «invalid escape string» con su configuración por defecto | El Lab 2B se presenta como ejercicio de aprendizaje, no como configuración soportada. El script de preparación de PostgreSQL pone `standard_conforming_strings = off` (y `escape_string_warning = off`) en `dx_core` |

### IQ (hcl-dx-iq 1.0.2; revisado en 1.0.3)

| Problema | Solución en los labs | ¿Case? |
|---|---|---|
| **`LITELLM_BASE_URL` no está documentada pero es imprescindible.** Con solo el valor documentado `configuration.litellm.liteLlmUrl`, el adaptador LLM del Integrator no envía las peticiones a nuestro LiteLLM | `LITELLM_BASE_URL` en `environment.pod.integrator` con la misma URL (`custom-iq-values.yaml`). **Sigue siendo necesaria en 1.0.3**: sin ella, IQ responde "The LLM service is temporarily unavailable" | Candidato a case |
| **`LITELLM_URL` y `LITELLM_API_KEY` no se pueden sobrescribir** con `environment.pod.integrator`: el chart las vuelve a definir | La URL va en `configuration.litellm.liteLlmUrl` (+ `LITELLM_BASE_URL`); la clave, en el secret `iq-litellm-api-secret`. **Igual en 1.0.3** | Pendiente de añadir como comentario al CS1479102 |
| **Los nombres de las herramientas MCP llevan puntos** (`dam.mime-type…`), que las APIs de Anthropic y OpenAI rechazan (solo `[a-zA-Z0-9_-]`): con un proveedor que no los adapte, la petición entera falla con HTTP 400 | LiteLLM usa su proveedor `anthropic/` contra el endpoint compatible con Anthropic de OpenRouter, que adapta los nombres. HCL recomienda `enableDam: false` con modelos que no sean Claude. **Resuelto en 1.0.3**: las 55 herramientas tienen nombres válidos (`get_collection_from_DAM`...), y el Integrator añade un prefijo por servidor (`tool61b8b48c_...`) | No (petición de mejora) |
| **El Integrator solo lee las herramientas MCP al arrancar.** Si arranca antes de que el MCP Server esté listo (lo normal en una instalación nueva), se queda sin herramientas hasta que se reinicia | La instalación espera al MCP Server y después reinicia el Integrator (`04-iq-install.sh`). **Mitigado en 1.0.3**: un *watchdog* vuelve a leer las herramientas cada 10 minutos (probado: las de un servidor arrancado después aparecieron a los 10 minutos) | No |
| **OpenRouter no está validado por HCL** (las guías de HCL usan AWS Bedrock) | Documentado en el Lab 3: se usa OpenRouter a través de LiteLLM para evitar preparar una cuenta de AWS Bedrock | No (decisión de diseño) |

### Search V2 (hcl-dx-search 2.36.0; los dos siguen en 2.37.0)

| Problema | Solución en los labs | ¿Case? |
|---|---|---|
| **Con DX publicado mediante un Ingress o una Route, los rastreadores usan `http` e indexan 0 documentos.** `automatedSetup.haproxyProtocol` viene vacío por defecto, y entonces el chart elige el protocolo según el tipo del Service del HAProxy de DX: `https` si es `LoadBalancer` (el valor por defecto del chart de DX) y `http` en cualquier otro caso. No mira `networking.haproxy.ssl`, que es lo que decide si HAProxy usa TLS. Con los valores por defecto de los dos charts funciona. Pero publicar DX con un Ingress (Kubernetes) o una Route (OpenShift) implica `serviceType: ClusterIP`, normalmente con el SSL activado: Search llama entonces al HAProxy por el puerto 80, donde no escucha nadie, y los rastreadores agotan el tiempo. La regla solo aparece en un comentario del `values.yaml` del chart de Search; la página de HCL «Installing the Search V2 backend» no la menciona | `haproxyProtocol: https` en `custom-search-values.yaml`, que conviene fijar siempre de forma explícita cuando el HAProxy es `ClusterIP` o `NodePort` con SSL | No (configuración nuestra; como mucho, una sugerencia de documentación) |
| **El File Processor es una dependencia no documentada.** El chart de Search lo desactiva por defecto (`applications.fileProcessor: false`), pero configura siempre el Search Middleware para usarlo (`fileprocessor_host: <release>-file-processor` en su ConfigMap, sin ninguna condición), así que el middleware lo busca igualmente y registra «Could not connect to file processor» cada 3 segundos. La página de HCL «Installing the Search V2 backend» (CF238) no dice en ningún momento que haya que activarlo: solo da su imagen y la lista de tipos de fichero permitidos, mientras que la salida esperada de «Validating the setup» muestra un pod `dx-search-file-processor` que los valores por defecto no despliegan | `applications.fileProcessor: true` | Candidato a case (documentación, o valores por defecto del chart incoherentes con el middleware) |

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

### LiteLLM con AWS Bedrock (documentación de CF239, «Deploying LiteLLM»)

Comprobado el 2026-11-07 con una clave de API de Bedrock (`AWS_BEARER_TOKEN_BEDROCK`), como recomienda la documentación.

| Problema | Lo que funciona | ¿Case? |
|---|---|---|
| El ID de modelo indicado para Sonnet 4.6, `us.anthropic.claude-sonnet-4-6-20250514-v1:0`, no existe: Bedrock responde «The provided model identifier is invalid» (20250514 es la fecha de Claude Sonnet 4) | `us.anthropic.claude-sonnet-4-6` (sin fecha). El ID de Haiku 4.5 de la documentación, `us.anthropic.claude-haiku-4-5-20251001-v1:0`, es correcto | Aún no |
| El ejemplo no indica región (`aws_region_name`), y los perfiles de inferencia `us.` solo funcionan desde regiones de EE. UU. | `aws_region_name: us-east-1` en cada modelo (o los perfiles `eu.` con `eu-west-1`, que mantienen los datos en la UE) | Aún no |
| Los modelos de Anthropic necesitan una vez por cuenta de AWS el formulario «use case details» (no se menciona): hasta enviarlo, Bedrock responde «Model use case details have not been submitted for this account» | Enviarlo una vez en la consola de Bedrock o con `aws bedrock put-use-case-for-model-access` | No (requisito de AWS) |

### Componentes de terceros (no de HCL)

| Problema | Solución en los labs |
|---|---|
| OpenLDAP (`openldap-stack-ha`): un LDIF propio sin la entrada raíz hace fallar el primer `ldapadd` y el LDAP arranca vacío | `demo-users.ldif` incluye `dn: dc=dxdemo,dc=com` |
| El `local-path` de k3s no admite ReadWriteMany (DAM lo necesita) | Lab 0: StorageClass estática con un volumen `hostPath` |
| Los volúmenes `hostPath` ignoran el `fsGroup` del pod: DAM (uid 1000/gid 1001) no puede escribir (`EACCES`) | Lab 0: `01-storage.sh` deja el directorio como `1000:1001` |
| Los modelos de razonamiento de OpenAI (gpt-5.x) inyectan `reasoning_effort` y rompen las herramientas de IQ | Documentado en `litellm-values.yaml`: usar Claude |
