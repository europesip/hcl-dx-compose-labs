#!/usr/bin/env bash
# Lab 2 · Enterprise branch · Step AD-1 · Active Directory connection data, in the DX namespace.
# Creates the dx-ad-bind secret, which the Web Engine receives as environment variables
# (customSecrets) and which ad-registry.xml uses (custom-values.ad.yaml).
#
# Variables (in env.sh, "Enterprise branch" section):
#   AD_HOST            e.g. dc01.company.local
#   AD_PORT            389 (LDAP) or 636 (LDAPS)
#   AD_SSL             false | true (with 636 and the AD CA in dx-ad-ca)
#   AD_BASE_DN         e.g. DC=company,DC=local
#   AD_BIND_USER       read-only service account, e.g. svc-dx@company.local
#   AD_BIND_PASSWORD
#   AD_CA_FILE         (optional, LDAPS only) AD CA in PEM -> dx-ad-ca secret
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"
require_vars DX_NS AD_HOST AD_PORT AD_SSL AD_BASE_DN AD_BIND_USER AD_BIND_PASSWORD

kubectl -n "$DX_NS" get secret dx-ldap-bind >/dev/null 2>&1 \
  && die "dx-ldap-bind exists (OpenLDAP branch). Use only one branch: kubectl -n $DX_NS delete secret dx-ldap-bind"

info "Checking connectivity to ${AD_HOST}:${AD_PORT} from the cluster"
kubectl -n "$DX_NS" run ad-check --rm -i --restart=Never --image=busybox:1.36 --quiet -- \
  nc -z -w 5 "$AD_HOST" "$AD_PORT" </dev/null && ok "port reachable" || die "The cluster cannot reach ${AD_HOST}:${AD_PORT}"

info "Secret dx-ad-bind"
apply_secret "$DX_NS" generic dx-ad-bind \
  --from-literal=AD_HOST="$AD_HOST" --from-literal=AD_PORT="$AD_PORT" --from-literal=AD_SSL="$AD_SSL" \
  --from-literal=AD_BASE_DN="$AD_BASE_DN" \
  --from-literal=AD_BIND_USER="$AD_BIND_USER" --from-literal=AD_BIND_PASSWORD="$AD_BIND_PASSWORD"

if [[ -n "${AD_CA_FILE:-}" ]]; then
  info "Secret dx-ad-ca (AD CA for LDAPS); uncomment customTruststoreSecrets in custom-values.ad.yaml"
  apply_secret "$DX_NS" generic dx-ad-ca --from-file=ad-ca.crt="$AD_CA_FILE"
fi
echo "Next: ./02-dx-upgrade.sh"
