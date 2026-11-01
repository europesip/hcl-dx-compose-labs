#!/usr/bin/env bash
# Lab 3 · Read-only checks of the DX -> IQ -> MCP / LiteLLM -> OpenRouter chain.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"
I="${IQ_RELEASE}-integrator"; M="${IQ_RELEASE}-mcp-server"

info "Pods"
kubectl -n "$DX_NS" get pods | grep -E "^${IQ_RELEASE}-"
kubectl -n "$SHARED_NS" get pods -l app.kubernetes.io/instance="$LITELLM_RELEASE"

info "Effective Integrator configuration"
url=$(kubectl -n "$DX_NS" get cm "$I" -o jsonpath='{.data.dx\.config\.integrator\.litellm_url}')
[[ "$url" == "$LITELLM_URL_INTERNAL" ]] && ok "litellm_url = $url" || fail "litellm_url = '$url' (expected $LITELLM_URL_INTERNAL)"

P=$(kubectl -n "$DX_NS" get pods -l app="$I" --field-selector=status.phase=Running \
     --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
echo "  pod: $P"
# The URL the LLM adapter REALLY uses is the one in the dynamic configuration
rt=$(kubectl -n "$DX_NS" exec "$P" -- node -e 'const c=require("/home/dx_user/server-v1/runtime-config.json");console.log([c.LITELLM_BASE_URL,c.LITELLM_GENERAL_PURPOSE_MODEL,c.LITELLM_SUMMARY_MODEL].join(" "))' 2>/dev/null)
read -r rt_url rt_gp rt_sum <<<"$rt"
[[ "$rt_url" == "$url" ]] && ok "LITELLM_BASE_URL = $rt_url (models: $rt_gp / $rt_sum)" \
  || fail "LITELLM_BASE_URL = '${rt_url}' (different from litellm_url: check environment in custom-iq-values.yaml)"

L=$(kubectl -n "$DX_NS" logs "$P" --tail=5000 2>/dev/null)
grep -q "LITELLM_API_KEY configured statically" <<<"$L" && ok "static LiteLLM key (no KMS)" || fail "'LITELLM_API_KEY configured statically' not found"
t=$(grep -oE "Fetched [0-9]+ tools from https?://[^ :]+:[0-9]+" <<<"$L" | tail -1)
[[ -n "$t" ]] && ok "MCP: $t" || fail "the Integrator has not listed tools from the MCP Server"
e=$(grep -cE "LLM_ERROR|INVALID_MODEL|FORBIDDEN|RATE_LIMIT" <<<"$L")
[[ "$e" == 0 ]] && ok "no recent LLM errors" || fail "$e recent LLM errors (kubectl -n $DX_NS logs $P | grep -E 'LLM_ERROR|LiteLLM')"

info "Connectivity from the Integrator (includes the $DX_NS -> $SHARED_NS hop)"
kubectl -n "$DX_NS" exec "$P" -- node -e "
const u=['http://${M}:3000/probe/ready','${LITELLM_URL_INTERNAL}/health/liveliness'];
(async()=>{for(const x of u){try{const r=await fetch(x);console.log('  '+(r.ok?'OK  ':'FAIL')+' '+r.status+' '+x)}catch(e){console.log('  FAIL '+x+' '+e.message)}}})()"

info "DX"
v=$(helm -n "$DX_NS" get values "$DX_RELEASE" --all -o json | python3 -c 'import sys,json; print(json.load(sys.stdin).get("networking",{}).get("dxIqService") or "")')
[[ "$v" == "$I" ]] && ok "networking.dxIqService = $v" || fail "networking.dxIqService = '${v:-<empty>}' (run ./05-dx-enable-iq.sh)"
cfg=$(kubectl -n "$DX_NS" get cm -o name | grep -i haproxy | head -1)
[[ -n "$cfg" ]] && kubectl -n "$DX_NS" get "$cfg" -o yaml | grep -q "$I" \
  && ok "HAProxy routes /dx/api/iq/v1/ and /dx/ui/iq/ to $I" || warn "$I not found in the HAProxy configuration"
