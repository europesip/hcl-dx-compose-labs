#!/usr/bin/env bash
# Lab 0 · Step 4 · ingress-nginx (the same Ingress Controller as the reference lab cluster).
# hostNetwork: the controller listens directly on ports 80/443 of WSL, so the Windows browser
# reaches it through localhost (WSL forwards Windows localhost to WSL).
set -euo pipefail
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
