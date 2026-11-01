#!/usr/bin/env bash
# Step 1 · Create the two lab namespaces.
#   dx-demo   -> HCL software only (DX Compose, IQ, search)
#   dx-shared -> every tool that is NOT HCL software (OpenLDAP, PostgreSQL/CNPG, LiteLLM, own MCP)
#
# Kubernetes (k3s): "kubectl create namespace" is enough.
# OpenShift: HCL requires SCC annotations (UID range, supplemental groups and MCS label) on the
#            DX namespace. See docs/kubernetes-vs-openshift.md.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if is_openshift; then
  info "OpenShift: namespaces with SCC annotations (common/openshift/namespaces.yaml)"
  render "$_LIB_DIR/openshift/namespaces.yaml" '$DX_NS $SHARED_NS' | kubectl apply -f -
else
  info "Kubernetes: namespaces without special annotations"
  for n in "$DX_NS" "$SHARED_NS"; do
    kubectl create namespace "$n" --dry-run=client -o yaml | kubectl apply -f -
  done
fi

# Common label to find (and clean up) everything created by the labs
kubectl label namespace "$DX_NS" "$SHARED_NS" lab=hcl-dx-compose --overwrite
kubectl get ns "$DX_NS" "$SHARED_NS" --show-labels
