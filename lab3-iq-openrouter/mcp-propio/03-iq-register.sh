#!/usr/bin/env bash
# Lab 3B · Paso 3 · Registra el MCP Server propio en IQ.
#
# El Integrator lee la lista de MCP Servers (separados por comas) de la clave
# dx.config.integrator.mcp_server_list del ConfigMap <IQ_RELEASE>-integrator. El chart 1.0.2 la
# genera con un único servidor (el de HCL) y no ofrece ningún valor para ampliarla; la variable de
# entorno MCP_SERVER_LIST tampoco tiene efecto (el ConfigMap la sobrescribe). Por eso:
#   1. se parchea el ConfigMap con los dos servidores, y
#   2. se reinicia el Integrator, que lista las herramientas de todos al arrancar.
# Como "helm upgrade" de IQ regenera el ConfigMap, 04-iq-install.sh repite este paso
# automáticamente si existe el servicio europesip-mcp en dx-shared.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars DX_NS SHARED_NS IQ_RELEASE

kubectl -n "$SHARED_NS" get svc europesip-mcp >/dev/null 2>&1 || die "No existe europesip-mcp en $SHARED_NS: ./01-mcp-deploy.sh"
LIST="http://${IQ_RELEASE}-mcp-server:3000,http://europesip-mcp.${SHARED_NS}.svc.cluster.local:3000"

info "ConfigMap ${IQ_RELEASE}-integrator: mcp_server_list = $LIST"
kubectl -n "$DX_NS" patch configmap "${IQ_RELEASE}-integrator" --type merge \
  -p "{\"data\":{\"dx.config.integrator.mcp_server_list\":\"$LIST\"}}"
kubectl -n "$DX_NS" rollout restart deployment/"${IQ_RELEASE}"-integrator
kubectl -n "$DX_NS" rollout status  deployment/"${IQ_RELEASE}"-integrator --timeout=300s

info "Herramientas que ha cargado el Integrator (pod nuevo)"
sleep 15
P=$(kubectl -n "$DX_NS" get pods -l app="${IQ_RELEASE}-integrator" --field-selector=status.phase=Running \
     --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl -n "$DX_NS" logs "$P" \
  | grep -oE "Fetched [0-9]+ tools from [^ ]+|Total tools: [0-9]+" | sort -u | sed 's/^/  /'
echo "Siguiente: ../06-iq-chat-test.sh \"¿Cuál es el horario de soporte de EUROPESIP?\""
