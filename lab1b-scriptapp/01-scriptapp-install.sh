#!/usr/bin/env bash
# Lab 1B · Deploy the sample Script Application "Hello DX" with its Helm chart
# (github.com/europesip/hcl-dx-scriptapp-helm). A Job runs HCL DXClient and pushes the app into
# WCM; every later run updates the same WCM item. Optional: it only needs Lab 1.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm kubectl
require_vars DX_NS SHARED_NS DX_HOST WPSADMIN_PASSWORD SCRIPTAPP_RELEASE SCRIPTAPP_CHART SCRIPTAPP_CHART_VERSION DXCLIENT_IMAGE

[[ "${DXCLIENT_ACCEPT_LICENSE:-}" == yes ]] || die "Read the DXClient license and set DXCLIENT_ACCEPT_LICENSE=yes in env.sh to accept it:
  kubectl -n $SHARED_NS run dxclient-license --rm -i --restart=Never --image=$DXCLIENT_IMAGE --command -- /dxclient/bin/dxclient accept-license"
kubectl -n "$DX_NS" get secret dx-tls-cert >/dev/null 2>&1 || die "dx-tls-cert is missing: do Lab 1 first"

# DX user for the push (in the lab, wpsadmin; in a real project, a technical user with Editor
# access to the Script Application Library) and the CA of the DX certificate (self-signed in the
# lab, so the certificate is its own CA). Both in the shared namespace, next to the Job.
info "Secrets scriptapp-dx (DX user) and scriptapp-dx-ca (CA of the DX certificate) in $SHARED_NS"
apply_secret "$SHARED_NS" generic scriptapp-dx \
  --from-literal=username=wpsadmin --from-literal=password="$WPSADMIN_PASSWORD"
CA=$(mktemp); trap 'rm -f "$CA"' EXIT
kubectl -n "$DX_NS" get secret dx-tls-cert -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CA"
apply_secret "$SHARED_NS" generic scriptapp-dx-ca --from-file=ca.crt="$CA"

info "helm upgrade --install $SCRIPTAPP_RELEASE ($SCRIPTAPP_CHART $SCRIPTAPP_CHART_VERSION)"
helm upgrade --install "$SCRIPTAPP_RELEASE" "$SCRIPTAPP_CHART" --version "$SCRIPTAPP_CHART_VERSION" -n "$SHARED_NS" \
  --set dx.host="$DX_HOST" \
  --set dx.credentialsSecret=scriptapp-dx \
  --set dx.caSecret=scriptapp-dx-ca \
  --set dxclient.image="$DXCLIENT_IMAGE" \
  --set dxclient.acceptLicense=true \
  "$@"
kubectl -n "$SHARED_NS" logs job/"$SCRIPTAPP_RELEASE"-hcl-dx-scriptapp-push -c dxclient | tail -1
echo
echo "Add it to a page once: edit a page in DX > add a component > Script Applications > \"Hello DX\"."
echo "Next: ./99-verify.sh"
