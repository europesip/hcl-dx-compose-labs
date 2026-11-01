#!/usr/bin/env bash
# Lab 2 · Enterprise branch · Step ORA-3 · helm upgrade: the Web Engine transfers Derby -> Oracle.
# Same procedure as the PostgreSQL branch (b-postgres/05-dx-transfer.sh).
#   kubectl -n dx-demo logs -f dx-deployment-web-engine-0 -c system-out-log
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"

kubectl -n "$DX_NS" get secret custom-credentials-webengine-dbdomain-secret >/dev/null 2>&1 \
  || die "The properties secrets are missing: run ./01-secrets-oracle.sh"
kubectl -n "$SHARED_NS" get clusters.postgresql.cnpg.io "$PG_CLUSTER" >/dev/null 2>&1 \
  && warn "The demo-branch PostgreSQL ($PG_CLUSTER) also exists: DX will use Oracle (whatever the secrets say)"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Check in Oracle (as DBA) that the 6 schemas have tables:"
echo "  SELECT owner, COUNT(*) FROM dba_tables WHERE owner IN"
echo "    ('RELEASE','COMMUNITY','CUSTOMIZATION','JCR','FEEDBACK','LIKEMINDS') GROUP BY owner;"
