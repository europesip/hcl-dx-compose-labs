#!/usr/bin/env bash
# Lab 2B · Paso 3 · Crea el cluster PostgreSQL dx-pg en dx-shared y espera a que esté sano.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS PG_CLUSTER
cd "$(dirname "$0")"

kubectl -n "$SHARED_NS" get secret dx-pg-superuser dx-pg-dxuser >/dev/null \
  || die "Faltan los secrets de PostgreSQL: ejecuta ./02-secrets-postgres.sh"
[[ -f setup-postgres-dx.sql ]] \
  || die "Falta setup-postgres-dx.sql en $(pwd): es el script de preparación de dx_core (ver GUIA, Lab 2B paso 3)"

# El SQL de preparación (esquemas, roles, permisos, parámetros) va en un ConfigMap que CNPG
# ejecuta una sola vez al crear el cluster (bootstrap.initdb.postInitApplicationSQLRefs)
info "ConfigMap dx-pg-setup-sql (setup-postgres-dx.sql)"
kubectl -n "$SHARED_NS" create configmap dx-pg-setup-sql --from-file=setup-postgres-dx.sql \
  --dry-run=client -o yaml | kubectl apply -f -

render cluster-dx-pg.yaml '$SHARED_NS' | kubectl apply -f -

info "Esperando a que el cluster $PG_CLUSTER esté listo (1-3 minutos)"
kubectl -n "$SHARED_NS" wait clusters.postgresql.cnpg.io/"$PG_CLUSTER" --for=condition=Ready --timeout=10m
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER"
kubectl -n "$SHARED_NS" get pods,svc,pvc -l cnpg.io/cluster="$PG_CLUSTER"
echo "Servicio para DX: ${PG_HOST}:5432"
