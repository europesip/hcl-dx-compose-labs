#!/usr/bin/env bash
# Lab 1 · Paso 3 · Crea en dx-demo los tres secrets que referencia custom-values.yaml:
#   regcred            docker-registry de hclcr.io (pull de las imágenes de HCL)
#   dx-tls-cert        certificado TLS de HAProxy (autofirmado, salvo que aportes el tuyo)
#   web-engine-secret  usuario y contraseña de wpsadmin
#
# Certificado corporativo: exporta TLS_CERT (cadena completa: servidor -> intermedia -> raíz)
# y TLS_KEY (clave privada sin contraseña) antes de ejecutar el script.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd kubectl openssl
require_vars DX_NS DX_HOST HCL_REGISTRY HCL_HARBOR_USER HCL_HARBOR_TOKEN WPSADMIN_PASSWORD
cd "$(dirname "$0")"

info "regcred (imagePullSecret de $HCL_REGISTRY)"
apply_secret "$DX_NS" docker-registry regcred \
  --docker-server="$HCL_REGISTRY" \
  --docker-username="$HCL_HARBOR_USER" \
  --docker-password="$HCL_HARBOR_TOKEN" \
  --docker-email="$HCL_HARBOR_USER"

info "dx-tls-cert"
if [[ -n "${TLS_CERT:-}" && -n "${TLS_KEY:-}" ]]; then
  echo "  usando el certificado aportado: $TLS_CERT"
  CERT="$TLS_CERT"; KEY="$TLS_KEY"
else
  CERT=dx-tls.crt; KEY=dx-tls.key
  if [[ ! -f "$CERT" ]]; then
    echo "  generando certificado autofirmado para $DX_HOST (válido 365 días)"
    # Con subjectAltName: los navegadores actuales ignoran el CN
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
