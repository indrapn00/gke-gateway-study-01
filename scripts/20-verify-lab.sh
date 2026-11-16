#!/usr/bin/env bash
# Run the lab tests and print what happened.
# Usage:  ./scripts/20-verify-lab.sh lab1|lab2|lab3|lab4|all
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

hr() { printf '%s\n' "------------------------------------------------------------"; }
code() { curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$@"; }

verify_lab1() {
  echo "== Lab 1 - one app, three doors"; hr
  local lb ing gw
  lb="$(kubectl get svc hello-lb -n lab1-three-doors -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  ing="$(kubectl get ingress hello-ingress -n lab1-three-doors -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  gw="$(kubectl get gateway hello-gateway -n lab1-three-doors -o jsonpath='{.status.addresses[0].value}')"
  echo "Door 1 Service LoadBalancer : ${lb:-<none>}  -> $(curl -s --max-time 10 "http://${lb}/metadata")"
  echo "Door 2 Ingress              : ${ing:-<none>}  -> $(curl -s --max-time 10 "http://${ing}/metadata")"
  echo "Door 3 Gateway              : ${gw:-<none>}  -> $(curl -s --max-time 10 "http://${gw}/metadata")"
  hr
  echo "Headers seen by the app via Door 1 (L4 passthrough):"; curl -s --max-time 10 "http://${lb}/headers"; echo
  echo "Headers seen by the app via Door 3 (L7 proxy):";      curl -s --max-time 10 "http://${gw}/headers"; echo
}

verify_lab2() {
  echo "== Lab 2 - shared Gateway"; hr
  local gw; gw="$(kubectl get gateway shared-ext-gw -n infra-ns -o jsonpath='{.status.addresses[0].value}')"
  echo "shared-ext-gw IP: ${gw}"
  echo "store host  -> $(curl -s --max-time 10 -H 'Host: store.example.com' "http://${gw}/metadata")"
  echo "site host   -> $(curl -s --max-time 10 -H 'Host: site.example.com' "http://${gw}/metadata")"
  echo "unknown host-> HTTP $(code -H 'Host: unknown.example.com' "http://${gw}/")   (expect 404)"
  hr; echo "Canary split, 100 requests (expect ~90 store-v1 / ~10 store-v2):"
  for _ in $(seq 1 100); do curl -s --max-time 10 -H 'Host: store.example.com' "http://${gw}/metadata"; echo; done | sort | uniq -c
  hr; echo "Header 'env: canary', 5 requests (expect store-v2 every time):"
  for _ in $(seq 1 5); do curl -s --max-time 10 -H 'Host: store.example.com' -H 'env: canary' "http://${gw}/metadata"; echo; done
  hr; echo "Response header added by the load balancer:"
  curl -s -D - -o /dev/null --max-time 10 -H 'Host: store.example.com' "http://${gw}/" | grep -i 'x-route-rule'
  echo "Request header added by the load balancer (seen by the app):"
  curl -s --max-time 10 -H 'Host: store.example.com' "http://${gw}/headers" | grep -io '"x-gateway-study": *"[^"]*"'
  hr; echo "Redirect (expect 301 -> http://site.example.com/blog/hello):"
  curl -s -o /dev/null --max-time 10 -w "%{http_code} -> %{redirect_url}\n" -H 'Host: site.example.com' "http://${gw}/old-blog/hello"
  hr; echo "Route status (expect rogue-route Accepted=False NotAllowedByListeners):"
  for r in store-ns/store-route site-ns/site-route rogue-ns/rogue-route; do
    echo "  ${r}: $(kubectl get httproute "${r#*/}" -n "${r%/*}" \
      -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status}({.reason}) {end}')"
  done
}

verify_lab3() {
  echo "== Lab 3 - policies"; hr
  local gw; gw="$(kubectl get gateway shared-ext-gw -n infra-ns -o jsonpath='{.status.addresses[0].value}')"
  kubectl get healthcheckpolicy,gcpbackendpolicy -n store-ns
  hr
  echo "store /admin -> HTTP $(code -H 'Host: store.example.com' "http://${gw}/admin")  (expect 403, Cloud Armor)"
  echo "store /      -> HTTP $(code -H 'Host: store.example.com' "http://${gw}/")       (expect 200)"
  echo "site  /admin -> HTTP $(code -H 'Host: site.example.com' "http://${gw}/admin")   (expect 200, no policy on site)"
}

verify_lab4() {
  echo "== Lab 4 - internal Gateway"; hr
  local igw; igw="$(kubectl get gateway shared-int-gw -n infra-ns -o jsonpath='{.status.addresses[0].value}')"
  echo "shared-int-gw private IP: ${igw}  (not reachable from Cloud Shell - testing from a Pod)"
  kubectl run curl-client -n infra-ns --rm -i --restart=Never --pod-running-timeout=5m \
    --image=curlimages/curl:8.11.1 -- \
    curl -s --max-time 10 -H 'Host: site.internal.example' "http://${igw}/metadata"
  echo
  kubectl get gcpgatewaypolicy -n infra-ns
}

case "${1:-}" in
  lab1) verify_lab1 ;;
  lab2) verify_lab2 ;;
  lab3) verify_lab3 ;;
  lab4) verify_lab4 ;;
  all)  verify_lab1; verify_lab2; verify_lab3; verify_lab4 ;;
  *) echo "Usage: $0 lab1|lab2|lab3|lab4|all" >&2; exit 2 ;;
esac
