#!/usr/bin/env bash
# Collect the status and logs of DX (and dx-shared) into ./logs-<date>/ to analyse a problem or
# send it to support. Read-only.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

OUT="./logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
info "Collecting into $OUT"

for n in "$DX_NS" "$SHARED_NS"; do
  kubectl -n "$n" get pods -o wide        > "$OUT/$n-pods.txt" 2>&1
  kubectl -n "$n" get events --sort-by=.lastTimestamp > "$OUT/$n-events.txt" 2>&1
  kubectl -n "$n" get pvc,svc,ingress     > "$OUT/$n-resources.txt" 2>&1
  kubectl -n "$n" top pods                > "$OUT/$n-top-pods.txt" 2>&1
done
kubectl top nodes > "$OUT/top-nodes.txt" 2>&1
helm list -n "$DX_NS" > "$OUT/helm-list.txt" 2>&1
helm list -n "$SHARED_NS" >> "$OUT/helm-list.txt" 2>&1
# Effective values (referenced secrets do not appear: only their names)
helm -n "$DX_NS" get values "$DX_RELEASE" > "$OUT/dx-user-values.yaml" 2>&1

# Logs of every container of the release (current and previous start)
kubectl -n "$DX_NS" logs -l release="$DX_RELEASE" --all-containers --prefix --tail=-1 > "$OUT/dx-current.log" 2>&1
kubectl -n "$DX_NS" logs -l release="$DX_RELEASE" --all-containers --prefix --tail=-1 --previous > "$OUT/dx-previous.log" 2>&1

ls -lh "$OUT"
echo "Review the files before sharing them: they may contain user names and internal host names."
