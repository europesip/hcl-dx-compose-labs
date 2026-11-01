#!/usr/bin/env bash
# Lab 2A · Step 3 · Connect DX to the LDAP: create the bind secret and run helm upgrade with the
# custom-values.ldap.yaml layer (common/dx-helm.sh adds it when it finds the dx-ldap-bind secret).
#
# Bind with cn=admin to keep the lab simple. In production: a read-only user.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_vars DX_NS LDAP_ADMIN_PASSWORD

info "Secret dx-ldap-bind in $DX_NS (keys bindUser / bindPassword, the ones the chart expects)"
apply_secret "$DX_NS" generic dx-ldap-bind \
  --from-literal=bindUser="cn=admin,dc=dxdemo,dc=com" \
  --from-literal=bindPassword="$LDAP_ADMIN_PASSWORD"

"$REPO_ROOT/common/dx-helm.sh" "$@"

# Open Liberty applies configuration changes on the fly; if the secret already existed and only
# its content changed, restart the Web Engine:  kubectl -n $DX_NS rollout restart sts/${DX_RELEASE}-web-engine
echo
echo "Test: https://${DX_HOST}/wps/myportal  with  macarena / <LDAP_USERS_PASSWORD>"
echo "      and check that wpsadmin can still log in."
echo "Next: give administrator rights to the dxadmins group from the portal (GUIDE.md, step 4)"
