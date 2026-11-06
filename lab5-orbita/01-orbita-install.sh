#!/usr/bin/env bash
# Lab 5 (advanced) · Install ÓRBITA with its Helm chart (github.com/europesip/orbita): six Script
# Applications, a microservice (REST API + MCP server, Open Liberty), its PostgreSQL database and the
# pages in DX. Needs Lab 1, PostgreSQL (external dependencies) and, to sign in with the demo users,
# the OpenLDAP of Lab 2A.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd helm kubectl
: "${ORBITA_RELEASE:=orbita}" "${ORBITA_CHART:=oci://ghcr.io/europesip/charts/hcl-dx-orbita}" "${ORBITA_CHART_VERSION:=2.2.1}"
: "${DXCLIENT_IMAGE:=hclcr.io/dx-public/dxclient:v95_CF239_20261103-1404}"
require_vars DX_NS SHARED_NS DX_HOST PG_HOST WPSADMIN_PASSWORD

[[ "${DXCLIENT_ACCEPT_LICENSE:-}" == yes ]] || die "Read the DXClient license and set DXCLIENT_ACCEPT_LICENSE=yes in env.sh to accept it:
  kubectl -n $SHARED_NS run dxclient-license --rm -i --restart=Never --image=$DXCLIENT_IMAGE --command -- /dxclient/bin/dxclient accept-license"
kubectl -n "$DX_NS" get secret dx-tls-cert >/dev/null 2>&1 || die "dx-tls-cert is missing: do Lab 1 first"
kubectl -n "$SHARED_NS" get secret dx-pg-superuser >/dev/null 2>&1 \
  || die "PostgreSQL is missing: install it first (external-deps/02-postgres.sh)"
kubectl -n "$DX_NS" get secret dx-ldap-bind >/dev/null 2>&1 \
  || warn "Lab 2A (OpenLDAP) is not done: ÓRBITA installs, but the demo users (patricia, andres, macarena...) cannot sign in"

# DX administrator for DXClient (it pushes the Script Applications and creates the pages with
# XMLAccess) and the CA of the DX certificate (self-signed in the lab: it is its own CA). The API
# uses the CA too, to ask DX who the user is.
info "Secrets orbita-dx (DX user) and orbita-dx-ca (CA of the DX certificate) in $SHARED_NS"
apply_secret "$SHARED_NS" generic orbita-dx --from-literal=username=wpsadmin --from-literal=password="$WPSADMIN_PASSWORD"
CA=$(mktemp); trap 'rm -f "$CA"' EXIT
kubectl -n "$DX_NS" get secret dx-tls-cert -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CA"
apply_secret "$SHARED_NS" generic orbita-dx-ca --from-file=ca.crt="$CA"

# Public chart and images: no registry login. The chart creates the database (a Job with the
# PostgreSQL superuser), the API, its Ingress on /orbita-api of the DX host and, with the subchart
# hcl-dx-scriptapp, the six Script Applications and their pages.
info "helm upgrade --install $ORBITA_RELEASE ($ORBITA_CHART $ORBITA_CHART_VERSION) in $SHARED_NS"
helm upgrade --install "$ORBITA_RELEASE" "$ORBITA_CHART" --version "$ORBITA_CHART_VERSION" -n "$SHARED_NS" --timeout 15m \
  --set dx.host="$DX_HOST" --set dx.caSecret=orbita-dx-ca \
  --set database.host="$PG_HOST" --set database.create.superuserSecret=dx-pg-superuser \
  --set mcp.networkPolicy.integratorNamespace="$DX_NS" \
  --set scriptapps.dx.host="$DX_HOST" --set scriptapps.dx.credentialsSecret=orbita-dx --set scriptapps.dx.caSecret=orbita-dx-ca \
  --set scriptapps.dxclient.image="$DXCLIENT_IMAGE" --set scriptapps.dxclient.acceptLicense=true \
  "$@" | sed -n '/^NOTES:/,$p'
kubectl -n "$SHARED_NS" rollout status deploy/"$ORBITA_RELEASE"-api --timeout=10m
kubectl -n "$SHARED_NS" logs job/"$ORBITA_RELEASE"-scriptapps-push -c dxclient | grep -E "OK:|pages:" | sed 's/^/  /'
echo
echo "Sign in to https://$DX_HOST/wps/myportal/Home/mi-intranet as a demo user (e.g. macarena)."
echo "Next (with Lab 3): ./02-orbita-iq.sh   ·   Check: ./99-verify.sh"
