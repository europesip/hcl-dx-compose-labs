#!/usr/bin/env bash
# Lab 3 · Apéndice · Prepara la BD iqdb en dx-pg (dx-shared) y el secret de IQ en dx-demo.
# El rol dx_iq_db_user ya lo crea CNPG (spec.managed.roles del cluster del Lab 2B).
# IQ crea sus propias tablas al arrancar: no hay script de esquema.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_vars SHARED_NS DX_NS PG_CLUSTER IQ_DB_PASSWORD

POD=$(kubectl -n "$SHARED_NS" get pod -l cnpg.io/cluster="$PG_CLUSTER",cnpg.io/instanceRole=primary -o name | head -1)
[[ -n "$POD" ]] || die "No hay cluster $PG_CLUSTER en $SHARED_NS: haz antes el Lab 2B"

info "Base de datos iqdb"
if kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -Atc "select 1 from pg_database where datname='iqdb'" | grep -q 1; then
  ok "iqdb ya existe"
else
  kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE DATABASE iqdb OWNER dx_iq_db_user;
REVOKE ALL ON DATABASE iqdb FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE iqdb TO dx_iq_db_user;
SQL
fi

info "Secret custom-external-db-credentials en $DX_NS"
apply_secret "$DX_NS" generic custom-external-db-credentials \
  --from-literal=username=dx_iq_db_user --from-literal=password="$IQ_DB_PASSWORD"

echo "Siguiente:  ./04-iq-install.sh -f custom-iq-values.db-external.yaml"
echo "Tras abrir un chat:  kubectl -n $SHARED_NS exec -i ${POD#pod/} -c postgres -- psql -U postgres -d iqdb -c '\\dt'"
