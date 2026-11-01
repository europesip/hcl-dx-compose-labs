# Lab 2 · LDAP and PostgreSQL database

**English** · [Español](GUIDE.es.md)

**Starting point:** Lab 1 finished (DX in `dx-demo`, reachable at `https://$DX_HOST`).

**⏱ Estimated time: ~27 minutes** (2A ~10 min · 2B ~17 min).

| Iteration · step | Time |
|---|---|
| 2A-1/2 · OpenLDAP and its test | ~1 min |
| 2A-3 · DX `helm upgrade` with LDAP (restarts the Web Engine) | ~5 min |
| 2A-4 · Administrator role for `dxadmins` in the portal console | ~3 min |
| 2B-1/2/3 · CNPG operator, users and PostgreSQL cluster | ~2 min |
| 2B-4 · Properties secrets | seconds |
| 2B-5 · Transfer from Derby to PostgreSQL (`helm upgrade`) | **~14 min** |
| Checks | ~1 min |

> Run times measured on the reference lab cluster (k3s, 3 workers with 14 CPU / 20 GiB), without
> the explanations. The first time on a new cluster, add the download of the HCL images from
> `hclcr.io`, which depends on the network.

**Goal:** two iterations over the existing installation, each one with a `helm upgrade`:

| Iteration | What changes | In `dx-shared` | DX layer |
|---|---|---|---|
| **2A · LDAP** | Users authenticate against an LDAP directory | OpenLDAP | `a-ldap/custom-values.ldap.yaml` |
| **2B · PostgreSQL** | The Web Engine database moves from Derby (embedded, not valid for production) to PostgreSQL | PostgreSQL 18 (CloudNativePG) | `b-postgres/custom-values.postgres.yaml` |

OpenLDAP, PostgreSQL and its operator are not HCL software: they go in **`dx-shared`**, the
namespace we created for every tool outside HCL. In `dx-demo` (DX) only the configuration changes:
`common/dx-helm.sh` adds the layer of each iteration to the Lab 1 `custom-values.yaml`.

### Two paths: demo or enterprise

```
                         ┌─► 2A OpenLDAP (dx-shared) ─────┐   ┌─► 2B PostgreSQL (dx-shared) ─┐
 Lab 1 (base DX) ──────► │        this guide · DEMO       ├─► │        this guide · DEMO     ├──► Lab 3
                         └─► 2A Active Directory ─────────┘   └─► 2B Oracle ─────────────────┘
                              GUIDE-enterprise.md · ENTERPRISE      GUIDE-enterprise.md · ENTERPRISE
```

- **Demo (this guide):** OpenLDAP and PostgreSQL are deployed in the cluster itself in minutes and
  depend on nothing external. It is the main path of the labs.
- **Enterprise ([GUIDE-enterprise.md](GUIDE-enterprise.md)):** in corporate environments the usual
  choice is **Microsoft Active Directory** as the directory and **Oracle** as the database. They are
  provided as an advanced reference: AD with `configOverrideFiles` (its filters differ from
  OpenLDAP) and Oracle over TCPS. Oracle, unlike PostgreSQL, is supported by HCL for the Web Engine.

Each iteration can follow either path (e.g. AD + PostgreSQL).

```bash
cd hcl-dx-compose-labs && source ./env.sh
```

---

## 2A · LDAP authentication

HCL documentation:
[Configuring LDAP (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_webengine/ldap_configuration/)

```
 DX (dx-demo)                                 dx-shared
 Web Engine ── LDAP 389 ──► openldap.dx-shared.svc.cluster.local
   federated repository:                       dc=dxdemo,dc=com
     o=defaultWIMFileBasedRealm (wpsadmin)       ou=users:  7 demo users
     dc=dxdemo,dc=com           (LDAP)           ou=groups: dxadmins, dxauthors, dxmarketing
```

| LDAP group | Users | Rights in DX |
|---|---|---|
| `dxadmins` | andres, eduardo | **Portal administrator** (step 4) |
| `dxauthors` | macarena, enrique, jordi | authenticated user |
| `dxmarketing` | patricia, german | authenticated user |

All of them with the password **EuropeS1P** (`LDAP_USERS_PASSWORD`). `wpsadmin` (basic registry,
`wpsadmins` group) is still the initial administrator.

### Step 1 · Lab OpenLDAP

```bash
lab2-ldap-postgres/a-ldap/01-ldap-install.sh
```

- Secret `openldap-admin` with the password of `cn=admin,dc=dxdemo,dc=com` (`LDAP_ADMIN_PASSWORD`).
- ConfigMap `openldap-demo-ldif` with [demo-users.ldif](a-ldap/demo-users.ldif): the root
  `dc=dxdemo,dc=com`, the 7 users and the 3 groups of the table above. The passwords are stored as
  salted `{SSHA}` hashes, never in plain text.
- Community chart `helm-openldap/openldap-stack-ha` 4.3.3 with
  [openldap-values.yaml](a-ldap/openldap-values.yaml): one replica and a 1 GiB PVC in the `SC_RWO`
  StorageClass.

> At a real customer this step does not exist: their corporate directory is used and only host,
> port, suffix and bind user change in the DX layer.

### Step 2 · Test the LDAP before touching DX

```bash
lab2-ldap-postgres/a-ldap/02-ldap-test.sh
```

It lists the entries, the groups with their members and checks that `andres` authenticates. If this
fails, DX will not be able to authenticate either.

### Step 3 · Connect DX to the LDAP

Read [custom-values.ldap.yaml](a-ldap/custom-values.ldap.yaml):

```yaml
configuration:
  webEngine:
    ldap:
      type: "other"                                  # external LDAP
      host: "openldap.dx-shared.svc.cluster.local"   # service in the OTHER namespace: FQDN (LDAP_HOST)
      port: 389
      sslEnabled: false
      suffix: "dc=dxdemo,dc=com"
      serverType: "Custom"
      customLdapSecret: "dx-ldap-bind"               # keys bindUser / bindPassword
```

```bash
lab2-ldap-postgres/a-ldap/03-dx-upgrade.sh
```

It creates the `dx-ldap-bind` secret in `dx-demo` and runs the `helm upgrade` with the LDAP layer:

```bash
helm upgrade --install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
  -f lab1-dx-base/custom-values.yaml \
  -f lab2-ldap-postgres/a-ldap/custom-values.ldap.yaml \
  --set-string networking.webEngine.host=$DX_HOST ... --timeout 30m --wait
```

**What the chart generates.** With `type: other`, the CF238 chart creates the Open Liberty
configuration: an `<ldapRegistry>` (`inetOrgPerson` filters for users and `groupOfUniqueNames` for
groups) and a `<federatedRepository>` that joins **the basic registry**
(`o=defaultWIMFileBasedRealm`, where `wpsadmin` lives) **and the LDAP**. That is why wpsadmin can
still log in and so can the LDAP users. For different filters or attributes you would use
`configuration.webEngine.configOverrideFiles` with your own XML.

> **Variant without the basic registry.** If every user, including the administrator, is in the
> LDAP: `security.webEngine.basicRegistry.enabled: false` and `webEngineUser` with the
> administrator **full DN** (e.g. `uid=dxadmin,ou=users,dc=dxdemo,dc=com`), who must belong to the
> `security.webEngine.webEngineAdminGroup` group.

### Step 4 · Administrator rights for the `dxadmins` group

**Authentication and authorisation are different things.** After step 3, DX knows *who* each LDAP
user is (authentication), but none of them can administer anything: what each one can do is
decided by the **DX permissions** (authorisation), which are stored in the DX database, not in the
LDAP.

The `dxadmins` group (andres, eduardo) **already exists in the LDAP**, but **you have to log in to
the portal and give it administrator rights**:

1. Go to `https://$DX_HOST/wps/myportal` as **wpsadmin**.
2. Open the security page: *Administration → Access → Resource Permissions*.
3. Resource type **Virtual Resources** → **PORTAL** → *Assign Access*.
4. In the **Administrator** role → *Add* → search for the `dxadmins` group → *OK*.

In DX permissions are **roles on resources**: the `PORTAL` virtual resource is the root of the
hierarchy and the *Administrator* role on it is inherited across the whole portal. It is assigned
to a **group**, not to users: for eduardo to stop being an administrator it is enough to remove
him from `dxadmins` in the LDAP. The permission is stored in the DX database, so in Lab 2B it
travels with the transfer.

> **Alternative: with an override.** Just as the Active Directory branch
> ([GUIDE-enterprise.md](GUIDE-enterprise.md)) configures the registry with `configOverrideFiles`,
> you can add LDAP users to the administration group of the basic registry (`wpsadmins`, the
> chart `DX_ADMIN_GROUP`). Besides the portal role, that gives them the tools DX Compose reserves to
> that group in Open Liberty (XMLAccess and WebDAV). It is added to the LDAP layer:
>
> ```yaml
> configuration:
>   webEngine:
>     configOverrideFiles:
>       admin-members.xml: |
>         <server description="DX administrators from the LDAP">
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
> The `${DX_ADMIN}`, `${DX_PASSWORD}` and `${DX_ADMIN_GROUP}` variables are defined by the chart
> itself from `web-engine-secret`: the password is not written in the file.

> **Why not `security.webEngine.webEngineAdminGroup: dxadmins`?** That value does not look the
> group up in the LDAP: it creates in the **basic registry** a group with that name that contains
> `wpsadmin`. With the federated repository there would be two `dxadmins` groups (one in each
> repository) and Liberty can fail with "multiple entities found".

### Check

1. `https://$DX_HOST/wps/myportal` with **macarena** / **EuropeS1P** → logs in as an authenticated
   user, **without** the administration menu.
2. With **andres** or **eduardo** → logs in and **does** have administration (and Practitioner
   Studio).
3. With **wpsadmin** → still works.
4. To see the LDAP configuration generated by the chart:
   `kubectl -n dx-demo get cm dx-deployment-web-engine-overrides -o jsonpath='{.data.ldap-config\.xml}'`.

> **LDAPS in production:** `port: 636`, `sslEnabled: true` and the LDAP CA in the Web Engine
> truststore (`configuration.webEngine.customTruststoreSecrets`). See
> [Custom certificates (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/working_with_compose/custom_certificates/).

---

## 2B · Database transfer to PostgreSQL

HCL documentation:
[External database and database transfer (CF238)](https://help.hcl-software.com/digital-experience/dx-compose/CF238/deploy_dx/manage/cfg_webengine/external_db_database_transfer/)

> ⚠️ **Support.** In CF238 HCL supports **DB2, Oracle and SQL Server** for the Web Engine
> ([Databases](https://help.hcl-software.com/digital-experience/9.5/CF238/get_started/system_requirements/kubernetes/databases/)).
> PostgreSQL is being validated by HCL (their tests work with PostgreSQL 18) but **it is not
> supported today**. The procedure (properties secrets, `useExternalDatabase`,
> `dropDatabaseTables`) is the same for the supported databases, which is what you learn here.

```
 Before: Web Engine ── Derby (file in the customization PVC)
 After:  Web Engine ── JDBC 5432 ──► dx-pg-rw.dx-shared.svc.cluster.local / dx_core
                                       6 schemas: release, jcr, community, customization,
                                                  feedback, likeminds  (~465 tables)
```

**Why our own PostgreSQL 18 (and not the HCL one).** HCL ships a PostgreSQL: the *Persistence
Node* (`dx-deployment-persistence-node-0`, in `dx-demo`), installed as the **DAM persistence**,
which today is **PostgreSQL 16** (16.15 on this cluster). It is managed by DX itself (repmgr,
connection pool, Runtime Controller) and is not meant as a general-purpose database. For the Web
Engine we preferred **our own version, PostgreSQL 18** (18.6), for two reasons:

- **Use a more modern version**, the same one HCL is validating the Web Engine on PostgreSQL with.
- **Reproduce the case of an installation that already had its own PostgreSQL**: at a customer,
  the database is usually corporate and external to DX. That is why it goes in **`dx-shared`**,
  outside the HCL namespace, and DX connects to it as it would to the company one.

| | HCL PostgreSQL (Persistence Node) | Our PostgreSQL |
|---|---|---|
| Version | 16 | **18** |
| Namespace | `dx-demo` (installed by the DX chart) | **`dx-shared`** (installed by us with CloudNativePG) |
| Use | DAM (and People Service / internal IQ) | **Web Engine** (`dx_core`) |
| Managed by | DX | Us (or the company DBA) |

### Step 1 · CloudNativePG operator

```bash
lab2-ldap-postgres/b-postgres/01-cnpg-operator.sh
```

It installs `cnpg/cloudnative-pg` 0.29.1 (operator 1.30.1) in `dx-shared`. CNPG manages PostgreSQL
declaratively: database, roles, tablespaces and replicas are described in a `Cluster` resource. On
OpenShift it would be installed from OperatorHub.

### Step 2 · PostgreSQL users

```bash
lab2-ldap-postgres/b-postgres/02-secrets-postgres.sh
```

`basic-auth` secrets in `dx-shared` for `postgres` (superuser), `dxuser` (owner of the Web Engine
database) and `dx_iq_db_user` (used by the Lab 3 appendix).

### Step 3 · PostgreSQL 18 cluster and database preparation

```bash
lab2-ldap-postgres/b-postgres/03-postgres-cluster.sh
```

**What we prepare and what DX does.** We leave an **empty** database ready, but with the shape DX
expects: the database, its schemas, roles, grants, tablespaces and parameters. **No script creates
the tables (~465)**: the Web Engine creates them during the step 5 transfer, just as with DB2 or
Oracle.

The preparation has two parts:

**1. The cluster, declarative** ([cluster-dx-pg.yaml](b-postgres/cluster-dx-pg.yaml)). CNPG creates:

| Item | Value | Why |
|---|---|---|
| Image | `ghcr.io/cloudnative-pg/postgresql:18.6-standard-trixie` | Pinned minor version |
| Name and storage | `PG_CLUSTER` (`dx-pg`) in the `SC_RWO` StorageClass | Set by the script from `env.sh` |
| Database | `dx_core`, owner `dxuser`, UTF8, `en_US.UTF-8` | A single database with one schema per DX domain |
| Tablespaces | `icmlfq32`, `icmlnf32`, `icmvfq04`, `icmsfq04`, `icmlsndx`, owned by `dxuser` | Used by the DX JCR; CNPG gives each one its own PVC |
| `max_connections` / `max_prepared_transactions` | 500 / 500 | DX uses XA transactions (2PC); in PostgreSQL `max_prepared_transactions` is 0 by default |
| Role `dx_iq_db_user` | with login | For the Lab 3 appendix (IQ sessions in PostgreSQL) |

**2. The SQL preparation script** ([setup-postgres-dx.sql](b-postgres/setup-postgres-dx.sql)).
It runs **only once**, as `postgres`, inside `dx_core`. The `03-...` script loads it into the
`dx-pg-setup-sql` ConfigMap and CNPG runs it when the cluster is created
(`bootstrap.initdb.postInitApplicationSQLRefs`). In this order, it does:

| Block | Statements | What for |
|---|---|---|
| Extensions | `uuid-ossp`, `pgcrypto` | UUID and cryptography functions |
| `dx_core` parameters | `ALTER DATABASE dx_core SET standard_conforming_strings = off` (and `escape_string_warning = off`) | The Web Engine OpenJPA writes `ESCAPE '\'` (DB2/Oracle style); with the default (`on`) PostgreSQL rejects it with "invalid escape string" |
| Schemas | `release`, `community`, `customization`, `jcr`, `feedback`, `likeminds`, owned by `dxuser` | One schema per DX domain (the `DbSchema` of the step 4 properties) |
| `dxuser` grants | `GRANT ALL` on the database and the schemas, and `ALTER DEFAULT PRIVILEGES` for tables and sequences | So that `dxuser` owns everything the Web Engine creates |
| DX roles | `WP_BASE_*`, `WP_JCR_*`, `WP_PZN_*` (`CONFIG` and `RUNTIME`) | The `DbConfigRoleName`/`DbRuntimeRoleName` of the properties |
| Role grants | `release`/`community`/`customization` → `WP_BASE_CONFIG_USERS`; `jcr` → `WP_JCR_CONFIG_USERS`; `feedback`/`likeminds` → `WP_PZN_CONFIG_USERS`; `dxuser` member of all six | The domain split DX uses |

> **Existing corporate PostgreSQL.** If the database is managed by a DBA, they first create the
> `dx_core` database, the `dxuser` user, the tablespaces and the XA parameters, and run the same
> script: `psql -U postgres -d dx_core -f setup-postgres-dx.sql`. In that case steps 1 to 3 of this
> guide (CNPG operator and cluster) are not used and the step 4 properties point to their server.

### Step 4 · Web Engine database properties

```bash
lab2-ldap-postgres/b-postgres/04-secrets-webengine.sh
```

It creates in `dx-demo` the two secrets HCL asks for, with fixed key names:

| Secret | Key | Content |
|---|---|---|
| `custom-credentials-webengine-dbtype-secret` | `dx_dbtype.properties` | JDBC driver ([dx_dbtype.properties](b-postgres/dx_dbtype.properties)): the PostgreSQL one already ships in the Web Engine image |
| `custom-credentials-webengine-dbdomain-secret` | `dx_dbdomain.properties` | The 6 domains ([template](b-postgres/dx_dbdomain.properties.template)): URL, schema, user, roles and datasource of each one |

Example of one domain:

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

> HCL rules: `key=value` **without quotes**, and with secrets the chart **ignores**
> `dbDomainProperties`/`dbTypeProperties` in the values: everything has to be in the secret.
> The script generates the file with the password, creates the secret and deletes the file.

### Step 5 · Transfer

Read [custom-values.postgres.yaml](b-postgres/custom-values.postgres.yaml):

```yaml
configuration:
  webEngine:
    useExternalDatabase: true      # transfers ONCE from Derby to the external database
    customDbTypePropertiesSecret: custom-credentials-webengine-dbtype-secret
    customDbDomainPropertiesSecret: custom-credentials-webengine-dbdomain-secret
    dropDatabaseTables: false      # the target database is empty
```

```bash
lab2-ldap-postgres/b-postgres/05-dx-transfer.sh
```

`helm upgrade` with the three layers (base + LDAP + PostgreSQL). The Web Engine restarts and, when
it starts, copies the Derby data to PostgreSQL. Follow it in another terminal:

```bash
kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
```

- **Do not scale the Web Engine** while it runs (HCL does not support scaling during the transfer).
- The transfer is recorded: later restarts and upgrades do not repeat it.
- `dropDatabaseTables: true` is only needed to redo it over a database with tables, and it
  **deletes their content**. If you use it, set it back to `false` as soon as it finishes (HCL
  explicitly recommends it).

### Check

```bash
lab2-ldap-postgres/b-postgres/99-verify.sh
```

- ~465 tables in `dx_core` (release ≈182, jcr ≈96, community ≈75, customization ≈51,
  feedback ≈48, likeminds ≈13) and open `dxuser` connections.
- In the portal: the **Lab 1 test page is still there** and `andres` can still log in (the LDAP
  does not depend on the database).

---

**Next:** [Lab 3 · IQ with OpenRouter](../lab3-iq-openrouter/GUIDE.md)
