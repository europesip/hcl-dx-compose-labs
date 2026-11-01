#!/usr/bin/env bash
# Lab 2 · Enterprise branch · Step ORA-2 · Web Engine secrets for Oracle, in the DX namespace.
#   custom-credentials-webengine-dbtype-secret     dx_dbtype.properties  (ojdbc11 driver, shipped in the image)
#   custom-credentials-webengine-dbdomain-secret   dx_dbdomain.properties (6 domains -> Oracle)
#   dx-oracle-ca                                   CA of the TCPS listener (only if ORACLE_CA_FILE)
# They are the SAME secret names as the PostgreSQL branch: the two are never used together.
#
# Variables (in env.sh, "Enterprise branch" section):
#   ORACLE_JDBC_URL     jdbc:oracle:thin:@tcps://oracle.company.local:2484/WPSDB   (TCPS)
#                       jdbc:oracle:thin:@//oracle.company.local:1521/WPSDB        (no TLS)
#   ORACLE_DX_USER      connection user created by setup-oracle-dx.sql (wpsuser)
#   ORACLE_DX_PASSWORD
#   ORACLE_CA_FILE      (TCPS) CA that signed the listener certificate, in PEM
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"
require_cmd envsubst
require_vars DX_NS ORACLE_JDBC_URL ORACLE_DX_USER ORACLE_DX_PASSWORD
cd "$(dirname "$0")"

if [[ "$ORACLE_JDBC_URL" == *tcps://* ]]; then
  require_vars ORACLE_CA_FILE
  info "Secret dx-oracle-ca (Web Engine truststore for TCPS)"
  apply_secret "$DX_NS" generic dx-oracle-ca --from-file=oracle-ca.crt="$ORACLE_CA_FILE"
fi

umask 077
render dx_dbdomain.properties.template '$ORACLE_JDBC_URL $ORACLE_DX_USER $ORACLE_DX_PASSWORD' > dx_dbdomain.properties
trap 'rm -f dx_dbdomain.properties' EXIT

apply_secret "$DX_NS" generic custom-credentials-webengine-dbtype-secret   --from-file=dx_dbtype.properties
apply_secret "$DX_NS" generic custom-credentials-webengine-dbdomain-secret --from-file=dx_dbdomain.properties
kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbtype-secret custom-credentials-webengine-dbdomain-secret
echo "Next: ./02-dx-transfer.sh"
