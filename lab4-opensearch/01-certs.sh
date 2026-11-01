#!/usr/bin/env bash
# Lab 4 · Paso 1 · Certificados de OpenSearch y sus secrets en dx-demo.
#
# OpenSearch y el Search Middleware se hablan por TLS mutuo. HCL pide tres certificados firmados
# por una misma CA:
#   admin   -> administración de OpenSearch (su DN va en configuration.openSearch.security.adminDN)
#   node    -> CN=opensearch-node    (comunicación entre nodos; el CN está preconfigurado)
#   client  -> CN=opensearch-client  (el Search Middleware como cliente; CN preconfigurado)
# con las extensiones X.509 basicConstraints=CA:FALSE, keyUsage=digitalSignature,keyEncipherment
# y extendedKeyUsage=serverAuth,clientAuth. Las claves en PKCS#8 sin cifrar.
#
# Aquí se crea una CA propia del laboratorio. Con la PKI de la empresa, se firman con su CA y
# se crean los mismos tres secrets (ver GUIA, "CA corporativa").
#
# Genera además admin-dn.rendered.yaml con el adminDN en formato RFC 2253 (lo usa 02-search-install.sh).
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_cmd openssl
require_vars DX_NS
cd "$(dirname "$0")"

D=certs; mkdir -p "$D"; umask 077
SUBJ="/C=ES/O=EUROPESIP/OU=Webinar DX"
EXT="$D/ext.cnf"
cat > "$EXT" <<'CNF'
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
CNF

if [[ ! -f "$D/root-ca.pem" ]]; then
  info "CA del laboratorio"
  openssl genrsa -out "$D/root-ca-key.pem" 2048 2>/dev/null
  openssl req -new -x509 -sha256 -key "$D/root-ca-key.pem" -subj "$SUBJ/CN=dx-search-root-ca" -out "$D/root-ca.pem" -days 730
fi

cert() {  # cert <nombre> <CN>
  [[ -f "$D/$1.pem" ]] && { ok "$1.pem ya existe"; return; }
  openssl genrsa -out "$D/$1-key-temp.pem" 2048 2>/dev/null
  openssl pkcs8 -inform PEM -outform PEM -in "$D/$1-key-temp.pem" -topk8 -nocrypt -out "$D/$1-key.pem"
  openssl req -new -key "$D/$1-key.pem" -subj "$SUBJ/CN=$2" -out "$D/$1.csr"
  openssl x509 -req -in "$D/$1.csr" -CA "$D/root-ca.pem" -CAkey "$D/root-ca-key.pem" -CAcreateserial \
    -sha256 -days 730 -extfile "$EXT" -out "$D/$1.pem" 2>/dev/null
  rm -f "$D/$1-key-temp.pem" "$D/$1.csr"
  ok "$1.pem  ($(openssl x509 -in "$D/$1.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//'))"
}
info "Certificados firmados por la CA"
cert admin  admin
cert node   opensearch-node
cert client opensearch-client

info "Secrets en $DX_NS (nombres por defecto del chart hcl-dx-search)"
apply_secret "$DX_NS" generic search-admin-cert  --from-file="$D/admin.pem"  --from-file="$D/admin-key.pem"  --from-file="$D/root-ca.pem"
apply_secret "$DX_NS" generic search-node-cert   --from-file="$D/node.pem"   --from-file="$D/node-key.pem"   --from-file="$D/root-ca.pem"
apply_secret "$DX_NS" generic search-client-cert --from-file="$D/client.pem" --from-file="$D/client-key.pem" --from-file="$D/root-ca.pem"

# adminDN tal como lo compara OpenSearch: RFC 2253 (orden inverso: CN primero) y entre comillas
# simples en YAML. HCL desaconseja pasarlo con --set: va en un fichero de values.
DN=$(openssl x509 -in "$D/admin.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
cat > admin-dn.rendered.yaml <<YAML
# Generado por 01-certs.sh: DN del certificado admin en formato RFC 2253
configuration:
  openSearch:
    security:
      adminDN: '${DN//\'/\'\'}'
YAML
info "adminDN = $DN   (admin-dn.rendered.yaml)"
