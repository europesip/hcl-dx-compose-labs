#!/usr/bin/env bash
# Instala o actualiza la release de DX Compose. Es el ÚNICO comando de Helm de DX de los labs.
#
# Siempre parte del custom-values.yaml del Lab 1 y le añade, por capas (-f), los ficheros de
# cada iteración que ya esté preparada en el clúster:
#
#   capa                                                   se añade si existe...
#   lab1-dx-base/custom-values.yaml                        (siempre)
#   lab2-ldap-postgres/a-ldap/custom-values.ldap.yaml      secret dx-ldap-bind              (Lab 2A)
#     o empresa/active-directory/custom-values.ad.yaml    secret dx-ad-bind                (rama empresarial)
#   lab2-ldap-postgres/b-postgres/custom-values.postgres.yaml  secret ...-dbdomain-secret   (Lab 2B)
#     o empresa/oracle/custom-values.oracle.yaml          + secret dx-oracle-ca            (rama empresarial)
#   lab3-iq-openrouter/custom-values.iq.yaml               servicio <IQ_RELEASE>-integrator (Lab 3)
#   lab4-opensearch/custom-values.search.yaml             servicio <SEARCH_RELEASE>-search-middleware-query (Lab 4)
#   lab0-poc-wsl/custom-values.poc.yaml                   DX_POC=1 en env.sh (POC en un nodo, Lab 0)
#
# Así cada "helm upgrade" lleva la configuración COMPLETA y no se usa --reuse-values (que arrastra
# valores antiguos y es la causa más habitual de sorpresas en los upgrades).
#
# Uso:  common/dx-helm.sh                 (detecta las capas)
#       common/dx-helm.sh -f extra.yaml   (capas adicionales al final)
#       DX_DRY_RUN=1 common/dx-helm.sh    (solo muestra el comando)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd helm kubectl
require_vars DX_NS DX_RELEASE DX_HOST DX_CHART_TGZ SEARCH_RELEASE
[[ -f "$DX_CHART_TGZ" ]] || die "No está $DX_CHART_TGZ: ejecuta antes common/02-pull-hcl-charts.sh"

has_secret() { kubectl -n "$DX_NS" get secret "$1" >/dev/null 2>&1; }
L2="$REPO_ROOT/lab2-ldap-postgres"
layers=("$REPO_ROOT/lab1-dx-base/custom-values.yaml")

# Lab 2 · directorio: OpenLDAP (demo) o Active Directory (rama empresarial), nunca los dos
if has_secret dx-ldap-bind && has_secret dx-ad-bind; then
  die "Existen dx-ldap-bind (OpenLDAP) y dx-ad-bind (Active Directory): borra el de la rama que no uses"
elif has_secret dx-ldap-bind; then layers+=("$L2/a-ldap/custom-values.ldap.yaml")
elif has_secret dx-ad-bind;   then layers+=("$L2/empresa/active-directory/custom-values.ad.yaml")
fi
# Lab 2 · base de datos: PostgreSQL (demo) u Oracle (rama empresarial; dx-oracle-ca = TCPS)
if has_secret custom-credentials-webengine-dbdomain-secret; then
  if has_secret dx-oracle-ca; then layers+=("$L2/empresa/oracle/custom-values.oracle.yaml")
  else                              layers+=("$L2/b-postgres/custom-values.postgres.yaml")
  fi
fi
kubectl -n "$DX_NS" get svc "${IQ_RELEASE}-integrator" >/dev/null 2>&1 \
  && layers+=("$REPO_ROOT/lab3-iq-openrouter/custom-values.iq.yaml")
kubectl -n "$DX_NS" get svc "${SEARCH_RELEASE}-search-middleware-query" >/dev/null 2>&1 \
  && layers+=("$REPO_ROOT/lab4-opensearch/custom-values.search.yaml")

# Lab 0 · POC en un solo nodo (WSL2): reservas de recursos reducidas, siempre la última capa
[[ "${DX_POC:-}" == 1 ]] && layers+=("$REPO_ROOT/lab0-poc-wsl/custom-values.poc.yaml")

args=(upgrade --install "$DX_RELEASE" "$DX_CHART_TGZ" -n "$DX_NS")
for l in "${layers[@]}"; do args+=(-f "$l"); done
args+=("$@")
# El FQDN sale de env.sh para no tener que editarlo en el YAML
args+=(--set-string "networking.webEngine.host=$DX_HOST" --timeout 30m "$HELM_WAIT")

info "Capas de configuración de DX:"
for l in "${layers[@]}"; do echo "    - ${l#"$REPO_ROOT"/}"; done
info "helm ${args[*]//$REPO_ROOT\//}"
[[ -n "${DX_DRY_RUN:-}" ]] && exit 0

helm "${args[@]}"
kubectl -n "$DX_NS" get pods
