#!/usr/bin/env bash
# Lab 3 · Appendix · Prepare the iqdb database in $PG_CLUSTER (shared namespace) and the IQ secret
# in the DX namespace. The dx_iq_db_user role is already created by CNPG (spec.managed.roles of the
# Lab 2B cluster). IQ creates its own tables when it starts: there is no schema script.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_vars SHARED_NS DX_NS PG_CLUSTER IQ_DB_PASSWORD

POD=$(kubectl -n "$SHARED_NS" get pod -l cnpg.io/cluster="$PG_CLUSTER",cnpg.io/instanceRole=primary -o name | head -1)
[[ -n "$POD" ]] || die "No cluster $PG_CLUSTER in $SHARED_NS: install PostgreSQL first (external-deps/02-postgres.sh)"

info "iqdb database"
if kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -Atc "select 1 from pg_database where datname='iqdb'" </dev/null | grep -q 1; then
  ok "iqdb already exists"
else
  kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE DATABASE iqdb OWNER dx_iq_db_user;
REVOKE ALL ON DATABASE iqdb FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE iqdb TO dx_iq_db_user;
SQL
fi

# pgvector, for IQ's optional cross-session memory (RAG, custom-iq-values.rag.yaml). The CNPG
# "standard" image includes it; harmless while RAG is off. Needs the superuser, not dx_iq_db_user.
kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -d iqdb -v ON_ERROR_STOP=1 \
  -Aq -c "SET client_min_messages TO warning" -c "CREATE EXTENSION IF NOT EXISTS vector" </dev/null >/dev/null \
  && ok "pgvector extension in iqdb" || warn "pgvector is not available in $PG_CLUSTER: RAG (optional) will not work"

info "Secret custom-external-db-credentials in $DX_NS"
apply_secret "$DX_NS" generic custom-external-db-credentials \
  --from-literal=username=dx_iq_db_user --from-literal=password="$IQ_DB_PASSWORD"

echo "Next:  ./04-iq-install.sh -f custom-iq-values.db-external.yaml    (add -f custom-iq-values.rag.yaml for RAG)"
echo "After opening a chat:  kubectl -n $SHARED_NS exec -i ${POD#pod/} -c postgres -- psql -U postgres -d iqdb -c '\\dt'"
