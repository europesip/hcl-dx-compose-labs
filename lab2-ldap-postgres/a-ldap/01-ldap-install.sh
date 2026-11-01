#!/usr/bin/env bash
# Lab 2A · Step 1 · Install a lab OpenLDAP in the shared namespace with demo users.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_cmd helm kubectl python3
require_vars SHARED_NS LDAP_RELEASE LDAP_CHART_VERSION LDAP_ADMIN_PASSWORD LDAP_USERS_PASSWORD SC_RWO
cd "$(dirname "$0")"

# Replace every ${LDAP_USERS_PASSWORD} of the LDIF with an {SSHA} hash (salted SHA-1, a different
# random salt per user), the format OpenLDAP verifies natively. So the password is never stored in
# plain text, neither in the ConfigMap nor in the directory (nor in the user profile DX shows).
# The password is passed through an environment variable, not on the command line.
ssha_ldif() {
  python3 -I -c '
import base64, hashlib, os, sys
pw = os.environ["LDAP_USERS_PASSWORD"].encode()
def ssha():
    salt = os.urandom(8)
    return "{SSHA}" + base64.b64encode(hashlib.sha1(pw + salt).digest() + salt).decode()
out = []
for line in open(sys.argv[1]):
    out.append(line.replace("${LDAP_USERS_PASSWORD}", ssha()) if "${LDAP_USERS_PASSWORD}" in line else line)
sys.stdout.write("".join(out))' "$1"
}

info "Secret openldap-admin (passwords of cn=admin and cn=admin,cn=config)"
apply_secret "$SHARED_NS" generic openldap-admin \
  --from-literal=LDAP_ADMIN_USERNAME=admin \
  --from-literal=LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD" \
  --from-literal=LDAP_CONFIG_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD"

info "ConfigMap openldap-demo-ldif (demo users and groups)"
# It is a ConfigMap (the chart requires it): that is why the passwords are already {SSHA} hashes.
ssha_ldif demo-users.ldif \
  | kubectl -n "$SHARED_NS" create configmap openldap-demo-ldif --from-file=00-demo-users.ldif=/dev/stdin \
      --dry-run=client -o yaml | kubectl apply -f -

info "helm upgrade --install $LDAP_RELEASE (openldap-stack-ha $LDAP_CHART_VERSION)"
helm repo add helm-openldap https://jp-gouin.github.io/helm-openldap/ >/dev/null 2>&1 || true
helm repo update helm-openldap >/dev/null
helm upgrade --install "$LDAP_RELEASE" helm-openldap/openldap-stack-ha --version "$LDAP_CHART_VERSION" \
  -n "$SHARED_NS" -f openldap-values.yaml --set persistence.storageClass="$SC_RWO" \
  "$HELM_WAIT" --timeout 10m

kubectl -n "$SHARED_NS" get pod "${LDAP_RELEASE}-0"
kubectl -n "$SHARED_NS" get svc "$LDAP_RELEASE"
# The LDIF is only loaded on the first start: if it fails, the container exits and the second
# start does not retry it (the PVC already has data). A restart here means something went wrong.
restarts=$(kubectl -n "$SHARED_NS" get pod "${LDAP_RELEASE}-0" -o jsonpath='{.status.containerStatuses[0].restartCount}')
[[ "$restarts" == 0 ]] || warn "${LDAP_RELEASE}-0 restarted $restarts time(s): check the LDIF load with ./02-ldap-test.sh"
echo "Next: ./02-ldap-test.sh"
