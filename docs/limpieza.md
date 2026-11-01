# Empezar de cero

```bash
common/99-cleanup.sh
```

Pide confirmación y borra, en este orden:

1. Las releases de `dx-demo` (DX e IQ) y sus PVC. Helm no borra los PVC de los StatefulSets
   (Web Engine, Persistence Node, License Manager), así que el script los borra aparte.
2. El cluster PostgreSQL de CNPG, **antes** que su operador.
3. Las releases de `dx-shared` (operador CNPG, OpenLDAP, LiteLLM) y sus PVC.
4. Los dos namespaces.

Los PV tienen `reclaimPolicy: Delete`: al borrar los PVC, Longhorn elimina también los volúmenes.
El script comprueba al final que no queda ninguno. **No toca** las StorageClasses ni las CRD de
CNPG, ni nada fuera de `dx-demo` y `dx-shared`.

Los charts descargados (`charts/`) y tu `env.sh` se conservan, así que para repetir basta con
volver al paso 1 del Lab 1 (`common/01-namespaces.sh`).

## Repetir solo una parte

| Quiero repetir... | Haz |
|---|---|
| La transferencia a PostgreSQL (2B) | No es trivial: el Web Engine registra que ya transfirió. Lo limpio es reinstalar DX entero |
| Solo IQ (Lab 3) | `helm -n dx-demo uninstall dx-iq` y `helm -n dx-shared uninstall litellm`; después `common/dx-helm.sh` quita la capa de IQ de DX |
| Solo el LDAP (2A) | `kubectl -n dx-demo delete secret dx-ldap-bind` y `common/dx-helm.sh` (DX vuelve al registro básico); después `helm -n dx-shared uninstall openldap` y borra su PVC |
