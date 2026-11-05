#!/usr/bin/env bash
# Lab 2B · Step 3 · Create the PostgreSQL cluster $PG_CLUSTER in the shared namespace and wait
# until it is healthy.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS PG_CLUSTER SC_RWO
cd "$(dirname "$0")"

kubectl -n "$SHARED_NS" get secret dx-pg-superuser dx-pg-dxuser >/dev/null \
  || die "The PostgreSQL secrets are missing: run ./02-secrets-postgres.sh"
# setup-postgres-dx.sql prepares dx_core for the Web Engine (schemas, roles, grants, parameters).
# It is NOT published with the labs. Without it the cluster is still created (dx_core empty, users
# and tablespaces ready): enough for the IQ sessions (Lab 3 appendix, iqdb) or to prepare dx_core
# yourself later. The Derby -> PostgreSQL transfer (05-dx-transfer.sh) needs it.
if [[ -f setup-postgres-dx.sql ]]; then
  # CNPG runs it only once, when the cluster is created (bootstrap.initdb.postInitApplicationSQLRefs)
  info "ConfigMap dx-pg-setup-sql (setup-postgres-dx.sql)"
  kubectl -n "$SHARED_NS" create configmap dx-pg-setup-sql --from-file=setup-postgres-dx.sql \
    --dry-run=client -o yaml | kubectl apply -f -
  render cluster-dx-pg.yaml '$SHARED_NS $PG_CLUSTER $SC_RWO' | kubectl apply -f -
else
  warn "setup-postgres-dx.sql not found: dx_core is created EMPTY (not prepared for the Web Engine)"
  render cluster-dx-pg.yaml '$SHARED_NS $PG_CLUSTER $SC_RWO' \
    | sed '/# Schemas, roles, grants/,/key: setup-postgres-dx.sql/d' | kubectl apply -f -
fi

info "Waiting for the cluster $PG_CLUSTER to be ready (1-3 minutes)"
kubectl -n "$SHARED_NS" wait clusters.postgresql.cnpg.io/"$PG_CLUSTER" --for=condition=Ready --timeout=10m
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER"
kubectl -n "$SHARED_NS" get pods,svc,pvc -l cnpg.io/cluster="$PG_CLUSTER"
echo "Service for DX: ${PG_HOST}:5432"
