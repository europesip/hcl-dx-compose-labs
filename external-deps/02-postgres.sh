#!/usr/bin/env bash
# External dependencies · PostgreSQL 18 (CloudNativePG) in the shared namespace.
# The same installation as Lab 2B steps 1-3. Without setup-postgres-dx.sql (not published with the
# labs) the database dx_core is created empty: the Web Engine keeps Derby, and PostgreSQL serves
# the IQ sessions (Lab 3 appendix) or any other use of yours.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
L2B="$REPO_ROOT/lab2-ldap-postgres/b-postgres"
"$L2B/01-cnpg-operator.sh"
"$L2B/02-secrets-postgres.sh"
"$L2B/03-postgres-cluster.sh"
echo "PostgreSQL ready: ${PG_HOST}:5432 (users dxuser and dx_iq_db_user)."
