#!/usr/bin/env bash
# Lab 2B · Paso 5 · helm upgrade con la capa custom-values.postgres.yaml: el Web Engine se reinicia
# y transfiere su base de datos de Derby (PVC customization) a PostgreSQL (dx_core en dx-pg).
#
# HCL: no escales el Web Engine mientras dure la transferencia.
# Para seguirla en otra terminal:
#   kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"

kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbdomain-secret >/dev/null 2>&1 \
  || die "Falta el secret de propiedades: ejecuta ./04-secrets-webengine.sh"
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER" >/dev/null 2>&1 \
  || die "No existe el cluster $PG_CLUSTER en $SHARED_NS: ejecuta ./03-postgres-cluster.sh"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Comprueba el resultado con ./99-verify.sh (debería haber unas 465 tablas en dx_core)."
