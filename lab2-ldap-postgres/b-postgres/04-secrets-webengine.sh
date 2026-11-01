#!/usr/bin/env bash
# Lab 2B · Paso 4 · Crea en dx-demo los dos secrets con las propiedades de base de datos del
# Web Engine. Las claves DEBEN llamarse dx_dbtype.properties y dx_dbdomain.properties.
# Con secrets, el chart ignora dbDomainProperties/dbTypeProperties del values: todas las
# propiedades tienen que estar en el secret (formato clave=valor, sin comillas).
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_cmd envsubst
require_vars DX_NS PG_HOST DXUSER_PASSWORD
cd "$(dirname "$0")"

umask 077
render dx_dbdomain.properties.template '$PG_HOST $DXUSER_PASSWORD' > dx_dbdomain.properties
trap 'rm -f dx_dbdomain.properties' EXIT    # no dejamos la contraseña en claro en disco

apply_secret "$DX_NS" generic custom-credentials-webengine-dbtype-secret   --from-file=dx_dbtype.properties
apply_secret "$DX_NS" generic custom-credentials-webengine-dbdomain-secret --from-file=dx_dbdomain.properties

kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbtype-secret custom-credentials-webengine-dbdomain-secret
echo "Dominios configurados: $(grep -c '\.DbType=' dx_dbdomain.properties) (feedback, likeminds, release, community, customization, jcr)"
