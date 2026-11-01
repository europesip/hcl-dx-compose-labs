#!/usr/bin/env bash
# Lab 1 · Paso 5 · Publica DX fuera del clúster en https://$DX_HOST
#   Kubernetes -> Ingress (ingress-dx.yaml)
#   OpenShift  -> Route passthrough (route-dx-openshift.yaml)
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
cd "$(dirname "$0")"
VARS='$DX_NS $DX_RELEASE $DX_HOST $INGRESS_CLASS'

kubectl -n "$DX_NS" get svc "${DX_RELEASE}-haproxy" >/dev/null || die "No existe el servicio ${DX_RELEASE}-haproxy: ¿terminó 02-install-dx.sh?"

if is_openshift; then
  render route-dx-openshift.yaml "$VARS" | kubectl apply -f -
  kubectl -n "$DX_NS" get route
else
  render ingress-dx.yaml "$VARS" | kubectl apply -f -
  kubectl -n "$DX_NS" get ingress
fi

echo
echo "Portal:        https://${DX_HOST}/wps/portal          (login: wpsadmin)"
echo "Admin Center:  https://${DX_HOST}/adminCenter"
echo "Sin DNS/Ingress puedes probar con:  kubectl -n $DX_NS port-forward svc/${DX_RELEASE}-haproxy 8443:443"
echo "                                    y abrir https://localhost:8443/wps/portal"
