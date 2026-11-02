#!/usr/bin/env bash
# ------------------------------------------------------------------------------------------
# Lab configuration. Two ways to create your env.sh:
#
#   a) By hand:
#        cp env.example.sh env.sh      # env.sh is in .gitignore: your credentials are never committed
#        vi env.sh                     # fill in at least the variables marked with  # <<<
#   b) With the OPTIONAL configuration wizard (a static web page, see README.md): it generates an
#      env.sh that sets your values and then loads this file for every other default.
#
#   source ./env.sh                    # it must be LOADED (source), not executed
#
# Every lab script loads env.sh automatically if you have not done it yourself.
# Any variable already exported in your shell is respected.
# ------------------------------------------------------------------------------------------

export REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- Platform -----------------------------------------------------------------------------
# kubernetes : k3s, RKE2, EKS, AKS, GKE... (the reference environment of the labs is k3s)
# openshift  : Red Hat OpenShift (namespaces with SCC annotations and a Route instead of an Ingress)
export PLATFORM="${PLATFORM:-kubernetes}"

# --- Namespaces ---------------------------------------------------------------------------
export DX_NS="${DX_NS:-dx-demo}"            # HCL software: DX Compose, IQ, search
export SHARED_NS="${SHARED_NS:-dx-shared}"  # everything that is not HCL: OpenLDAP, PostgreSQL, LiteLLM, own MCP

# --- Helm releases ------------------------------------------------------------------------
export DX_RELEASE="${DX_RELEASE:-dx-deployment}"      # hcl-dx-deployment (pods dx-deployment-*)
export IQ_RELEASE="${IQ_RELEASE:-dx-iq}"              # hcl-dx-iq (service dx-iq-integrator)
export SEARCH_RELEASE="${SEARCH_RELEASE:-dx-search}"  # hcl-dx-search (the DX chart expects "dx-search")
export LDAP_RELEASE="${LDAP_RELEASE:-openldap}"       # OpenLDAP (service openldap)
export LITELLM_RELEASE="${LITELLM_RELEASE:-litellm}"

# --- Storage ------------------------------------------------------------------------------
# DX needs one ReadWriteOnce and one ReadWriteMany StorageClass (docs/requirements.md).
export SC_RWO="${SC_RWO:-dx-deploy-rwo}"   # Web Engine, Persistence Node, PostgreSQL, OpenLDAP, OpenSearch
export SC_RWX="${SC_RWX:-dx-deploy-rwx}"   # DAM binaries (shared by the DAM pods)

# --- External access to DX ----------------------------------------------------------------
# FQDN used to reach DX. It must resolve to the Ingress (Kubernetes) or the router (OpenShift).
export DX_HOST="${DX_HOST:-dx-demo.example.com}"   # <<<
export INGRESS_CLASS="${INGRESS_CLASS:-nginx}"     # PLATFORM=kubernetes only: nginx, traefik (k3s default) or yours
# Single-node PoC (Lab 0, k3s on WSL2): 1 = reduced resource requests so that the four labs fit
# in ~15 GiB. Leave empty on a normal cluster.
export DX_POC="${DX_POC:-}"

# --- Official HCL Harbor (hclcr.io) -------------------------------------------------------
# User: the e-mail of your HCL account. Token: the "CLI secret" of your profile on https://hclcr.io
# (User Profile -> CLI secret). Used to download the charts and for the imagePullSecret.
export HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
export HCL_HARBOR_USER="${HCL_HARBOR_USER:-}"      # <<<
export HCL_HARBOR_TOKEN="${HCL_HARBOR_TOKEN:-}"    # <<<

# --- Versions (HCL DX Compose CF238) ------------------------------------------------------
export DX_CHART="${DX_CHART:-oci://${HCL_REGISTRY}/dx-compose/hcl-dx-deployment}"
export DX_CHART_VERSION="${DX_CHART_VERSION:-2.49.0}"
export IQ_CHART="${IQ_CHART:-oci://${HCL_REGISTRY}/dx/hcl-dx-iq}"
export IQ_CHART_VERSION="${IQ_CHART_VERSION:-1.0.2}"
export SEARCH_CHART="${SEARCH_CHART:-oci://${HCL_REGISTRY}/dx-compose/hcl-dx-search}"   # Lab 4
export SEARCH_CHART_VERSION="${SEARCH_CHART_VERSION:-2.36.0}"
export CHARTS_DIR="${CHARTS_DIR:-$REPO_ROOT/charts}"
export DX_CHART_TGZ="${DX_CHART_TGZ:-$CHARTS_DIR/hcl-dx-deployment-${DX_CHART_VERSION}.tgz}"
export IQ_CHART_TGZ="${IQ_CHART_TGZ:-$CHARTS_DIR/hcl-dx-iq-${IQ_CHART_VERSION}.tgz}"
export SEARCH_CHART_TGZ="${SEARCH_CHART_TGZ:-$CHARTS_DIR/hcl-dx-search-${SEARCH_CHART_VERSION}.tgz}"

# Third-party software (pinned, tested versions)
export LDAP_CHART_VERSION="${LDAP_CHART_VERSION:-4.3.3}"        # helm-openldap/openldap-stack-ha
export CNPG_CHART_VERSION="${CNPG_CHART_VERSION:-0.29.1}"       # cnpg/cloudnative-pg (operator 1.30.1)
export LITELLM_CHART="${LITELLM_CHART:-oci://ghcr.io/berriai/litellm-helm}"
export LITELLM_CHART_VERSION="${LITELLM_CHART_VERSION:-1.106.5}"

# --- Passwords ----------------------------------------------------------------------------
# By default ALL lab passwords are "EuropeS1P": the users that log in to DX (wpsadmin and the 7
# LDAP users: andres, eduardo, macarena, enrique, jordi, patricia, german) and the technical
# accounts (OpenLDAP admin, PostgreSQL, IQ database).
# It is a LAB password and it is public (it is in this repository): change it anywhere that is
# not a test environment.
# They must be STABLE: if you change one after its secret was created, run the script that creates
# it again. Avoid the characters  ' " \ $ & |  (used in properties files and LDIF).
export WPSADMIN_PASSWORD="${WPSADMIN_PASSWORD:-EuropeS1P}"        # Lab 1: DX wpsadmin
export LDAP_USERS_PASSWORD="${LDAP_USERS_PASSWORD:-EuropeS1P}"    # Lab 2A: LDAP demo users
# Technical accounts (not used to log in to DX)
export LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-EuropeS1P}"      # Lab 2A: OpenLDAP cn=admin (DX bind user)
export PG_SUPERUSER_PASSWORD="${PG_SUPERUSER_PASSWORD:-EuropeS1P}"  # Lab 2B: postgres
export DXUSER_PASSWORD="${DXUSER_PASSWORD:-EuropeS1P}"              # Lab 2B: dxuser (owner of dx_core, Web Engine DB)
export IQ_DB_PASSWORD="${IQ_DB_PASSWORD:-EuropeS1P}"                # Lab 2B/3: dx_iq_db_user (optional in Lab 3)

# --- Lab 3: IQ with OpenRouter ------------------------------------------------------------
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"        # <<< Lab 3: sk-or-v1-...
# LiteLLM master key (must start with "sk-"). If empty, Lab 3 01-secrets.sh reuses the one already
# in the cluster or generates a new one.
export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# --- Lab 2 · Enterprise path (optional): Active Directory and Oracle ----------------------
# Only if you follow lab2-ldap-postgres/GUIDE-enterprise.md instead of OpenLDAP / PostgreSQL.
export AD_HOST="${AD_HOST:-}"                    # dc01.company.local
export AD_PORT="${AD_PORT:-389}"                 # 389 LDAP · 636 LDAPS
export AD_SSL="${AD_SSL:-false}"                 # true with 636 (and AD_CA_FILE)
export AD_BASE_DN="${AD_BASE_DN:-}"              # DC=company,DC=local
export AD_BIND_USER="${AD_BIND_USER:-}"          # svc-dx@company.local (read-only)
export AD_BIND_PASSWORD="${AD_BIND_PASSWORD:-}"
export AD_CA_FILE="${AD_CA_FILE:-}"              # AD CA in PEM (LDAPS)
export AD_ADMIN_GROUP_DN="${AD_ADMIN_GROUP_DN:-}" # (reference) CN=DX-Admins,OU=Groups,DC=company,DC=local
export ORACLE_JDBC_URL="${ORACLE_JDBC_URL:-}"    # jdbc:oracle:thin:@tcps://oracle.company.local:2484/WPSDB
export ORACLE_DX_USER="${ORACLE_DX_USER:-wpsuser}"
export ORACLE_DX_PASSWORD="${ORACLE_DX_PASSWORD:-}"
export ORACLE_CA_FILE="${ORACLE_CA_FILE:-}"      # TCPS listener CA in PEM

# --- Derived values (do not change) -------------------------------------------------------
export PG_CLUSTER="${PG_CLUSTER:-dx-pg}"
export PG_HOST="${PG_HOST:-${PG_CLUSTER}-rw.${SHARED_NS}.svc.cluster.local}"
export LDAP_HOST="${LDAP_HOST:-${LDAP_RELEASE}.${SHARED_NS}.svc.cluster.local}"
export LITELLM_URL_INTERNAL="${LITELLM_URL_INTERNAL:-http://${LITELLM_RELEASE}.${SHARED_NS}.svc.cluster.local:4000}"
export DX_ENV_LOADED=1
