#!/usr/bin/env bash
# Lab 3 · Paso 3 · Prueba LiteLLM -> OpenRouter -> Claude ANTES de instalar IQ.
# Usa un port-forward local: la clave no aparece en ningún pod ni en la línea de comandos remota.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd curl python3
PORT=${PORT:-8000}

KEY=$(kubectl -n "$SHARED_NS" get secret litellm-env -o jsonpath='{.data.PROXY_MASTER_KEY}' | base64 -d)
kubectl -n "$SHARED_NS" port-forward svc/"$LITELLM_RELEASE" "$PORT":4000 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT
for _ in $(seq 1 20); do curl -s "http://localhost:$PORT/health/liveliness" >/dev/null && break; sleep 1; done

H=(-H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json")
info "readiness";  curl -s "http://localhost:$PORT/health/readiness"; echo
info "modelos publicados"
curl -s "${H[@]}" "http://localhost:$PORT/v1/models" | python3 -c 'import sys,json; print("  ", [m["id"] for m in json.load(sys.stdin)["data"]])'
for m in iq-general-purpose iq-summary; do
  info "chat con $m"
  curl -s "${H[@]}" "http://localhost:$PORT/v1/chat/completions" \
    -d "{\"model\":\"$m\",\"max_tokens\":60,\"messages\":[{\"role\":\"user\",\"content\":\"Responde solo: listo\"}]}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ", d["choices"][0]["message"]["content"].strip(), "| modelo:", d.get("model")) if "choices" in d else print("  ERROR:", json.dumps(d)[:400])'
done
