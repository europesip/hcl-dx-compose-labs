#!/usr/bin/env bash
# Lab 3 · Step 3 · Test LiteLLM -> OpenRouter -> the models BEFORE installing IQ.
# Uses a local port-forward: the key never appears in any pod nor on a remote command line.
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
info "published models"
curl -s "${H[@]}" "http://localhost:$PORT/v1/models" | python3 -c 'import sys,json; print("  ", [m["id"] for m in json.load(sys.stdin)["data"]])'
for m in iq-general-purpose iq-summary; do
  info "chat with $m"
  curl -s "${H[@]}" "http://localhost:$PORT/v1/chat/completions" \
    -d "{\"model\":\"$m\",\"max_tokens\":1000,\"messages\":[{\"role\":\"user\",\"content\":\"Answer only: ready\"}]}" \
  | python3 -c '
import sys,json
d=json.load(sys.stdin)
if "choices" not in d: print("  ERROR:", json.dumps(d)[:400]); sys.exit()
c=d["choices"][0]; u=d.get("usage") or {}
print("  ", (c["message"].get("content") or "(empty: finish_reason=%s)" % c.get("finish_reason")).strip(),
      "| model:", d.get("model"), "| tokens in/out:", u.get("prompt_tokens"), "/", u.get("completion_tokens"))'
done
