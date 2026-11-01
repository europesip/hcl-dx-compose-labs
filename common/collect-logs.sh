#!/usr/bin/env bash
# Recoge el estado y los logs de DX (y de dx-shared) en ./logs-<fecha>/ para analizar un problema
# o enviarlo a soporte. Solo lectura.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

OUT="./logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
info "Recogiendo en $OUT"

for n in "$DX_NS" "$SHARED_NS"; do
  kubectl -n "$n" get pods -o wide        > "$OUT/$n-pods.txt" 2>&1
  kubectl -n "$n" get events --sort-by=.lastTimestamp > "$OUT/$n-events.txt" 2>&1
  kubectl -n "$n" get pvc,svc,ingress     > "$OUT/$n-resources.txt" 2>&1
  kubectl -n "$n" top pods                > "$OUT/$n-top-pods.txt" 2>&1
done
kubectl top nodes > "$OUT/top-nodes.txt" 2>&1
helm list -n "$DX_NS" > "$OUT/helm-list.txt" 2>&1
helm list -n "$SHARED_NS" >> "$OUT/helm-list.txt" 2>&1
# Values efectivos (los secretos referenciados no aparecen: solo sus nombres)
helm -n "$DX_NS" get values "$DX_RELEASE" > "$OUT/dx-user-values.yaml" 2>&1

# Logs de todos los contenedores de la release (actuales y del arranque anterior)
kubectl -n "$DX_NS" logs -l release="$DX_RELEASE" --all-containers --prefix --tail=-1 > "$OUT/dx-current.log" 2>&1
kubectl -n "$DX_NS" logs -l release="$DX_RELEASE" --all-containers --prefix --tail=-1 --previous > "$OUT/dx-previous.log" 2>&1

ls -lh "$OUT"
echo "Revisa los ficheros antes de compartirlos: pueden contener nombres de usuario y hosts internos."
