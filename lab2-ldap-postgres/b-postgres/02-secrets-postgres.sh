#!/usr/bin/env bash
# Lab 2B · Paso 2 · Secrets basic-auth de los usuarios de PostgreSQL, en dx-shared.
#   dx-pg-superuser  postgres       superusuario del cluster
#   dx-pg-dxuser     dxuser         dueño de la BD dx_core del Web Engine
#   dx-pg-iquser     dx_iq_db_user  BD de IQ (solo se usa en el apéndice del Lab 3)
# La etiqueta cnpg.io/reload=true hace que CNPG aplique al rol los cambios de contraseña.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS PG_SUPERUSER_PASSWORD DXUSER_PASSWORD IQ_DB_PASSWORD

mk() {  # mk <secret> <usuario> <password>
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
