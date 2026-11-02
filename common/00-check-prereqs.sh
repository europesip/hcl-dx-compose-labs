#!/usr/bin/env bash
# Step 0 · Read-only check that the workstation and the cluster meet the requirements.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

info "Workstation tools"
for c in kubectl helm openssl envsubst curl python3; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else fail "$c is not installed"; fi
done
is_openshift && { command -v oc >/dev/null 2>&1 && ok "oc" || fail "oc is not installed"; }
helm version --short 2>/dev/null | sed 's/^/          helm /'

info "Cluster access"
if kubectl version -o json >/dev/null 2>&1; then
  ok "context: $(kubectl config current-context)"
  kubectl version -o json | python3 -c 'import sys,json; print("          server:", json.load(sys.stdin)["serverVersion"]["gitVersion"])'
else
  fail "kubectl cannot reach the cluster"; exit 1
fi

info "Nodes (HCL: x86-64 only)"
kubectl get nodes -o custom-columns='NODE:.metadata.name,ARCH:.status.nodeInfo.architecture,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory' 2>/dev/null
kubectl top nodes 2>/dev/null || warn "metrics-server not available: current usage cannot be measured"
echo "          The DX base (Lab 1) requests ~5 CPU and ~11 GiB. Labs 2 and 3 add ~1 CPU / 2.5 GiB."

info "Required StorageClasses (SC_RWO / SC_RWX in env.sh)"
for sc in "$SC_RWO" "$SC_RWX"; do
  if kubectl get sc "$sc" >/dev/null 2>&1; then
    ok "$sc ($(kubectl get sc "$sc" -o jsonpath='{.provisioner}'))"
  else
    fail "StorageClass $sc is missing (reference: common/storageclasses-longhorn.yaml; no cluster? lab0-poc-wsl)"
  fi
done

info "External access"
if is_openshift; then
  ok "OpenShift: a passthrough Route will be used"
else
  kubectl get ingressclass "$INGRESS_CLASS" >/dev/null 2>&1 && ok "IngressClass $INGRESS_CLASS" \
    || fail "IngressClass $INGRESS_CLASS does not exist (set INGRESS_CLASS in env.sh)"
  if [[ "$INGRESS_CLASS" == traefik ]]; then
    kubectl get crd ingressroutes.traefik.io serverstransports.traefik.io >/dev/null 2>&1 && ok "Traefik CRDs (IngressRoute, ServersTransport)" \
      || fail "Traefik CRDs missing: Traefik v3 with its CRDs is needed (k3s installs them)"
  fi
fi
if getent hosts "$DX_HOST" >/dev/null 2>&1; then ok "DNS: $DX_HOST -> $(getent hosts "$DX_HOST" | awk '{print $1}')"
else fail "DNS: $DX_HOST does not resolve"; fi

info "HCL Harbor credentials (hclcr.io)"
[[ -n "${HCL_HARBOR_USER:-}" && -n "${HCL_HARBOR_TOKEN:-}" ]] && ok "HCL_HARBOR_USER and HCL_HARBOR_TOKEN are set" \
  || fail "set HCL_HARBOR_USER and HCL_HARBOR_TOKEN in env.sh"

info "Lab namespaces"
for n in "$DX_NS" "$SHARED_NS"; do
  kubectl get ns "$n" >/dev/null 2>&1 && warn "$n already exists (previous install? see docs/cleanup.md)" || ok "$n does not exist yet"
done
