#!/usr/bin/env bash
# Lab 3 · Step 2 · Install or upgrade LiteLLM in the shared namespace (public OCI chart, no login).
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm
require_vars SHARED_NS LITELLM_RELEASE LITELLM_CHART LITELLM_CHART_VERSION
cd "$(dirname "$0")"

kubectl -n "$SHARED_NS" get secret litellm-env >/dev/null 2>&1 || die "Secret litellm-env is missing: run ./01-secrets.sh"

# LLM behind IQ's two logical models: claude (default, recommended for production) or qwen
# (cheaper, for a PoC or a lab): litellm-values.qwen.yaml replaces the model list
case "${IQ_LLM:-claude}" in
  claude) VALUES=(-f litellm-values.yaml) ;;
  qwen)   VALUES=(-f litellm-values.yaml -f litellm-values.qwen.yaml) ;;
  *)      die "IQ_LLM=${IQ_LLM}: use claude or qwen (env.sh)" ;;
esac
info "LLM: ${IQ_LLM:-claude} (${VALUES[*]})"

existed=0; helm -n "$SHARED_NS" status "$LITELLM_RELEASE" >/dev/null 2>&1 && existed=1
helm upgrade --install "$LITELLM_RELEASE" "$LITELLM_CHART" --version "$LITELLM_CHART_VERSION" \
  -n "$SHARED_NS" "${VALUES[@]}" "$@"
# On an upgrade, Helm does not restart the pod if only the secret changed: force it to re-read it
((existed)) && kubectl -n "$SHARED_NS" rollout restart deployment/"$LITELLM_RELEASE"
kubectl -n "$SHARED_NS" rollout status  deployment/"$LITELLM_RELEASE" --timeout=300s
kubectl -n "$SHARED_NS" get pods,svc -l app.kubernetes.io/instance="$LITELLM_RELEASE"
echo "Internal URL for IQ: $LITELLM_URL_INTERNAL"
