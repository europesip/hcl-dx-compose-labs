#!/usr/bin/env bash
# Lab 2 · Rama empresarial · Paso AD-2 · helm upgrade de DX con la capa custom-values.ad.yaml
# (common/dx-helm.sh la añade al detectar el secret dx-ad-bind).
set -euo pipefail
source "$(dirname "$0")/../../../common/lib.sh"
kubectl -n "$DX_NS" get secret dx-ad-bind >/dev/null 2>&1 || die "Falta dx-ad-bind: ejecuta ./01-secrets-ad.sh"

"$REPO_ROOT/common/dx-helm.sh" "$@"

echo
echo "Comprueba en el log que Liberty ha cargado el registro del AD y no hay errores CWIML:"
echo "  kubectl -n $DX_NS logs ${DX_RELEASE}-web-engine-0 -c system-out-log | grep -E 'CWIML|CWWKG|ad-registry'"
echo "Prueba: https://${DX_HOST}/wps/myportal con un usuario del AD (sAMAccountName) y con wpsadmin."
echo "Siguiente: da el rol Administrator a un grupo del AD desde el portal (GUIA-empresa.md, paso AD-3)"
