#!/usr/bin/env bash
# Lab 1 · Step 4 · Install DX Compose in the DX namespace (the "helm install" of the HCL
# documentation, with --wait to wait until everything is Ready; the first time takes 15-25 minutes).
#
# Equivalent command, by hand (the wizard RUNBOOK.md shows it with your values):
#   helm install dx-deployment charts/hcl-dx-deployment-2.50.0.tgz -n dx-demo \
#     -f lab1-dx-base/custom-values.yaml --set-string networking.webEngine.host=$DX_HOST \
#     --timeout 30m --wait          (with Helm 4: --wait=legacy, see common/lib.sh)
#
# While it waits, in another terminal:
#   kubectl -n dx-demo get pods -w
#   kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"

for s in regcred dx-tls-cert web-engine-secret; do
  kubectl -n "$DX_NS" get secret "$s" >/dev/null 2>&1 || die "Secret $s is missing: run lab1-dx-base/01-secrets.sh"
done

exec "$REPO_ROOT/common/dx-helm.sh" "$@"
