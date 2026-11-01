#!/usr/bin/env bash
# Lab 0 · Step 3 · StorageClasses $SC_RWO / $SC_RWX and the DAM RWX volume.
# Idempotent. Run it also after common/99-cleanup.sh: when DX is deleted, the DAM volume is left
# "Released" (Retain) and it is recreated empty here for the next installation.
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
require_vars SC_RWO SC_RWX
cd "$(dirname "$0")"
VARS='$SC_RWO $SC_RWX'
render storage-poc.yaml "$VARS" | kubectl apply -f -

phase=$(kubectl get pv dx-poc-dam-binaries -o jsonpath='{.status.phase}' 2>/dev/null || true)
CLEAN=""
if [[ "$phase" == "Released" || "$phase" == "Failed" ]]; then
  echo "dx-poc-dam-binaries was $phase: recreating it empty"
  kubectl delete pv dx-poc-dam-binaries --wait=true
  CLEAN='rm -rf /d/* /d/.[!.]* 2>/dev/null; '
fi
render dam-binaries-pv.yaml "$VARS" | kubectl apply -f -

# Kubernetes creates the hostPath directory as root (755) and the pod fsGroup is not applied to
# hostPath: DAM, which runs as uid 1000 / gid 1001, could not write ("EACCES ... /opt/app/upload"
# and DAM never becomes Ready). An ephemeral pod (no sudo needed) sets it to 1000:1001 with 2775.
kubectl delete pod dx-poc-prepare-dam --ignore-not-found >/dev/null
kubectl run dx-poc-prepare-dam --rm -i --restart=Never --quiet --image=busybox:1.36 --overrides="{
  \"spec\":{\"containers\":[{\"name\":\"c\",\"image\":\"busybox:1.36\",
  \"command\":[\"sh\",\"-c\",\"${CLEAN}chown 1000:1001 /d && chmod 2775 /d && ls -ld /d\"],
  \"volumeMounts\":[{\"name\":\"d\",\"mountPath\":\"/d\"}]}],
  \"volumes\":[{\"name\":\"d\",\"hostPath\":{\"path\":\"/var/lib/dx-poc/dam-binaries\",\"type\":\"DirectoryOrCreate\"}}]}}" </dev/null
kubectl get sc "$SC_RWO" "$SC_RWX"
kubectl get pv dx-poc-dam-binaries
