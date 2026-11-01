#!/usr/bin/env bash
# Lab 2 · Rama empresarial · Paso ORA-2 · Secrets del Web Engine para Oracle, en dx-demo.
#   custom-credentials-webengine-dbtype-secret     dx_dbtype.properties  (driver ojdbc11, viene en la imagen)
#   custom-credentials-webengine-dbdomain-secret   dx_dbdomain.properties (6 dominios -> Oracle)
#   dx-oracle-ca                                   CA del listener TCPS (solo si ORACLE_CA_FILE)
# Son los MISMOS nombres de secret que la rama PostgreSQL: no se usan las dos a la vez.
#
# Variables (en env.sh, sección "Rama empresarial"):
#   ORACLE_JDBC_URL     jdbc:oracle:thin:@tcps://oracle.empresa.local:2484/WPSDB   (TCPS)
#                       jdbc:oracle:thin:@//oracle.empresa.local:1521/WPSDB        (sin TLS)
#   ORACLE_DX_USER      usuario de conexión creado por setup-oracle-dx.sql (wpsuser)
#   ORACLE_DX_PASSWORD
#   ORACLE_CA_FILE      (TCPS) CA que firmó el certificado del listener, en PEM
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"
require_cmd envsubst
require_vars DX_NS ORACLE_JDBC_URL ORACLE_DX_USER ORACLE_DX_PASSWORD
cd "$(dirname "$0")"

if [[ "$ORACLE_JDBC_URL" == *tcps://* ]]; then
  require_vars ORACLE_CA_FILE
  info "Secret dx-oracle-ca (truststore del Web Engine para TCPS)"
  apply_secret "$DX_NS" generic dx-oracle-ca --from-file=oracle-ca.crt="$ORACLE_CA_FILE"
fi

umask 077
render dx_dbdomain.properties.template '$ORACLE_JDBC_URL $ORACLE_DX_USER $ORACLE_DX_PASSWORD' > dx_dbdomain.properties
trap 'rm -f dx_dbdomain.properties' EXIT

apply_secret "$DX_NS" generic custom-credentials-webengine-dbtype-secret   --from-file=dx_dbtype.properties
apply_secret "$DX_NS" generic custom-credentials-webengine-dbdomain-secret --from-file=dx_dbdomain.properties
kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbtype-secret custom-credentials-webengine-dbdomain-secret
echo "Siguiente: ./02-dx-transfer.sh"
