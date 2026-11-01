#!/usr/bin/env bash
# Lab 2B · Step 2 · basic-auth secrets of the PostgreSQL users, in the shared namespace.
#   dx-pg-superuser  postgres       cluster superuser
#   dx-pg-dxuser     dxuser         owner of the Web Engine dx_core database
#   dx-pg-iquser     dx_iq_db_user  IQ database (only used in the Lab 3 appendix)
# The cnpg.io/reload=true label makes CNPG apply password changes to the role.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS PG_SUPERUSER_PASSWORD DXUSER_PASSWORD IQ_DB_PASSWORD

mk() {  # mk <secret> <user> <password>
  kubectl -n "$SHARED_NS" create secret generic "$1" \
    --type=kubernetes.io/basic-auth \
    --from-literal=username="$2" --from-literal=password="$3" \
    --dry-run=client -o yaml \
  | kubectl label --local -f - cnpg.io/reload=true -o yaml \
  | kubectl apply -f -
}

mk dx-pg-superuser postgres      "$PG_SUPERUSER_PASSWORD"
mk dx-pg-dxuser    dxuser        "$DXUSER_PASSWORD"
mk dx-pg-iquser    dx_iq_db_user "$IQ_DB_PASSWORD"

kubectl -n "$SHARED_NS" get secrets -l cnpg.io/reload=true
