#!/usr/bin/env bash
# Lab 0 · Paso 4 · ingress-nginx (el mismo Ingress Controller que el clúster del webinar).
# hostNetwork: el controlador escucha directamente en los puertos 80/443 de WSL, así que el
# navegador de Windows llega por localhost (WSL reenvía localhost de Windows a WSL).
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
# Con DaemonSet, "helm --wait" no espera al pod: lo hacemos aquí
kubectl -n ingress-nginx rollout status ds/ingress-nginx-controller --timeout=300s
kubectl get ingressclass
echo "Prueba: curl -s -o /dev/null -w '%{http_code}\n' http://localhost/   (404 = ingress-nginx responde)"
