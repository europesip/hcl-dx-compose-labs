#!/usr/bin/env bash
# Lab 3 · Step 6 · End-to-end test: ask IQ from the terminal, just like the browser does
# (WebSocket through the DX HAProxy, with the session of a DX user).
# Usage:  ./06-iq-chat-test.sh                          (wpsadmin, default question)
#         IQ_USER=andres IQ_PASSWORD=... ./06-iq-chat-test.sh "Which WCM libraries are there?"
#         IQ_LANG=es ./06-iq-chat-test.sh "¿Qué bibliotecas de WCM hay?"     (answer language)
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd curl python3
require_vars DX_HOST WPSADMIN_PASSWORD
cd "$(dirname "$0")"
Q="${1:-List the names of every WCM content library that exists. Answer only with the list.}"
U="${IQ_USER:-wpsadmin}"; P="${IQ_PASSWORD:-$WPSADMIN_PASSWORD}"
JAR=$(mktemp); trap 'rm -f "$JAR"' EXIT

# Log in to DX (Ring API) and first visit to the portal to get the full session
code=$(python3 -I -c 'import json,sys; print(json.dumps({"username":sys.argv[1],"password":sys.argv[2]}))' "$U" "$P" \
  | curl -sk -c "$JAR" -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data @- \
      "https://${DX_HOST}/dx/api/core/v1/auth/login")
[[ "$code" == 200 ]] || die "Login of $U in DX: HTTP $code"
curl -sk -b "$JAR" -c "$JAR" -L -o /dev/null "https://${DX_HOST}/wps/myportal"

info "Asking IQ as $U: $Q"
python3 -I iq-chat.py "$DX_HOST" "$JAR" "$Q" "${IQ_LANG:-en}"
