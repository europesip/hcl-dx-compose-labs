#!/usr/bin/env bash
# Paso 2 · Login en el Harbor oficial de HCL (hclcr.io) y descarga de los charts de CF238 a ./charts
#   hcl-dx-deployment 2.49.0  (oci://hclcr.io/dx-compose/hcl-dx-deployment)  -> Labs 1 y 2
#   hcl-dx-iq         1.0.2   (oci://hclcr.io/dx/hcl-dx-iq)                   -> Lab 3
#   hcl-dx-search     2.36.0  (oci://hclcr.io/dx-compose/hcl-dx-search)       -> Lab 4
# Las imágenes NO se descargan: el clúster las baja directamente de hclcr.io con el secret regcred.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd helm
require_vars HCL_HARBOR_USER HCL_HARBOR_TOKEN

mkdir -p "$CHARTS_DIR"

info "Login en $HCL_REGISTRY como $HCL_HARBOR_USER"
# --password-stdin: el token no queda en el historial ni en la lista de procesos
printf '%s' "$HCL_HARBOR_TOKEN" | helm registry login "$HCL_REGISTRY" -u "$HCL_HARBOR_USER" --password-stdin

pull() {  # pull <oci> <versión> <tgz esperado>
  if [[ -f "$3" ]]; then ok "ya descargado: $(basename "$3")"; return; fi
  helm pull "$1" --version "$2" -d "$CHARTS_DIR"
  ok "descargado: $(basename "$3")"
}
info "Descarga de charts en $CHARTS_DIR"
pull "$DX_CHART" "$DX_CHART_VERSION" "$DX_CHART_TGZ"
pull "$IQ_CHART" "$IQ_CHART_VERSION" "$IQ_CHART_TGZ"
pull "$SEARCH_CHART" "$SEARCH_CHART_VERSION" "$SEARCH_CHART_TGZ"

info "Versiones"
for t in "$DX_CHART_TGZ" "$IQ_CHART_TGZ" "$SEARCH_CHART_TGZ"; do
  helm show chart "$t" | grep -E '^(name|version|appVersion):' | paste -sd' ' | sed 's/^/  /'
done

# Values por defecto, para consultarlos durante el webinar (no se usan para instalar)
helm show values "$DX_CHART_TGZ" > "$CHARTS_DIR/values-dx-default-${DX_CHART_VERSION}.yaml"
helm show values "$IQ_CHART_TGZ" > "$CHARTS_DIR/values-iq-default-${IQ_CHART_VERSION}.yaml"
helm show values "$SEARCH_CHART_TGZ" > "$CHARTS_DIR/values-search-default-${SEARCH_CHART_VERSION}.yaml"
ls -lh "$CHARTS_DIR"
