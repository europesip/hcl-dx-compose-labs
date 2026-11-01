#!/usr/bin/env bash
# Lab 4 · Comprobaciones de Search V2 por su API REST (https://$DX_HOST/dx/api/search/v2).
# Uso:  ./99-verify.sh            (estado, fuentes de contenido, rastreadores y una búsqueda)
#       ./99-verify.sh --crawl    (además lanza ahora todos los rastreadores, sin esperar 15 min)
#       ./99-verify.sh --crawl "webinar"   (y busca ese texto)
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd curl python3
CRAWL=0; [[ "${1:-}" == "--crawl" ]] && { CRAWL=1; shift; }
Q="${1:-Woodburn}"
API="https://${DX_HOST}/dx/api/search/v2"
J=$(mktemp); trap 'rm -f "$J"' EXIT

info "Pods de búsqueda"
kubectl -n "$DX_NS" get pods --no-headers | awk -v r="$SEARCH_RELEASE" '$1 ~ "^"r"-" {print "  "$1, $2, $3}'

info "DX: Search V2 activado"
v=$(helm -n "$DX_NS" get values "$DX_RELEASE" --all -o json | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["networking"].get("searchMiddlewareService"), d["configuration"]["searchMiddleware"].get("enabled"))')
[[ "$v" == "${SEARCH_RELEASE}-search-middleware-query True" ]] && ok "searchMiddlewareService + searchMiddleware.enabled" || fail "valores de DX: $v (¿./03-dx-enable-search.sh?)"
code=$(curl -sk -o /dev/null -w '%{http_code}' "$API/explorer/")
[[ "$code" == 200 ]] && ok "API explorer accesible por HAProxy de DX ($API/explorer)" || fail "explorer HTTP $code"

info "Token de administración (searchadmin, credenciales generadas por el chart)"
SECRET="${SEARCH_RELEASE}-search-middleware-admin"
U=$(kubectl -n "$DX_NS" get secret "$SECRET" -o jsonpath='{.data.username}' | base64 -d)
P=$(kubectl -n "$DX_NS" get secret "$SECRET" -o jsonpath='{.data.password}' | base64 -d)
TOKEN=$(python3 -I -c 'import json,sys; print(json.dumps({"username":sys.argv[1],"password":sys.argv[2]}))' "$U" "$P" \
  | curl -sk -H 'Content-Type: application/json' --data @- "$API/admin/authenticate" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("jwt") or d.get("token") or d.get("access_token") or "")' 2>/dev/null)
[[ -n "$TOKEN" ]] && ok "token obtenido" || { fail "no se obtuvo token de $SECRET"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")

info "Fuentes de contenido (creadas por automatedSetup)"
curl -sk "${AUTH[@]}" "$API/contentsources" > "$J"
python3 -I - "$J" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1])); items=d.get("contentSources", d if isinstance(d,list) else d.get("items",[]))
for c in items: print(f"  {c.get('type','?'):24} {c.get('name','?'):40} {c.get('id','')}")
print(f"  total: {len(items)}")
EOF

info "Rastreadores"
curl -sk "${AUTH[@]}" "$API/crawlers" > "$J"
mapfile -t CRAWLERS < <(python3 -I - "$J" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1])); items=d.get("crawlers", d if isinstance(d,list) else d.get("items",[]))
import datetime
for c in items:
    lc=c.get("lastCrawled") or 0
    last=datetime.datetime.fromtimestamp(lc/1000).strftime("%H:%M:%S") if lc else "nunca"
    print(f"{c.get('id')}\t{c.get('type','?')}\t{c.get('configuration',{}).get('schedule','')}\t{last}\t{c.get('lastCrawlDuration',0)}")
EOF
)
for c in "${CRAWLERS[@]}"; do IFS=$'\t' read -r id t s last dur <<<"$c"; printf '  %-7s programado "%s"  último rastreo: %s (%s ms)\n' "$t" "$s" "$last" "$dur"; done

if ((CRAWL)); then
  info "Lanzando los rastreadores ahora"
  for c in "${CRAWLERS[@]}"; do id=${c%%$'\t'*}
    printf '  %s -> HTTP %s\n' "$id" "$(curl -sk "${AUTH[@]}" -X POST -o /dev/null -w '%{http_code}' "$API/crawlers/$id/trigger")"
  done
  echo "  esperando 90 s a que indexen..."; sleep 90
fi

info "Búsqueda como wpsadmin (con sus permisos): \"$Q\""
JAR=$(mktemp)
python3 -I -c 'import json,sys; print(json.dumps({"username":"wpsadmin","password":sys.argv[1]}))' "$WPSADMIN_PASSWORD" \
  | curl -sk -c "$JAR" -o /dev/null -H 'Content-Type: application/json' --data @- "https://${DX_HOST}/dx/api/core/v1/auth/login"
python3 -I -c 'import json,sys; print(json.dumps({"query":{"must":[{"multi_match":{"query":sys.argv[1],"fields":["title^3","description^2","text"]}}]},"pageSize":5,"aggregations":{"tipo":{"terms":{"field":"type.keyword"}}}}))' "$Q" \
  | curl -sk -b "$JAR" -H 'Content-Type: application/json' --data @- "$API/mysearch" > "$J"
rm -f "$JAR"
python3 -I - "$J" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1]))
hits=d.get("hits",{}); tot=hits.get("total",{}); tot=tot.get("value",tot) if isinstance(tot,dict) else tot
print(f"  resultados: {tot}")
for h in hits.get("hits",[])[:5]:
    s=h.get("_source",{}); print(f"   - [{s.get('type','?')}] {s.get('title','?')[:70]}")
for b in d.get("aggregations",{}).get("tipo",{}).get("buckets",[]): print(f"   por tipo: {b['key']} = {b['doc_count']}")
if not hits: print("  respuesta:", json.dumps(d)[:300])
EOF
