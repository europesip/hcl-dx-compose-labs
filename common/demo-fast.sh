#!/usr/bin/env bash
# Fast demo mode: installs everything chosen in DEMO_DEPS and DEMO_LABS (env.sh) in the order that
# takes the least time. The same result as the labs one by one, with fewer DX "helm upgrade"s:
#
#   1. checks, namespaces and HCL charts (and Lab 0 if DX_POC=1)
#   2. external dependencies (OpenLDAP, PostgreSQL, LiteLLM, MCP)          ~ 3-6 min
#   3. DX installed ONCE, already connected to the directory (Lab 1 + 2A)  ~ 15-25 min
#   4. IQ (Lab 3A, with 3B and the appendix) and search (Lab 4), in parallel
#   5. ONE "helm upgrade" of DX that enables IQ and search together       ~ 5 min
#   6. Lab 1B (sample Script Application) and the checks
#
# The step-by-step path does 1 install + up to 3 upgrades of DX; this one, 1 install + 1 upgrade.
# Not covered here: the Oracle transfer (Lab 2B enterprise path), do it afterwards with its guide.
#
# Usage:  common/demo-fast.sh            (reads DEMO_DEPS and DEMO_LABS from env.sh)
#         DEMO_LABS="2a-openldap 3a" common/demo-fast.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd helm kubectl
R="$REPO_ROOT"
has() { [[ " ${DEMO_DEPS:-} ${DEMO_LABS:-} " == *" $1 "* ]]; }
T0=$(date +%s)
phase() { printf '\n\033[1;35m### [%s] %s\033[0m\n' "$(date -u -d @$(( $(date +%s) - T0 )) +%M:%S)" "$*"; }

# Coherence of the choice: each lab needs its dependency
has 3a && ! has litellm && die "Lab 3A needs LiteLLM in DEMO_DEPS"
has 3b && ! { has mcp && has 3a; } && die "Lab 3B needs Lab 3A and mcp in DEMO_DEPS"
has iqdb && ! { has postgres && has 3a; } && die "The IQ sessions appendix (iqdb) needs Lab 3A and postgres in DEMO_DEPS"
has 2a-openldap && ! has openldap && die "Lab 2A with OpenLDAP needs openldap in DEMO_DEPS"
has 2a-openldap && has 2a-ad && die "Choose 2a-openldap or 2a-ad, not both"
info "Dependencies: ${DEMO_DEPS:-none} · Labs: 1 ${DEMO_LABS:-}"

phase "1 · Checks, namespaces and HCL charts"
"$R/common/00-check-prereqs.sh" || warn "check the warnings above"
"$R/common/01-namespaces.sh"
"$R/common/02-pull-hcl-charts.sh"
if [[ "${DX_POC:-}" == 1 ]]; then "$R/lab0-poc-wsl/01-storage.sh"; "$R/lab0-poc-wsl/02-ingress.sh"; fi

phase "2 · External dependencies"
has openldap && "$R/external-deps/01-openldap.sh"
has postgres && "$R/external-deps/02-postgres.sh"
has litellm  && "$R/external-deps/03-litellm.sh"
has mcp      && "$R/external-deps/04-mcp.sh"

phase "3 · DX, installed once with its directory (Lab 1 + Lab 2A)"
"$R/lab1-dx-base/01-secrets.sh"
if has 2a-openldap; then
  # The same secret as Lab 2A step 3: with it, dx-helm.sh adds the LDAP layer to the install
  apply_secret "$DX_NS" generic dx-ldap-bind \
    --from-literal=bindUser="cn=admin,dc=dxdemo,dc=com" --from-literal=bindPassword="$LDAP_ADMIN_PASSWORD"
elif has 2a-ad; then
  "$R/lab2-ldap-postgres/enterprise/active-directory/01-secrets-ad.sh"
fi
"$R/lab1-dx-base/02-install-dx.sh"
"$R/lab1-dx-base/03-expose.sh"

if has 3a || has 4; then
  phase "4 · IQ and search, in parallel"
  LOGS=$(mktemp -d); pids=()
  if has 3a; then
    ( set -e
      IQF=()
      if has iqdb; then "$R/lab3-iq-openrouter/A1-iq-database.sh"; IQF=(-f custom-iq-values.db-external.yaml); fi
      "$R/lab3-iq-openrouter/04-iq-install.sh" "${IQF[@]}" ) > "$LOGS/iq.log" 2>&1 & pids+=("$!:iq")
  fi
  if has 4; then
    ( set -e; "$R/lab4-opensearch/01-certs.sh"; "$R/lab4-opensearch/02-search-install.sh" ) > "$LOGS/search.log" 2>&1 & pids+=("$!:search")
  fi
  for p in "${pids[@]}"; do
    if wait "${p%%:*}"; then ok "${p#*:} installed"; else tail -30 "$LOGS/${p#*:}.log"; die "${p#*:} failed (full log: $LOGS/${p#*:}.log)"; fi
  done
  phase "5 · One DX upgrade that enables IQ and search"
  "$R/common/dx-helm.sh"
fi

if has 1b; then
  phase "6 · Lab 1B · sample Script Application"
  "$R/lab1b-scriptapp/01-scriptapp-install.sh"
fi

phase "Checks"
"$R/lab1-dx-base/99-verify.sh" || true
"$R/external-deps/99-verify.sh" || true
has 3a && { "$R/lab3-iq-openrouter/99-verify.sh" || true; }
has 1b && { "$R/lab1b-scriptapp/99-verify.sh" || true; }
phase "Done in $(( ($(date +%s) - T0) / 60 )) min · https://${DX_HOST}/wps/portal"
has 2a-openldap && echo "Manual step (Lab 2A step 4): give the Administrator role to the dxadmins group in the portal."
