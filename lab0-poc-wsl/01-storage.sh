#!/usr/bin/env bash
# Lab 0 · Paso 3 · StorageClasses dx-deploy-rwo / dx-deploy-rwx y el volumen RWX de DAM.
# Idempotente. Ejecútalo también después de common/99-cleanup.sh: al borrar DX, el volumen de DAM
# queda "Released" (Retain) y aquí se recrea vacío para la siguiente instalación.
set -euo pipefail
cd "$(dirname "$0")"
kubectl apply -f storage-poc.yaml

phase=$(kubectl get pv dx-poc-dam-binaries -o jsonpath='{.status.phase}' 2>/dev/null || true)
CLEAN=""
if [[ "$phase" == "Released" || "$phase" == "Failed" ]]; then
  echo "dx-poc-dam-binaries estaba $phase: se recrea vacío"
  kubectl delete pv dx-poc-dam-binaries --wait=true
  CLEAN='rm -rf /d/* /d/.[!.]* 2>/dev/null; '
fi
kubectl apply -f dam-binaries-pv.yaml

# Kubernetes crea el directorio hostPath como root (755) y con hostPath no se aplica el fsGroup
# del pod: DAM, que corre como uid 1000 / gid 1001, no podría escribir ("EACCES ... /opt/app/upload"
# y DAM nunca queda Ready). Un pod efímero (sin sudo) lo deja como 1000:1001 con permisos 2775.
kubectl delete pod dx-poc-prepare-dam --ignore-not-found >/dev/null
kubectl run dx-poc-prepare-dam --rm -i --restart=Never --quiet --image=busybox:1.36 --overrides="{
  \"spec\":{\"containers\":[{\"name\":\"c\",\"image\":\"busybox:1.36\",
  \"command\":[\"sh\",\"-c\",\"${CLEAN}chown 1000:1001 /d && chmod 2775 /d && ls -ld /d\"],
  \"volumeMounts\":[{\"name\":\"d\",\"mountPath\":\"/d\"}]}],
  \"volumes\":[{\"name\":\"d\",\"hostPath\":{\"path\":\"/var/lib/dx-poc/dam-binaries\",\"type\":\"DirectoryOrCreate\"}}]}}"
kubectl get sc dx-deploy-rwo dx-deploy-rwx
kubectl get pv dx-poc-dam-binaries
