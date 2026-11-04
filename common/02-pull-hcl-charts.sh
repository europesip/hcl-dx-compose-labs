#!/usr/bin/env bash
# Step 2 · Log in to the official HCL Harbor (hclcr.io) and download the CF239 charts to ./charts
#   hcl-dx-deployment 2.50.0  (oci://hclcr.io/dx-compose/hcl-dx-deployment)  -> Labs 1 and 2
#   hcl-dx-iq         1.0.3   (oci://hclcr.io/dx/hcl-dx-iq)                   -> Lab 3
#   hcl-dx-search     2.37.0  (oci://hclcr.io/dx-compose/hcl-dx-search)       -> Lab 4
# Images are NOT downloaded here: the cluster pulls them from hclcr.io with the regcred secret.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd helm
require_vars HCL_HARBOR_USER HCL_HARBOR_TOKEN

mkdir -p "$CHARTS_DIR"

info "Logging in to $HCL_REGISTRY as $HCL_HARBOR_USER"
# --password-stdin: the token stays out of the shell history and the process list
printf '%s' "$HCL_HARBOR_TOKEN" | helm registry login "$HCL_REGISTRY" -u "$HCL_HARBOR_USER" --password-stdin

pull() {  # pull <oci> <version> <expected tgz>
  if [[ -f "$3" ]]; then ok "already downloaded: $(basename "$3")"; return; fi
  helm pull "$1" --version "$2" -d "$CHARTS_DIR"
  ok "downloaded: $(basename "$3")"
}
info "Downloading charts to $CHARTS_DIR"
pull "$DX_CHART" "$DX_CHART_VERSION" "$DX_CHART_TGZ"
pull "$IQ_CHART" "$IQ_CHART_VERSION" "$IQ_CHART_TGZ"
pull "$SEARCH_CHART" "$SEARCH_CHART_VERSION" "$SEARCH_CHART_TGZ"

info "Versions"
for t in "$DX_CHART_TGZ" "$IQ_CHART_TGZ" "$SEARCH_CHART_TGZ"; do
  helm show chart "$t" | grep -E '^(name|version|appVersion):' | paste -sd' ' | sed 's/^/  /'
done

# Default values, for reference during the labs (they are not used to install)
helm show values "$DX_CHART_TGZ" > "$CHARTS_DIR/values-dx-default-${DX_CHART_VERSION}.yaml"
helm show values "$IQ_CHART_TGZ" > "$CHARTS_DIR/values-iq-default-${IQ_CHART_VERSION}.yaml"
helm show values "$SEARCH_CHART_TGZ" > "$CHARTS_DIR/values-search-default-${SEARCH_CHART_VERSION}.yaml"
ls -lh "$CHARTS_DIR"
