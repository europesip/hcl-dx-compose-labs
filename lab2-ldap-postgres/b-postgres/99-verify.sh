#!/usr/bin/env bash
# Lab 2B · Comprobaciones de solo lectura del PostgreSQL y de su uso por el Web Engine.
set -uo pipefail
source "$(dirname "$0")/../../common/lib.sh"

POD=$(kubectl -n "$SHARED_NS" get pod -l cnpg.io/cluster="$PG_CLUSTER",cnpg.io/instanceRole=primary -o name | head -1)
[[ -n "$POD" ]] || die "No hay primario del cluster $PG_CLUSTER en $SHARED_NS"
q() { kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -At "$@"; }

info "Cluster CNPG";          kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER"
info "Versión";               q -c "select version()"
info "Parámetros XA";         q -c "show max_connections" -c "show max_prepared_transactions"
info "Bases de datos";        q -c "select datname, pg_get_userbyid(datdba) from pg_database where not datistemplate order by 1"
info "Tablespaces del JCR";   q -c "select spcname, pg_get_userbyid(spcowner) from pg_tablespace where spcname like 'icm%' order by 1"

info "Tablas por esquema en dx_core (tras la transferencia: release ≈182, jcr ≈96, community ≈75, ...)"
q -d dx_core -c "select schemaname, count(*) from pg_tables where schemaname in ('release','jcr','community','customization','feedback','likeminds') group by 1 order by 2 desc"
total=$(q -d dx_core -c "select count(*) from pg_tables where schemaname in ('release','jcr','community','customization','feedback','likeminds')")
((total > 400)) && ok "$total tablas: transferencia completada" || warn "$total tablas: ¿la transferencia no ha terminado todavía?"

info "Conexiones del Web Engine"
q -c "select usename, datname, count(*) from pg_stat_activity where usename='wpsuser' group by 1,2"

info "Configuración en DX"
helm -n "$DX_NS" get values "$DX_RELEASE" --all -o json | python3 -c '
import sys, json
w = json.load(sys.stdin)["configuration"]["webEngine"]
for k in ("useExternalDatabase", "dropDatabaseTables", "customDbDomainPropertiesSecret"):
    print(f"  {k} = {w.get(k)}")'

info "Mensajes de base de datos del Web Engine"
kubectl -n "$DX_NS" logs "${DX_RELEASE}-web-engine-0" -c system-out-log --tail=3000 2>/dev/null \
  | grep -iE "database transfer|transfer.*(complete|success)|DSRA|SQLException" | tail -15 | sed 's/^/  /'
