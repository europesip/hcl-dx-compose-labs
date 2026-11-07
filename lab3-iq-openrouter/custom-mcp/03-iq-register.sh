#!/usr/bin/env bash
# Lab 3B · Step 3 · Register the custom MCP Server in IQ.
#
# The Integrator reads the list of MCP Servers (comma separated) from the key
# dx.config.integrator.mcp_server_list of the <IQ_RELEASE>-integrator ConfigMap. Chart 1.0.3
# generates it with a single server (the HCL one) and offers no value to extend it; the
# MCP_SERVER_LIST environment variable has no effect either (the ConfigMap overrides it). So:
#   1. the ConfigMap is patched with both servers, and
#   2. the Integrator is restarted, and it lists the tools of all of them when it starts.
# As an IQ "helm upgrade" regenerates the ConfigMap, 04-iq-install.sh repeats this step
# automatically if the europesip-mcp service exists in the shared namespace.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars DX_NS SHARED_NS IQ_RELEASE

kubectl -n "$SHARED_NS" get svc europesip-mcp >/dev/null 2>&1 || die "europesip-mcp does not exist in $SHARED_NS: ./01-mcp-deploy.sh"
# First the HCL MCP Server as the chart wrote it (https:// with mcpServer.httpsEnabled), then ours (HTTP)
HCL=$(kubectl -n "$DX_NS" get configmap "${IQ_RELEASE}-integrator" -o jsonpath='{.data.dx\.config\.integrator\.mcp_server_list}' | cut -d, -f1)
[ -n "$HCL" ] || HCL="https://${IQ_RELEASE}-mcp-server:3000"
LIST="$HCL,http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"

info "ConfigMap ${IQ_RELEASE}-integrator: mcp_server_list = $LIST"
kubectl -n "$DX_NS" patch configmap "${IQ_RELEASE}-integrator" --type merge \
  -p "{\"data\":{\"dx.config.integrator.mcp_server_list\":\"$LIST\"}}"
kubectl -n "$DX_NS" rollout restart deployment/"${IQ_RELEASE}"-integrator
kubectl -n "$DX_NS" rollout status  deployment/"${IQ_RELEASE}"-integrator --timeout=300s

info "Tools loaded by the Integrator (new pod)"
sleep 15
P=$(kubectl -n "$DX_NS" get pods -l app="${IQ_RELEASE}-integrator" --field-selector=status.phase=Running \
     --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl -n "$DX_NS" logs "$P" \
  | grep -oE "Fetched [0-9]+ tools from [^ ]+|Total tools: [0-9]+" | sort -u | sed 's/^/  /'
echo "Next: ../06-iq-chat-test.sh \"What are the EUROPESIP support hours?\""
