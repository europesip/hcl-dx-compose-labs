#!/usr/bin/env bash
# Lab 2B · Step 4 · Create in the DX namespace the two secrets with the Web Engine database
# properties. The keys MUST be named dx_dbtype.properties and dx_dbdomain.properties.
# With secrets, the chart ignores dbDomainProperties/dbTypeProperties of the values: every
# property has to be in the secret (key=value format, no quotes).
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_cmd envsubst
require_vars DX_NS PG_HOST DXUSER_PASSWORD
cd "$(dirname "$0")"

umask 077
render dx_dbdomain.properties.template '$PG_HOST $DXUSER_PASSWORD' > dx_dbdomain.properties
trap 'rm -f dx_dbdomain.properties' EXIT    # do not leave the plain-text password on disk

apply_secret "$DX_NS" generic custom-credentials-webengine-dbtype-secret   --from-file=dx_dbtype.properties
apply_secret "$DX_NS" generic custom-credentials-webengine-dbdomain-secret --from-file=dx_dbdomain.properties

kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbtype-secret custom-credentials-webengine-dbdomain-secret
echo "Configured domains: $(grep -c '\.DbType=' dx_dbdomain.properties) (feedback, likeminds, release, community, customization, jcr)"
