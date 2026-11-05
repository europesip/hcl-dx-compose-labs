#!/usr/bin/env bash
# External dependencies · What is installed in the shared namespace.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"
chk() {  # chk <name> <command...>
  local n=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$n"; else warn "$n: not installed"; fi
}
info "External dependencies in $SHARED_NS"
chk "OpenLDAP ($LDAP_RELEASE)"         kubectl -n "$SHARED_NS" get statefulset "$LDAP_RELEASE"
chk "PostgreSQL ($PG_CLUSTER)"         kubectl -n "$SHARED_NS" wait clusters.postgresql.cnpg.io/"$PG_CLUSTER" --for=condition=Ready --timeout=5s
chk "LiteLLM ($LITELLM_RELEASE)"       kubectl -n "$SHARED_NS" rollout status deployment/"$LITELLM_RELEASE" --timeout=5s
chk "EUROPESIP MCP (europesip-mcp)"    kubectl -n "$SHARED_NS" rollout status deployment/europesip-mcp --timeout=5s
