#!/usr/bin/env bash
# Lab 4 · Paso 2 · Instala hcl-dx-search (OpenSearch + Search Middleware) en dx-demo.
# Comando equivalente:
#   helm upgrade --install dx-search charts/hcl-dx-search-2.36.0.tgz -n dx-demo \
#     -f lab4-opensearch/custom-search-values.yaml -f lab4-opensearch/admin-dn.rendered.yaml --wait
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm
require_vars DX_NS SEARCH_RELEASE SEARCH_CHART_TGZ
cd "$(dirname "$0")"

[[ -f "$SEARCH_CHART_TGZ" ]] || die "No está $SEARCH_CHART_TGZ: ejecuta common/02-pull-hcl-charts.sh"
[[ -f admin-dn.rendered.yaml ]] || die "Falta admin-dn.rendered.yaml: ejecuta ./01-certs.sh"
for s in search-admin-cert search-node-cert search-client-cert; do
  kubectl -n "$DX_NS" get secret "$s" >/dev/null 2>&1 || die "Falta el secret $s: ./01-certs.sh"
done

POC=(); [[ "${DX_POC:-}" == 1 ]] && POC=(-f ../lab0-poc-wsl/custom-search-values.poc.yaml)   # Lab 0: un nodo
helm upgrade --install "$SEARCH_RELEASE" "$SEARCH_CHART_TGZ" -n "$DX_NS" \
  -f custom-search-values.yaml -f admin-dn.rendered.yaml "${POC[@]}" --timeout 20m "$HELM_WAIT" "$@"

kubectl -n "$DX_NS" get pods,pvc | grep -E "NAME|${SEARCH_RELEASE}"
echo "Siguiente: ./03-dx-enable-search.sh"
