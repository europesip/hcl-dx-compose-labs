#!/usr/bin/env bash
# Lab 2 · Rama empresarial · Paso AD-1 · Datos de conexión al Active Directory, en dx-demo.
# Crea el secret dx-ad-bind, que el Web Engine recibe como variables de entorno (customSecrets)
# y que usa ad-registry.xml (custom-values.ad.yaml).
#
# Variables (en env.sh, sección "Rama empresarial"):
#   AD_HOST            p. ej. dc01.empresa.local
#   AD_PORT            389 (LDAP) o 636 (LDAPS)
#   AD_SSL             false | true (con 636 y la CA del AD en dx-ad-ca)
#   AD_BASE_DN         p. ej. DC=empresa,DC=local
#   AD_BIND_USER       cuenta de servicio de solo lectura, p. ej. svc-dx@empresa.local
#   AD_BIND_PASSWORD
#   AD_CA_FILE         (opcional, solo LDAPS) CA del AD en PEM -> secret dx-ad-ca
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"
require_vars DX_NS AD_HOST AD_PORT AD_SSL AD_BASE_DN AD_BIND_USER AD_BIND_PASSWORD

kubectl -n "$DX_NS" get secret dx-ldap-bind >/dev/null 2>&1 \
  && die "Existe dx-ldap-bind (rama OpenLDAP). Usa una sola rama: kubectl -n $DX_NS delete secret dx-ldap-bind"

info "Comprobando conectividad con ${AD_HOST}:${AD_PORT} desde el clúster"
kubectl -n "$DX_NS" run ad-check --rm -i --restart=Never --image=busybox:1.36 --quiet -- \
  nc -z -w 5 "$AD_HOST" "$AD_PORT" && ok "puerto accesible" || die "El clúster no llega a ${AD_HOST}:${AD_PORT}"

info "Secret dx-ad-bind"
apply_secret "$DX_NS" generic dx-ad-bind \
  --from-literal=AD_HOST="$AD_HOST" --from-literal=AD_PORT="$AD_PORT" --from-literal=AD_SSL="$AD_SSL" \
  --from-literal=AD_BASE_DN="$AD_BASE_DN" \
  --from-literal=AD_BIND_USER="$AD_BIND_USER" --from-literal=AD_BIND_PASSWORD="$AD_BIND_PASSWORD"

if [[ -n "${AD_CA_FILE:-}" ]]; then
  info "Secret dx-ad-ca (CA del AD para LDAPS); descomenta customTruststoreSecrets en custom-values.ad.yaml"
  apply_secret "$DX_NS" generic dx-ad-ca --from-file=ad-ca.crt="$AD_CA_FILE"
fi
echo "Siguiente: ./02-dx-upgrade.sh"
