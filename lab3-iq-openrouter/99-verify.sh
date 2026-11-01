#!/usr/bin/env bash
# Lab 3 · Comprobaciones de solo lectura de la cadena DX -> IQ -> MCP / LiteLLM -> OpenRouter.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"
I="${IQ_RELEASE}-integrator"; M="${IQ_RELEASE}-mcp-server"

info "Pods"
kubectl -n "$DX_NS" get pods | grep -E "^${IQ_RELEASE}-"
kubectl -n "$SHARED_NS" get pods -l app.kubernetes.io/instance="$LITELLM_RELEASE"

info "Configuración efectiva del Integrator"
url=$(kubectl -n "$DX_NS" get cm "$I" -o jsonpath='{.data.dx\.config\.integrator\.litellm_url}')
[[ "$url" == "$LITELLM_URL_INTERNAL" ]] && ok "litellm_url = $url" || fail "litellm_url = '$url' (esperado $LITELLM_URL_INTERNAL)"

P=$(kubectl -n "$DX_NS" get pods -l app="$I" --field-selector=status.phase=Running \
     --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
echo "  pod: $P"
# La URL que usa DE VERDAD el adaptador LLM es la de la configuración dinámica
rt=$(kubectl -n "$DX_NS" exec "$P" -- node -e 'const c=require("/home/dx_user/server-v1/runtime-config.json");console.log([c.LITELLM_BASE_URL,c.LITELLM_GENERAL_PURPOSE_MODEL,c.LITELLM_SUMMARY_MODEL].join(" "))' 2>/dev/null)
read -r rt_url rt_gp rt_sum <<<"$rt"
[[ "$rt_url" == "$url" ]] && ok "LITELLM_BASE_URL = $rt_url (modelos: $rt_gp / $rt_sum)" \
  || fail "LITELLM_BASE_URL = '${rt_url}' (distinta de litellm_url: revisa environment en custom-iq-values.yaml)"

L=$(kubectl -n "$DX_NS" logs "$P" --tail=5000 2>/dev/null)
grep -q "LITELLM_API_KEY configured statically" <<<"$L" && ok "clave de LiteLLM estática (sin KMS)" || fail "no aparece 'LITELLM_API_KEY configured statically'"
t=$(grep -oE "Fetched [0-9]+ tools from https?://[^ :]+:[0-9]+" <<<"$L" | tail -1)
[[ -n "$t" ]] && ok "MCP: $t" || fail "el Integrator no ha listado herramientas del MCP Server"
e=$(grep -cE "LLM_ERROR|INVALID_MODEL|FORBIDDEN|RATE_LIMIT" <<<"$L")
[[ "$e" == 0 ]] && ok "sin errores LLM recientes" || fail "$e errores LLM recientes (kubectl -n $DX_NS logs $P | grep -E 'LLM_ERROR|LiteLLM')"

info "Conectividad desde el Integrator (incluye el salto dx-demo -> dx-shared)"
kubectl -n "$DX_NS" exec "$P" -- node -e "
const u=['http://${M}:3000/probe/ready','${LITELLM_URL_INTERNAL}/health/liveliness'];
(async()=>{for(const x of u){try{const r=await fetch(x);console.log('  '+(r.ok?'OK   ':'FALLO')+' '+r.status+' '+x)}catch(e){console.log('  FALLO '+x+' '+e.message)}}})()"

info "DX"
v=$(helm -n "$DX_NS" get values "$DX_RELEASE" --all -o json | python3 -c 'import sys,json; print(json.load(sys.stdin).get("networking",{}).get("dxIqService") or "")')
[[ "$v" == "$I" ]] && ok "networking.dxIqService = $v" || fail "networking.dxIqService = '${v:-<vacío>}' (ejecuta ./05-dx-enable-iq.sh)"
cfg=$(kubectl -n "$DX_NS" get cm -o name | grep -i haproxy | head -1)
[[ -n "$cfg" ]] && kubectl -n "$DX_NS" get "$cfg" -o yaml | grep -q "$I" \
  && ok "HAProxy enruta /dx/api/iq/v1/ y /dx/ui/iq/ a $I" || warn "no se encuentra $I en la configuración de HAProxy"
