#!/usr/bin/env bash
# External dependencies · EUROPESIP custom MCP Server (Lab 3B) in the shared namespace.
# The same installation as Lab 3B steps 1-2. When IQ is installed (Lab 3A step 4), it registers
# this server by itself; Lab 3B step 3 does it too if IQ already exists.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
MCP="$REPO_ROOT/lab3-iq-openrouter/custom-mcp"
"$MCP/01-mcp-deploy.sh"
"$MCP/02-mcp-test.sh"
