#!/usr/bin/env bash
# ------------------------------------------------------------------------------------------
# Configuración de los laboratorios. Úsalo así:
#
#   cp env.example.sh env.sh      # env.sh está en .gitignore: tus credenciales no se suben
#   vi env.sh                     # rellena al menos las variables marcadas con  # <<<
#   source ./env.sh               # hay que CARGARLO (source), no ejecutarlo
#
# Todos los scripts de los labs lo cargan automáticamente si no lo has hecho tú.
# Cualquier variable que ya tengas exportada en tu shell se respeta.
# ------------------------------------------------------------------------------------------

export REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- Plataforma ---------------------------------------------------------------------------
# kubernetes : k3s, RKE2, EKS, AKS, GKE... (es la que usamos en el webinar: k3s)
# openshift  : Red Hat OpenShift (namespaces con anotaciones SCC y Route en vez de Ingress)
export PLATFORM="${PLATFORM:-kubernetes}"

# --- Namespaces ---------------------------------------------------------------------------
export DX_NS="${DX_NS:-dx-demo}"            # software de HCL: DX Compose e IQ
export SHARED_NS="${SHARED_NS:-dx-shared}"  # software de terceros: OpenLDAP, PostgreSQL, LiteLLM

# --- Releases de Helm ---------------------------------------------------------------------
export DX_RELEASE="${DX_RELEASE:-dx-deployment}"   # hcl-dx-deployment (pods dx-deployment-*)
export IQ_RELEASE="${IQ_RELEASE:-dx-iq}"           # hcl-dx-iq (servicio dx-iq-integrator)
export SEARCH_RELEASE="${SEARCH_RELEASE:-dx-search}"  # hcl-dx-search (el chart de DX espera "dx-search")
export LDAP_RELEASE="${LDAP_RELEASE:-openldap}"    # OpenLDAP (servicio openldap)
export LITELLM_RELEASE="${LITELLM_RELEASE:-litellm}"

# --- Acceso externo a DX ------------------------------------------------------------------
# FQDN con el que se accede a DX. Debe resolver al Ingress (k8s) o al router (OpenShift).
export DX_HOST="${DX_HOST:-dx-demo.apps.promox.europesip-lab.com}"   # <<<
export INGRESS_CLASS="${INGRESS_CLASS:-nginx}"     # solo PLATFORM=kubernetes

# --- Harbor oficial de HCL (hclcr.io) -----------------------------------------------------
# Usuario: el e-mail de tu cuenta de HCL. Token: "CLI secret" de tu perfil en https://hclcr.io
# (User Profile -> CLI secret). Se usa para descargar los charts y para el imagePullSecret.
export HCL_REGISTRY="${HCL_REGISTRY:-hclcr.io}"
export HCL_HARBOR_USER="${HCL_HARBOR_USER:-}"      # <<<
export HCL_HARBOR_TOKEN="${HCL_HARBOR_TOKEN:-}"    # <<<

# --- Versiones (HCL DX Compose CF238) -----------------------------------------------------
export DX_CHART="${DX_CHART:-oci://${HCL_REGISTRY}/dx-compose/hcl-dx-deployment}"
export DX_CHART_VERSION="${DX_CHART_VERSION:-2.49.0}"
export IQ_CHART="${IQ_CHART:-oci://${HCL_REGISTRY}/dx/hcl-dx-iq}"
export IQ_CHART_VERSION="${IQ_CHART_VERSION:-1.0.2}"
export CHARTS_DIR="${CHARTS_DIR:-$REPO_ROOT/charts}"
export DX_CHART_TGZ="${DX_CHART_TGZ:-$CHARTS_DIR/hcl-dx-deployment-${DX_CHART_VERSION}.tgz}"
export IQ_CHART_TGZ="${IQ_CHART_TGZ:-$CHARTS_DIR/hcl-dx-iq-${IQ_CHART_VERSION}.tgz}"
export SEARCH_CHART="${SEARCH_CHART:-oci://${HCL_REGISTRY}/dx-compose/hcl-dx-search}"   # Lab 4
export SEARCH_CHART_VERSION="${SEARCH_CHART_VERSION:-2.36.0}"
export SEARCH_CHART_TGZ="${SEARCH_CHART_TGZ:-$CHARTS_DIR/hcl-dx-search-${SEARCH_CHART_VERSION}.tgz}"

# Software de terceros (versiones fijadas y probadas)
export LDAP_CHART_VERSION="${LDAP_CHART_VERSION:-4.3.3}"        # helm-openldap/openldap-stack-ha
export CNPG_CHART_VERSION="${CNPG_CHART_VERSION:-0.29.1}"       # cnpg/cloudnative-pg (operador 1.30.1)
export LITELLM_CHART="${LITELLM_CHART:-oci://ghcr.io/berriai/litellm-helm}"
export LITELLM_CHART_VERSION="${LITELLM_CHART_VERSION:-1.106.5}"

# --- Contraseñas --------------------------------------------------------------------------
# Por defecto TODAS las contraseñas del laboratorio son "EuropeS1P": los usuarios con los que se
# entra en DX (wpsadmin y los 7 del LDAP: andres, eduardo, macarena, enrique, jordi, patricia,
# german) y las cuentas técnicas (admin del OpenLDAP, PostgreSQL, base de datos de IQ).
# Es una contraseña de LABORATORIO y es pública (está en este repositorio): cámbiala en cualquier
# entorno que no sea una demo.
# Deben ser ESTABLES: si cambias una después de crear su secret, vuelve a ejecutar el script
# que lo crea. Evita los caracteres  ' " \ $ & |  (se usan en ficheros de propiedades y LDIF).
export WPSADMIN_PASSWORD="${WPSADMIN_PASSWORD:-EuropeS1P}"        # Lab 1: wpsadmin de DX
export LDAP_USERS_PASSWORD="${LDAP_USERS_PASSWORD:-EuropeS1P}"    # Lab 2A: usuarios de demo del LDAP
# Cuentas técnicas (no se usan para entrar en DX)
export LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-EuropeS1P}"      # Lab 2A: cn=admin del OpenLDAP (bind de DX)
export PG_SUPERUSER_PASSWORD="${PG_SUPERUSER_PASSWORD:-EuropeS1P}"  # Lab 2B: postgres
export WPSUSER_PASSWORD="${WPSUSER_PASSWORD:-EuropeS1P}"            # Lab 2B: wpsuser (BD del Web Engine)
export IQ_DB_PASSWORD="${IQ_DB_PASSWORD:-EuropeS1P}"                # Lab 2B/3: dx_iq_db_user (opcional en Lab 3)

# --- Lab 3: IQ con OpenRouter -------------------------------------------------------------
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"        # <<< Lab 3: sk-or-v1-...
# Clave maestra de LiteLLM (debe empezar por "sk-"). Si la dejas vacía, 01-secrets.sh del Lab 3
# reutiliza la que ya esté en el clúster o genera una nueva.
export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# --- Lab 2 · Rama empresarial (opcional): Active Directory y Oracle -------------------------
# Solo si sigues lab2-ldap-postgres/GUIA-empresa.md en lugar de OpenLDAP / PostgreSQL.
export AD_HOST="${AD_HOST:-}"                    # dc01.empresa.local
export AD_PORT="${AD_PORT:-389}"                 # 389 LDAP · 636 LDAPS
export AD_SSL="${AD_SSL:-false}"                 # true con 636 (y AD_CA_FILE)
export AD_BASE_DN="${AD_BASE_DN:-}"              # DC=empresa,DC=local
export AD_BIND_USER="${AD_BIND_USER:-}"          # svc-dx@empresa.local (solo lectura)
export AD_BIND_PASSWORD="${AD_BIND_PASSWORD:-}"
export AD_CA_FILE="${AD_CA_FILE:-}"              # CA del AD en PEM (LDAPS)
export AD_ADMIN_GROUP_DN="${AD_ADMIN_GROUP_DN:-}" # (referencia) CN=DX-Admins,OU=Grupos,DC=empresa,DC=local
export ORACLE_JDBC_URL="${ORACLE_JDBC_URL:-}"    # jdbc:oracle:thin:@tcps://oracle.empresa.local:2484/WPSDB
export ORACLE_DX_USER="${ORACLE_DX_USER:-wpsuser}"
export ORACLE_DX_PASSWORD="${ORACLE_DX_PASSWORD:-}"
export ORACLE_CA_FILE="${ORACLE_CA_FILE:-}"      # CA del listener TCPS en PEM

# --- Derivadas (no tocar) -----------------------------------------------------------------
export PG_CLUSTER="${PG_CLUSTER:-dx-pg}"
export PG_HOST="${PG_HOST:-${PG_CLUSTER}-rw.${SHARED_NS}.svc.cluster.local}"
export LDAP_HOST="${LDAP_HOST:-${LDAP_RELEASE}.${SHARED_NS}.svc.cluster.local}"
export LITELLM_URL_INTERNAL="${LITELLM_URL_INTERNAL:-http://${LITELLM_RELEASE}.${SHARED_NS}.svc.cluster.local:4000}"
export DX_ENV_LOADED=1
