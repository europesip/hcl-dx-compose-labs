#!/usr/bin/env bash
# Lab 1 · Step 5 · Publish DX outside the cluster at https://$DX_HOST
#   Kubernetes -> Ingress (ingress-dx.yaml), or IngressRoute with INGRESS_CLASS=traefik (ingressroute-dx-traefik.yaml)
#   OpenShift  -> passthrough Route (route-dx-openshift.yaml)
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
cd "$(dirname "$0")"
VARS='$DX_NS $DX_RELEASE $DX_HOST $INGRESS_CLASS'

kubectl -n "$DX_NS" get svc "${DX_RELEASE}-haproxy" >/dev/null || die "Service ${DX_RELEASE}-haproxy does not exist: did 02-install-dx.sh finish?"

if is_openshift; then
  render route-dx-openshift.yaml "$VARS" | kubectl apply -f -
  kubectl -n "$DX_NS" get route
elif [[ "$INGRESS_CLASS" == traefik ]]; then
  render ingressroute-dx-traefik.yaml "$VARS" | kubectl apply -f -
  kubectl -n "$DX_NS" get ingressroute
else
  render ingress-dx.yaml "$VARS" | kubectl apply -f -
  kubectl -n "$DX_NS" get ingress
fi

echo
echo "Portal:        https://${DX_HOST}/wps/portal          (login: wpsadmin)"
echo "Admin Center:  https://${DX_HOST}/adminCenter"
echo "Without DNS/Ingress you can test with:  kubectl -n $DX_NS port-forward svc/${DX_RELEASE}-haproxy 8443:443"
echo "                                        and open https://localhost:8443/wps/portal"
