#!/usr/bin/env bash
# Paso 0 · Comprueba (solo lectura) que la estación de trabajo y el clúster cumplen los requisitos.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

info "Herramientas de la estación de trabajo"
for c in kubectl helm openssl envsubst curl python3; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else fail "$c no está instalado"; fi
done
is_openshift && { command -v oc >/dev/null 2>&1 && ok "oc" || fail "oc no está instalado"; }
helm version --short 2>/dev/null | sed 's/^/          helm /'

info "Acceso al clúster"
if kubectl version -o json >/dev/null 2>&1; then
  ok "contexto: $(kubectl config current-context)"
  kubectl version -o json | python3 -c 'import sys,json; print("          servidor:", json.load(sys.stdin)["serverVersion"]["gitVersion"])'
else
  fail "kubectl no llega al clúster"; exit 1
fi

info "Nodos (HCL: solo x86-64)"
kubectl get nodes -o custom-columns='NODO:.metadata.name,ARQ:.status.nodeInfo.architecture,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory' 2>/dev/null
kubectl top nodes 2>/dev/null || warn "metrics-server no disponible: no se puede medir el uso actual"
echo "          El DX base (Lab 1) reserva ~5 CPU y ~11 GiB (requests). Labs 2 y 3 añaden ~1 CPU / 2,5 GiB."

info "StorageClasses requeridas (se usan en custom-values.yaml y en el cluster PostgreSQL)"
for sc in dx-deploy-rwo dx-deploy-rwx; do
  if kubectl get sc "$sc" >/dev/null 2>&1; then
    ok "$sc ($(kubectl get sc "$sc" -o jsonpath='{.provisioner}'))"
  else
    fail "falta la StorageClass $sc (referencia: common/storageclasses-longhorn.yaml)"
  fi
done

info "Acceso externo"
if is_openshift; then
  ok "OpenShift: se usará una Route passthrough"
else
  kubectl get ingressclass "$INGRESS_CLASS" >/dev/null 2>&1 && ok "IngressClass $INGRESS_CLASS" \
    || fail "no existe la IngressClass $INGRESS_CLASS (ajusta INGRESS_CLASS en env.sh)"
fi
if getent hosts "$DX_HOST" >/dev/null 2>&1; then ok "DNS: $DX_HOST -> $(getent hosts "$DX_HOST" | awk '{print $1}')"
else fail "DNS: $DX_HOST no resuelve"; fi

info "Credenciales de Harbor (hclcr.io)"
[[ -n "${HCL_HARBOR_USER:-}" && -n "${HCL_HARBOR_TOKEN:-}" ]] && ok "HCL_HARBOR_USER y HCL_HARBOR_TOKEN definidas" \
  || fail "define HCL_HARBOR_USER y HCL_HARBOR_TOKEN en env.sh"

info "Namespaces del webinar"
for n in "$DX_NS" "$SHARED_NS"; do
  kubectl get ns "$n" >/dev/null 2>&1 && warn "$n ya existe (¿instalación previa? ver docs/limpieza.md)" || ok "$n no existe todavía"
done
