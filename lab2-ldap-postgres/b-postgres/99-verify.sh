#!/usr/bin/env bash
# Lab 2B · Read-only checks of PostgreSQL and of its use by the Web Engine.
set -uo pipefail
source "$(dirname "$0")/../../common/lib.sh"

POD=$(kubectl -n "$SHARED_NS" get pod -l cnpg.io/cluster="$PG_CLUSTER",cnpg.io/instanceRole=primary -o name | head -1)
[[ -n "$POD" ]] || die "No primary for cluster $PG_CLUSTER in $SHARED_NS"
q() { kubectl -n "$SHARED_NS" exec -i "$POD" -c postgres -- psql -U postgres -At "$@"; }

info "CNPG cluster";          kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER"
info "Version";               q -c "select version()"
info "XA parameters";         q -c "show max_connections" -c "show max_prepared_transactions"
info "Databases";             q -c "select datname, pg_get_userbyid(datdba) from pg_database where not datistemplate order by 1"
info "JCR tablespaces";       q -c "select spcname, pg_get_userbyid(spcowner) from pg_tablespace where spcname like 'icm%' order by 1"

info "Tables per schema in dx_core (after the transfer: release ≈182, jcr ≈96, community ≈75, ...)"
q -d dx_core -c "select schemaname, count(*) from pg_tables where schemaname in ('release','jcr','community','customization','feedback','likeminds') group by 1 order by 2 desc"
total=$(q -d dx_core -c "select count(*) from pg_tables where schemaname in ('release','jcr','community','customization','feedback','likeminds')")
((total > 400)) && ok "$total tables: transfer completed" || warn "$total tables: has the transfer not finished yet?"

info "Web Engine connections"
q -c "select usename, datname, count(*) from pg_stat_activity where usename='dxuser' group by 1,2"

info "Configuration in DX"
helm -n "$DX_NS" get values "$DX_RELEASE" --all -o json | python3 -c '
import sys, json
w = json.load(sys.stdin)["configuration"]["webEngine"]
for k in ("useExternalDatabase", "dropDatabaseTables", "customDbDomainPropertiesSecret"):
    print(f"  {k} = {w.get(k)}")'

info "Web Engine database messages"
kubectl -n "$DX_NS" logs "${DX_RELEASE}-web-engine-0" -c system-out-log --tail=3000 2>/dev/null \
  | grep -iE "database transfer|transfer.*(complete|success)|DSRA|SQLException" | tail -15 | sed 's/^/  /'
