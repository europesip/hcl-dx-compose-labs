#!/usr/bin/env bash
# Lab 1 · Step 3 · Create in the DX namespace the three secrets referenced by custom-values.yaml:
#   regcred            docker-registry for hclcr.io (pull of the HCL images)
#   dx-tls-cert        HAProxy TLS certificate (self-signed, unless you provide your own)
#   web-engine-secret  wpsadmin user and password
#
# Corporate certificate: export TLS_CERT (full chain: server -> intermediate -> root)
# and TLS_KEY (private key without passphrase) before running the script.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd kubectl openssl
require_vars DX_NS DX_HOST HCL_REGISTRY HCL_HARBOR_USER HCL_HARBOR_TOKEN WPSADMIN_PASSWORD
cd "$(dirname "$0")"

info "regcred (imagePullSecret for $HCL_REGISTRY)"
apply_secret "$DX_NS" docker-registry regcred \
  --docker-server="$HCL_REGISTRY" \
  --docker-username="$HCL_HARBOR_USER" \
  --docker-password="$HCL_HARBOR_TOKEN" \
  --docker-email="$HCL_HARBOR_USER"

info "dx-tls-cert"
if [[ -n "${TLS_CERT:-}" && -n "${TLS_KEY:-}" ]]; then
  echo "  using the provided certificate: $TLS_CERT"
  CERT="$TLS_CERT"; KEY="$TLS_KEY"
else
  CERT=dx-tls.crt; KEY=dx-tls.key
  if [[ ! -f "$CERT" ]]; then
    echo "  generating a self-signed certificate for $DX_HOST (valid for 365 days)"
    # With subjectAltName: current browsers ignore the CN
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 365 \
      -keyout "$KEY" -out "$CERT" \
      -subj "/CN=${DX_HOST}" -addext "subjectAltName=DNS:${DX_HOST}" 2>/dev/null
  fi
fi
apply_secret "$DX_NS" tls dx-tls-cert --cert="$CERT" --key="$KEY"
openssl x509 -in "$CERT" -noout -subject -enddate | sed 's/^/  /'

info "web-engine-secret (wpsadmin)"
apply_secret "$DX_NS" generic web-engine-secret \
  --from-literal=username=wpsadmin \
  --from-literal=password="$WPSADMIN_PASSWORD"

kubectl -n "$DX_NS" get secret regcred dx-tls-cert web-engine-secret
