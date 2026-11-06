#!/usr/bin/env bash
# Lab 5 · Check: database Job, API, Script Applications and pages, public API and IQ registration.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"
: "${ORBITA_RELEASE:=orbita}"
R="$ORBITA_RELEASE"
helm -n "$SHARED_NS" status "$R" 2>/dev/null | grep -E "^STATUS|^REVISION" | sed 's/^/    /'
kubectl -n "$SHARED_NS" wait job/"$R"-db --for=condition=Complete --timeout=5s >/dev/null 2>&1 \
  && ok "Database and user created (job $R-db)" || fail "job $R-db did not complete: kubectl -n $SHARED_NS logs job/$R-db"
kubectl -n "$SHARED_NS" rollout status deploy/"$R"-api --timeout=5s >/dev/null 2>&1 \
  && ok "orbita-api ready: $(kubectl -n "$SHARED_NS" logs deploy/"$R"-api | grep -o 'esquema en la versión [0-9]*' | tail -1)" \
  || fail "orbita-api is not ready: kubectl -n $SHARED_NS logs deploy/$R-api"
if kubectl -n "$SHARED_NS" wait job/"$R"-scriptapps-push --for=condition=Complete --timeout=5s >/dev/null 2>&1; then
  ok "Script Applications: $(kubectl -n "$SHARED_NS" logs job/"$R"-scriptapps-push -c dxclient | grep -c "is in WCM") in WCM, pages created"
else
  fail "job $R-scriptapps-push did not complete: kubectl -n $SHARED_NS logs job/$R-scriptapps-push -c dxclient"
fi
s=$(curl -sk -o /dev/null -w '%{http_code}' "https://$DX_HOST/orbita-api/v1/salud")
[[ "$s" == 200 ]] && ok "https://$DX_HOST/orbita-api/v1/salud -> 200" || fail "https://$DX_HOST/orbita-api/v1/salud -> $s"
s=$(curl -sk -o /dev/null -w '%{http_code}' "https://$DX_HOST/orbita-api/v1/yo")
[[ "$s" == 401 ]] && ok "without a DX session -> 401 (the API asks DX who the user is)" || fail "without a DX session -> $s (expected 401)"
if kubectl -n "$DX_NS" get configmap "${IQ_RELEASE}-integrator" >/dev/null 2>&1; then
  kubectl -n "$DX_NS" get configmap "${IQ_RELEASE}-integrator" -o jsonpath='{.data.dx\.config\.integrator\.mcp_server_list}' | grep -q "$R-api" \
    && ok "ÓRBITA MCP server registered in IQ" || warn "ÓRBITA is not in the IQ MCP list yet: ./02-orbita-iq.sh"
fi
