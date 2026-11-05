#!/usr/bin/env bash
# External dependencies · OpenLDAP with the demo users, in the shared namespace.
# The same installation as Lab 2A steps 1-2, done before Lab 1: Lab 2A then only connects DX to it.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
L2A="$REPO_ROOT/lab2-ldap-postgres/a-ldap"
"$L2A/01-ldap-install.sh"
"$L2A/02-ldap-test.sh"
echo "Ready for Lab 2A step 3 (connect DX to the LDAP)."
