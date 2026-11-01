#!/usr/bin/env bash
# Lab 3 · Paso 5 · helm upgrade de DX con la capa custom-values.iq.yaml (networking.dxIqService).
# Solo se reinicia HAProxy (y el Web Engine si cambia su configuración); el contenido no se toca.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"

want="${IQ_RELEASE}-integrator"
kubectl -n "$DX_NS" get svc "$want" >/dev/null 2>&1 || die "No existe el servicio $want: ejecuta ./04-iq-install.sh"
grep -q "\"$want\"" "$(dirname "$0")/custom-values.iq.yaml" \
  || die "custom-values.iq.yaml no apunta a $want: ajusta networking.dxIqService"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Prueba: https://${DX_HOST}/wps/myportal -> botón ✨ de IQ en la barra de DX"
echo "        Ejemplo: \"¿Qué bibliotecas de contenido hay en WCM?\""
