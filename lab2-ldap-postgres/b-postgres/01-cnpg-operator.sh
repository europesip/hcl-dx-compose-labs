#!/usr/bin/env bash
# Lab 2B · Step 1 · Install the CloudNativePG (CNPG) operator in the shared namespace.
# CNPG is a CNCF project: official PostgreSQL images with pinned versions, and declarative
# databases, roles and tablespaces. The operator watches the whole cluster (clusterWide) and its
# CRDs (Cluster, Backup...) are global.
#
# OpenShift: instead of this chart, install "CloudNativePG" from OperatorHub (certified operator),
# in the openshift-operators namespace or in dx-shared.
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
