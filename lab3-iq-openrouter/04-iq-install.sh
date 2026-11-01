#!/usr/bin/env bash
# Lab 3 · Paso 4 · Instala o actualiza IQ (Integrator + MCP Server) en dx-demo.
# Uso:  ./04-iq-install.sh                                        (sesiones en SQLite en memoria)
#       ./04-iq-install.sh -f custom-iq-values.db-external.yaml   (apéndice: sesiones en PostgreSQL)
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm
require_vars DX_NS IQ_RELEASE IQ_CHART_TGZ DX_RELEASE DX_HOST
cd "$(dirname "$0")"

[[ -f "$IQ_CHART_TGZ" ]] || die "No está $IQ_CHART_TGZ: ejecuta common/02-pull-hcl-charts.sh"
kubectl -n "$DX_NS" get secret iq-litellm-api-secret >/dev/null 2>&1 || die "Falta iq-litellm-api-secret: ./01-secrets.sh"
helm -n "$DX_NS" status "$DX_RELEASE" >/dev/null 2>&1 || die "DX ($DX_RELEASE) no está instalado en $DX_NS"

helm upgrade --install "$IQ_RELEASE" "$IQ_CHART_TGZ" -n "$DX_NS" -f custom-iq-values.yaml "$@" \
  --set-string configuration.dx.releaseName="$DX_RELEASE" \
  --set-string configuration.dx.externalHost="$DX_HOST"

# Lab 3B: el chart regenera la lista de MCP Servers con solo el de HCL. Si existe el MCP propio
# en dx-shared, se vuelve a añadir (ver mcp-propio/03-iq-register.sh).
if kubectl -n "$SHARED_NS" get svc europesip-mcp >/dev/null 2>&1; then
  LIST="http://${IQ_RELEASE}-mcp-server:3000,http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"
  kubectl -n "$DX_NS" patch configmap "${IQ_RELEASE}-integrator" --type merge \
    -p "{\"data\":{\"dx.config.integrator.mcp_server_list\":\"$LIST\"}}"
  info "MCP Servers: $LIST"
fi

# Helm no reinicia los pods si solo cambian secrets: reiniciamos los dos.
# Primero el MCP Server (el Integrator lee su lista de herramientas al arrancar).
kubectl -n "$DX_NS" rollout restart deployment/"$IQ_RELEASE"-mcp-server
kubectl -n "$DX_NS" rollout status  deployment/"$IQ_RELEASE"-mcp-server --timeout=300s
kubectl -n "$DX_NS" rollout restart deployment/"$IQ_RELEASE"-integrator
kubectl -n "$DX_NS" rollout status  deployment/"$IQ_RELEASE"-integrator --timeout=300s
kubectl -n "$DX_NS" get pods | grep -E "^${IQ_RELEASE}-"
echo "Siguiente: ./05-dx-enable-iq.sh (habilita IQ en DX)"
