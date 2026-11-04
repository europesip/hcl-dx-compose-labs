# Lab 2 · Enterprise branch: Active Directory and Oracle

**English** · [Español](GUIDE-enterprise.es.md)

> **Advanced, optional case.** In the demo path we use **OpenLDAP** and **PostgreSQL**
> ([GUIDE.md](GUIDE.md)) because they are deployed in the cluster itself in a couple of minutes.
> In corporate environments the directory is usually **Microsoft Active Directory** and the
> database **Oracle**, already existing and managed by other teams. This branch shows how DX
> Compose connects to them, as a reference for taking the lab to a real environment.

**⏱ Estimated time:** in DX, the same as the demo branch (~5 min for the AD `helm upgrade` and
~14 min for the Oracle transfer). Add the preparation on the corporate side (AD service account
and CA; Oracle PDB, SQL script and TCPS listener), which depends on each company.

The two iterations are the same as in the demo branch; only what DX connects to changes:

| Iteration | Demo branch | Enterprise branch | What changes in DX |
|---|---|---|---|
| **2A · Directory** | OpenLDAP in `dx-shared` | Corporate **Active Directory** | Native `ldap:` block → **`configOverrideFiles`** with an AD `<ldapRegistry>` |
| **2B · Database** | PostgreSQL 18 (CNPG) in `dx-shared` | Corporate **Oracle 19c/21c**, over **TCPS** | The properties point to Oracle + listener CA in the truststore |

They can be combined: AD + PostgreSQL, OpenLDAP + Oracle, AD + Oracle. `common/dx-helm.sh`
chooses the layer of each iteration from the secrets that exist (and stops if two branches are
present at the same time).

| | HCL support in CF238 |
|---|---|
| Active Directory | Yes (LDAP supported; Open Liberty `ldapType="Microsoft Active Directory"`) |
| Oracle | **Yes** for the Web Engine (19c and 21c, AL32UTF8/AL16UTF16). PostgreSQL, the demo one, not yet |

```bash
cd hcl-dx-compose-labs && source ./env.sh   # fill in the "Enterprise branch" section of env.sh
```

---

## 2A-E · Active Directory

We start from Lab 1 finished. The OpenLDAP part of the demo guide is **not** run (if you already
did it: `kubectl -n dx-demo delete secret dx-ldap-bind`).

### Why overrides and not the native block

The chart native `configuration.webEngine.ldap` block generates filters meant for OpenLDAP
(`inetOrgPerson`, `groupOfUniqueNames`/`uniqueMember`). Active Directory uses others:

| | OpenLDAP (demo) | Active Directory |
|---|---|---|
| Login | `uid` | `sAMAccountName` (Windows user) |
| User class | `inetOrgPerson` | `person` / `objectCategory=person` |
| Group class | `groupOfUniqueNames` | `group` / `objectCategory=group` |
| Membership | `uniqueMember` in the group | `member` in the group **and** `memberOf` in the user |
| Bind | DN (`cn=admin,dc=...`) | UPN (`svc-dx@company.local`) or DN |

That is why we write the registry with **`configOverrideFiles`**: Open Liberty XML that the chart
merges with the Web Engine `server.xml` (applied on the fly, without restarting the pod).

### Step AD-1 · Connection secret

Variables in `env.sh`: `AD_HOST`, `AD_PORT`, `AD_SSL`, `AD_BASE_DN`, `AD_BIND_USER`,
`AD_BIND_PASSWORD` (**read-only** service account) and, for LDAPS, `AD_CA_FILE`.

```bash
lab2-ldap-postgres/enterprise/active-directory/01-secrets-ad.sh
```

It checks that the cluster reaches the AD and creates the `dx-ad-bind` secret. The chart injects it
into the Web Engine as **environment variables** (`configuration.webEngine.customSecrets`) and Open
Liberty replaces them in the XML: neither the host nor the password end up in the values.

### Step AD-2 · The DX layer

[custom-values.ad.yaml](enterprise/active-directory/custom-values.ad.yaml), the essentials:

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
    <participatingBaseEntry name="${AD_BASE_DN}"/>                <!-- the AD -->
  </primaryRealm>
</federatedRepository>
```

Points to explain:

- **`activedFilters`** (and not `customFilters`): with `ldapType="Microsoft Active Directory"`,
  Open Liberty uses the AD filters. In XML the `&` of the filters is written `&amp;`.
- **`referral="ignore"`**: prevents Liberty from following referrals to other domains of the
  forest, a typical cause of slowness and timeouts with AD.
- **`searchPageSize`** and timeouts: in directories with thousands of users, paged and bounded
  searches.
- **`<federatedRepository>`**: joins the basic registry the chart generates (where `wpsadmin` is)
  with the AD. Without it, the AD is not part of the realm. `allowOpIfRepoDown` lets wpsadmin log
  in even if the AD does not answer.
- There is no need to redefine the `basicRegistry` (or to put the wpsadmin password in the XML):
  in CF239 the chart generates it from `web-engine-secret`.

```bash
lab2-ldap-postgres/enterprise/active-directory/02-dx-upgrade.sh
```

**Check:** log in to `https://$DX_HOST/wps/myportal` with an AD user (their `sAMAccountName`) and
with `wpsadmin`. If something fails, the Web Engine log says why:

```bash
kubectl -n dx-demo logs dx-deployment-web-engine-0 -c system-out-log | grep -E 'CWIML|CWWKG|LDAP'
```

### Step AD-3 · Administrators from an AD group

Same as the demo branch (step 4 of [GUIDE.md](GUIDE.md)): connecting the AD gives nobody any
rights. Log in to the portal as **wpsadmin** and, in *Administration → Access → Resource
Permissions → Virtual Resources → PORTAL*, add the relevant AD group to the **Administrator** role
(e.g. `CN=DX-Admins,OU=Groups,DC=company,DC=local`).

As an alternative, the same `basicRegistry` override described in the demo branch adds AD users
(by their `sAMAccountName`) to the administration group of the basic registry.

### LDAPS (port 636)

1. `AD_PORT=636`, `AD_SSL=true` and `AD_CA_FILE` with the CA that signed the DC certificates.
2. `01-secrets-ad.sh` also creates the `dx-ad-ca` secret.
3. Uncomment `customTruststoreSecrets` in `custom-values.ad.yaml` and repeat `02-dx-upgrade.sh`
   (truststore changes restart the pod).

---

## 2B-E · Database transfer to Oracle

HCL documentation:
[External database and database transfer (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_webengine/external_db_database_transfer/)

The DX procedure is **identical** to PostgreSQL (properties secrets, `useExternalDatabase`,
transfer on the next start). What changes is the database preparation, done by the DBA, and the
**TCPS** (TLS) connection, common in corporate environments.

### Step ORA-1 · Prepare Oracle (DBA)

HCL requirements: Oracle **19c or 21c**, character set **AL32UTF8** (and AL16UTF16 national).

[setup-oracle-dx.sql](enterprise/oracle/setup-oracle-dx.sql) is the HCL sample script with the
passwords and the PDB as SQL*Plus variables (it prompts for them when run):

```bash
sqlplus / as sysdba @setup-oracle-dx.sql
```

| Creates | What for |
|---|---|
| User `wpsuser` | The one DX connects with (`ORACLE_DX_USER`) |
| Users/schemas `release`, `community`, `customization`, `jcr`, `feedback`, `likeminds` | One schema per DX domain |
| Roles `WP_BASE_*`, `WP_JCR_*`, `WP_PZN_*` (CONFIG and RUNTIME) | The ones the properties reference |
| Tablespaces `ICMLFQ32`, `ICMLNF32`, `ICMVFQ04`, `ICMSFQ04`, `ICMLSNDX` | Used by the JCR |

> Review it with the DBA: the HCL script grants broad privileges (`ANY TABLE`, `GRANT DBA` for the
> timer tables) that each company adapts to its policy. To repeat the test,
> [clean-oracle-dx.sql](enterprise/oracle/clean-oracle-dx.sql) deletes everything.

### Step ORA-2 · Web Engine secrets

Variables in `env.sh`: `ORACLE_JDBC_URL`, `ORACLE_DX_USER`, `ORACLE_DX_PASSWORD` and, with TCPS,
`ORACLE_CA_FILE`.

```bash
lab2-ldap-postgres/enterprise/oracle/01-secrets-oracle.sh
```

| Secret | Content |
|---|---|
| `custom-credentials-webengine-dbtype-secret` | [dx_dbtype.properties](enterprise/oracle/dx_dbtype.properties): `ojdbc11.jar` + `xdb6` driver (shipped in the image) |
| `custom-credentials-webengine-dbdomain-secret` | [The 6 domains](enterprise/oracle/dx_dbdomain.properties.template) with `DbType=oracle` and the URL |
| `dx-oracle-ca` | CA of the TCPS listener, for the Web Engine truststore |

URL format:

```properties
# TCPS (TLS), typical port 2484
jcr.DbUrl=jdbc:oracle:thin:@tcps://oracle.company.local:2484/WPSDB
# Without TLS
jcr.DbUrl=jdbc:oracle:thin:@//oracle.company.local:1521/WPSDB
```

> Variant: instead of a common connection user (`wpsuser`, the HCL script model), each domain can
> connect with the owner of its schema (`release.DbUser=release`, etc.). It is another common
> model; only the properties change.

### Step ORA-3 · Transfer

[custom-values.oracle.yaml](enterprise/oracle/custom-values.oracle.yaml) is the PostgreSQL layer
plus the truststore:

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

**Check** (as DBA): the six schemas have tables, about 465 in total.

```sql
SELECT owner, COUNT(*) FROM dba_tables
 WHERE owner IN ('RELEASE','COMMUNITY','CUSTOMIZATION','JCR','FEEDBACK','LIKEMINDS')
 GROUP BY owner;
```

| Typical Oracle problem | Cause |
|---|---|
| `ORA-12505` / `ORA-12514` | Wrong service name in the URL (`/WPSDB` must be the PDB *service name*) |
| `PKIX path building failed` | The listener CA is missing in `dx-oracle-ca` or the URL is `tcps://` without truststore |
| `ORA-01950: no privileges on tablespace` | Missing quotas on `USERS` or on the `ICM*` tablespaces |
| XA errors at start-up | Missing `SELECT ON DBA_PENDING_TRANSACTIONS` for the roles (the script grants it) |


> **Tools.** If something fails and you need to open a case with HCL Support:
> `common/collect-support-data.sh --case <number>` ([support data](../docs/support.md)). To start the
> installation again from scratch: `common/99-cleanup.sh` ([cleanup](../docs/cleanup.md)).

---

**Back to:** [GUIDE.md](GUIDE.md) (demo branch) · **Next:** [Lab 3 · IQ with OpenRouter](../lab3-iq-openrouter/GUIDE.md)
