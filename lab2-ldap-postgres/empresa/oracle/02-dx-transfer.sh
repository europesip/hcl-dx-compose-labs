#!/usr/bin/env bash
# Lab 2 · Rama empresarial · Paso ORA-3 · helm upgrade: el Web Engine transfiere Derby -> Oracle.
# Mismo procedimiento que la rama PostgreSQL (b-postgres/05-dx-transfer.sh).
#   kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"

kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbdomain-secret >/dev/null 2>&1 \
  || die "Faltan los secrets de propiedades: ejecuta ./01-secrets-oracle.sh"
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER" >/dev/null 2>&1 \
  && warn "Existe también el PostgreSQL de la rama demo ($PG_CLUSTER): DX usará Oracle (lo que digan los secrets)"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Comprueba en Oracle (como DBA) que los 6 esquemas tienen tablas:"
echo "  SELECT owner, COUNT(*) FROM dba_tables WHERE owner IN"
echo "    ('RELEASE','COMMUNITY','CUSTOMIZATION','JCR','FEEDBACK','LIKEMINDS') GROUP BY owner;"
