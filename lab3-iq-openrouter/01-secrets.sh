#!/usr/bin/env bash
# Lab 3 · Paso 1 · Secrets de la cadena IQ -> LiteLLM -> OpenRouter
#   dx-shared/litellm-env            (lo lee LiteLLM)  OPENROUTER_API_KEY + PROXY_MASTER_KEY
#   dx-demo/iq-litellm-api-secret    (lo lee IQ)       virtualKey = clave con la que IQ llama a LiteLLM
# LiteLLM va sin base de datos ("quick start" de HCL): no hay virtual keys, así que IQ usa la
# master key. Cada secret vive en el namespace de quien lo usa.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd openssl
require_vars DX_NS SHARED_NS OPENROUTER_API_KEY

# Master key: la de env.sh, la que ya esté en el clúster o una nueva. Debe empezar por "sk-".
if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  LITELLM_MASTER_KEY=$(kubectl -n "$SHARED_NS" get secret litellm-env -o jsonpath='{.data.PROXY_MASTER_KEY}' 2>/dev/null | base64 -d || true)
  [[ -n "$LITELLM_MASTER_KEY" ]] || LITELLM_MASTER_KEY="sk-$(openssl rand -hex 24)"
fi
[[ "$LITELLM_MASTER_KEY" == sk-* ]] || die "LITELLM_MASTER_KEY debe empezar por sk-"

apply_secret "$SHARED_NS" generic litellm-env \
  --from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  --from-literal=PROXY_MASTER_KEY="$LITELLM_MASTER_KEY"

apply_secret "$DX_NS" generic iq-litellm-api-secret \
  --from-literal=virtualKey="$LITELLM_MASTER_KEY"

kubectl -n "$SHARED_NS" get secret litellm-env
kubectl -n "$DX_NS" get secret iq-litellm-api-secret
