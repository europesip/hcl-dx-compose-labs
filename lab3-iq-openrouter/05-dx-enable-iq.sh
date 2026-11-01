#!/usr/bin/env bash
# Lab 3 · Step 5 · helm upgrade of DX with the custom-values.iq.yaml layer (networking.dxIqService,
# set by common/dx-helm.sh to "<IQ_RELEASE>-integrator").
# Only HAProxy restarts (and the Web Engine if its configuration changes); content is untouched.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"

want="${IQ_RELEASE}-integrator"
kubectl -n "$DX_NS" get svc "$want" >/dev/null 2>&1 || die "Service $want does not exist: run ./04-iq-install.sh"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Test: https://${DX_HOST}/wps/myportal -> IQ ✨ button in the DX toolbar"
echo "      Example: \"Which content libraries exist in WCM?\""
