#!/usr/bin/env bash
# Deploy one lab (or all labs) and wait until the load balancers are ready.
# Usage:  ./scripts/10-deploy-lab.sh lab1|lab2|lab3|lab4|all
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

M="${REPO_ROOT}/manifests"

wait_for_gateway() {   # $1=namespace $2=gateway
  echo "   waiting for Gateway $1/$2 to be Programmed (up to 15 min)..."
  kubectl wait --for=condition=Programmed "gateway/$2" -n "$1" --timeout=15m
  echo "   Gateway $1/$2 address: $(kubectl get gateway "$2" -n "$1" -o jsonpath='{.status.addresses[0].value}')"
}

wait_for_lb_ip() {     # $1=svc|ingress $2=namespace $3=name
  echo "   waiting for $1 $2/$3 to get an IP (up to 15 min)..."
  for _ in $(seq 1 90); do
    ip="$(kubectl get "$1" "$3" -n "$2" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "${ip}" ]]; then echo "   $1 $2/$3 IP: ${ip}"; return 0; fi
    sleep 10
  done
  echo "   ERROR: $1 $2/$3 has no IP after 15 minutes" >&2
  return 1
}

deploy_lab1() {
  echo "== Lab 1 - one app, three doors"
  kubectl apply -f "${M}/lab1-three-doors/"
  kubectl rollout status deployment/hello -n lab1-three-doors --timeout=10m
  wait_for_lb_ip svc lab1-three-doors hello-lb
  wait_for_lb_ip ingress lab1-three-doors hello-ingress
  wait_for_gateway lab1-three-doors hello-gateway
}

deploy_lab2() {
  echo "== Lab 2 - shared Gateway, many teams"
  kubectl apply -f "${M}/lab2-shared-gateway/"
  kubectl rollout status deployment/store-v1 -n store-ns --timeout=10m
  kubectl rollout status deployment/store-v2 -n store-ns --timeout=10m
  kubectl rollout status deployment/site -n site-ns --timeout=10m
  wait_for_gateway infra-ns shared-ext-gw
}

deploy_lab3() {
  echo "== Lab 3 - policies (HealthCheckPolicy, GCPBackendPolicy + Cloud Armor)"
  if gcloud compute security-policies describe "${ARMOR_POLICY}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "   Cloud Armor policy ${ARMOR_POLICY} already exists - skipped"
  else
    gcloud compute security-policies create "${ARMOR_POLICY}" --type=CLOUD_ARMOR \
      --description="GKE Gateway study - block /admin" --project="${PROJECT_ID}"
  fi
  if gcloud compute security-policies rules describe 1000 --security-policy="${ARMOR_POLICY}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "   Cloud Armor rule 1000 already exists - skipped"
  else
    gcloud compute security-policies rules create 1000 --security-policy="${ARMOR_POLICY}" \
      --expression='request.path.startsWith("/admin")' --action=deny-403 \
      --description="Block /admin" --project="${PROJECT_ID}"
  fi
  kubectl apply -f "${M}/lab3-policies/"
  echo "   policies applied - allow 2-5 minutes before testing"
}

deploy_lab4() {
  echo "== Lab 4 - internal Gateway (gke-l7-rilb)"
  kubectl apply -f "${M}/lab4-internal-gateway/"
  wait_for_gateway infra-ns shared-int-gw
}

case "${1:-}" in
  lab1) deploy_lab1 ;;
  lab2) deploy_lab2 ;;
  lab3) deploy_lab3 ;;
  lab4) deploy_lab4 ;;
  all)  deploy_lab1; deploy_lab2; deploy_lab3; deploy_lab4 ;;
  *) echo "Usage: $0 lab1|lab2|lab3|lab4|all" >&2; exit 2 ;;
esac
