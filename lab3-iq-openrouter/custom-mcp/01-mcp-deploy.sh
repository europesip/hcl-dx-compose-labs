#!/usr/bin/env bash
# Lab 3B · Step 1 · Deploy the custom MCP Server in the shared namespace. IQ is not touched yet.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS DX_NS DX_RELEASE
cd "$(dirname "$0")"

render europesip-mcp.yaml '$SHARED_NS $DX_NS $DX_RELEASE' | kubectl apply -f -
kubectl -n "$SHARED_NS" rollout status deployment/europesip-mcp --timeout=300s
kubectl -n "$SHARED_NS" get pods,svc -l app=europesip-mcp
echo "URL for IQ: http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"
echo "Next: ./02-mcp-test.sh"
