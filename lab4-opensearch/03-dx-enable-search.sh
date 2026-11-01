#!/usr/bin/env bash
# Lab 4 · Step 3 · helm upgrade of DX with the custom-values.search.yaml layer (Search V2).
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
kubectl -n "$DX_NS" get svc "${SEARCH_RELEASE}-search-middleware-query" >/dev/null 2>&1 \
  || die "${SEARCH_RELEASE}-search-middleware-query does not exist: run ./02-search-install.sh"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Search Center:  https://${DX_HOST}/wps/myportal/Practitioner/SearchCenter"
echo "API (explorer): https://${DX_HOST}/dx/api/search/v2/explorer"
echo "The WCM, JCR and portal crawlers run every 15 minutes: ./99-verify.sh"
