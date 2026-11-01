#!/usr/bin/env bash
# Lab 2A · Paso 2 · Comprueba el LDAP antes de conectar DX: estructura, usuarios, grupos y login.
# Las contraseñas no aparecen en la línea de comandos (se pasan por stdin al pod).
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS LDAP_RELEASE LDAP_USERS_PASSWORD
POD="${LDAP_RELEASE}-0"
BASE="dc=dxdemo,dc=com"
# Dentro del contenedor OpenLDAP escucha en 1389 (el servicio publica 389)
URL="ldap://localhost:1389"

info "Entradas bajo $BASE (bind como admin)"
kubectl -n "$SHARED_NS" exec "$POD" -c openldap-stack-ha -- sh -c \
  "ldapsearch -x -LLL -H $URL -D cn=admin,$BASE -w \"\$LDAP_ADMIN_PASSWORD\" -b $BASE dn" | grep '^dn:' \
  || die "No existe $BASE o está vacío: el LDIF no se cargó. Ver docs/problemas-frecuentes.md (Lab 2A)"

info "Grupos y miembros"
kubectl -n "$SHARED_NS" exec "$POD" -c openldap-stack-ha -- sh -c \
  "ldapsearch -x -LLL -H $URL -D cn=admin,$BASE -w \"\$LDAP_ADMIN_PASSWORD\" -b ou=groups,$BASE '(objectClass=groupOfUniqueNames)' cn uniqueMember"

info "Login de un usuario de demo (uid=andres)"
printf '%s' "$LDAP_USERS_PASSWORD" | kubectl -n "$SHARED_NS" exec -i "$POD" -c openldap-stack-ha -- sh -c \
  "umask 077; cat > /tmp/.pw; ldapwhoami -x -H $URL -D uid=andres,ou=users,$BASE -y /tmp/.pw; rc=\$?; rm -f /tmp/.pw; exit \$rc" \
  && ok "andres se autentica" || fail "andres no se autentica"

echo "Desde DX el LDAP se alcanza en: ${LDAP_HOST}:389"
