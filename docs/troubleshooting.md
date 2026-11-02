# Troubleshooting

**English** · [Español](troubleshooting.es.md)

If you need to open a case with HCL Support: `common/collect-support-data.sh --case <number>` collects everything they ask for into a `.tar.gz` (see [support.md](support.md)).

## Lab 1

| Symptom | Likely cause | Solution |
|---|---|---|
| DAM in `Error`/`CrashLoopBackOff` (`ECONNREFUSED ...:5432`) and `persistence-connection-pool` with 1 restart during the first minutes | **Normal.** DAM and PgPool start before the Persistence Node; they retry by themselves | Wait: in ~3 minutes they are `Running` (on the reference cluster, 5 DAM restarts) |
| `Error: resource StatefulSet/.../dx-deployment-digital-asset-management not ready. status: Failed` and the release in `failed` | **Helm 4**: `--wait` uses the `watcher` strategy, which aborts at the first failure, and DAM fails normally while starting | The scripts already use `--wait=legacy` with Helm 4 (`common/lib.sh`). If you ran it by hand, repeat the command with `--wait=legacy`: `upgrade --install` completes the release without deleting anything |
| `ErrImagePull` / `ImagePullBackOff` with `unauthorized` | `regcred` with wrong credentials or an account not entitled to DX Compose | Check `HCL_HARBOR_USER`/`HCL_HARBOR_TOKEN` (it is the *CLI secret*, not the web password) and run `lab1-dx-base/01-secrets.sh` again |
| `helm pull` → `unauthorized` | Not logged in to hclcr.io | `common/02-pull-hcl-charts.sh` logs in; check the credentials |
| `The secret 'web-engine-secret' ... could not be found` | Installed before creating the secrets or in another namespace | `lab1-dx-base/01-secrets.sh` and repeat |
| PVC in `Pending` | The StorageClass does not exist, or RWX is not supported (Longhorn needs `nfs-common` on the nodes) | `kubectl describe pvc ...`; see [requirements.md](requirements.md) |
| Pods in `Pending` with `Insufficient cpu/memory` | Not enough resources | `kubectl describe pod ...`; free resources or add nodes |
| `helm` times out but the pods are still starting | The first image download is slow | Wait until they are `Running` and repeat `common/dx-helm.sh` (it is idempotent) |
| 502/503 in the browser | Web Engine still starting | `kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log` |
| 404 on `/adminCenter` or another path | Ingress that only publishes some paths | Use `lab1-dx-base/ingress-dx.yaml` (it publishes `/`) |

## Lab 2A · LDAP

| Symptom | Likely cause | Solution |
|---|---|---|
| LDAP users cannot log in, wpsadmin can | Wrong bind or unreachable LDAP | `./02-ldap-test.sh`; check `dx-ldap-bind` and look for `CWIML` in `kubectl -n dx-demo logs dx-deployment-web-engine-0 -c system-out-log` |
| `02-ldap-test.sh` → `No such object (32)` and `openldap-0` with 1 restart (exit 123) | The custom LDIF does not include the root entry and the first `ldapadd` fails | `demo-users.ldif` already has `dn: dc=dxdemo,dc=com`; if you change it, keep it. Reinstall as in the next row |
| The LDAP starts without the demo users | The LDIF is only loaded on the first start, with an empty PVC | `helm -n dx-shared uninstall openldap`, delete the `data-openldap-0` PVC and run `./01-ldap-install.sh` again |
| Users OK but no groups | Groups with another objectClass | The DX chart looks for `groupOfUniqueNames` / `uniqueMember` |

## Lab 2B · PostgreSQL

| Symptom | Likely cause | Solution |
|---|---|---|
| `kubectl get cluster` returns something else | On Rancher, `cluster` belongs to Cluster API | Use `kubectl get clusters.postgresql.cnpg.io` |
| The transfer fails with XA / prepared transactions errors | `max_prepared_transactions` at 0 | It is 500 in `cluster-dx-pg.yaml`; check it with `./99-verify.sh` |
| `ERROR: invalid escape string` in `WCM_USER_SHORTCUT` | `standard_conforming_strings=on` in `dx_core` (OpenJPA uses `ESCAPE '\\'`) | `setup-postgres-dx.sql` already sets it to `off`. On a cluster created before: `ALTER DATABASE dx_core SET standard_conforming_strings = off` and restart the Web Engine |
| `DSRA8020E: ... property 'driverType' does not exist ... org.postgresql` warnings | Liberty applies a DB2-specific property to the datasource | **Normal**, it is a warning (`W`): ignore it |
| `password authentication failed for user "dxuser"` | Different password in the CNPG secret and in the properties | Same `DXUSER_PASSWORD` in `02-secrets-postgres.sh` and `04-secrets-webengine.sh` (repeat both and restart the Web Engine) |
| The transfer is not repeated after an error | The Web Engine already recorded an attempt | Fix the cause; if dx_core was left with tables, `dropDatabaseTables: true` only for that upgrade and back to `false` |

## Lab 3 · IQ

| Symptom | Likely cause | Solution |
|---|---|---|
| The IQ button does not appear | `networking.dxIqService` is missing | `./05-dx-enable-iq.sh` |
| IQ answers "error" to everything | LiteLLM does not answer or OpenRouter rejects the key | `./03-litellm-test.sh` and `./99-verify.sh` |
| HTTP 400 from Claude about tool names | Model configured with the `openrouter/` provider | Use `anthropic/<id>` with `api_base: https://openrouter.ai/api` (see `litellm-values.yaml`) |
| The Integrator calls an unknown HCL URL | `LITELLM_BASE_URL` is missing | It is in `custom-iq-values.yaml` (`environment.pod.integrator`) |
| `fetch failed` towards `litellm.dx-shared` | NetworkPolicy isolating namespaces (common on OpenShift) | Allow traffic from `dx-demo` to `dx-shared` port 4000 |

## Lab 4 · Search

| Symptom | Likely cause | Solution |
|---|---|---|
| The crawlers finish with 0 documents or time out | `haproxyProtocol` set to `http`: the DX HAProxy only listens on 443 | `automatedSetup.haproxyProtocol: https` (already in `custom-search-values.yaml`) |
| `Could not connect to file processor` every 3 s | File Processor disabled (chart default) | `applications.fileProcessor: true` (already in `custom-search-values.yaml`) |
| OpenSearch rejects the administrator | `adminDN` is not in RFC 2253 format | `./01-certs.sh` generates it in `admin-dn.rendered.yaml`; do not pass it with `--set` |

More details in the guide of each lab.
