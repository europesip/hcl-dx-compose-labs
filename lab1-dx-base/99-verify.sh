#!/usr/bin/env bash
# Lab 1 · Read-only checks of the base DX.
set -uo pipefail
source "$(dirname "$0")/../common/lib.sh"

info "Release"
helm -n "$DX_NS" list -f "^${DX_RELEASE}$"

info "Pods (all must be Running and fully READY)"
kubectl -n "$DX_NS" get pods -o wide
notready=$(kubectl -n "$DX_NS" get pods --no-headers | awk '{split($2,a,"/"); if ($3!="Completed" && (a[1]!=a[2] || $3!="Running")) print $1}')
[[ -z "$notready" ]] && ok "all pods are ready" || fail "pods still starting: $(echo $notready)"

info "PVC (all Bound)"
kubectl -n "$DX_NS" get pvc
kubectl -n "$DX_NS" get pvc --no-headers | awk '$2!="Bound"{exit 1}' && ok "all Bound" || fail "there are unbound PVCs (check the StorageClasses)"

info "Images in use (they must come from hclcr.io and be CF238)"
kubectl -n "$DX_NS" get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u | sed 's/^/  /'

info "HTTPS access to https://${DX_HOST}/wps/portal"
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "https://${DX_HOST}/wps/portal")
[[ "$code" =~ ^(200|302)$ ]] && ok "HTTP $code" || fail "HTTP $code (03-expose.sh? DNS? Web Engine still starting?)"

info "Last lines of the Web Engine"
kubectl -n "$DX_NS" logs "${DX_RELEASE}-web-engine-0" -c system-out-log --tail=15 2>/dev/null | sed 's/^/  /'
