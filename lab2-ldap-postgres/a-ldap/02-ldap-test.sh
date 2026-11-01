#!/usr/bin/env bash
# Lab 2A · Step 2 · Check the LDAP before connecting DX: structure, users, groups and login.
# Passwords never appear on the command line (they are passed to the pod through stdin).
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars SHARED_NS LDAP_RELEASE LDAP_USERS_PASSWORD
POD="${LDAP_RELEASE}-0"
BASE="dc=dxdemo,dc=com"
# Inside the container OpenLDAP listens on 1389 (the service publishes 389)
URL="ldap://localhost:1389"

info "Entries under $BASE (bind as admin)"
kubectl -n "$SHARED_NS" exec "$POD" -c openldap-stack-ha -- sh -c \
  "ldapsearch -x -LLL -H $URL -D cn=admin,$BASE -w \"\$LDAP_ADMIN_PASSWORD\" -b $BASE dn" | grep '^dn:' \
  || die "$BASE does not exist or is empty: the LDIF was not loaded. See docs/troubleshooting.md (Lab 2A)"

info "Groups and members"
kubectl -n "$SHARED_NS" exec "$POD" -c openldap-stack-ha -- sh -c \
  "ldapsearch -x -LLL -H $URL -D cn=admin,$BASE -w \"\$LDAP_ADMIN_PASSWORD\" -b ou=groups,$BASE '(objectClass=groupOfUniqueNames)' cn uniqueMember"

info "Login of a demo user (uid=andres)"
printf '%s' "$LDAP_USERS_PASSWORD" | kubectl -n "$SHARED_NS" exec -i "$POD" -c openldap-stack-ha -- sh -c \
  "umask 077; cat > /tmp/.pw; ldapwhoami -x -H $URL -D uid=andres,ou=users,$BASE -y /tmp/.pw; rc=\$?; rm -f /tmp/.pw; exit \$rc" \
  && ok "andres authenticates" || fail "andres does not authenticate"

echo "From DX the LDAP is reached at: ${LDAP_HOST}:389"
