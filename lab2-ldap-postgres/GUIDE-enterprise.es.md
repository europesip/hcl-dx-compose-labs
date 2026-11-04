# Lab 2 · Rama empresarial: Active Directory y Oracle

[English](GUIDE-enterprise.md) · **Español**

> **Caso avanzado y opcional.** En la demo usamos **OpenLDAP** y **PostgreSQL** ([GUIDE.es.md](GUIDE.es.md))
> porque se despliegan en el propio clúster en un par de minutos. En empresas corporativas lo
> habitual es que el directorio sea **Microsoft Active Directory** y la base de datos **Oracle**,
> ya existentes y gestionados por otros equipos. Esta rama muestra cómo se conecta DX Compose a
> ellos, como referencia para llevar el laboratorio a un entorno real.

**⏱ Tiempo estimado:** en DX, el mismo que en la rama demo (~5 min el `helm upgrade` del AD y
~14 min la transferencia a Oracle). A eso se suma la preparación del lado corporativo (cuenta de
servicio y CA del AD; PDB, script SQL y listener TCPS de Oracle), que depende de cada empresa.

Las dos iteraciones son las mismas que en la rama demo; solo cambia contra qué se conecta DX:

| Iteración | Rama demo | Rama empresarial | Qué cambia en DX |
|---|---|---|---|
| **2A · Directorio** | OpenLDAP en `dx-shared` | **Active Directory** corporativo | Bloque nativo `ldap:` → **`configOverrideFiles`** con un `<ldapRegistry>` de AD |
| **2B · Base de datos** | PostgreSQL 18 (CNPG) en `dx-shared` | **Oracle 19c/21c** corporativo, por **TCPS** | Las properties apuntan a Oracle + CA del listener en el truststore |

Se pueden combinar: AD + PostgreSQL, OpenLDAP + Oracle, AD + Oracle. `common/dx-helm.sh` elige la
capa de cada iteración según los secrets que existan (y se para si hay dos ramas a la vez).

| | Soporte HCL en CF238 |
|---|---|
| Active Directory | Sí (LDAP soportado; `ldapType="Microsoft Active Directory"` de Open Liberty) |
| Oracle | **Sí** para el Web Engine (19c y 21c, AL32UTF8/AL16UTF16). PostgreSQL, el de la demo, todavía no |

```bash
cd hcl-dx-compose-labs && source ./env.sh   # rellena la sección "Enterprise branch" de env.sh
```

---

## 2A-E · Active Directory

Partimos del Lab 1 terminado. **No** se ejecuta la parte OpenLDAP de la guía demo (si ya la
hiciste: `kubectl -n dx-demo delete secret dx-ldap-bind`).

### Por qué overrides y no el bloque nativo

El bloque nativo `configuration.webEngine.ldap` del chart genera filtros pensados para OpenLDAP
(`inetOrgPerson`, `groupOfUniqueNames`/`uniqueMember`). Active Directory usa otros:

| | OpenLDAP (demo) | Active Directory |
|---|---|---|
| Login | `uid` | `sAMAccountName` (usuario de Windows) |
| Clase de usuario | `inetOrgPerson` | `person` / `objectCategory=person` |
| Clase de grupo | `groupOfUniqueNames` | `group` / `objectCategory=group` |
| Pertenencia | `uniqueMember` en el grupo | `member` en el grupo **y** `memberOf` en el usuario |
| Bind | DN (`cn=admin,dc=...`) | UPN (`svc-dx@empresa.local`) o DN |

Por eso escribimos el registro con **`configOverrideFiles`**: XML de Open Liberty que el chart
fusiona con el `server.xml` del Web Engine (se aplica en caliente, sin reiniciar el pod).

### Paso AD-1 · Secret de conexión

Variables en `env.sh`: `AD_HOST`, `AD_PORT`, `AD_SSL`, `AD_BASE_DN`, `AD_BIND_USER`,
`AD_BIND_PASSWORD` (cuenta de servicio de **solo lectura**) y, para LDAPS, `AD_CA_FILE`.

```bash
lab2-ldap-postgres/enterprise/active-directory/01-secrets-ad.sh
```

Comprueba que el clúster llega al AD y crea el secret `dx-ad-bind`. El chart lo inyecta en el
Web Engine como **variables de entorno** (`configuration.webEngine.customSecrets`) y Open Liberty
las sustituye en el XML: ni el host ni la contraseña quedan en los values.

### Paso AD-2 · La capa de DX

[custom-values.ad.yaml](enterprise/active-directory/custom-values.ad.yaml), lo esencial:

```xml
<ldapRegistry id="ad" realm="ActiveDirectoryRealm"
    host="${AD_HOST}" port="${AD_PORT}" baseDN="${AD_BASE_DN}"
    bindDN="${AD_BIND_USER}" bindPassword="${AD_BIND_PASSWORD}"
    ldapType="Microsoft Active Directory" sslEnabled="${AD_SSL}"
    referral="ignore" searchPageSize="500" searchTimeLimit="15s" readTimeout="30s" connectTimeout="10s">
  <activedFilters
      userFilter="(&amp;(sAMAccountName=%v)(objectcategory=person))"
      groupFilter="(&amp;(cn=%v)(objectcategory=group))"
      userIdMap="user:sAMAccountName" groupIdMap="*:cn" groupMemberIdMap="memberOf:member"/>
  <attributeConfiguration>
    <attribute name="sAMAccountName" propertyName="uid" entityType="PersonAccount"/>
  </attributeConfiguration>
  <groupProperties>
    <memberAttribute name="member" scope="direct" objectClass="group"/>
    <membershipAttribute name="memberOf" scope="direct"/>
  </groupProperties>
</ldapRegistry>
<federatedRepository>
  <primaryRealm name="FederatedRealm" allowOpIfRepoDown="true">
    <participatingBaseEntry name="o=defaultWIMFileBasedRealm"/>   <!-- wpsadmin -->
    <participatingBaseEntry name="${AD_BASE_DN}"/>                <!-- el AD -->
  </primaryRealm>
</federatedRepository>
```

Puntos a explicar:

- **`activedFilters`** (y no `customFilters`): con `ldapType="Microsoft Active Directory"`,
  Open Liberty usa los filtros de AD. En XML los `&` de los filtros se escriben `&amp;`.
- **`referral="ignore"`**: evita que Liberty siga referencias a otros dominios del bosque, causa
  típica de lentitud y timeouts con AD.
- **`searchPageSize`** y timeouts: en directorios con miles de usuarios, búsquedas paginadas y
  acotadas.
- **`<federatedRepository>`**: une el registro básico que genera el chart (donde está `wpsadmin`)
  con el AD. Sin él, el AD no forma parte del realm. `allowOpIfRepoDown` permite que wpsadmin
  siga entrando aunque el AD no responda.
- No hace falta redefinir el `basicRegistry` (ni poner la contraseña de wpsadmin en el XML): en
  CF239 lo genera el chart desde `web-engine-secret`.

```bash
lab2-ldap-postgres/enterprise/active-directory/02-dx-upgrade.sh
```

**Comprobar:** entra en `https://$DX_HOST/wps/myportal` con un usuario del AD (su
`sAMAccountName`) y con `wpsadmin`. Si algo falla, el log del Web Engine dice por qué:

```bash
kubectl -n dx-demo logs dx-deployment-web-engine-0 -c system-out-log | grep -E 'CWIML|CWWKG|LDAP'
```

### Paso AD-3 · Administradores desde un grupo del AD

Igual que en la rama demo (paso 4 de [GUIDE.es.md](GUIDE.es.md)): conectar el AD no da permisos a nadie.
Hay que entrar en el portal como **wpsadmin** y, en *Administración → Acceso → Permisos de
recursos → Recursos virtuales → PORTAL*, añadir al rol **Administrator** el grupo del AD que
corresponda (p. ej. `CN=DX-Admins,OU=Grupos,DC=empresa,DC=local`).

Como alternativa, el mismo override de `basicRegistry` descrito en la rama demo añade usuarios
del AD (por su `sAMAccountName`) al grupo de administración del registro básico.

### LDAPS (puerto 636)

1. `AD_PORT=636`, `AD_SSL=true` y `AD_CA_FILE` con la CA que firmó el certificado de los DC.
2. `01-secrets-ad.sh` crea además el secret `dx-ad-ca`.
3. Descomenta `customTruststoreSecrets` en `custom-values.ad.yaml` y repite `02-dx-upgrade.sh`
   (los cambios de truststore reinician el pod).

---

## 2B-E · Transferencia de la base de datos a Oracle

Documentación de HCL:
[External database and database transfer (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_webengine/external_db_database_transfer/)

El procedimiento en DX es **idéntico** al de PostgreSQL (secrets de properties,
`useExternalDatabase`, transferencia en el siguiente arranque). Cambian la preparación de la base
de datos, que la hace el DBA, y la conexión **TCPS** (TLS), habitual en entornos corporativos.

### Paso ORA-1 · Preparar Oracle (DBA)

Requisitos de HCL: Oracle **19c o 21c**, juego de caracteres **AL32UTF8** (y AL16UTF16 nacional).

[setup-oracle-dx.sql](enterprise/oracle/setup-oracle-dx.sql) es el script de ejemplo de HCL con las
contraseñas y la PDB como variables de SQL*Plus (las pide al ejecutarlo):

```bash
sqlplus / as sysdba @setup-oracle-dx.sql
```

| Crea | Para qué |
|---|---|
| Usuario `wpsuser` | Con el que se conecta DX (`ORACLE_DX_USER`) |
| Usuarios/esquemas `release`, `community`, `customization`, `jcr`, `feedback`, `likeminds` | Un esquema por dominio de DX |
| Roles `WP_BASE_*`, `WP_JCR_*`, `WP_PZN_*` (CONFIG y RUNTIME) | Los que referencian las properties |
| Tablespaces `ICMLFQ32`, `ICMLNF32`, `ICMVFQ04`, `ICMSFQ04`, `ICMLSNDX` | Los usa el JCR |

> Revísalo con el DBA: el script de HCL da privilegios amplios (`ANY TABLE`, `GRANT DBA` para las
> tablas de timers) que cada empresa adapta a su política. Para repetir la prueba,
> [clean-oracle-dx.sql](enterprise/oracle/clean-oracle-dx.sql) lo borra todo.

### Paso ORA-2 · Secrets del Web Engine

Variables en `env.sh`: `ORACLE_JDBC_URL`, `ORACLE_DX_USER`, `ORACLE_DX_PASSWORD` y, con TCPS,
`ORACLE_CA_FILE`.

```bash
lab2-ldap-postgres/enterprise/oracle/01-secrets-oracle.sh
```

| Secret | Contenido |
|---|---|
| `custom-credentials-webengine-dbtype-secret` | [dx_dbtype.properties](enterprise/oracle/dx_dbtype.properties): driver `ojdbc11.jar` + `xdb6` (vienen en la imagen) |
| `custom-credentials-webengine-dbdomain-secret` | [Los 6 dominios](enterprise/oracle/dx_dbdomain.properties.template) con `DbType=oracle` y la URL |
| `dx-oracle-ca` | CA del listener TCPS, para el truststore del Web Engine |

Formato de la URL:

```properties
# TCPS (TLS), puerto típico 2484
jcr.DbUrl=jdbc:oracle:thin:@tcps://oracle.empresa.local:2484/WPSDB
# Sin TLS
jcr.DbUrl=jdbc:oracle:thin:@//oracle.empresa.local:1521/WPSDB
```

> Variante: en lugar de un usuario de conexión común (`wpsuser`, modelo del script de HCL), cada
> dominio puede conectarse con el propietario de su esquema (`release.DbUser=release`, etc.). Es
> otro modelo habitual; cambian solo las properties.

### Paso ORA-3 · Transferencia

[custom-values.oracle.yaml](enterprise/oracle/custom-values.oracle.yaml) es la capa de PostgreSQL más
el truststore:

```yaml
configuration:
  webEngine:
    useExternalDatabase: true
    customDbTypePropertiesSecret: custom-credentials-webengine-dbtype-secret
    customDbDomainPropertiesSecret: custom-credentials-webengine-dbdomain-secret
    dropDatabaseTables: false
    customTruststoreSecrets:
      oracle-ca: "dx-oracle-ca"
```

```bash
lab2-ldap-postgres/enterprise/oracle/02-dx-transfer.sh
kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
```

**Comprobar** (como DBA): los seis esquemas tienen tablas, en total unas 465.

```sql
SELECT owner, COUNT(*) FROM dba_tables
 WHERE owner IN ('RELEASE','COMMUNITY','CUSTOMIZATION','JCR','FEEDBACK','LIKEMINDS')
 GROUP BY owner;
```

| Problema típico con Oracle | Causa |
|---|---|
| `ORA-12505` / `ORA-12514` | Nombre de servicio de la URL incorrecto (`/WPSDB` debe ser el *service name* de la PDB) |
| `PKIX path building failed` | Falta la CA del listener en `dx-oracle-ca` o la URL es `tcps://` sin truststore |
| `ORA-01950: no privileges on tablespace` | Faltan cuotas en `USERS` o en los tablespaces `ICM*` |
| Errores XA al arrancar | Falta `SELECT ON DBA_PENDING_TRANSACTIONS` para los roles (lo da el script) |


> **Herramientas.** Si algo falla y tienes que abrir un case con HCL Support:
> `common/collect-support-data.sh --case <número>` ([datos para soporte](../docs/support.es.md)). Para
> empezar la instalación de cero: `common/99-cleanup.sh` ([limpieza](../docs/cleanup.es.md)).

---

**Volver a:** [GUIDE.es.md](GUIDE.es.md) (rama demo) · **Siguiente:** [Lab 3 · IQ con OpenRouter](../lab3-iq-openrouter/GUIDE.es.md)
