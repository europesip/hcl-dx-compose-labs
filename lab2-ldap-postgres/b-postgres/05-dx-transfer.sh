#!/usr/bin/env bash
# Lab 2B · Step 5 · helm upgrade with the custom-values.postgres.yaml layer: the Web Engine restarts
# and transfers its database from Derby (customization PVC) to PostgreSQL (dx_core in $PG_CLUSTER).
#
# HCL: do not scale the Web Engine while the transfer is running.
# To follow it in another terminal:
#   kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"

kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbdomain-secret >/dev/null 2>&1 \
  || die "The properties secret is missing: run ./04-secrets-webengine.sh"
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER" >/dev/null 2>&1 \
  || die "Cluster $PG_CLUSTER does not exist in $SHARED_NS: run ./03-postgres-cluster.sh"
# dx_core must have been prepared by setup-postgres-dx.sql when the cluster was created (not
# published with the labs); a cluster created without it has an empty dx_core and the transfer fails
kubectl -n "$SHARED_NS" get configmap dx-pg-setup-sql >/dev/null 2>&1 \
  || die "dx_core was not prepared for the Web Engine (setup-postgres-dx.sql, not supplied with the labs): keep Derby or use Oracle"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Check the result with ./99-verify.sh (there should be about 465 tables in dx_core)."
