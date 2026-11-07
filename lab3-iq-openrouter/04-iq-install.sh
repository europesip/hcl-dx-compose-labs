#!/usr/bin/env bash
# Lab 3 · Step 4 · Install or upgrade IQ (Integrator + MCP Server) in the DX namespace.
# Usage:  ./04-iq-install.sh                                        (sessions in in-memory SQLite)
#         ./04-iq-install.sh -f custom-iq-values.db-external.yaml   (appendix: sessions in PostgreSQL)
#         ./04-iq-install.sh -f custom-iq-values.db-external.yaml -f custom-iq-values.rag.yaml
#                                                                   (appendix: + cross-session memory, RAG)
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm
require_vars DX_NS SHARED_NS IQ_RELEASE IQ_CHART_TGZ DX_RELEASE DX_HOST LITELLM_URL_INTERNAL
cd "$(dirname "$0")"

[[ -f "$IQ_CHART_TGZ" ]] || die "$IQ_CHART_TGZ not found: run common/02-pull-hcl-charts.sh"
kubectl -n "$DX_NS" get secret iq-litellm-api-secret >/dev/null 2>&1 || die "iq-litellm-api-secret is missing: ./01-secrets.sh"
helm -n "$DX_NS" status "$DX_RELEASE" >/dev/null 2>&1 || die "DX ($DX_RELEASE) is not installed in $DX_NS"

# The LiteLLM URL appears twice in custom-iq-values.yaml (litellm.liteLlmUrl and the
# LITELLM_BASE_URL variable, inside a list that --set cannot address): a temporary copy gets the
# value from env.sh.
VALUES=$(mktemp --suffix=.yaml); RAGV=$(mktemp --suffix=.yaml); trap 'rm -f "$VALUES" "$RAGV"' EXIT
sed "s|http://litellm.dx-shared.svc.cluster.local:4000|${LITELLM_URL_INTERNAL}|g" custom-iq-values.yaml > "$VALUES"
EXTRA=()
[[ " $* " == *custom-iq-values.db-external.yaml* ]] && EXTRA+=(--set-string configuration.database.dbHost="$PG_HOST")
# RAG (appendix): its list repeats LITELLM_BASE_URL, so it gets the same substitution
ARGS=()
for a in "$@"; do
  if [[ "$a" == *custom-iq-values.rag.yaml ]]; then
    [[ " $* " == *custom-iq-values.db-external.yaml* ]] || die "RAG needs PostgreSQL: add -f custom-iq-values.db-external.yaml (and run ./A1-iq-database.sh)"
    sed "s|http://litellm.dx-shared.svc.cluster.local:4000|${LITELLM_URL_INTERNAL}|g" "$a" > "$RAGV"; a="$RAGV"
  fi
  ARGS+=("$a")
done

# Helm 4: after Lab 3B the MCP server list of the ConfigMap belongs to "kubectl patch" (see below), so the
# upgrade needs --force-conflicts (empty with Helm 3, see common/lib.sh); the list is patched again below.
helm upgrade --install "$IQ_RELEASE" "$IQ_CHART_TGZ" -n "$DX_NS" -f "$VALUES" "${ARGS[@]}" "${EXTRA[@]}" $HELM_FORCE_CONFLICTS \
  --set-string configuration.dx.releaseName="$DX_RELEASE" \
  --set-string configuration.dx.externalHost="$DX_HOST"

# Lab 3B and Lab 5: the chart regenerates the MCP Server list with only the HCL one. The custom MCP
# servers that exist in the shared namespace are added back (see custom-mcp/03-iq-register.sh and
# lab5-orbita/02-orbita-iq.sh).
# The HCL MCP Server as the chart wrote it (https with mcpServer.httpsEnabled), then the custom ones
LIST=$(kubectl -n "$DX_NS" get configmap "${IQ_RELEASE}-integrator" -o jsonpath='{.data.dx\.config\.integrator\.mcp_server_list}' | cut -d, -f1)
[ -n "$LIST" ] || LIST="https://${IQ_RELEASE}-mcp-server:3000"
kubectl -n "$SHARED_NS" get svc europesip-mcp >/dev/null 2>&1 && LIST="$LIST,http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"
kubectl -n "$SHARED_NS" get svc "${ORBITA_RELEASE:-orbita}-api" >/dev/null 2>&1 && LIST="$LIST,http://${ORBITA_RELEASE:-orbita}-api.${SHARED_NS}.svc.cluster.local:9081"
if [[ "$LIST" == *,* ]]; then
  kubectl -n "$DX_NS" patch configmap "${IQ_RELEASE}-integrator" --type merge \
    -p "{\"data\":{\"dx.config.integrator.mcp_server_list\":\"$LIST\"}}"
  info "MCP Servers: $LIST"
fi

# Helm does not restart the pods if only secrets change: restart both.
# First the MCP Server (the Integrator reads its tool list when it starts).
kubectl -n "$DX_NS" rollout restart deployment/"$IQ_RELEASE"-mcp-server
kubectl -n "$DX_NS" rollout status  deployment/"$IQ_RELEASE"-mcp-server --timeout=300s
kubectl -n "$DX_NS" rollout restart deployment/"$IQ_RELEASE"-integrator
kubectl -n "$DX_NS" rollout status  deployment/"$IQ_RELEASE"-integrator --timeout=300s
kubectl -n "$DX_NS" get pods | grep -E "^${IQ_RELEASE}-"
echo "Next: ./05-dx-enable-iq.sh (enables IQ in DX)"
