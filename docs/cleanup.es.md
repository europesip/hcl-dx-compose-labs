# Empezar de cero

[English](cleanup.md) · **Español**

```bash
common/99-cleanup.sh
```

> Si vas a abrir un case con HCL Support, recoge los datos **antes**
> (`common/collect-support-data.sh`, ver [support.es.md](support.es.md)): una vez borrado, los logs se pierden.

Pide confirmación (escribe `delete`) y borra, en este orden:

1. Las releases de `dx-demo` (DX, IQ y búsqueda) y sus PVC. Helm no borra los PVC de los StatefulSets
   (Web Engine, Persistence Node, License Manager, OpenSearch), así que el script los borra aparte.
2. El cluster PostgreSQL de CNPG, **antes** que su operador.
3. Las releases de `dx-shared` (operador CNPG, OpenLDAP, LiteLLM) y sus PVC.
4. Los dos namespaces.

Los PV tienen `reclaimPolicy: Delete`: al borrar los PVC, Longhorn elimina también los volúmenes.
El script comprueba al final que no queda ninguno. **No toca** las StorageClasses ni las CRD de
CNPG, ni nada fuera de `dx-demo` y `dx-shared`.

Los charts descargados (`charts/`) y tu `env.sh` se conservan, así que para repetir basta con
volver al paso 1 del Lab 1 (`common/01-namespaces.sh`).

Lab 0 (PoC): ejecuta `lab0-poc-wsl/01-storage.sh` antes de volver a instalar (recrea el volumen de DAM).

## Repetir solo una parte

| Quiero repetir... | Haz |
|---|---|
| La transferencia a PostgreSQL (2B) | No es trivial: el Web Engine registra que ya transfirió. Lo limpio es reinstalar DX entero |
| Solo IQ (Lab 3) | `helm -n dx-demo uninstall dx-iq` y `helm -n dx-shared uninstall litellm`; después `common/dx-helm.sh` quita la capa de IQ de DX |
| Solo el LDAP (2A) | `kubectl -n dx-demo delete secret dx-ldap-bind` y `common/dx-helm.sh` (DX vuelve al registro básico); después `helm -n dx-shared uninstall openldap` y borra su PVC |
| Solo la búsqueda (Lab 4) | `helm -n dx-demo uninstall dx-search`, borra sus PVC y ejecuta `common/dx-helm.sh` (quita la capa de búsqueda) |
