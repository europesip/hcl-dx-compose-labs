#!/usr/bin/env bash
# Lab 1 · Comprobaciones de solo lectura del DX base.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"

info "Release"
helm -n "$DX_NS" list -f "^${DX_RELEASE}$"

info "Pods (todos deben estar Running y READY completo)"
kubectl -n "$DX_NS" get pods -o wide
notready=$(kubectl -n "$DX_NS" get pods --no-headers | awk '{split($2,a,"/"); if ($3!="Completed" && (a[1]!=a[2] || $3!="Running")) print $1}')
[[ -z "$notready" ]] && ok "todos los pods están listos" || fail "pods sin terminar de arrancar: $(echo $notready)"

info "PVC (todos Bound)"
kubectl -n "$DX_NS" get pvc
kubectl -n "$DX_NS" get pvc --no-headers | awk '$2!="Bound"{exit 1}' && ok "todos Bound" || fail "hay PVC sin enlazar (revisa las StorageClasses)"

info "Imágenes en uso (deben venir de hclcr.io y ser de CF238)"
kubectl -n "$DX_NS" get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u | sed 's/^/  /'

info "Acceso HTTPS a https://${DX_HOST}/wps/portal"
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "https://${DX_HOST}/wps/portal")
[[ "$code" =~ ^(200|302)$ ]] && ok "HTTP $code" || fail "HTTP $code (¿03-expose.sh? ¿DNS? ¿Web Engine aún arrancando?)"

info "Últimas líneas del Web Engine"
kubectl -n "$DX_NS" logs "${DX_RELEASE}-web-engine-0" -c system-out-log --tail=15 2>/dev/null | sed 's/^/  /'
