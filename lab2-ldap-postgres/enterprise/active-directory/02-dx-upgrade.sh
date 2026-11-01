#!/usr/bin/env bash
# Lab 2 · Enterprise branch · Step AD-2 · helm upgrade of DX with the custom-values.ad.yaml layer
# (common/dx-helm.sh adds it when it finds the dx-ad-bind secret).
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"
kubectl -n "$DX_NS" get secret dx-ad-bind >/dev/null 2>&1 || die "dx-ad-bind is missing: run ./01-secrets-ad.sh"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Check in the log that Liberty loaded the AD registry and there are no CWIML errors:"
echo "  kubectl -n $DX_NS logs ${DX_RELEASE}-web-engine-0 -c system-out-log | grep -E 'CWIML|CWWKG|ad-registry'"
echo "Test: https://${DX_HOST}/wps/myportal with an AD user (sAMAccountName) and with wpsadmin."
echo "Next: give the Administrator role to an AD group from the portal (GUIDE-enterprise.md, step AD-3)"
