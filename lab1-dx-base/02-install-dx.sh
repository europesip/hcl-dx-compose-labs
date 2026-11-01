#!/usr/bin/env bash
# Lab 1 · Paso 4 · Instala DX Compose en dx-demo (equivale al "helm install" de la documentación
# de HCL, con --wait para esperar a que todo esté Ready; la primera vez tarda 15-25 minutos).
#
# Comando equivalente, a mano:
#   helm install dx-deployment charts/hcl-dx-deployment-2.49.0.tgz -n dx-demo \
#     -f lab1-dx-base/custom-values.yaml --set-string networking.webEngine.host=$DX_HOST \
#     --timeout 30m --wait          (con Helm 4: --wait=legacy, ver common/lib.sh)
#
# Mientras espera, en otra terminal:
#   kubectl -n dx-demo get pods -w
#   kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"

for s in regcred dx-tls-cert web-engine-secret; do
  kubectl -n "$DX_NS" get secret "$s" >/dev/null 2>&1 || die "Falta el secret $s: ejecuta lab1-dx-base/01-secrets.sh"
done

exec "$REPO_ROOT/common/dx-helm.sh" "$@"
