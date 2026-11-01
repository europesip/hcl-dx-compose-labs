#!/usr/bin/env bash
# Lab 2B · Paso 1 · Instala el operador CloudNativePG (CNPG) en dx-shared.
# CNPG es un proyecto CNCF: imágenes oficiales de PostgreSQL con versiones fijadas, y bases de
# datos, roles y tablespaces declarativos. El operador vigila todo el clúster (clusterWide) y
# sus CRD (Cluster, Backup...) son globales.
#
# OpenShift: en lugar de este chart, instala "CloudNativePG" desde OperatorHub (operador
# certificado), en el namespace openshift-operators o en dx-shared.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_cmd helm kubectl
require_vars SHARED_NS CNPG_CHART_VERSION

helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
helm repo update cnpg >/dev/null
helm upgrade --install cnpg cnpg/cloudnative-pg --version "$CNPG_CHART_VERSION" \
  -n "$SHARED_NS" "$HELM_WAIT" --timeout 10m

kubectl -n "$SHARED_NS" get pods -l app.kubernetes.io/name=cloudnative-pg
kubectl get crd clusters.postgresql.cnpg.io
