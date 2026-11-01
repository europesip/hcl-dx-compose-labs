# Lab 2 · LDAP y base de datos PostgreSQL

**Punto de partida:** el Lab 1 terminado (DX en `dx-demo`, accesible por `https://$DX_HOST`).

**⏱ Tiempo estimado: ~27 minutos** (2A ~10 min · 2B ~17 min).

| Iteración · paso | Tiempo |
|---|---|
| 2A-1/2 · OpenLDAP y su prueba | ~1 min |
| 2A-3 · `helm upgrade` de DX con LDAP (reinicia el Web Engine) | ~5 min |
| 2A-4 · Rol de administrador para `dxadmins` en la consola del portal | ~3 min |
| 2B-1/2/3 · Operador CNPG, usuarios y cluster PostgreSQL | ~2 min |
| 2B-4 · Secrets de propiedades | segundos |
| 2B-5 · Transferencia de Derby a PostgreSQL (`helm upgrade`) | **~14 min** |
| Comprobaciones | ~1 min |

> Tiempos de ejecución medidos en el clúster del webinar (k3s, 3 workers de 14 CPU / 20 GiB), sin
> contar las explicaciones. La primera vez en un clúster nuevo hay que sumar la descarga de las
> imágenes de HCL desde `hclcr.io`, que depende de la red.

**Objetivo:** dos iteraciones sobre la instalación existente, cada una con un `helm upgrade`:

| Iteración | Qué cambia | En `dx-shared` | Capa de DX |
|---|---|---|---|
| **2A · LDAP** | Los usuarios se autentican contra un directorio LDAP | OpenLDAP | `a-ldap/custom-values.ldap.yaml` |
| **2B · PostgreSQL** | La BD del Web Engine pasa de Derby (embebida, no válida en producción) a PostgreSQL | PostgreSQL 18 (CloudNativePG) | `b-postgres/custom-values.postgres.yaml` |

El OpenLDAP, el PostgreSQL y su operador no son software de HCL: van en **`dx-shared`**, el
namespace que hemos creado para todas las herramientas externas a HCL. En `dx-demo` (DX) solo
cambia la configuración: `common/dx-helm.sh` añade la capa de cada iteración al
`custom-values.yaml` del Lab 1.

### Dos caminos: demo o empresarial

```
                         ┌─► 2A OpenLDAP (dx-shared) ─────┐   ┌─► 2B PostgreSQL (dx-shared) ─┐
 Lab 1 (DX base) ──────► │        esta guía · DEMO        ├─► │        esta guía · DEMO      ├──► Lab 3
                         └─► 2A Active Directory ─────────┘   └─► 2B Oracle ─────────────────┘
                              GUIA-empresa.md · EMPRESARIAL       GUIA-empresa.md · EMPRESARIAL
```

- **Demo (esta guía):** OpenLDAP y PostgreSQL se despliegan en el propio clúster en minutos y no
  dependen de nada externo. Es lo que hacemos en el webinar.
- **Empresarial ([GUIA-empresa.md](GUIA-empresa.md)):** en empresas corporativas lo habitual es
  **Microsoft Active Directory** como directorio y **Oracle** como base de datos. Se aportan como
  referencia avanzada: AD con `configOverrideFiles` (sus filtros difieren de OpenLDAP) y Oracle
  por TCPS. Oracle, a diferencia de PostgreSQL, está soportado por HCL para el Web Engine.

Cada iteración se puede hacer por cualquiera de los dos caminos (p. ej. AD + PostgreSQL).

```bash
cd hcl-dx-compose-labs && source ./env.sh
```

---

## 2A · Autenticación LDAP

Documentación de HCL:
[Configuring LDAP (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_webengine/ldap_configuration/)

```
 DX (dx-demo)                                 dx-shared
 Web Engine ── LDAP 389 ──► openldap.dx-shared.svc.cluster.local
   repositorio federado:                       dc=dxdemo,dc=com
     o=defaultWIMFileBasedRealm (wpsadmin)       ou=users:  7 usuarios de demo
     dc=dxdemo,dc=com           (LDAP)           ou=groups: dxadmins, dxauthors, dxmarketing
```

| Grupo LDAP | Usuarios | Permisos en DX |
|---|---|---|
| `dxadmins` | andres, eduardo | **Administrador del portal** (paso 4) |
| `dxauthors` | macarena, enrique, jordi | usuario autenticado |
| `dxmarketing` | patricia, german | usuario autenticado |

Todos con la contraseña **EuropeS1P** (`LDAP_USERS_PASSWORD`). `wpsadmin` (registro básico, grupo `wpsadmins`)
sigue siendo el administrador inicial.

### Paso 1 · OpenLDAP de laboratorio

```bash
lab2-ldap-postgres/a-ldap/01-ldap-install.sh
```

- Secret `openldap-admin` con la contraseña de `cn=admin,dc=dxdemo,dc=com` (`LDAP_ADMIN_PASSWORD`).
- ConfigMap `openldap-demo-ldif` con [demo-users.ldif](a-ldap/demo-users.ldif): la raíz `dc=dxdemo,dc=com`,
  los 7 usuarios y los 3 grupos de la tabla de arriba.
- Chart comunitario `helm-openldap/openldap-stack-ha` 4.3.3 con
  [openldap-values.yaml](a-ldap/openldap-values.yaml): una réplica y un PVC de 1 GiB en `dx-deploy-rwo`.

> En un cliente real este paso no existe: se usa su directorio corporativo y solo cambian host,
> puerto, sufijo y usuario de bind en la capa de DX.

### Paso 2 · Probar el LDAP antes de tocar DX

```bash
lab2-ldap-postgres/a-ldap/02-ldap-test.sh
```

Lista las entradas, los grupos con sus miembros y comprueba que `andres` se autentica. Si esto
falla, DX tampoco podrá autenticar.

### Paso 3 · Conectar DX al LDAP

Lee [custom-values.ldap.yaml](a-ldap/custom-values.ldap.yaml):

```yaml
configuration:
  webEngine:
    ldap:
      type: "other"                                  # LDAP externo
      host: "openldap.dx-shared.svc.cluster.local"   # servicio en el OTRO namespace: FQDN
      port: 389
      sslEnabled: false
      suffix: "dc=dxdemo,dc=com"
      serverType: "Custom"
      customLdapSecret: "dx-ldap-bind"               # claves bindUser / bindPassword
```

```bash
lab2-ldap-postgres/a-ldap/03-dx-upgrade.sh
```

Crea el secret `dx-ldap-bind` en `dx-demo` y hace el `helm upgrade` con la capa LDAP:

```bash
helm upgrade --install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
  -f lab1-dx-base/custom-values.yaml \
  -f lab2-ldap-postgres/a-ldap/custom-values.ldap.yaml \
  --set-string networking.webEngine.host=$DX_HOST --timeout 30m --wait
```

**Qué genera el chart.** Con `type: other`, el chart de CF238 crea la configuración de Open Liberty:
un `<ldapRegistry>` (filtros `inetOrgPerson` para usuarios y `groupOfUniqueNames` para grupos) y un
`<federatedRepository>` que une **el registro básico** (`o=defaultWIMFileBasedRealm`, donde vive
`wpsadmin`) **y el LDAP**. Por eso wpsadmin sigue entrando y los usuarios del LDAP también. Para
filtros o atributos distintos se usaría `configuration.webEngine.configOverrideFiles` con XML propio.

> **Variante sin registro básico.** Si todos los usuarios, incluido el administrador, están en el
> LDAP: `security.webEngine.basicRegistry.enabled: false` y `webEngineUser` con el **DN completo**
> del administrador (p. ej. `uid=dxadmin,ou=users,dc=dxdemo,dc=com`), que debe pertenecer al grupo
> `security.webEngine.webEngineAdminGroup`.

### Paso 4 · Permisos de administrador para el grupo `dxadmins`

**Autenticación y autorización son cosas distintas.** Tras el paso 3, DX sabe *quién* es cada
usuario del LDAP (autenticación), pero ninguno puede administrar nada: lo que cada uno puede hacer
lo deciden los **permisos de DX** (autorización), que se guardan en la base de datos de DX, no en
el LDAP.

El grupo `dxadmins` (andres, eduardo) **ya existe en el LDAP**, pero **hay que entrar en el portal
y darle los permisos de administrador**:

1. Entra en `https://$DX_HOST/wps/myportal` como **wpsadmin**.
2. Ve a la página de seguridad: *Administración → Acceso → Permisos de recursos*
   (*Administration → Access → Resource Permissions*).
3. Tipo de recurso **Recursos virtuales** (*Virtual Resources*) → **PORTAL** → *Asignar acceso*.
4. En el rol **Administrator** → *Añadir* → busca el grupo `dxadmins` → *Aceptar*.

En DX los permisos son **roles sobre recursos**: el recurso virtual `PORTAL` es la raíz de la
jerarquía y el rol *Administrator* sobre él se hereda en todo el portal. Se asigna a un **grupo** y
no a usuarios: para que eduardo deje de ser administrador basta con sacarlo de `dxadmins` en el
LDAP. El permiso queda en la base de datos de DX, así que en el Lab 2B viaja con la transferencia.

> **Alternativa: con un override.** Igual que la rama de Active Directory
> ([GUIA-empresa.md](GUIA-empresa.md)) configura el registro con `configOverrideFiles`, se puede
> añadir a usuarios del LDAP al grupo de administración del registro básico (`wpsadmins`, el
> `DX_ADMIN_GROUP` del chart). Además del rol del portal, eso les da las herramientas que DX
> Compose reserva a ese grupo en Open Liberty (XMLAccess y WebDAV). Se añade a la capa LDAP:
>
> ```yaml
> configuration:
>   webEngine:
>     configOverrideFiles:
>       admin-members.xml: |
>         <server description="Administradores de DX desde el LDAP">
>           <basicRegistry id="basic" realm="defaultWIMFileBasedRealm">
>             <user name="${DX_ADMIN}" password="${DX_PASSWORD}"/>
>             <group name="${DX_ADMIN_GROUP}">
>               <member name="${DX_ADMIN}"/>
>               <member name="andres"/>
>               <member name="eduardo"/>
>             </group>
>           </basicRegistry>
>         </server>
> ```
>
> Las variables `${DX_ADMIN}`, `${DX_PASSWORD}` y `${DX_ADMIN_GROUP}` las define el propio chart
> desde `web-engine-secret`: la contraseña no se escribe en el fichero.

> **¿Por qué no `security.webEngine.webEngineAdminGroup: dxadmins`?** Ese valor no busca el grupo
> en el LDAP: crea en el **registro básico** un grupo con ese nombre que contiene a `wpsadmin`. Con
> el repositorio federado habría dos grupos `dxadmins` (uno en cada repositorio) y Liberty puede
> fallar con "múltiples entidades encontradas".

### Comprobar

1. `https://$DX_HOST/wps/myportal` con **macarena** / **EuropeS1P** → entra como usuario
   autenticado, **sin** menú de administración.
2. Con **andres** o **eduardo** → entra y **sí** tiene administración (y Practitioner Studio).
3. Con **wpsadmin** → sigue funcionando.
4. Para ver qué configuración LDAP ha generado el chart:
   `kubectl -n dx-demo get cm dx-deployment-web-engine-overrides -o jsonpath='{.data.ldap-config\.xml}'`.

> **LDAPS en producción:** `port: 636`, `sslEnabled: true` y la CA del LDAP en el truststore del
> Web Engine (`configuration.webEngine.customTruststoreSecrets`). Ver
> [Custom certificates (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/working_with_compose/custom_certificates/).

---

## 2B · Transferencia de la base de datos a PostgreSQL

Documentación de HCL:
[External database and database transfer (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_webengine/external_db_database_transfer/)

> ⚠️ **Soporte.** En CF238 HCL soporta para el Web Engine **DB2, Oracle y SQL Server**
> ([Databases](https://help.hcl-software.com/digital-experience/9.5/CF238/get_started/system_requirements/kubernetes/databases/)).
> PostgreSQL está en validación por HCL (sus pruebas funcionan con PostgreSQL 18) pero **hoy no
> está soportado**. El procedimiento (secrets de propiedades, `useExternalDatabase`,
> `dropDatabaseTables`) es el mismo para las BD soportadas, que es lo que se aprende aquí.

```
 Antes:  Web Engine ── Derby (fichero en el PVC customization)
 Después: Web Engine ── JDBC 5432 ──► dx-pg-rw.dx-shared.svc.cluster.local / dx_core
                                        6 esquemas: release, jcr, community, customization,
                                                    feedback, likeminds  (~465 tablas)
```

**Por qué nuestro propio PostgreSQL 18 (y no el de HCL).** HCL distribuye un PostgreSQL: el
*Persistence Node* (`dx-deployment-persistence-node-0`, en `dx-demo`), que se instala como
**persistencia de DAM** y que hoy es **PostgreSQL 16** (16.15 en este clúster). Lo gestiona el
propio DX (repmgr, pool de conexiones, Runtime Controller) y no está pensado como base de datos de
propósito general. Para el Web Engine hemos preferido **nuestra propia versión, PostgreSQL 18**
(18.6), por dos motivos:

- **Usar una versión más moderna**, la misma con la que HCL está validando el Web Engine sobre
  PostgreSQL.
- **Ponernos en el caso de una instalación que ya tuviera su PostgreSQL**: en un cliente, la base
  de datos suele ser corporativa y externa a DX. Por eso va en **`dx-shared`**, fuera del
  namespace de HCL, y DX se conecta a ella como lo haría a la de la empresa.

| | PostgreSQL de HCL (Persistence Node) | Nuestro PostgreSQL |
|---|---|---|
| Versión | 16 | **18** |
| Namespace | `dx-demo` (lo instala el chart de DX) | **`dx-shared`** (lo instalamos nosotros con CloudNativePG) |
| Uso | DAM (y People Service / IQ interno) | **Web Engine** (`dx_core`) |
| Quién lo gestiona | DX | Nosotros (o el DBA de la empresa) |

### Paso 1 · Operador CloudNativePG

```bash
lab2-ldap-postgres/b-postgres/01-cnpg-operator.sh
```

Instala `cnpg/cloudnative-pg` 0.29.1 (operador 1.30.1) en `dx-shared`. CNPG gestiona PostgreSQL
de forma declarativa: base de datos, roles, tablespaces y réplicas se describen en un recurso
`Cluster`. En OpenShift se instalaría desde OperatorHub.

### Paso 2 · Usuarios de PostgreSQL

```bash
lab2-ldap-postgres/b-postgres/02-secrets-postgres.sh
```

Secrets `basic-auth` en `dx-shared` para `postgres` (superusuario), `dxuser` (dueño de la BD del
Web Engine) y `dx_iq_db_user` (lo usa el apéndice del Lab 3).

### Paso 3 · Cluster PostgreSQL 18 y preparación de la base de datos

```bash
lab2-ldap-postgres/b-postgres/03-postgres-cluster.sh
```

**Qué preparamos y qué hace DX.** Nosotros dejamos lista una base de datos **vacía** pero con la
forma que espera DX: la base de datos, sus esquemas, roles, permisos, tablespaces y parámetros.
**Las tablas (~465) no las crea ningún script**: las crea el Web Engine durante la transferencia
del paso 5, igual que con DB2 u Oracle.

La preparación tiene dos partes:

**1. El cluster, declarativo** ([cluster-dx-pg.yaml](b-postgres/cluster-dx-pg.yaml)). CNPG crea:

| Elemento | Valor | Por qué |
|---|---|---|
| Imagen | `ghcr.io/cloudnative-pg/postgresql:18.6-standard-trixie` | Versión menor fijada |
| BD | `dx_core`, dueño `dxuser`, UTF8, `en_US.UTF-8` | Una sola BD con un esquema por dominio de DX |
| Tablespaces | `icmlfq32`, `icmlnf32`, `icmvfq04`, `icmsfq04`, `icmlsndx`, de `dxuser` | Los usa el JCR de DX; CNPG da a cada uno su PVC |
| `max_connections` / `max_prepared_transactions` | 500 / 500 | DX usa transacciones XA (2PC); en PostgreSQL `max_prepared_transactions` vale 0 por defecto |
| Rol `dx_iq_db_user` | con login | Para el apéndice del Lab 3 (sesiones de IQ en PostgreSQL) |

**2. El script SQL de preparación** ([setup-postgres-dx.sql](b-postgres/setup-postgres-dx.sql)).
Se ejecuta **una sola vez**, como `postgres`, dentro de `dx_core`. El script `03-...` lo carga en el
ConfigMap `dx-pg-setup-sql` y CNPG lo ejecuta al crear el cluster
(`bootstrap.initdb.postInitApplicationSQLRefs`). Hace, por este orden:

| Bloque | Sentencias | Para qué |
|---|---|---|
| Extensiones | `uuid-ossp`, `pgcrypto` | Funciones de UUID y criptografía (incluidas en la preparación de PostgreSQL del laboratorio original) |
| Parámetros de `dx_core` | `ALTER DATABASE dx_core SET standard_conforming_strings = off` (y `escape_string_warning = off`) | El OpenJPA del Web Engine escribe `ESCAPE '\'` (estilo DB2/Oracle); con el valor por defecto (`on`) PostgreSQL lo rechaza con "invalid escape string" |
| Esquemas | `release`, `community`, `customization`, `jcr`, `feedback`, `likeminds`, propiedad de `dxuser` | Un esquema por dominio de DX (los `DbSchema` de las properties del paso 4) |
| Permisos de `dxuser` | `GRANT ALL` sobre la BD y los esquemas, y `ALTER DEFAULT PRIVILEGES` para tablas y secuencias | Que `dxuser` sea dueño de todo lo que cree el Web Engine |
| Roles de DX | `WP_BASE_*`, `WP_JCR_*`, `WP_PZN_*` (`CONFIG` y `RUNTIME`) | Los `DbConfigRoleName`/`DbRuntimeRoleName` de las properties |
| Permisos de los roles | `release`/`community`/`customization` → `WP_BASE_CONFIG_USERS`; `jcr` → `WP_JCR_CONFIG_USERS`; `feedback`/`likeminds` → `WP_PZN_CONFIG_USERS`; `dxuser` miembro de los seis | El reparto de dominios que usa DX |

> **PostgreSQL corporativo ya existente.** Si la base de datos la gestiona un DBA, él crea antes
> la BD `dx_core`, el usuario `dxuser`, los tablespaces y los parámetros XA, y ejecuta el mismo
> script: `psql -U postgres -d dx_core -f setup-postgres-dx.sql`. En ese caso no se usan los pasos
> 1 a 3 de esta guía (operador y cluster CNPG) y las properties del paso 4 apuntan a su servidor.

### Paso 4 · Propiedades de base de datos del Web Engine

```bash
lab2-ldap-postgres/b-postgres/04-secrets-webengine.sh
```

Crea en `dx-demo` los dos secrets que pide HCL, con claves de nombre fijo:

| Secret | Clave | Contenido |
|---|---|---|
| `custom-credentials-webengine-dbtype-secret` | `dx_dbtype.properties` | Driver JDBC ([dx_dbtype.properties](b-postgres/dx_dbtype.properties)): el de PostgreSQL ya viene en la imagen del Web Engine |
| `custom-credentials-webengine-dbdomain-secret` | `dx_dbdomain.properties` | Los 6 dominios ([plantilla](b-postgres/dx_dbdomain.properties.template)): URL, esquema, usuario, roles y datasource de cada uno |

Ejemplo de un dominio:

```properties
release.DbType=postgresql
release.DbName=dx_core
release.DbSchema=release
release.DataSourceName=wpreldbDS
release.DbUrl=jdbc:postgresql://dx-pg-rw.dx-shared.svc.cluster.local:5432/dx_core?sslmode=disable
release.DbUser=dxuser
release.DbConfigRoleName=WP_BASE_CONFIG_USERS
release.DbRuntimeRoleName=WP_BASE_RUNTIME_USERS
...
```

> Reglas de HCL: `clave=valor` **sin comillas**, y con secrets el chart **ignora**
> `dbDomainProperties`/`dbTypeProperties` del values: todo tiene que estar en el secret.
> El script genera el fichero con la contraseña, crea el secret y lo borra del disco.

### Paso 5 · Transferencia

Lee [custom-values.postgres.yaml](b-postgres/custom-values.postgres.yaml):

```yaml
configuration:
  webEngine:
    useExternalDatabase: true      # transfiere UNA vez de Derby a la BD externa
    customDbTypePropertiesSecret: custom-credentials-webengine-dbtype-secret
    customDbDomainPropertiesSecret: custom-credentials-webengine-dbdomain-secret
    dropDatabaseTables: false      # la BD de destino está vacía
```

```bash
lab2-ldap-postgres/b-postgres/05-dx-transfer.sh
```

`helm upgrade` con las tres capas (base + LDAP + PostgreSQL). El Web Engine se reinicia y, al
arrancar, copia los datos de Derby a PostgreSQL. Síguelo en otra terminal:

```bash
kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
```

- **No escales el Web Engine** mientras dura (HCL no soporta escalar durante la transferencia).
- La transferencia queda registrada: reinicios y upgrades posteriores no la repiten.
- `dropDatabaseTables: true` solo hace falta para rehacerla sobre una BD con tablas, y **borra su
  contenido**. Si la usas, vuelve a `false` en cuanto termine (HCL lo recomienda expresamente).

### Comprobar

```bash
lab2-ldap-postgres/b-postgres/99-verify.sh
```

- ~465 tablas en `dx_core` (release ≈182, jcr ≈96, community ≈75, customization ≈51, feedback ≈48,
  likeminds ≈13) y conexiones abiertas de `dxuser`.
- En el portal: la **página de prueba del Lab 1 sigue ahí** y `andres` sigue entrando (el LDAP no
  depende de la BD).

---

**Siguiente:** [Lab 3 · IQ con OpenRouter](../lab3-iq-openrouter/GUIA.md)
