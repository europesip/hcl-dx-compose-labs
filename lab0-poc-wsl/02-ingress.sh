#!/usr/bin/env bash
# Lab 0 · Step 5 · Ingress controller listening on ports 80/443 of WSL, so the Windows browser
# reaches it through localhost (WSL forwards Windows localhost to WSL).
#   INGRESS_CLASS=traefik : the Traefik that k3s installs by default, set to hostNetwork
#   INGRESS_CLASS=nginx   : ingress-nginx, the same controller as the reference lab cluster
#                           (k3s installed with --disable traefik); hostNetwork
set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"

if [[ "$INGRESS_CLASS" == traefik ]]; then
  kubectl -n kube-system get deploy traefik >/dev/null 2>&1 \
    || die "Traefik is not installed (k3s installed with --disable traefik?): use INGRESS_CLASS=nginx in env.sh"
  kubectl apply -f "$(dirname "$0")/traefik-config.yaml"   # hostNetwork on 80/443 and longer timeouts
  for _ in $(seq 60); do   # until k3s has redeployed Traefik with this configuration
    kubectl -n kube-system get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q "web.address=127.0.0.1:80/" && break
    sleep 5
  done
  kubectl -n kube-system rollout status deploy/traefik --timeout=300s
  kubectl get ingressclass
  echo "Test: curl -s -o /dev/null -w '%{http_code}\n' http://localhost/   (404 = Traefik is answering)"
  exit 0
fi

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update ingress-nginx >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --version 4.15.1 \
  -n ingress-nginx --create-namespace \
  --set controller.kind=DaemonSet \
  --set controller.hostNetwork=true \
  --set controller.dnsPolicy=ClusterFirstWithHostNet \
  --set controller.service.type=ClusterIP \
  --set controller.ingressClassResource.default=true
# With a DaemonSet, "helm --wait" does not wait for the pod: we do it here
kubectl -n ingress-nginx rollout status ds/ingress-nginx-controller --timeout=300s
kubectl get ingressclass
echo "Test: curl -s -o /dev/null -w '%{http_code}\n' http://localhost/   (404 = ingress-nginx is answering)"
