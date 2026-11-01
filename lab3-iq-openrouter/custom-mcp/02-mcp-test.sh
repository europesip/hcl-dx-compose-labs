#!/usr/bin/env bash
# Lab 3B · Step 2 · Test the MCP Server from INSIDE the cluster, speaking MCP the way the IQ
# Integrator will: initialize -> tools/list -> tools/call. IQ is not touched.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars DX_NS SHARED_NS
U="http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000/mcp"

# The test pod runs in the DX namespace: this also checks the DX -> shared namespace hop
kubectl -n "$DX_NS" run mcp-test --rm -i --restart=Never --quiet --image=curlimages/curl:8.11.1 --command -- sh -c "
H1='Content-Type: application/json'; H2='Accept: application/json, text/event-stream'
echo '== initialize'
curl -sS -X POST $U -H \"\$H1\" -H \"\$H2\" -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"curl\",\"version\":\"1\"}}}'; echo
echo '== tools/list'
curl -sS -X POST $U -H \"\$H1\" -H \"\$H2\" -d '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}'; echo
echo '== tools/call europesip_faq(topic=support)'
curl -sS -X POST $U -H \"\$H1\" -H \"\$H2\" -d '{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"europesip_faq\",\"arguments\":{\"topic\":\"support\"}}}'; echo
" </dev/null
echo "Next: ./03-iq-register.sh"
