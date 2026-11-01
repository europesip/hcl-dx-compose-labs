#!/usr/bin/env bash
# Lab 3 · Paso 2 · Instala o actualiza LiteLLM en dx-shared (chart OCI público, sin login).
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm
require_vars SHARED_NS LITELLM_RELEASE LITELLM_CHART LITELLM_CHART_VERSION
cd "$(dirname "$0")"

kubectl -n "$SHARED_NS" get secret litellm-env >/dev/null 2>&1 || die "Falta el secret litellm-env: ejecuta ./01-secrets.sh"

existed=0; helm -n "$SHARED_NS" status "$LITELLM_RELEASE" >/dev/null 2>&1 && existed=1
helm upgrade --install "$LITELLM_RELEASE" "$LITELLM_CHART" --version "$LITELLM_CHART_VERSION" \
  -n "$SHARED_NS" -f litellm-values.yaml "$@"
# En un upgrade, Helm no reinicia el pod si solo cambió el secret: forzamos que lo relea
((existed)) && kubectl -n "$SHARED_NS" rollout restart deployment/"$LITELLM_RELEASE"
kubectl -n "$SHARED_NS" rollout status  deployment/"$LITELLM_RELEASE" --timeout=300s
kubectl -n "$SHARED_NS" get pods,svc -l app.kubernetes.io/instance="$LITELLM_RELEASE"
echo "URL interna para IQ: $LITELLM_URL_INTERNAL"
