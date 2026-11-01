#!/usr/bin/env bash
# Lab 2A · Paso 3 · Conecta DX al LDAP: crea el secret de bind y hace helm upgrade con la capa
# custom-values.ldap.yaml (common/dx-helm.sh la añade al detectar el secret dx-ldap-bind).
#
# Bind con cn=admin para simplificar el laboratorio. En producción: un usuario de solo lectura.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars DX_NS LDAP_ADMIN_PASSWORD

info "Secret dx-ldap-bind en $DX_NS (claves bindUser / bindPassword, las que pide el chart)"
apply_secret "$DX_NS" generic dx-ldap-bind \
  --from-literal=bindUser="cn=admin,dc=dxdemo,dc=com" \
  --from-literal=bindPassword="$LDAP_ADMIN_PASSWORD"

"$REPO_ROOT/common/dx-helm.sh" "$@"

# Open Liberty aplica los cambios de configuración en caliente; si el secret ya existía y solo
# cambió su contenido, reinicia el Web Engine:  kubectl -n $DX_NS rollout restart sts/${DX_RELEASE}-web-engine
echo
echo "Prueba: https://${DX_HOST}/wps/myportal  con  macarena / <LDAP_USERS_PASSWORD>"
echo "        y comprueba que wpsadmin sigue entrando."
echo "Siguiente: da permisos de administrador al grupo dxadmins desde el portal (GUIA.md, paso 4)"
