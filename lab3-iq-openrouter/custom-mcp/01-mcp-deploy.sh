#!/usr/bin/env bash
# Lab 3B · Step 1 · Deploy the custom MCP Server in the shared namespace. IQ is not touched yet.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS
cd "$(dirname "$0")"

existed=0; kubectl -n "$SHARED_NS" get deployment europesip-mcp >/dev/null 2>&1 && existed=1
kubectl -n "$SHARED_NS" create configmap europesip-mcp-code --from-file=server.py \
  --dry-run=client -o yaml | kubectl apply -f -
render europesip-mcp.yaml '$SHARED_NS' | kubectl apply -f -
# On an update, if only server.py (ConfigMap) changed, the pod does not restart by itself
((existed)) && kubectl -n "$SHARED_NS" rollout restart deployment/europesip-mcp >/dev/null
kubectl -n "$SHARED_NS" rollout status deployment/europesip-mcp --timeout=300s
kubectl -n "$SHARED_NS" get pods,svc -l app=europesip-mcp
echo "URL for IQ: http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"
echo "Next: ./02-mcp-test.sh"
