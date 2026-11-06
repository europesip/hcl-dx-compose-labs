#!/usr/bin/env bash
# Lab 5 · Register the ÓRBITA MCP server in HCL DX IQ (needs Lab 3), so that the IQ assistant can
# answer and act on ÓRBITA as the user asking.
#
# The documented variable MCP_SERVER_LIST has no effect (HCL case CS1479102, see issues.md): the IQ
# chart generates the ConfigMap <IQ_RELEASE>-integrator with its own list. This script ADDS the ÓRBITA
# URL to that list (keeping the HCL MCP Server and any other), restarts the Integrator and shows the
# tools it loaded. Running it again does not duplicate the entry. Lab 3 04-iq-install.sh adds ÓRBITA
# back after every IQ upgrade.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd kubectl
: "${ORBITA_RELEASE:=orbita}"
require_vars DX_NS SHARED_NS IQ_RELEASE
CM="${IQ_RELEASE}-integrator"
URL="http://${ORBITA_RELEASE}-api.${SHARED_NS}.svc.cluster.local:9081"

kubectl -n "$SHARED_NS" get svc "$ORBITA_RELEASE"-api >/dev/null 2>&1 || die "ÓRBITA is not installed: ./01-orbita-install.sh"
kubectl -n "$DX_NS" get configmap "$CM" >/dev/null 2>&1 || die "ConfigMap $CM is missing: do Lab 3 first"

LIST=$(kubectl -n "$DX_NS" get configmap "$CM" -o jsonpath='{.data.dx\.config\.integrator\.mcp_server_list}')
info "Current list: ${LIST:-(empty)}"
if [[ ",$LIST," == *",$URL,"* ]]; then
  ok "ÓRBITA is already in the list"
else
  LIST="${LIST:+$LIST,}$URL"
  kubectl -n "$DX_NS" patch configmap "$CM" --type merge -p "{\"data\":{\"dx.config.integrator.mcp_server_list\":\"$LIST\"}}"
  info "New list: $LIST"
fi
info "Restarting the Integrator (it reads the list and the tools at start-up)"
kubectl -n "$DX_NS" rollout restart deployment/"$CM"
kubectl -n "$DX_NS" rollout status deployment/"$CM" --timeout=300s
sleep 15
kubectl -n "$DX_NS" logs deploy/"$CM" | grep -oE "Fetched [0-9]+ tools from [^ ]+|Total tools: [0-9]+" | sort -u | sed 's/^/  /'
echo "Ask in the IQ chat, as a demo user:  ¿Cuántos días de vacaciones me quedan?   (more: lab5-orbita/GUIDE.md)"
