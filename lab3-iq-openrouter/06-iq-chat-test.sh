#!/usr/bin/env bash
# Lab 3 · Paso 6 · Prueba de extremo a extremo: pregunta a IQ desde la terminal, igual que el
# navegador (WebSocket por HAProxy de DX, con la sesión de un usuario de DX).
# Uso:  ./06-iq-chat-test.sh                          (wpsadmin, pregunta por defecto)
#       IQ_USER=andres IQ_PASSWORD=... ./06-iq-chat-test.sh "¿Qué bibliotecas de WCM hay?"
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd curl python3
require_vars DX_HOST WPSADMIN_PASSWORD
cd "$(dirname "$0")"
Q="${1:-Lista los nombres de todas las bibliotecas de contenido WCM que existen. Responde solo con la lista.}"
U="${IQ_USER:-wpsadmin}"; P="${IQ_PASSWORD:-$WPSADMIN_PASSWORD}"
JAR=$(mktemp); trap 'rm -f "$JAR"' EXIT

# Login en DX (API de Ring) y primera visita al portal para tener la sesión completa
code=$(python3 -I -c 'import json,sys; print(json.dumps({"username":sys.argv[1],"password":sys.argv[2]}))' "$U" "$P" \
  | curl -sk -c "$JAR" -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data @- \
      "https://${DX_HOST}/dx/api/core/v1/auth/login")
[[ "$code" == 200 ]] || die "Login de $U en DX: HTTP $code"
curl -sk -b "$JAR" -c "$JAR" -L -o /dev/null "https://${DX_HOST}/wps/myportal"

info "Pregunta a IQ como $U: $Q"
python3 -I iq-chat.py "$DX_HOST" "$JAR" "$Q"
