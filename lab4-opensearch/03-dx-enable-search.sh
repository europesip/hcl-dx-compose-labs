#!/usr/bin/env bash
# Lab 4 · Paso 3 · helm upgrade de DX con la capa custom-values.search.yaml (Search V2).
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
kubectl -n "$DX_NS" get svc "${SEARCH_RELEASE}-search-middleware-query" >/dev/null 2>&1 \
  || die "No existe ${SEARCH_RELEASE}-search-middleware-query: ejecuta ./02-search-install.sh"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Search Center:  https://${DX_HOST}/wps/myportal/Practitioner/SearchCenter"
echo "API (explorer): https://${DX_HOST}/dx/api/search/v2/explorer"
echo "Los rastreadores de WCM, JCR y portal se ejecutan cada 15 minutos: ./99-verify.sh"
