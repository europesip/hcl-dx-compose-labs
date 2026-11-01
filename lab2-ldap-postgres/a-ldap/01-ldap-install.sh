#!/usr/bin/env bash
# Lab 2A · Paso 1 · Instala un OpenLDAP de laboratorio en dx-shared con usuarios de demo.
set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_cmd helm kubectl python3
require_vars SHARED_NS LDAP_RELEASE LDAP_CHART_VERSION LDAP_ADMIN_PASSWORD LDAP_USERS_PASSWORD
cd "$(dirname "$0")"

# Sustituye cada ${LDAP_USERS_PASSWORD} del LDIF por un hash {SSHA} (SHA-1 con sal aleatoria, una
# distinta por usuario), el formato que OpenLDAP verifica de forma nativa. Así la contraseña no
# queda en claro ni en el ConfigMap ni en el directorio (ni en el perfil de usuario que muestra DX).
# La contraseña llega por variable de entorno, no por la línea de comandos.
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

info "Secret openldap-admin (contraseñas de cn=admin y cn=admin,cn=config)"
apply_secret "$SHARED_NS" generic openldap-admin \
  --from-literal=LDAP_ADMIN_USERNAME=admin \
  --from-literal=LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD" \
  --from-literal=LDAP_CONFIG_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD"

info "ConfigMap openldap-demo-ldif (usuarios y grupos de demo)"
# Es un ConfigMap (lo exige el chart): por eso las contraseñas van ya cifradas con {SSHA}.
ssha_ldif demo-users.ldif \
  | kubectl -n "$SHARED_NS" create configmap openldap-demo-ldif --from-file=00-demo-users.ldif=/dev/stdin \
      --dry-run=client -o yaml | kubectl apply -f -

info "helm upgrade --install $LDAP_RELEASE (openldap-stack-ha $LDAP_CHART_VERSION)"
helm repo add helm-openldap https://jp-gouin.github.io/helm-openldap/ >/dev/null 2>&1 || true
helm repo update helm-openldap >/dev/null
helm upgrade --install "$LDAP_RELEASE" helm-openldap/openldap-stack-ha --version "$LDAP_CHART_VERSION" \
  -n "$SHARED_NS" -f openldap-values.yaml "$HELM_WAIT" --timeout 10m

kubectl -n "$SHARED_NS" get pod "${LDAP_RELEASE}-0"
kubectl -n "$SHARED_NS" get svc "$LDAP_RELEASE"
# El LDIF solo se carga en el primer arranque: si falla, el contenedor sale y el segundo arranque
# ya no lo reintenta (el PVC tiene datos). Un reinicio aquí es la señal de que algo fue mal.
restarts=$(kubectl -n "$SHARED_NS" get pod "${LDAP_RELEASE}-0" -o jsonpath='{.status.containerStatuses[0].restartCount}')
[[ "$restarts" == 0 ]] || warn "openldap-0 se ha reiniciado $restarts vez/veces: revisa la carga del LDIF con ./02-ldap-test.sh"
echo "Siguiente: ./02-ldap-test.sh"
