#!/usr/bin/env bash
# Delete EVERYTHING installed by the labs to start from scratch: Helm releases (DX, IQ, search,
# OpenLDAP, CNPG operator, LiteLLM), the PostgreSQL cluster, the PVCs (and with them their PVs and
# volumes, reclaimPolicy Delete) and the dx-demo and dx-shared namespaces. StorageClasses are kept.
#
# Usage:  common/99-cleanup.sh          (asks for confirmation)
#         common/99-cleanup.sh --yes
set -euo pipefail
source "$(dirname "$0")/lib.sh"

YES=0
for a in "$@"; do
  case "$a" in --yes) YES=1 ;; *) die "Unknown option: $a" ;; esac
done

info "About to delete:"
for n in "$DX_NS" "$SHARED_NS"; do
  kubectl get ns "$n" >/dev/null 2>&1 || { echo "    $n (does not exist)"; continue; }
  echo "    namespace $n:"
  helm list -n "$n" -q | sed 's/^/      release: /'
  kubectl -n "$n" get pvc --no-headers 2>/dev/null | awk '{print "      pvc:     "$1"  "$4}'
done

if ((YES == 0)); then
  read -r -p "Are you sure? Type 'delete' to continue: " r
  [[ "$r" == "delete" ]] || die "Cancelled"
fi

# 1. DX, IQ and search (they depend on what is in dx-shared)
if kubectl get ns "$DX_NS" >/dev/null 2>&1; then
  for r in $(helm list -n "$DX_NS" -q); do
    info "helm uninstall $r -n $DX_NS"
    helm uninstall "$r" -n "$DX_NS" --wait --timeout 10m || warn "could not uninstall $r"
  done
  kubectl -n "$DX_NS" delete pvc --all --wait=false   # Helm does not delete StatefulSet PVCs
fi

# 2. Third-party software. The PostgreSQL cluster is deleted BEFORE its operator (CNPG)
if kubectl get ns "$SHARED_NS" >/dev/null 2>&1; then
  if kubectl api-resources --api-group=postgresql.cnpg.io -o name 2>/dev/null | grep -q '^clusters'; then
    info "Deleting PostgreSQL (CNPG) clusters in $SHARED_NS"
    kubectl -n "$SHARED_NS" delete clusters.postgresql.cnpg.io --all --wait=true --timeout=5m || true
  fi
  for r in $(helm list -n "$SHARED_NS" -q); do
    info "helm uninstall $r -n $SHARED_NS"
    helm uninstall "$r" -n "$SHARED_NS" --wait --timeout 10m || warn "could not uninstall $r"
  done
  kubectl -n "$SHARED_NS" delete pvc --all --wait=false
fi

info "Deleting namespaces"
kubectl delete ns "$DX_NS" "$SHARED_NS" --ignore-not-found --wait=true --timeout=10m

info "Check: PVs still bound to the deleted namespaces"
left=$(kubectl get pv --no-headers 2>/dev/null | awk -v a="$DX_NS/" -v b="$SHARED_NS/" 'index($6,a)==1 || index($6,b)==1')
if [[ -n "$left" ]]; then
  echo "$left"; warn "PVs left: with reclaimPolicy Delete they disappear by themselves in a few seconds"
else
  ok "no PV left"
fi
echo "Note: the CloudNativePG CRDs (*.postgresql.cnpg.io) are kept; they do nothing without the operator."
[[ "${DX_POC:-}" == 1 ]] && echo "Lab 0 (PoC): run lab0-poc-wsl/01-storage.sh before installing again (it recreates the DAM volume)."
exit 0
