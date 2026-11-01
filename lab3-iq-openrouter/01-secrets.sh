#!/usr/bin/env bash
# Lab 3 · Step 1 · Secrets of the IQ -> LiteLLM -> OpenRouter chain
#   <SHARED_NS>/litellm-env          (read by LiteLLM)  OPENROUTER_API_KEY + PROXY_MASTER_KEY
#   <DX_NS>/iq-litellm-api-secret    (read by IQ)       virtualKey = key IQ uses to call LiteLLM
# LiteLLM runs without a database (HCL "quick start"): there are no virtual keys, so IQ uses the
# master key. Each secret lives in the namespace of whoever uses it.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd openssl
require_vars DX_NS SHARED_NS OPENROUTER_API_KEY

# Master key: the one in env.sh, the one already in the cluster or a new one. It must start with "sk-".
if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  LITELLM_MASTER_KEY=$(kubectl -n "$SHARED_NS" get secret litellm-env -o jsonpath='{.data.PROXY_MASTER_KEY}' 2>/dev/null | base64 -d || true)
  [[ -n "$LITELLM_MASTER_KEY" ]] || LITELLM_MASTER_KEY="sk-$(openssl rand -hex 24)"
fi
[[ "$LITELLM_MASTER_KEY" == sk-* ]] || die "LITELLM_MASTER_KEY must start with sk-"

apply_secret "$SHARED_NS" generic litellm-env \
  --from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  --from-literal=PROXY_MASTER_KEY="$LITELLM_MASTER_KEY"

apply_secret "$DX_NS" generic iq-litellm-api-secret \
  --from-literal=virtualKey="$LITELLM_MASTER_KEY"

kubectl -n "$SHARED_NS" get secret litellm-env
kubectl -n "$DX_NS" get secret iq-litellm-api-secret
