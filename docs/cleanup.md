# Starting from scratch

**English** · [Español](cleanup.es.md)

```bash
common/99-cleanup.sh
```

If you installed with option C of the configuration wizard (the `dx-install/` folder), run
`./uninstall.sh` from that folder instead: it does the same.

> If you are going to open a case with HCL Support, collect the data **first**
> (`common/collect-support-data.sh`, see [support.md](support.md)): once deleted, the logs are gone.

It asks for confirmation (type `delete`) and removes, in this order:

1. The releases in the DX namespace (DX, IQ and search) and their PVCs. Helm does not delete the
   StatefulSet PVCs (Web Engine, Persistence Node, License Manager, OpenSearch), so the script
   deletes them separately.
2. The CNPG PostgreSQL cluster, **before** its operator.
3. The releases in the shared namespace (CNPG operator, OpenLDAP, LiteLLM) and their PVCs.
4. Both namespaces.

The PVs have `reclaimPolicy: Delete`: when the PVCs are deleted, Longhorn also removes the volumes.
At the end the script checks that none is left. It **does not touch** the StorageClasses, the CNPG
CRDs, or anything outside the two lab namespaces.

The downloaded charts (`charts/`) and your `env.sh` are kept, so to repeat you just go back to
step 1 of Lab 1 (`common/01-namespaces.sh`).

Lab 0 (PoC): run `lab0-poc-wsl/01-storage.sh` before installing again (it recreates the DAM volume).

## Repeating only one part

| I want to repeat... | Do |
|---|---|
| The transfer to PostgreSQL (2B) | Not trivial: the Web Engine records that it already transferred. The clean way is to reinstall the whole DX |
| Only IQ (Lab 3) | `helm -n dx-demo uninstall dx-iq` and `helm -n dx-shared uninstall litellm`; then `common/dx-helm.sh` removes the IQ layer from DX |
| Only the LDAP (2A) | `kubectl -n dx-demo delete secret dx-ldap-bind` and `common/dx-helm.sh` (DX goes back to the basic registry); then `helm -n dx-shared uninstall openldap` and delete its PVC |
| Only search (Lab 4) | `helm -n dx-demo uninstall dx-search`, delete its PVCs and run `common/dx-helm.sh` (it removes the search layer) |
