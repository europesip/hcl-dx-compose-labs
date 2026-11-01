#!/usr/bin/env bash
# Lab 2B · Step 3 · Create the PostgreSQL cluster $PG_CLUSTER in the shared namespace and wait
# until it is healthy.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS PG_CLUSTER SC_RWO
cd "$(dirname "$0")"

kubectl -n "$SHARED_NS" get secret dx-pg-superuser dx-pg-dxuser >/dev/null \
  || die "The PostgreSQL secrets are missing: run ./02-secrets-postgres.sh"
[[ -f setup-postgres-dx.sql ]] \
  || die "setup-postgres-dx.sql is missing in $(pwd): it is the dx_core preparation script (see GUIDE, Lab 2B step 3)"

# The preparation SQL (schemas, roles, grants, parameters) goes into a ConfigMap that CNPG runs
# only once, when the cluster is created (bootstrap.initdb.postInitApplicationSQLRefs)
info "ConfigMap dx-pg-setup-sql (setup-postgres-dx.sql)"
kubectl -n "$SHARED_NS" create configmap dx-pg-setup-sql --from-file=setup-postgres-dx.sql \
  --dry-run=client -o yaml | kubectl apply -f -

render cluster-dx-pg.yaml '$SHARED_NS $PG_CLUSTER $SC_RWO' | kubectl apply -f -

info "Waiting for the cluster $PG_CLUSTER to be ready (1-3 minutes)"
kubectl -n "$SHARED_NS" wait clusters.postgresql.cnpg.io/"$PG_CLUSTER" --for=condition=Ready --timeout=10m
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER"
kubectl -n "$SHARED_NS" get pods,svc,pvc -l cnpg.io/cluster="$PG_CLUSTER"
echo "Service for DX: ${PG_HOST}:5432"
