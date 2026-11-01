#!/usr/bin/env bash
# Borra TODO lo instalado por los labs para empezar de cero: releases de Helm (DX, IQ, OpenLDAP,
# operador CNPG, LiteLLM), cluster PostgreSQL, PVC (y con ellos sus PV y volúmenes, reclaimPolicy
# Delete) y los namespaces dx-demo y dx-shared. Las StorageClasses no se tocan.
#
# Uso:  common/99-cleanup.sh          (pide confirmación)
#       common/99-cleanup.sh --yes
set -euo pipefail
source "$(dirname "$0")/lib.sh"

YES=0
for a in "$@"; do
  case "$a" in --yes) YES=1 ;; *) die "Opción desconocida: $a" ;; esac
done

info "Se va a borrar:"
for n in "$DX_NS" "$SHARED_NS"; do
  kubectl get ns "$n" >/dev/null 2>&1 || { echo "    $n (no existe)"; continue; }
  echo "    namespace $n:"
  helm list -n "$n" -q | sed 's/^/      release: /'
  kubectl -n "$n" get pvc --no-headers 2>/dev/null | awk '{print "      pvc:     "$1"  "$4}'
done

if ((YES == 0)); then
  read -r -p "¿Seguro? Escribe 'borrar' para continuar: " r
  [[ "$r" == "borrar" ]] || die "Cancelado"
fi

# 1. DX e IQ (dependen de lo que hay en dx-shared)
if kubectl get ns "$DX_NS" >/dev/null 2>&1; then
  for r in $(helm list -n "$DX_NS" -q); do
    info "helm uninstall $r -n $DX_NS"
    helm uninstall "$r" -n "$DX_NS" --wait --timeout 10m || warn "no se pudo desinstalar $r"
  done
  kubectl -n "$DX_NS" delete pvc --all --wait=false   # Helm no borra los PVC de los StatefulSets
fi

# 2. Software de terceros. El cluster PostgreSQL se borra ANTES que su operador (CNPG)
if kubectl get ns "$SHARED_NS" >/dev/null 2>&1; then
  if kubectl api-resources --api-group=postgresql.cnpg.io -o name 2>/dev/null | grep -q '^clusters'; then
    info "Borrando clusters PostgreSQL (CNPG) de $SHARED_NS"
    kubectl -n "$SHARED_NS" delete clusters.postgresql.cnpg.io --all --wait=true --timeout=5m || true
  fi
  for r in $(helm list -n "$SHARED_NS" -q); do
    info "helm uninstall $r -n $SHARED_NS"
    helm uninstall "$r" -n "$SHARED_NS" --wait --timeout 10m || warn "no se pudo desinstalar $r"
  done
  kubectl -n "$SHARED_NS" delete pvc --all --wait=false
fi

info "Borrando namespaces"
kubectl delete ns "$DX_NS" "$SHARED_NS" --ignore-not-found --wait=true --timeout=10m

info "Comprobación: PV que siguieran asociados a los namespaces borrados"
left=$(kubectl get pv --no-headers 2>/dev/null | awk -v a="$DX_NS/" -v b="$SHARED_NS/" 'index($6,a)==1 || index($6,b)==1')
if [[ -n "$left" ]]; then
  echo "$left"; warn "quedan PV: con reclaimPolicy Delete desaparecen solos en unos segundos"
else
  ok "no queda ningún PV"
fi
echo "Nota: las CRD de CloudNativePG (*.postgresql.cnpg.io) se conservan; no afectan a nada sin el operador."
