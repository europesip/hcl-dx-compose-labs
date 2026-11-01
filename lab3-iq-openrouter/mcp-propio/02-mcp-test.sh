#!/usr/bin/env bash
# Lab 3B · Paso 2 · Prueba el MCP Server desde DENTRO del clúster, hablando MCP como lo hará el
# IQ Integrator: initialize -> tools/list -> tools/call. No toca IQ.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars DX_NS SHARED_NS
U="http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000/mcp"

# El pod de prueba se lanza en dx-demo: así se comprueba también el salto dx-demo -> dx-shared
kubectl -n "$DX_NS" run mcp-test --rm -i --restart=Never --quiet --image=curlimages/curl:8.11.1 --command -- sh -c "
H1='Content-Type: application/json'; H2='Accept: application/json, text/event-stream'
echo '== initialize'
curl -sS -X POST $U -H \"\$H1\" -H \"\$H2\" -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"curl\",\"version\":\"1\"}}}'; echo
echo '== tools/list'
curl -sS -X POST $U -H \"\$H1\" -H \"\$H2\" -d '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}'; echo
echo '== tools/call consultar_faq_europesip(tema=soporte)'
curl -sS -X POST $U -H \"\$H1\" -H \"\$H2\" -d '{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"consultar_faq_europesip\",\"arguments\":{\"tema\":\"soporte\"}}}'; echo
"
echo "Siguiente: ./03-iq-register.sh"
