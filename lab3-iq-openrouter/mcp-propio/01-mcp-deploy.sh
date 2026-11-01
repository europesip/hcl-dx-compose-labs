#!/usr/bin/env bash
# Lab 3B · Paso 1 · Despliega el MCP Server propio en dx-shared. No toca IQ todavía.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS
cd "$(dirname "$0")"

existed=0; kubectl -n "$SHARED_NS" get deployment europesip-mcp >/dev/null 2>&1 && existed=1
kubectl -n "$SHARED_NS" create configmap europesip-mcp-code --from-file=server.py \
  --dry-run=client -o yaml | kubectl apply -f -
render europesip-mcp.yaml '$SHARED_NS' | kubectl apply -f -
# En una actualización, si solo cambió server.py (ConfigMap), el pod no se reinicia solo
((existed)) && kubectl -n "$SHARED_NS" rollout restart deployment/europesip-mcp >/dev/null
kubectl -n "$SHARED_NS" rollout status deployment/europesip-mcp --timeout=300s
kubectl -n "$SHARED_NS" get pods,svc -l app=europesip-mcp
echo "URL para IQ: http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"
echo "Siguiente: ./02-mcp-test.sh"
