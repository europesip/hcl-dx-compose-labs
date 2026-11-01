#!/usr/bin/env bash
# Paso 1 · Crea los dos namespaces del webinar.
#   dx-demo   -> software de HCL (DX Compose, IQ)
#   dx-shared -> software de terceros (OpenLDAP, PostgreSQL/CNPG, LiteLLM)
#
# Kubernetes (k3s): basta con "kubectl create namespace".
# OpenShift: HCL exige anotaciones de SCC (rango de UID, grupos suplementarios y etiqueta MCS)
#            en el namespace de DX. Ver docs/kubernetes-vs-openshift.md.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if is_openshift; then
  info "OpenShift: namespaces con anotaciones SCC (common/openshift/namespaces.yaml)"
  render "$_LIB_DIR/openshift/namespaces.yaml" '$DX_NS $SHARED_NS' | kubectl apply -f -
else
  info "Kubernetes: namespaces sin anotaciones especiales"
  for n in "$DX_NS" "$SHARED_NS"; do
    kubectl create namespace "$n" --dry-run=client -o yaml | kubectl apply -f -
  done
fi

# Etiqueta común para localizar (y limpiar) todo lo del webinar
kubectl label namespace "$DX_NS" "$SHARED_NS" webinar=hcl-dx-compose --overwrite
kubectl get ns "$DX_NS" "$SHARED_NS" --show-labels
