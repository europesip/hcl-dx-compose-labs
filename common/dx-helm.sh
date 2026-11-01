#!/usr/bin/env bash
# Install or upgrade the DX Compose release. It is the ONLY DX Helm command in the labs.
#
# It always starts from the Lab 1 custom-values.yaml and adds, as layers (-f), the files of every
# iteration already prepared in the cluster:
#
#   layer                                                  added when this exists...
#   lab1-dx-base/custom-values.yaml                        (always)
#   lab2-ldap-postgres/a-ldap/custom-values.ldap.yaml      secret dx-ldap-bind              (Lab 2A)
#     or enterprise/active-directory/custom-values.ad.yaml secret dx-ad-bind               (enterprise path)
#   lab2-ldap-postgres/b-postgres/custom-values.postgres.yaml  secret ...-dbdomain-secret   (Lab 2B)
#     or enterprise/oracle/custom-values.oracle.yaml       + secret dx-oracle-ca            (enterprise path)
#   lab3-iq-openrouter/custom-values.iq.yaml               service <IQ_RELEASE>-integrator  (Lab 3)
#   lab4-opensearch/custom-values.search.yaml              service <SEARCH_RELEASE>-search-middleware-query (Lab 4)
#   lab0-poc-wsl/custom-values.poc.yaml                    DX_POC=1 in env.sh (single-node PoC, Lab 0)
#
# So every "helm upgrade" carries the COMPLETE configuration and --reuse-values is never used (it
# drags old values along and is the most common source of surprises in upgrades).
#
# Values that depend on env.sh (host, StorageClasses, namespaces, release names) are passed with
# --set-string, so the YAML files keep readable defaults and env.sh is the single source of truth.
#
# Usage:  common/dx-helm.sh                 (detects the layers)
#         common/dx-helm.sh -f extra.yaml   (additional layers at the end)
#         DX_DRY_RUN=1 common/dx-helm.sh    (only prints the command)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd helm kubectl
require_vars DX_NS DX_RELEASE DX_HOST DX_CHART_TGZ SEARCH_RELEASE SC_RWO SC_RWX
[[ -f "$DX_CHART_TGZ" ]] || die "$DX_CHART_TGZ not found: run common/02-pull-hcl-charts.sh first"

has_secret() { kubectl -n "$DX_NS" get secret "$1" >/dev/null 2>&1; }
L2="$REPO_ROOT/lab2-ldap-postgres"
layers=("$REPO_ROOT/lab1-dx-base/custom-values.yaml")
sets=(
  "networking.webEngine.host=$DX_HOST"
  "volumes.digitalAssetManagement.binaries.storageClassName=$SC_RWX"
  "volumes.persistenceNode.database.storageClassName=$SC_RWO"
  "volumes.licenseManager.data.storageClassName=$SC_RWO"
  "volumes.webEngine.customization.storageClassName=$SC_RWO"
  "volumes.webEngine.log.storageClassName=$SC_RWO"
)

# Lab 2 · directory: OpenLDAP (default path) or Active Directory (enterprise path), never both
if has_secret dx-ldap-bind && has_secret dx-ad-bind; then
  die "Both dx-ldap-bind (OpenLDAP) and dx-ad-bind (Active Directory) exist: delete the one you do not use"
elif has_secret dx-ldap-bind; then
  layers+=("$L2/a-ldap/custom-values.ldap.yaml"); sets+=("configuration.webEngine.ldap.host=$LDAP_HOST")
elif has_secret dx-ad-bind; then
  layers+=("$L2/enterprise/active-directory/custom-values.ad.yaml")
fi
# Lab 2 · database: PostgreSQL (default path) or Oracle (enterprise path; dx-oracle-ca = TCPS)
if has_secret custom-credentials-webengine-dbdomain-secret; then
  if has_secret dx-oracle-ca; then layers+=("$L2/enterprise/oracle/custom-values.oracle.yaml")
  else                              layers+=("$L2/b-postgres/custom-values.postgres.yaml")
  fi
fi
if kubectl -n "$DX_NS" get svc "${IQ_RELEASE}-integrator" >/dev/null 2>&1; then
  layers+=("$REPO_ROOT/lab3-iq-openrouter/custom-values.iq.yaml"); sets+=("networking.dxIqService=${IQ_RELEASE}-integrator")
fi
if kubectl -n "$DX_NS" get svc "${SEARCH_RELEASE}-search-middleware-query" >/dev/null 2>&1; then
  layers+=("$REPO_ROOT/lab4-opensearch/custom-values.search.yaml")
  sets+=("networking.searchMiddlewareService=${SEARCH_RELEASE}-search-middleware-query"
         "configuration.searchMiddleware.searchReleaseName=$SEARCH_RELEASE")
fi

# Lab 0 · single-node PoC (WSL2): reduced resource requests, always the last layer
[[ "${DX_POC:-}" == 1 ]] && layers+=("$REPO_ROOT/lab0-poc-wsl/custom-values.poc.yaml")

args=(upgrade --install "$DX_RELEASE" "$DX_CHART_TGZ" -n "$DX_NS")
for l in "${layers[@]}"; do args+=(-f "$l"); done
args+=("$@")
for s in "${sets[@]}"; do args+=(--set-string "$s"); done
args+=(--timeout 30m "$HELM_WAIT")

info "DX configuration layers:"
for l in "${layers[@]}"; do echo "    - ${l#"$REPO_ROOT"/}"; done
info "helm ${args[*]//$REPO_ROOT\//}"
[[ -n "${DX_DRY_RUN:-}" ]] && exit 0

helm "${args[@]}"
kubectl -n "$DX_NS" get pods
