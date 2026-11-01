#!/usr/bin/env bash
# Lab 4 · Step 2 · Install hcl-dx-search (OpenSearch + Search Middleware) in the DX namespace.
# Equivalent command (the wizard RUNBOOK.md shows it with your values):
#   helm upgrade --install dx-search charts/hcl-dx-search-2.36.0.tgz -n dx-demo \
#     -f lab4-opensearch/custom-search-values.yaml -f lab4-opensearch/admin-dn.rendered.yaml --wait
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm
require_vars DX_NS DX_RELEASE SEARCH_RELEASE SEARCH_CHART_TGZ SC_RWO
cd "$(dirname "$0")"

[[ -f "$SEARCH_CHART_TGZ" ]] || die "$SEARCH_CHART_TGZ not found: run common/02-pull-hcl-charts.sh"
[[ -f admin-dn.rendered.yaml ]] || die "admin-dn.rendered.yaml is missing: run ./01-certs.sh"
for s in search-admin-cert search-node-cert search-client-cert; do
  kubectl -n "$DX_NS" get secret "$s" >/dev/null 2>&1 || die "Secret $s is missing: ./01-certs.sh"
done

POC=(); [[ "${DX_POC:-}" == 1 ]] && POC=(-f ../lab0-poc-wsl/custom-search-values.poc.yaml)   # Lab 0: single node
helm upgrade --install "$SEARCH_RELEASE" "$SEARCH_CHART_TGZ" -n "$DX_NS" \
  -f custom-search-values.yaml -f admin-dn.rendered.yaml "${POC[@]}" \
  --set-string volumes.openSearchManager.data.storageClassName="$SC_RWO" \
  --set-string security.pushAdministration.deploymentReleaseName="$DX_RELEASE" \
  --set-string configuration.automatedSetup.dxDeploymentName="$DX_RELEASE" \
  --timeout 20m "$HELM_WAIT" "$@"

kubectl -n "$DX_NS" get pods,pvc | grep -E "NAME|${SEARCH_RELEASE}"
echo "Next: ./03-dx-enable-search.sh"
